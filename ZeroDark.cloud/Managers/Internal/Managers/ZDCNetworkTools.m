/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCNetworkTools.h"

#import "S3Request.h"
#import "ZDCLocalUserPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+Auth0API.h"
#import "NSError+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

@implementation ZDCNetworkTools {
@private
	
	__weak ZeroDarkCloud *zdc;
	dispatch_queue_t serialQueue;
	
	YapDatabaseConnection *_rwConnection;      // we queue hundreds of transactions - don't block rwDatabaseConnection
	YapDatabaseConnection *_decryptConnection; // decryption is slow - don't block roDatabaseConnection
	
	NSMutableDictionary *recentRequestDict;  // must access through serialQueue
}

- (instancetype)init
{
	return nil; // To access this class use: owner.networkTools (This class is internal)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		serialQueue = dispatch_queue_create("ZDCNetworkTools", DISPATCH_QUEUE_SERIAL);
		
		recentRequestDict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseConnection *)rwConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_rwConnection == nil)
		{
			_rwConnection = [zdc.databaseManager.database newConnection];
			_rwConnection.name = @"ZDCNetworkTools.pushPull.rwConnection";
		}
		
		connection = _rwConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

- (YapDatabaseConnection *)decryptConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_decryptConnection == nil)
		{
			_decryptConnection = [zdc.databaseManager.database newConnection];
			_decryptConnection.name = @"ZDCNetworkTools.pushPull.decryptConnection";
		}
		
		connection = _decryptConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSTimeInterval)exponentialBackoffForFailCount:(NSUInteger)failCount
{
	switch (failCount)
	{
		case 0 : return  0.0; // seconds
		case 1 : return  1.0;
		case 2 : return  2.0;
		case 3 : return  4.0;
		case 4 : return  8.0;
		case 5 : return 16.0;
		case 6 : return 32.0;
		default: return 60.0;
	}
}

- (void)addRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID
{
	if (requestID == nil) return;
	if (localUserID == nil) return;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray *recents = recentRequestDict[localUserID];
		if (recents == nil)
		{
			recents = recentRequestDict[localUserID] = [[NSMutableArray alloc] init];
		}
		
		if (![recents containsObject:requestID])
		{
			[recents insertObject:requestID atIndex:0];
			
			while (recents.count > 100)
			{
				[recents removeLastObject];
			}
		}
		
	#pragma clang diagnostic pop
	}});
}

