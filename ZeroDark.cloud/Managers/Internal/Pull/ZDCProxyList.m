/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCProxyList.h"

#import "AWSCredentialsManager.h"
#import "AWSDate.h"
#import "AWSNumber.h"
#import "AWSSignature.h"
#import "S3ObjectInfo.h"
#import "S3ResponsePrivate.h"
#import "ZDCSessionManager.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSString+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"


@implementation ZDCProxyList

+ (void)recursiveProxyList:(ZeroDarkCloud *)zdc
                    region:(AWSRegion)region
                    bucket:(NSString *)inBucket
                 cloudPath:(ZDCCloudPath *)inRootCloudPath
                 pullState:(ZDCPullState *)pullState
           completionQueue:(dispatch_queue_t)completionQueue
           completionBlock:(void (^)(NSArray<S3ObjectInfo*>*, NSError*))completionBlock
{
	if (completionQueue == nil)
		completionQueue = dispatch_get_main_queue();
	
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(inBucket != nil);
	NSParameterAssert(inRootCloudPath != nil);
	NSParameterAssert(pullState != nil);
	NSParameterAssert(completionBlock != nil);
	
	NSString *const bucket = [inBucket copy];
	
	NSString *const localUserID = pullState.localUserID;
	NSString *const zAppID      = pullState.zAppID;
	NSString *const pullID      = pullState.pullID;
	
	NSString *rootAppPrefix = inRootCloudPath.zAppID;
	
	NSMutableArray<NSString *> *pendingCloudPaths = [[NSMutableArray alloc] init];
	NSMutableArray<S3ObjectInfo *> *fetchedItems = [[NSMutableArray alloc] init];
	
	NSString *rootRcrdPath = [inRootCloudPath pathWithExt:@"rcrd"];
	[pendingCloudPaths addObject:rootRcrdPath];
	
	dispatch_queue_t queue = dispatch_queue_create("ZDCProxyList", DISPATCH_QUEUE_SERIAL);
	
	__block void (^processResponseBlock)(NSURLResponse*, id, NSError*);
	__block void (^sendNextRequestBlock)(void);
	__block void (^retryRequestBlock)(void);
	__block void (^resetBlock)(void);
	
	__block NSUInteger inFlightCount = 0;
	__block NSUInteger failCount = 0;
	__block NSString *continuation_id = nil;
	__block NSNumber *continuation_offset = nil;
	__block NSString *continuation_token = nil;
	__block NSError *lastError = nil;
	
	processResponseBlock = ^(NSURLResponse *urlResponse, id responseObject, NSError *error){ @autoreleasepool {
		
		NSInteger statusCode = urlResponse.httpStatusCode;
		
		if (error || statusCode != 200)
		{
			failCount++;
			
			if (statusCode == 412)
			{
				resetBlock();
			}
			else
			{
				retryRequestBlock();
			}
			return;
		}
		
		failCount = 0;
		
		NSLog(@"responseObject: %@", responseObject);
		
		NSMutableSet *recursive_prefixes = [NSMutableSet set];
		
		NSDictionary *response_object = responseObject;
		if (![response_object isKindOfClass:[NSDictionary class]])
			response_object = @{};
		
		NSDictionary *file_paths = response_object[@"file_paths"];
		if (![file_paths isKindOfClass:[NSDictionary class]])
			file_paths = @{};
		
		for (NSString *cp in file_paths)
		{
			NSDictionary *cp_info = file_paths[cp];
			if (![cp_info isKindOfClass:[NSDictionary class]])
				cp_info = @{};
			
			NSDictionary *children = cp_info[@"children"];
			if (![children isKindOfClass:[NSDictionary class]])
				children = @{};
			
			for (NSString *prefix_type in children)
			{
				if ([prefix_type isEqualToString:@"dir"] || [prefix_type isEqualToString:@"comments"])
				{
					NSString *child_prefix = children[prefix_type];
					NSString *file_prefix = [NSString stringWithFormat:@"%@/%@", rootAppPrefix, child_prefix];
					
					[recursive_prefixes addObject:file_prefix];
				}
			}
		}
		
		NSArray *list = response_object[@"list"];
		if (![list isKindOfClass:[NSArray class]])
			list = @[];
		
		for (NSDictionary *item_info in list)
		{
			id value;
			
			NSString *key = nil;
			NSString *eTag = nil;
			NSDate *lastModified = nil;
			uint64_t size = 0;
			S3StorageClass storageClass = S3StorageClass_Standard;
			
			value = item_info[@"Key"];
			if (value && [value isKindOfClass:[NSString class]])
			{
				key = (NSString *)value;
			}
			
			value = item_info[@"ETag"];
			if (value && [value isKindOfClass:[NSString class]])
			{
				eTag = (NSString *)value;
				
				eTag = [eTag stringByRemovingPercentEncoding];
				
				NSCharacterSet *quotes = [NSCharacterSet characterSetWithCharactersInString:@"\""];
				eTag = [eTag stringByTrimmingCharactersInSet:quotes];
			}
			
			value = item_info[@"LastModified"];
			if (value && [value isKindOfClass:[NSString class]])
			{
				lastModified = [AWSDate parseISO8601Timestamp:(NSString *)value];
			}
			
			value = item_info[@"Size"];
			if (value)
			{
				if ([value isKindOfClass:[NSNumber class]]) {
					size = [(NSNumber *)value unsignedLongLongValue];
				}
				else if ([value isKindOfClass:[NSString class]]) {
					[AWSNumber parseUInt64:&size fromString:(NSString *)value];
				}
			}
			
			value = item_info[@"StorageClass"];
			if (value && [value isKindOfClass:[NSString class]])
			{
				if ([(NSString *)value isEqualToString:@"STANDARD"])
				{
					storageClass = S3StorageClass_Standard;
				}
				else if ([(NSString *)value isEqualToString:@"STANDARD_IA"])
				{
					storageClass = S3StorageClass_InfrequentAccess;
				}
				else if ([(NSString *)value isEqualToString:@"REDUCED_REDUNDANCY"])
				{
					storageClass = S3StorageClass_ReducedRedundancy;
				}
				else if ([(NSString *)value isEqualToString:@"GLACIER"])
				{
					storageClass = S3StorageClass_Glacier;
				}
			}
			
			if (key && eTag && lastModified)
			{
				S3ObjectInfo *objInfo = [[S3ObjectInfo alloc] init];
				objInfo.key = key;
				objInfo.eTag = eTag;
				objInfo.lastModified = lastModified;
				objInfo.size = size;
				objInfo.storageClass = storageClass;
				
				[fetchedItems addObject:objInfo];
			}
			
			if (key)
			{
				NSArray<NSString *> *keyComponents = [key componentsSeparatedByString:@"/"];
				
				NSString *keyAppPrefix = keyComponents.count > 0 ? keyComponents[0] : @"";
				NSString *keyDirPrefix = keyComponents.count > 1 ? keyComponents[1] : @"";
				
				NSString *keyPrefix = [NSString stringWithFormat:@"%@/%@", keyAppPrefix, keyDirPrefix];
				
				if ([recursive_prefixes containsObject:keyPrefix] && [key hasSuffix:@".rcrd"])
				{
					[pendingCloudPaths addObject:key];
				}
			}
		}
		
		continuation_id     = response_object[@"continuation_id"];
		continuation_offset = response_object[@"continuation_offset"];
		continuation_token  = response_object[@"continuation_token"];
		
		if (continuation_offset || continuation_token)
		{
			sendNextRequestBlock();
		}
		else
		{
			[pendingCloudPaths removeObjectsInRange:NSMakeRange(0, inFlightCount)];
		
			if (pendingCloudPaths.count == 0)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock([fetchedItems copy], nil);
				}});
			}
			else
			{
				sendNextRequestBlock();
			}
		}
	}};
	
	sendNextRequestBlock = ^{ @autoreleasepool {
		
		if (!continuation_offset && !continuation_token)
		{
			inFlightCount = MIN([pendingCloudPaths count], 100);
		}
		
		NSMutableArray *requestCloudPaths = [NSMutableArray arrayWithCapacity:inFlightCount];
		
		for (NSUInteger i = 0; i < inFlightCount; i++)
		{
			NSString *cp = pendingCloudPaths[i];
			
			if ([cp hasPrefix:zAppID])
				cp = [cp substringFromIndex:zAppID.length];
			if ([cp hasPrefix:@"/"])
				cp = [cp substringFromIndex:1];
			
			[requestCloudPaths addObject:cp];
		}
		
		[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
		                                    completionQueue: queue
		                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				failCount++;
				lastError = error;
				
				retryRequestBlock();
				return;
			}
			
			ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		#if TARGET_OS_IPHONE
			AFURLSessionManager *session = sessionInfo.foregroundSession;
		#else
			AFURLSessionManager *session = sessionInfo.session;
		#endif
			
			NSMutableURLRequest *request =
				[zdc.webManager listProxyWithPaths: requestCloudPaths
				                         appPrefix: rootAppPrefix
				                            pullID: pullID
				                    continuationID: continuation_id
				                continuationOffset: continuation_offset
			                    continuationToken: continuation_token
				                          inBucket: bucket
				                            region: region
				                    forLocalUserID: localUserID
				                          withAuth: auth];
			
			NSURLSessionDataTask *task =
			  [session dataTaskWithRequest: request
			                uploadProgress: nil
			              downloadProgress: nil
			             completionHandler: processResponseBlock];
			
			[task resume];
		}];
	}};
	
	retryRequestBlock = ^{ @autoreleasepool {
		
		if (failCount > 6)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(nil, lastError);
			}});
		}
		
		NSTimeInterval delayInSeconds;
		switch (failCount)
		{
			case 0 : delayInSeconds =  0.0; break;
			case 1 : delayInSeconds =  1.0; break;
			case 2 : delayInSeconds =  2.0; break;
			case 3 : delayInSeconds =  4.0; break;
			case 4 : delayInSeconds =  8.0; break;
			case 5 : delayInSeconds = 16.0; break;
			default: delayInSeconds = 32.0; break;
		}
		
		dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(delay, queue, sendNextRequestBlock);
	}};
	
	resetBlock = ^{ @autoreleasepool {
		
		[pendingCloudPaths removeAllObjects];
		[fetchedItems removeAllObjects];
		
		[pendingCloudPaths addObject:rootRcrdPath];
		
		continuation_id = nil;
		continuation_offset = nil;
		continuation_token = nil;
		
		retryRequestBlock();
	}};
	
	sendNextRequestBlock();
}

@end