- (BOOL)isRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID
{
	if (requestID == nil) return NO;
	if (localUserID == nil) return NO;
	
	__block BOOL result = NO;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray *recents = recentRequestDict[localUserID];
		if (recents)
		{
			result = [recents containsObject:requestID];
		}
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth Failure
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method should be invoked whenever an authentication failure is detected.
**/
- (void)handleAuthFailureForUser:(NSString *)userID withError:(NSError *)error
{
	[self handleAuthFailureForUser:userID withError:error pullState:nil];
}

- (void)handleAuthFailureForUser:(NSString *)userID withError:(NSError *)error pullState:(ZDCPullState *)pullState
{
	if (pullState)
	{
		BOOL firstDetectedAuthFailure = [pullState isFirstAuthFailure];
		if (!firstDetectedAuthFailure)
		{
			return;
		}
	}
	
	BOOL isAccountSuspended = NO;
	BOOL accountNeedsA0Token = NO;
	if ([error.auth0API_error isEqualToString:kAuth0ErrorDescription_Blocked])
	{
		// The account still exists (in Auth0), but has been blocked.
		// So the account is suspended.
		
		isAccountSuspended = YES;
	}
	else if ([error.auth0API_error isEqualToString:kAuth0Error_InvalidRefreshToken])
	{
		accountNeedsA0Token = YES;
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
		ZDCLocalUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		user = [user copy];
		
		if (isAccountSuspended)
		{
			// Auth0 specific error code has informed us of the problem.
			// Our account is suspended.
			// This probably means the user owes us money. (expired credit card, etc)
			
			user.accountSuspended = YES;
		}
		else if(accountNeedsA0Token)
		{
			user.accountNeedsA0Token = YES;
		}
		else
		{
			// This flag will trigger a YapActionItem to check with the server.
			// If the server reports the account deleted, we'll set the appropriate user flag.
			//
			user.needsCheckAccountDeleted = YES;
		}
		
		[transaction setObject: user
		                forKey: user.uuid
		          inCollection: kZDCCollection_Users];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)downloadDataAtPath:(NSString *)inRemotePath
                  inBucket:(NSString *)inBucket
                    region:(AWSRegion)region
                  withETag:(NSString *)inETag
                     range:(NSValue *)range
               requesterID:(NSString *)inLocalUserID
             canBackground:(BOOL)canBackground
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	if (!completionBlock) return;
	
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();
	
	// Mutable string protection
	NSString *remotePath  = [inRemotePath copy];
	NSString *bucket      = [inBucket copy];
	NSString *localUserID = [inLocalUserID copy];
	NSString *eTag        = [inETag copy];
	
	__weak typeof(self) weakSelf = self;
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{
					completionBlock(nil, nil, error);
				});
			}
			return;
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCSessionInfo *sessionInfo = [strongSelf->zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = canBackground ? sessionInfo.backgroundSession : sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request getObject:remotePath inBucket:bucket region:region outUrlComponents:&urlComponents];
		
		if (eTag)
			[request setValue:[NSString stringWithFormat:@"\"%@\"", eTag] forHTTPHeaderField:@"If-Match"];
		
		if (range)
		{
			NSRange byteRange = range.rangeValue;
			if (byteRange.length > 0)
			{
				NSString *rangeString = [NSString stringWithFormat:@"bytes=%lu-%lu",
				                          (unsigned long)(byteRange.location),
				                          (unsigned long)(byteRange.location + byteRange.length - 1)];
				
				[request setValue:rangeString forHTTPHeaderField:@"Range"];
			}
		}
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_S3
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		void (^completionBlockWrapper)(NSURLResponse *response, id responseObject, NSError *error);
		completionBlockWrapper = ^(NSURLResponse *response, id responseObject, NSError *error){
			
			if (!completionBlock) return;
			
			if (completionQueue == sessionInfo.queue)
			{
				completionBlock(response, responseObject, error);
			}
			else
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool{
					completionBlock(response, responseObject, error);
				}});
			}
		};
		
		NSURLSessionTask *task = nil;
		
	#if TARGET_OS_IPHONE
		if (canBackground)
		{
			task = [session downloadTaskWithRequest:request
													 progress:nil
												 destination:^NSURL *(NSURL *targetPath, NSURLResponse *response)
			{
				return [ZDCDirectoryManager generateTempURL];
				
			} completionHandler:^(NSURLResponse *response, NSURL *downloadedFileURL, NSError *error) {
				
				id responseObject = nil;
				if (downloadedFileURL)
				{
					responseObject = [NSData dataWithContentsOfURL:downloadedFileURL];
					[[NSFileManager defaultManager] removeItemAtURL:downloadedFileURL error:nil];
				}
				
				completionBlockWrapper(response, responseObject, error);
			}];
		}
		else
	#endif
		{
			task = [session dataTaskWithRequest: request
			                     uploadProgress: nil
			                   downloadProgress: nil
			                  completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
			{
				completionBlockWrapper(response, responseObject, error);
			}];
		}
		
		[task resume];
	}];
}

- (void)downloadFileFromURL:(NSURL *)sourceURL
               andSaveToURL:(NSURL *)destinationURL
                       eTag:(nullable NSString *)eTag
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSString *eTag, NSError *error))completionBlock
{
	void (^InvokeCompletionBlock)(NSString*, NSError*) =
	^(NSString *eTag, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(eTag, error);
			}});
		}
	};
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:sourceURL];
	[request setHTTPMethod:@"GET"];
	
	if (eTag) {
		[request setValue:[NSString stringWithFormat:@"\"%@\"", eTag] forHTTPHeaderField:@"If-None-Match"];
	}
	
	NSURLSessionDownloadTask* task =
	  [session downloadTaskWithRequest:request
	                 completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, error);
			return;
		}
		
		NSInteger statusCode = response.httpStatusCode;
		if (statusCode != 200)
		{
			NSString *errMsg = @"Non-200 response from server.";
			NSError *error = [NSError errorWithClass:[self class] code:statusCode description:errMsg];
			
			InvokeCompletionBlock(nil, error);
		}
		else if (!location)
		{
			NSString *errMsg = @"No data from server";
			NSError *error = [NSError errorWithClass:[self class] code:204 description:errMsg];
			
			InvokeCompletionBlock(nil, error);
		}
		else
		{
			[NSFileManager.defaultManager removeItemAtURL:destinationURL error:NULL];
			[NSFileManager.defaultManager moveItemAtURL:location toURL:destinationURL error:&error];
			
			InvokeCompletionBlock(!error?response.eTag:nil, error);
		}
	}];
	
	[task resume];
}

@end
