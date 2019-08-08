#import "ZDCRestManagerPrivate.h"

#import "AWSCredentialsManager.h"
#import "AWSPayload.h"
#import "AWSSignature.h"
#import "S3Request.h"
#import "S4DeepCopy.h"
#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCCachedResponse.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCDirectoryManager.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLocalUserAuth.h"
#import "ZDCLogging.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+ZeroDark.h"
#import "NSURLRequest+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int ddLogLevel = DDLogLevelInfo | DDLogFlagTrace;
#elif DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

#define CLAMP(min, num, max) (MAX(min, MIN(max, num)))

#ifndef DEFAULT_AWS_STAGE
  #if DEBUG && robbie_hanson
    #define DEFAULT_AWS_STAGE @"dev"
  #else
    #define DEFAULT_AWS_STAGE @"prod"
  #endif
#endif

@implementation ZDCRestManager {
@private
	
	__weak ZeroDarkCloud *zdc;
	
	ZDCAsyncCompletionDispatch *asyncCompletionDispatch;
	
	dispatch_queue_t billing_queue;
	NSMutableDictionary *billing_history;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.pullManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		asyncCompletionDispatch = [[ZDCAsyncCompletionDispatch alloc] init];
		
		billing_queue = dispatch_queue_create("ZDCRestManager", DISPATCH_QUEUE_SERIAL);
		billing_history = [[NSMutableDictionary alloc] initWithCapacity:1];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (NSString *)apiGatewayIDForRegion:(AWSRegion)region stage:(NSString *)stage
{
	switch(region)
	{
		case AWSRegion_US_West_2:
		{
			if ([stage isEqualToString:@"dev"])  return @"pzg66sum7l";
			if ([stage isEqualToString:@"test"]) return @"xvsiisz5m0";
			if ([stage isEqualToString:@"prod"]) return @"4trp9uu0h1";
		}
		case AWSRegion_EU_West_1:
		{
			if ([stage isEqualToString:@"dev"])  return @"74bukw6pwc";
			if ([stage isEqualToString:@"test"]) return @"3ip9q72kwf";
			if ([stage isEqualToString:@"prod"]) return @"b0mf3mdmt0";
		}
		default: break;
	}
	
	return nil;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (NSURLComponents *)apiGatewayForRegion:(AWSRegion)region stage:(NSString *)stage path:(NSString *)path
{
	NSString *regionStr = [AWSRegions shortNameForRegion:region];
	NSString *apiGatewayID = [self apiGatewayIDForRegion:region stage:stage];
	if (apiGatewayID == nil) {
		return nil;
	}
	
	NSString *host = [NSString stringWithFormat:@"%@.execute-api.%@.amazonaws.com", apiGatewayID, regionStr];
	
	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = host;
	
	if (path)
	{
		if ([path hasPrefix:@"/"])
			urlComponents.path = [NSString stringWithFormat:@"/%@%@", stage, path];
		else
			urlComponents.path = [NSString stringWithFormat:@"/%@/%@", stage, path];
	}
	
	return urlComponents;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchConfigWithCompletionQueue:(nullable dispatch_queue_t)inCompletionQueue
                       completionBlock:(void(^)(NSDictionary *_Nullable config,
                                                     NSError *_Nullable error))inCompletionBlock
{
	DDLogAutoTrace();

	if (!inCompletionBlock)
		return;

	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();

	NSString *requestKey = NSStringFromSelector(_cmd);

	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue:inCompletionQueue
	                               completionBlock:inCompletionBlock
	                                      forKey:requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	void (^InvokeCompletionBlocks)(NSDictionary*, NSError*) = ^(NSDictionary* config, NSError *error) {

		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
									completionBlocks:&completionBlocks
											  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSDictionary* config, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(config, error);
			}});
		}
	};

	NSDictionary* (^ParseResponse)(NSData*) = ^NSDictionary* (NSData *data){ @autoreleasepool {

		NSMutableDictionary *configInfo = nil;

		id json = nil;
		if ([data isKindOfClass:[NSData class]])
		{
			json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		}

		if ([json isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *dict = (NSDictionary *)json;

			// clean up the awsRegions

			NSArray *supportedRegionNames = [dict objectForKey:@"awsRegions"];
			NSMutableArray<NSNumber *> *supportedRegionNumbers =
			[NSMutableArray arrayWithCapacity:supportedRegionNames.count];

			if ([supportedRegionNames isKindOfClass:[NSArray class]])
			{
				for (id regionName in supportedRegionNames)
				{
					if ([regionName isKindOfClass:[NSString class]])
					{
						AWSRegion region =  [AWSRegions regionForName:(NSString *)regionName];

						if (region != AWSRegion_Invalid)
						{
							[supportedRegionNumbers addObject:@(region)];
						}
					}
				}
			}

			NSArray *comingSoonRegionNames = [dict objectForKey:@"awsRegionsSoon"];

			NSMutableArray<NSNumber *> *comingSoonRegionNumbers =
			[NSMutableArray arrayWithCapacity:comingSoonRegionNames.count];

			if ([comingSoonRegionNames isKindOfClass:[NSArray class]])
			{
				for (id regionName in comingSoonRegionNames)
				{
					if ([regionName isKindOfClass:[NSString class]])
					{
						AWSRegion region =  [AWSRegions regionForName:(NSString *)regionName];

						if (region != AWSRegion_Invalid)
						{
							[comingSoonRegionNumbers addObject:@(region)];
						}
					}
				}
			}

			// clean up the identityProviders
			NSDictionary* supportedProviders =  [dict objectForKey:@"identityProviders"];
			NSMutableArray<NSDictionary *> *supportedProviderInfo =
			[NSMutableArray arrayWithCapacity:supportedProviders.count];

			if ([supportedProviders isKindOfClass:[NSArray class]])
			{
				for (id dict in supportedProviders)
				{
					if ([dict isKindOfClass:[NSDictionary class]])
					{
						NSMutableDictionary* newDict = [dict mutableCopy];

						NSString* eTag64 = newDict[@"eTag_64x64"];
						eTag64 = [eTag64 stringByReplacingOccurrencesOfString:@"\"" withString:@""];
						if(eTag64)
  							newDict[@"eTag_64x64"] = eTag64;

						NSString* eTag_signin = newDict[@"eTag_signin"];
						eTag_signin = [eTag_signin stringByReplacingOccurrencesOfString:@"\"" withString:@""];
						if(eTag_signin)
							newDict[@"eTag_signin"] = eTag_signin;

						[supportedProviderInfo addObject:newDict];
 					}
				}
			}

			NSDictionary* appleIap =  [dict objectForKey:@"appleIap"];

			if(supportedRegionNumbers.count
			   || supportedProviderInfo.count
			   || comingSoonRegionNumbers.count
			   || appleIap.count)
			{
				configInfo = [NSMutableDictionary dictionary];

				if (supportedRegionNumbers.count)
				{
					configInfo[kSupportedConfigurations_Key_AWSRegions] = supportedRegionNumbers;
				}

				if (comingSoonRegionNumbers.count)
				{
					configInfo[kSupportedConfigurations_Key_AWSRegions_ComingSoon] = comingSoonRegionNumbers;
				}

				if (supportedProviderInfo.count)
				{
					configInfo[kSupportedConfigurations_Key_Providers] = supportedProviderInfo;
				}

				if (appleIap.count)
				{
					configInfo[kSupportedConfigurations_Key_AppleIAP] = appleIap;
				}
			}
		}
		return configInfo;
	}};

	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		AWSRegion region = AWSRegion_Master;
		NSString *stage = DEFAULT_AWS_STAGE;

		NSString *path = @"/config";
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";

		// Send request

		NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
		NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

		NSURLSessionDataTask *task =
		[session dataTaskWithRequest:request
				   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
		{
			NSInteger statusCode = response.httpStatusCode;

			NSDictionary* config = nil;

			if (!error && (statusCode == 200) && (data.length > 0))
			{
				config = ParseResponse(data);
				if (config)
				{
					NSTimeInterval timeout = (60 * 60 * 1); // 1 hour

					ZDCCachedResponse *cachedResponse = [[ZDCCachedResponse alloc] initWithData:data timeout:timeout];

					YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
					[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

						[transaction setObject:cachedResponse forKey:requestKey inCollection:kZDCCollection_CachedResponse];
					}];
				}
			}
			InvokeCompletionBlocks(config, error);
		}];

		[task resume];
	}};

	__block NSData *cachedResponseData = nil;

	YapDatabaseConnection *roConnection = zdc.databaseManager.roDatabaseConnection;
	[roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {

		ZDCCachedResponse *cachedResponse =
			[transaction objectForKey:requestKey inCollection:kZDCCollection_CachedResponse];

		cachedResponseData = cachedResponse.data;

	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{

		NSDictionary *cachedConfig = nil;

		if (cachedResponseData)
		{
			cachedConfig = ParseResponse(cachedResponseData);
		}

		if (cachedConfig)
		{
			InvokeCompletionBlocks(cachedConfig, nil);
		}
		else
		{
			requestBlock();
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Account Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)setupAccountForLocalUser:(ZDCLocalUser *)localUser
								withAuth:(ZDCLocalUserAuth *)auth
								 zAppIDs:(NSArray<NSString*> *)zAppIDs
					  completionQueue:(nullable dispatch_queue_t)completionQueue
					  completionBlock:(void (^)(NSString *_Nullable bucket,
														 NSString *_Nullable stage,
														 NSString *_Nullable syncedSalt,
														 NSDate *_Nullable activationDate,
														 NSError *_Nullable error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(localUser != nil);
	NSParameterAssert(auth != nil);
	NSParameterAssert(zAppIDs.count > 0);
	
	NSParameterAssert(localUser.auth0_primary != nil);            // User not configured properly
	NSParameterAssert(localUser.aws_region != AWSRegion_Invalid); // User not configured properly
	
	NSParameterAssert(auth.aws_accessKeyID != nil); // Need this to sign request
	NSParameterAssert(auth.aws_secret != nil);      // Need this to sign request
	NSParameterAssert(auth.aws_session != nil);     // Need this to sign request
	
	// Create JSON for request
	
	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:4];
	
	jsonDict[@"app_id"] = zAppIDs[0];
	jsonDict[@"auth0_id"] = localUser.auth0_primary;
	jsonDict[@"region"] = [AWSRegions shortNameForRegion:localUser.aws_region];
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
	
	// Generate request
	
	AWSRegion requestRegion = AWSRegion_Master; // Activation always goes through Oregon
	
	NSString *awsStage = localUser.aws_stage;
	if (!awsStage)
	{
		awsStage = DEFAULT_AWS_STAGE;
	}

	NSString *path = @"/activation/setup";
	NSURLComponents *urlComponents = [self apiGatewayForRegion:requestRegion stage:awsStage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;
	
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	[AWSSignature signRequest: request
	               withRegion: requestRegion
	                  service: AWSService_APIGateway
	              accessKeyID: auth.aws_accessKeyID
	                   secret: auth.aws_secret
	                  session: auth.aws_session];
	
#if DEBUG && robbie_hanson
	DDLogDonut(@"%@", [request zdcDescription]);
#endif
	
	// Send request
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest:request
	             completionHandler:^(NSData *data, NSURLResponse *response, NSError *sessionError)
	{
		NSString *bucket = nil;
		NSString *syncedSalt = nil;
		NSString *stage = nil;
		NSDate   *activationDate = nil;
		NSError *error = sessionError;
		
		if (!error && response && data)
		{
			NSInteger statusCode = response.httpStatusCode;
			
			NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
			if ([json isKindOfClass:[NSDictionary class]])
			{
				if ((statusCode >= 200) && (statusCode < 300))
				{
					// Success response from server
					
					id value = json[@"bucket"];
					if ([value isKindOfClass:[NSString class]]) {
						bucket = (NSString *)value;
					}
					
					value = json[@"stage"];
					if ([value isKindOfClass:[NSString class]]) {
						stage = (NSString *)value;
					}
					
					value = json[@"salt"];
					if ([value isKindOfClass:[NSString class]]) {
						syncedSalt = (NSString *)value;
					}
					
					// process activationDate
					value = json[@"created"];
					if ([value isKindOfClass:[NSNumber class]]) {
						// Javascript Dates are in milliseconds since unix epoch, UTC.
						
						NSTimeInterval seconds = [value doubleValue] / 1000.0;
						activationDate = [NSDate dateWithTimeIntervalSince1970:seconds];
					}
				}
				else
				{
					// Error response from server
					
					NSString *domain = [NSError domainForClass:[self class]];
					error = [NSError errorWithDomain:domain code:statusCode userInfo:json];
				}
			}
		}
		
		if (!error && !bucket)
		{
			NSString *description = @"Server returned unparsable response.";
			error = [NSError errorWithClass:[self class] code:1000 description:description];
		}
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(bucket, stage, syncedSalt, activationDate, error);
			}});
		}
	}];
	
	[task resume];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)registerPushTokenForLocalUser:(ZDCLocalUser *)localUser
                      completionQueue:(dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	NSParameterAssert(localUser != nil);
	
	localUser = [localUser copy];
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUser.uuid
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
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUser.uuid];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		AWSRegion region = userInfo.region;
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/registerPushToken";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSString *zAppID = zdc.zAppID;
		NSString *platform;
		#if TARGET_OS_IPHONE
		  #if DEBUG
		    platform = @"iOS-dev";
		  #else
		    platform = @"iOS-prod";
		  #endif
		#else
		  #if DEBUG
		    platform = @"macOS-dev";
		  #else
		    platform = @"macOS-prod";
		  #endif
		#endif
		
		NSDictionary* bodyDict = @{
			@"app_id"     : zAppID,
			@"platform"   : platform,
			@"push_token" : localUser.pushToken
		};
		
		NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = bodyData;
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request zdcDescription]);
	#endif
		
		NSURLSessionDataTask *task =
		[session dataTaskWithRequest: request
		              uploadProgress: nil
		            downloadProgress: nil
		           completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{
					completionBlock(response, responseObject, error);
				});
			}
		}];
		
		[task resume];
	}];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)unregisterPushToken:(NSString *)pushToken
                  forUserID:(NSString *)userID
                     region:(AWSRegion)region
            completionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSURLResponse *response, NSError *error))completionBlock
{
	DDLogAutoTrace();
	NSParameterAssert(pushToken != nil);
	NSParameterAssert(userID != nil);
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	// Generate request
	
	if (region == AWSRegion_Invalid)
		region = AWSRegion_US_West_2;
	
	NSString *stage = DEFAULT_AWS_STAGE;
	
	NSString *path = @"/unregisterPushToken";
	NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
	
	NSString *platform;
	#if TARGET_OS_IPHONE
	  #if DEBUG
	    platform = @"iOS-dev";
	  #else
	    platform = @"iOS-prod";
	  #endif
	#else
	  #if DEBUG
	    platform = @"macOS-dev";
	  #else
	    platform = @"macOS-prod";
	  #endif
	#endif
	
	NSDictionary* bodyDict = @{
		@"user_id"    : userID,
		@"push_token" : pushToken,
		@"platform"   : platform,
	};
	
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = bodyData;
	
#if DEBUG && robbie_hanson
	DDLogDonut(@"%@", [request s4Description]);
#endif
	
	NSURLSessionDataTask *task =
	[session dataTaskWithRequest:request
	          completionHandler:^(NSData *data, NSURLResponse *response, NSError *sessionError)
	{
		NSUInteger statusCode = response.httpStatusCode;
		DDLogRed(@"/unregisterPushToken => %lu", (unsigned long)statusCode);
		
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{
				completionBlock(response, sessionError);
			});
		}
	}];
	
	[task resume];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Users
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchInfoForLocalUser:(ZDCLocalUser *)localUser
                     withAuth:(ZDCLocalUserAuth *)auth
              completionQueue:(dispatch_queue_t)completionQueue
              completionBlock:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(auth != nil);
	NSParameterAssert(auth.aws_accessKeyID != nil); // Need this to sign request
	NSParameterAssert(auth.aws_secret != nil);      // Need this to sign request
	NSParameterAssert(auth.aws_session != nil);     // Need this to sign request
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	// Generate request
	
	AWSRegion region = AWSRegion_Master; // Activation always goes through Oregon
	
	NSString *stage = localUser.aws_stage;
	if (!stage)
	{
		stage = DEFAULT_AWS_STAGE;
	}
	
	NSString *path = @"/users/info";
	
	NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"GET";
	
	[AWSSignature signRequest:request
	               withRegion:region
	                  service:AWSService_APIGateway
	              accessKeyID:auth.aws_accessKeyID
	                   secret:auth.aws_secret
	                  session:auth.aws_session];
	
#if DEBUG && robbie_hanson
	DDLogDonut(@"%@", [request s4Description]);
#endif
	
	// Send request
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest:request
	             completionHandler:^(NSData *data, NSURLResponse *response, NSError *sessionError)
	{
		NSMutableDictionary *json = nil;
		NSError *error = sessionError;
		
		if (!error)
		{
			if (data.length == 0)
				error = [NSError errorWithClass:[self class] code:[response httpStatusCode] description:@"Not Found"];
			else
				json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
		}
		
		if (json && !error)
		{
			NSString *errorMessage = json[@"message"];
			if (errorMessage)
			{
				NSUInteger statusCode = [json[@"statusCode"] unsignedIntegerValue];
				error = [NSError errorWithClass:[self class] code:statusCode description:errorMessage];
			}
		}
		
		if (!json && !error)
		{
			error = [NSError errorWithClass:[self class] code:500 description:@"Invalid response from server"];
		}
		
		if (json && !error)
		{
			NSDate* (^ConvertToDate)(id) = ^NSDate* (id value){
				
				NSDate *date = nil;
				
				if ([value isKindOfClass:[NSNumber class]])
				{
					// Javascript Dates are in milliseconds since unix epoch, UTC.
					
					NSTimeInterval seconds = [value doubleValue] / 1000.0;
					date = [NSDate dateWithTimeIntervalSince1970:seconds];
				}
				
				return date;
			};
			
			// Convert values to NSDate for convenience.
			
			NSArray<NSString *> *keysToConvert = @[@"created", @"trial_start", @"trial_end"];
			for (NSString *key in keysToConvert)
			{
				json[key] = ConvertToDate(json[key]);
			}
  
 			// Add implicit dates (if missing)
			
			if (json[@"trial_start"] == nil) {
				json[@"trial_start"] = json[@"created"];
			}
			
			if (json[@"trial_end"] == nil) {
				json[@"trial_end"] = [json[@"trial_start"] dateByAddingTimeInterval:(60 * 60 * 24 * 14)];
			}
		}
		
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(json, error);
			}});
		}
	}];
	
	[task resume];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchInfoForRemoteUserID:(NSString *)remoteUserID
                     requesterID:(NSString *)localUserID
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(remoteUserID != nil);
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(completionBlock != nil);
	
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			dispatch_async(completionQueue, ^{
				completionBlock(nil, error);
			});
			return;
		}
		
		// Generate request
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		AWSRegion region = AWSRegion_Master; // Activation always goes through Oregon
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}

		NSString *path = @"/users/info/";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];

		NSURLQueryItem *user_id = [NSURLQueryItem queryItemWithName:@"user_id" value:remoteUserID];
		NSURLQueryItem *check_archive = [NSURLQueryItem queryItemWithName:@"check_archive" value:@"1"];
		urlComponents.queryItems = @[ user_id, check_archive ];

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
	
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
	
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request zdcDescription]);
	#endif
		
		// Send request
	
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			NSError *jsonError = nil;
			NSDictionary *jsonDict = nil;
			
			if ([responseObject isKindOfClass:[NSDictionary class]])
			{
				jsonDict = (NSDictionary *)responseObject;
			}
			else if ([responseObject isKindOfClass:[NSData class]])
			{
				jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&jsonError];
			}
			
			if (jsonDict && !error)
			{
				NSString *errorMessage = jsonDict[@"message"];
				if (errorMessage)
				{
					NSUInteger statusCode = [jsonDict[@"statusCode"] unsignedIntegerValue];
					jsonError = [NSError errorWithClass:[self class] code:statusCode description:errorMessage];
				}
			}
			
			if (!jsonDict && !error && !jsonError)
			{
				error = [NSError errorWithClass:[self class] code:500 description:@"Invalid response from server"];
			}
			
			if (error || jsonError)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(nil, (error ?: jsonError));
				}});
			}
			else
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(jsonDict, nil);
				}});
			}
		}];
		
		[task resume];
	}];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchUserExists:(NSString *)userID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(BOOL exists, NSError *_Nullable error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(userID != nil);
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	// Generate request
	
	AWSRegion region = AWSRegion_Master; // Account status always goes through Oregon
	NSString *stage = DEFAULT_AWS_STAGE;
	
	NSString *path = [NSString stringWithFormat:@"/users/exists/%@", userID];
	
	NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"GET";
	
#if DEBUG && robbie_hanson
	DDLogDonut(@"%@", [request s4Description]);
#endif
	
	// Send request
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest:request
	             completionHandler:^(NSData *data, NSURLResponse *response, NSError *sessionError)
	{
		NSMutableDictionary *json = nil;
		NSError *error = sessionError;
		
		if (!error)
		{
			json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
		}
		
		BOOL validResponse = NO;
		BOOL exists = NO;
		
		if (json)
		{
			id value = json[@"exists"];
			
			if ([value isKindOfClass:[NSNumber class]])
			{
				validResponse = YES;
				exists = [(NSNumber *)value boolValue];
			}
			else if ([value isKindOfClass:[NSString class]])
			{
				validResponse = YES;
				exists = [(NSString *)value boolValue];
			}
		}
		
		if (!error && !validResponse)
		{
			error = [NSError errorWithClass:[self class] code:500 description:@"Invalid response from server"];
		}
		
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(exists, error);
			}});
		}
	}];
	
	[task resume];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Priv/Pub Key
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)uploadPrivKey:(NSData *)privKey
               pubKey:(NSData *)pubKey
         forLocalUser:(ZDCLocalUser *)user
             withAuth:(ZDCLocalUserAuth *)auth
      completionQueue:(dispatch_queue_t)completionQueue
      completionBlock:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(privKey.length > 0);
	NSParameterAssert(pubKey.length > 0);
	
	NSParameterAssert(user.aws_region != AWSRegion_Invalid); // Need this to create request
	NSParameterAssert(user.aws_bucket != nil);               // Need this to create request
	
	NSParameterAssert(auth.aws_accessKeyID != nil); // Need this to sign request
	NSParameterAssert(auth.aws_secret != nil);      // Need this to sign request
	NSParameterAssert(auth.aws_session != nil);     // Need this to sign request
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	void (^InvokeCompletionBlock)(NSData*, NSURLResponse*, NSError*) =
		^(NSData *data, NSURLResponse *response, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(data, response, error);
			}});
		}
	};
	
	// Create JSON for request
	
	NSError *jsonError = nil;
	NSDictionary *jsonDict = @{
		@"privKey" : [privKey base64EncodedStringWithOptions:0],
		@"pubKey"  : [pubKey base64EncodedStringWithOptions:0]
	};
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&jsonError];
	if (jsonError)
	{
		InvokeCompletionBlock(nil, nil, jsonError);
		return;
	}
    
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	AWSRegion region = user.aws_region;
	NSString *stage = user.aws_stage;
	if (!stage)
	{
		stage = DEFAULT_AWS_STAGE;
	}

	// Generate request
	
	NSString *path = @"/users/privPubKey";
	
	NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;

	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
         
	[AWSSignature signRequest:request
	               withRegion:user.aws_region
	                  service:AWSService_APIGateway
	              accessKeyID:auth.aws_accessKeyID
	                   secret:auth.aws_secret
	                  session:auth.aws_session];
         
#if DEBUG // && robbie_hanson
	DDLogDonut(@"%@", [request zdcDescription]);
#endif
	
	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest:request
	             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		InvokeCompletionBlock(data, response, error);
	}];
	
	[task resume];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)updatePubKeySigs:(NSData *)pubKey
          forLocalUserID:(NSString *)localUserID
         completionQueue:(dispatch_queue_t)completionQueue
         completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(pubKey.length > 0);
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	void (^InvokeCompletionBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(response, responseObject, error);
			}});
		}
	};
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, nil, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		AWSRegion region = userInfo.region;
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		// Create JSON for request
		
		NSError *jsonError = nil;
		NSDictionary *jsonDict = @{
			@"pubKey": [pubKey base64EncodedStringWithOptions:0]
		};
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&jsonError];
		if (jsonError)
		{
			InvokeCompletionBlock(nil, nil,jsonError);
			return;
		}
		
		// Generate request
		
		NSString *path = @"/users/pubKeySigs";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
	#if DEBUG // && robbie_hanson
		DDLogDonut(@"%@", [request zdcDescription]);
	#endif
		
		NSURLSessionDataTask *task =
			[session uploadTaskWithRequest:request
			                      fromData:jsonData
			                      progress:nil
			             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			InvokeCompletionBlock(response, responseObject, error);
		}];
		
		[task resume];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Avatar
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)updateAvatar:(NSData *)rawAvatarData
         contentType:(NSString *)contentType
        previousETag:(NSString *)previousETag
      forLocalUserID:(NSString *)localUserID
             auth0ID:(NSString *)auth0ID
     completionQueue:(nullable dispatch_queue_t)completionQueue
     completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();

	NSParameterAssert(rawAvatarData != nil);
	NSParameterAssert(localUserID != nil);
	
	void (^InvokeCompletionBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(response, responseObject, error);
			}});
		}
	};

	NSArray *comps = [auth0ID componentsSeparatedByString:@"|"];
	NSParameterAssert(comps.count == 2);
	
	NSString *social_provider = comps[0];
	NSString *social_userID   = comps[1];
	
	if (![social_provider isEqualToString:@"auth0"])
	{
		NSError *error = [NSError errorWithClass:[self class] code:400 description:@"Invalid auth0ID"];
		
		InvokeCompletionBlock(nil, nil, error);
		return;
	}

	// Create JSON for request
	
	NSData *jsonData = nil; // nil indicates a delete
	if (rawAvatarData)
	{
		NSDictionary *jsonDict = @{
			@"avatar"       : [rawAvatarData base64EncodedStringWithOptions:0],
			@"content-type" : (contentType ?: @"image/png")
		};

		NSError *jsonError = nil;
		jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&jsonError];
		if (jsonError)
		{
			InvokeCompletionBlock(nil, nil, jsonError);
			return;
		}

		if (jsonData.length > (1024 * 1024 * 10))
		{
			NSError *error = [NSError errorWithClass:[self class] code:400 description:@"Avatar image is too big !"];

			InvokeCompletionBlock(nil, nil, error);
			return;
		}
	}

	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, nil, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		AWSRegion region = userInfo.region;
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}

		// Generate request

		NSString *path = [NSString stringWithFormat:@"/users/avatar/%@", social_userID];
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];

		if (jsonData)
		{
			request.HTTPMethod = @"POST";
			request.HTTPBody = jsonData;
			[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
 		}
		else
		{
			request.HTTPMethod = @"DELETE";
		}

		if (previousETag) {
			[request setValue:previousETag forHTTPHeaderField:@"If-Match"];
		} else {
			[request setValue:@"*" forHTTPHeaderField:@"If-None-Match"];
		}
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif

		// Are we uploading or deleting?
		if (jsonData)
		{
			NSURLSessionUploadTask *task =
			  [session uploadTaskWithRequest: request
			                        fromData: jsonData
			                        progress: nil
			               completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
			{
				InvokeCompletionBlock(response, responseObject, error);
			}];

			[task resume];
		}
		else
		{
			NSURLSessionDataTask  *task =
			[session dataTaskWithRequest: request
			              uploadProgress: nil
			            downloadProgress: nil
			           completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
			{
				InvokeCompletionBlock(response, responseObject, error);
			}];

			[task resume];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sync
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (NSMutableURLRequest *)multipartComplete:(NSString *)key
                              withUploadID:(NSString *)uploadID
                                     eTags:(NSArray<NSString*> *)eTags
                                  inBucket:(NSString *)bucket
                                    region:(AWSRegion)region
                            forLocalUserID:(NSString *)localUserID
                                  withAuth:(ZDCLocalUserAuth *)auth
{
	__block ZDCLocalUser *localUser = nil;
	YapDatabaseConnection *roConnection = zdc.databaseManager.roDatabaseConnection;
	[roConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		
		ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		if ([user isKindOfClass:[ZDCLocalUser class]]) {
			localUser = (ZDCLocalUser *)user;
		}
	}];
	
	NSString *stage = localUser.aws_stage;
	if (!stage)
	{
		stage = DEFAULT_AWS_STAGE;
	}
	
	NSString *path = @"/multipartComplete";
	
	NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	
	NSDictionary *jsonDict = @{
		@"bucket"      : bucket,
		@"staging_path": key,
		@"upload_id"   : uploadID,
		@"parts"       : eTags
	};
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
	
	request.HTTPBody = jsonData;
	
	// macOS will automatically add the following incorrect HTTP header:
	// Content-Type: application/x-www-form-urlencoded
	//
	// So we explicitly set it here.
	
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	[AWSSignature signRequest:request
	               withRegion:region
	                  service:AWSService_APIGateway // custom server API
	              accessKeyID:auth.aws_accessKeyID
	                   secret:auth.aws_secret
	                  session:auth.aws_session];
	
	return request;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (NSMutableURLRequest *)listProxyWithPaths:(NSArray<NSString *> *)paths
                                  appPrefix:(NSString *)appPrefix
                                     pullID:(NSString *)pullID
                             continuationID:(NSString *)continuationID
                         continuationOffset:(NSNumber *)continuationOffset
                          continuationToken:(NSString *)continuationToken
                                   inBucket:(NSString *)bucket
                                     region:(AWSRegion)region
                             forLocalUserID:(NSString *)localUserID
                                   withAuth:(ZDCLocalUserAuth *)auth
{
	__block ZDCLocalUser *localUser = nil;
	[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		if ([user isKindOfClass:[ZDCLocalUser class]]) {
			localUser = (ZDCLocalUser *)user;
		}
	}];
	
	NSString *stage = localUser.aws_stage;
	if (!stage)
	{
		stage = DEFAULT_AWS_STAGE;
	}
	
	NSString *path = @"/listProxy";
	
	NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	
	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:16];
	
	jsonDict[@"file_paths"] = paths;
	jsonDict[@"app_prefix"] = appPrefix;
	jsonDict[@"device_key"] = pullID;
	jsonDict[@"bucket"]     = bucket;
	
	if (continuationID) {
		jsonDict[@"continuation_id"] = continuationID;
	}
	if (continuationOffset) {
		jsonDict[@"continuation_offset"] = continuationOffset;
	}
	if (continuationToken) {
		jsonDict[@"continuation_token"] = continuationToken;
	}
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
	
	request.HTTPBody = jsonData;
	
	// macOS will automatically add the following incorrect HTTP header:
	// Content-Type: application/x-www-form-urlencoded
	//
	// So we explicitly set it here.
	
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	[AWSSignature signRequest:request
	               withRegion:region
	                  service:AWSService_APIGateway
	              accessKeyID:auth.aws_accessKeyID
	                   secret:auth.aws_secret
	                  session:auth.aws_session];
	
	return request;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)lostAndFound:(NSString *)cloudID
              bucket:(NSString *)bucket
              region:(AWSRegion)region
         requesterID:(NSString *)localUserID
     completionQueue:(nullable dispatch_queue_t)completionQueue
     completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(cloudID != nil);
	NSParameterAssert(bucket != nil);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(localUserID != nil);
	
	void (^InvokeCompletionBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(response, responseObject, error);
			}});
		}
	};
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, nil, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}

		// Generate request

		NSString *path = @"/lostAndFound";
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:16];
		
		jsonDict[@"bucket"]  = bucket;
		jsonDict[@"file_id"] = cloudID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		request.HTTPBody = jsonData;
		
		// macOS will automatically add the following incorrect HTTP header:
		// Content-Type: application/x-www-form-urlencoded
		//
		// So we explicitly set it here.
		//
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
		NSURLSessionDataTask *task =
			[session dataTaskWithRequest: request
			              uploadProgress: nil
			            downloadProgress: nil
			           completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			InvokeCompletionBlock(response, responseObject, error);
		}];

		[task resume];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth0
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchAuth0ProfileForLocalUserID:(NSString*) localUserID
					  completionQueue:(dispatch_queue_t)completionQueue
					  completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock

{

	void (^InvokeCompletionBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(response, responseObject, error);
			}});
		}
	};

	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, nil, error);
			return;
		}

		NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
		AFURLSessionManager *session = [[AFURLSessionManager alloc] initWithSessionConfiguration:sessionConfig];

		// What region do we use ?
		//
		// Technically, any region should work.
		// That is, we can perform the HTTP request from any AWS region we're running in.
		// However, there are financial costs to consider.
		// Amazon will charge us for the outgoing bandwidth.
		//
		// Interestingly, it appears that auth0 is itself running within AWS.
		// And they appear to have setup our account in us-west-2.
		// So there's a chance AWS won't charge us for outgoing bandwidth if our query doesn't leave their datacenter.
		//
		// Thus we're going to always direct the query to the us-west-2 center.
		
		AWSRegion region = AWSRegion_Master;
		NSString *stage = DEFAULT_AWS_STAGE;

		NSString *path = [NSString stringWithFormat:@"/auth0/fetch/%@", localUserID];

		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		[request setHTTPMethod:@"GET"];

		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];

		NSURLSessionDataTask *task =
			[session dataTaskWithRequest: request
			              uploadProgress: nil
			            downloadProgress: nil
			           completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			InvokeCompletionBlock(response, responseObject, error);
		}];

		[task resume];
	}];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchFilteredAuth0Profile:(NSString *)remoteUserID
                      requesterID:(NSString *)localUserID
                  completionQueue:(dispatch_queue_t)completionQueue
                  completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	remoteUserID = [remoteUserID copy]; // mutable string protection
	localUserID = [localUserID copy];   // mutable string protection
	
	void (^InvokeCompletionBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(response, responseObject, error);
			}});
		}
	};
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, nil, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		// What region do we use ?
		//
		// Technically, any region should work.
		// That is, we can perform the HTTP request from any AWS region we're running in.
		// However, there are financial costs to consider.
		// Amazon will charge us for the outgoing bandwidth.
		//
		// Interestingly, it appears that auth0 is itself running within AWS.
		// And they appear to have setup our account in us-west-2.
		// So there's a chance AWS won't charge us for outgoing bandwidth if our query doesn't leave their datacenter.
		//
		// Thus we're going to always direct the query to the us-west-2 center.
		
		AWSRegion region = AWSRegion_Master;
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}

		NSString *path = [NSString stringWithFormat:@"/auth0/fetch/%@", remoteUserID];
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		[request setHTTPMethod:@"GET"];
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			InvokeCompletionBlock(response, responseObject, error);
		}];
		
		[task resume];
	}];
}

- (void)searchUserMatch:(NSString *)queryString
               provider:(nullable NSString *)providerString
                 zAppID:(NSString *)zAppID
            requesterID:(NSString *)localUserID
        completionQueue:(dispatch_queue_t)completionQueue
        completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	queryString = [queryString copy];
	localUserID = [localUserID copy];
	zAppID      = [zAppID copy];
	
	void (^InvokeCompletionBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(response, responseObject, error);
			}});
		}
	};
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(nil, nil, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		// What region do we use ?
		//
		// Technically, any region should work.
		// That is, we can perform the HTTP request from any AWS region we're running in.
		// However, there are financial costs to consider.
		// Amazon will charge us for the outgoing bandwidth.
		//
		// Interestingly, it appears that auth0 is itself running within AWS.
		// And they appear to have setup our account in us-west-2.
		// So there's a chance AWS won't charge us for outgoing bandwidth if our query doesn't leave their datacenter.
		//
		// Thus we're going to always direct the query to the us-west-2 center.
		
		AWSRegion region = AWSRegion_Master;
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}

		NSString *path = @"/auth0/search";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		// Currently this method only support sending a query that matches based on the name.
		// However the server also supports limiting the search to a particular social provider.
		//

		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];

		jsonDict[@"query"]    = queryString;
		jsonDict[@"provider"] = providerString.length ? providerString : @"*";
		jsonDict[@"app_id"]   = zAppID;

		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];

		NSURL *url = [urlComponents URL];

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;


//		NSURLQueryItem *name = [NSURLQueryItem queryItemWithName:@"query" value:queryString];
//		NSURLQueryItem *provider = [NSURLQueryItem queryItemWithName:@"provider" value:
//									providerString.length?providerString:@"*"];
//
//		urlComponents.queryItems = @[ name, provider ];
//		
//		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
//		[request setHTTPMethod:@"GET"];
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_APIGateway
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			InvokeCompletionBlock(response, responseObject, error);
		}];
		
		[task resume];
	}];
}

/**
 * See header file for description.
 */
- (void)linkAuth0ID:(NSString *)linkAuth0ID
       toRecoveryID:(NSString *)recoveryAuth0ID
            forUser:(NSString *)inLocalUserID
    completionQueue:(nullable dispatch_queue_t)completionQueue
    completionBlock:(nullable void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{
					completionBlock(nil, nil, error);
				});
			}
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		// What region do we use ?
		//
		// Technically, any region should work.
		// That is, we can perform the HTTP request from any AWS region we're running in.
		// However, there are financial costs to consider.
		// Amazon will charge us for the outgoing bandwidth.
		//
		// Interestingly, it appears that auth0 is itself running within AWS.
		// And they appear to have setup our account in us-west-2.
		// So there's a chance AWS won't charge us for outgoing bandwidth if our query doesn't leave their datacenter.
		//
		// Thus we're going to always direct the query to the us-west-2 center.
		//
		AWSRegion region = AWSRegion_Master;
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/auth0/linkRecovery";
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];
		
		jsonDict[@"auth0_id"] = recoveryAuth0ID;
		jsonDict[@"link"]     = linkAuth0ID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		
		NSURL *url = [urlComponents URL];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			if (error) {
				NSLog(@"linkAuth0ID: error: %@", error);
			}
			else {
				NSLog(@"linkAuth0ID: %ld: %@", (long)response.httpStatusCode, responseObject);
			}
			
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(response, responseObject, error);
				}});
			}
		}];
		
		[task resume];
	}];
}

/**
 * Uses the server API to link a secondary Auth0 ID to the user's auth0 identity.
**/
- (void)linkAuth0ID:(NSString *)linkAuth0ID
            forUser:(ZDCLocalUser *)localUser
    completionQueue:(dispatch_queue_t)completionQueue
    completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();
	
	NSString *localUserID = localUser.uuid;
	NSString *auth0ID = localUser.auth0_primary;

	if (!auth0ID)
	{
		if (completionBlock)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSString *desc = @"Internal error, primary user ID Not Found";
				NSError *error = [NSError errorWithClass:[self class] code:0 description:desc];
				
				completionBlock(nil, nil, error);
			});
		}
		return;
	}
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if (completionBlock)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					completionBlock(nil, nil, error);
				});
			}
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		// What region do we use ?
		//
		// Technically, any region should work.
		// That is, we can perform the HTTP request from any AWS region we're running in.
		// However, there are financial costs to consider.
		// Amazon will charge us for the outgoing bandwidth.
		//
		// Interestingly, it appears that auth0 is itself running within AWS.
		// And they appear to have setup our account in us-west-2.
		// So there's a chance AWS won't charge us for outgoing bandwidth if our query doesn't leave their datacenter.
		//
		// Thus we're going to always direct the query to the us-west-2 center.
		
		AWSRegion region = AWSRegion_Master;
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/auth0/linkIdentity";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];
		
		jsonDict[@"auth0_id"] = auth0ID;
		jsonDict[@"link"] = linkAuth0ID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_APIGateway
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			if (error) {
				NSLog(@"linkAuth0ID: error: %@", error);
			}
			else {
				NSLog(@"linkAuth0ID: %ld: %@", (long)response.httpStatusCode, responseObject);
			}
			
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(response, responseObject, error);
				}});
			}
		}];
		
		[task resume];
	}];
}

- (void)unlinkAuth0ID:(NSString *)unlinkAuth0ID
              forUser:(ZDCLocalUser *)localUser
      completionQueue:(dispatch_queue_t)completionQueue
      completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();
	
	NSString *localUserID = localUser.uuid;
	NSString *auth0ID = localUser.auth0_primary;

	if(!auth0ID)
	{
		if (completionBlock)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSString *desc = @"Internal error, primary user ID Not Found";
				NSError *error = [NSError errorWithClass:[self class] code:0 description:desc];
				
				completionBlock(nil, nil, error);
			});
		}
		return;
	}
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if (completionBlock)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					completionBlock(nil, nil, error);
				});
			}
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		// What region do we use ?
		//
		// Technically, any region should work.
		// That is, we can perform the HTTP request from any AWS region we're running in.
		// However, there are financial costs to consider.
		// Amazon will charge us for the outgoing bandwidth.
		//
		// Interestingly, it appears that auth0 is itself running within AWS.
		// And they appear to have setup our account in us-west-2.
		// So there's a chance AWS won't charge us for outgoing bandwidth if our query doesn't leave their datacenter.
		//
		// Thus we're going to always direct the query to the us-west-2 center.
		
		AWSRegion region = AWSRegion_Master;
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/auth0/unlinkIdentity";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];
		jsonDict[@"auth0_id"] = auth0ID;
		jsonDict[@"unlink"] = unlinkAuth0ID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_APIGateway
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
						 completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			if (error) {
				NSLog(@"unlinkAuth0ID: error: %@", error);
			}
			else {
				NSLog(@"unlinkAuth0ID: %ld: %@", (long)response.httpStatusCode, responseObject);
			}
			
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(response, responseObject, error);
				}});
			}
		}];
		
		[task resume];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Billing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)productPurchasedByUser:(NSString *)inLocalUserID
			 productIdentifier:(NSString *)productIdentifier
		 transactionIdentifier:(NSString *)transactionIdentifier
			   appStoreReceipt:(NSData 	*) appStoreReceipt
			   completionQueue:(nullable dispatch_queue_t)inCompletionQueue
			   completionBlock:(void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))inCompletionBlock
{
	DDLogAutoTrace();

	NSParameterAssert(inLocalUserID != nil);
	NSParameterAssert(productIdentifier != nil);
	NSParameterAssert(appStoreReceipt != nil);
 
//	DDLogRed(@"productPurchasedByUser %@",  [appStoreReceipt base64EncodedStringWithOptions:0]);

	NSString *localUserID = [inLocalUserID copy]; // mutable string protection

	if (!inCompletionBlock)
		return;

	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();

	NSString *requestKey = [NSString stringWithFormat:@"%@|%@|%@",
							NSStringFromSelector(_cmd), localUserID, transactionIdentifier];


	NSUInteger requestCount =
	[asyncCompletionDispatch pushCompletionQueue:inCompletionQueue
								 completionBlock:inCompletionBlock
										  forKey:requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	void (^InvokeCompletionBlocks)(NSURLResponse*, id, NSError*) = ^(NSURLResponse *response, id responseObject, NSError *error) {

		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
									completionBlocks:&completionBlocks
											  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSURLResponse *response, id responseObject, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(response, responseObject,error);
			}});
		}
	};

	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlocks(nil, nil, error);
			return;
		}

		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;

		AWSRegion region = AWSRegion_Master; // Payment always goes through Oregon

		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}

		// Create JSON for request
		NSDictionary *jsonDict = @{
			@"type"         : @"apple",
			@"receipt_data" : [appStoreReceipt base64EncodedStringWithOptions:0]
		};
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];

		NSString *path = @"/payment/oneTime";

		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;

		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	#if DEBUG
		DDLogDonut(@"%@", [request zdcDescription]);
	#endif
		
		// Send request
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];

		NSURLSessionDataTask *task =
			[session dataTaskWithRequest: request
			              uploadProgress: nil
			            downloadProgress: nil
			           completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			InvokeCompletionBlocks(response, responseObject,error);
		}];

		[task resume];
	}];
}


/**
 * Queries the server to see if the user has transitioned from "free trial user" to "paying customer".
 *
 * Note: The server also sends a push notification for this change.
 * But if push notifications are disabled, this method should be consulted on-demand.
**/
- (void)fetchIsCustomer:(NSString *)inLocalUserID
        completionQueue:(nullable dispatch_queue_t)inCompletionQueue
        completionBlock:(void (^)(BOOL isPayingCustomer, NSError *_Nullable error))inCompletionBlock
{
	DDLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	if (!inCompletionBlock)
		return;
	
	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();
	
	NSString *requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), localUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue:inCompletionQueue
	                               completionBlock:inCompletionBlock
	                                        forKey:requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	void (^InvokeCompletionBlocks)(BOOL, NSError*) = ^(BOOL result, NSError *error) {
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
		                            completionBlocks:&completionBlocks
		                                      forKey:requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(BOOL result, NSError *error) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(result, error);
			}});
		}
	};
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlocks(NO, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		AWSRegion region = AWSRegion_Master; // Payment always goes through Oregon
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/payment/isCustomer";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_APIGateway
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		// Send request
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			NSDictionary *jsonDict = nil;
			
			if ([responseObject isKindOfClass:[NSDictionary class]])
			{
				jsonDict = (NSDictionary *)responseObject;
			}
			else if ([responseObject isKindOfClass:[NSData class]])
			{
				jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
			}
			
			BOOL isPayingCustomer = NO;
			if (jsonDict)
			{
				id value = jsonDict[@"is_customer"];
				
				if ([value isKindOfClass:[NSNumber class]])
					isPayingCustomer = [(NSNumber *)value boolValue];
				else if ([value isKindOfClass:[NSString class]])
					isPayingCustomer = [(NSString *)value boolValue];
			}
			
			InvokeCompletionBlocks(isPayingCustomer, error);
		}];
		
		[task resume];
	}];
}

/**
 * Queries the server for the current balance of the user.
 *
 * Note: The server also sends a push notification for this change.
 * But if push notifications are disabled, this method should be consulted on-demand.
**/
- (void)fetchCurrentBalance:(NSString *)inLocalUserID
            completionQueue:(nullable dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(double credit, NSError *_Nullable error))inCompletionBlock
{
	DDLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	if (!inCompletionBlock)
		return;
	
	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();
	
	NSString *requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), localUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue:inCompletionQueue
	                               completionBlock:inCompletionBlock
	                                        forKey:requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	void (^InvokeCompletionBlocks)(double, NSError*) = ^(double credit, NSError *error) {
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
		                            completionBlocks:&completionBlocks
		                                      forKey:requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(double credit, NSError *error) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(credit, error);
			}});
		}
	};
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlocks(0.0, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		AWSRegion region = AWSRegion_Master; // Payment always goes through Oregon
		
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/payment/balance";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_APIGateway
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		// Send request
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			NSDictionary *jsonDict = nil;
			
			if ([responseObject isKindOfClass:[NSDictionary class]])
			{
				jsonDict = (NSDictionary *)responseObject;
			}
			else if ([responseObject isKindOfClass:[NSData class]])
			{
				jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
			}
			
			double credit = 0.0;
			if (jsonDict)
			{
				id value = jsonDict[@"balance"];
				
				if ([value isKindOfClass:[NSNumber class]])
					credit = [value doubleValue];
				else if ([value isKindOfClass:[NSString class]])
					credit = [value doubleValue];
			}
			
			InvokeCompletionBlocks(credit, error);
		}];
		
		[task resume];
	}];
}

/**
 * Queries the server for the user's billing info.
 * 
 * The result will include billing & usage information for the user's account,
 * as well as detailed information on a per-app basis.
**/
- (void)fetchCurrentBilling:(NSString *)inLocalUserID
            completionQueue:(dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(NSDictionary *billing, NSError *error))inCompletionBlock
{
	DDLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	if (!inCompletionBlock)
		return;
	
	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();
	
	NSString *requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), localUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue:inCompletionQueue
	                               completionBlock:inCompletionBlock
	                                        forKey:requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	void (^InvokeCompletionBlocks)(NSDictionary*, NSError*) = ^(NSDictionary *response, NSError *error) {
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
		                            completionBlocks:&completionBlocks
		                                      forKey:requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSDictionary *response, NSError *error) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(response, error);
			}});
		}
	};
	
	__block NSDictionary *billing_last;
	dispatch_sync(billing_queue, ^{
		
		billing_last = billing_history[localUserID];
	});
	
	NSString *xIfModifiedSince = nil;
	
	if (billing_last)
	{
		// Notes:
		//
		// billing_month is 0-based (javascript).
		// now_month is 1-based (NSCalendar).
		//
		// billing_offset is in hours (from UTC).
		// This should be zero for AWS.
		
		NSUInteger billing_year  = [billing_last[@"metadata"][@"year"] unsignedIntegerValue];
		NSUInteger billing_month = [billing_last[@"metadata"][@"month"] unsignedIntegerValue] + 1;
		
		NSUInteger billing_offset = [billing_last[@"metadata"][@"timezoneOffset"] unsignedIntegerValue];
		
		NSDate *now = [NSDate date];
		
		NSCalendar *calendar = [NSCalendar currentCalendar];
		calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:(billing_offset * 60 * 60)];
		
		NSUInteger now_year  = [calendar component:NSCalendarUnitYear fromDate:now];
		NSUInteger now_month = [calendar component:NSCalendarUnitMonth fromDate:now];
		
		if ((billing_year == now_year) && (billing_month == now_month))
		{
			id value = billing_last[@"metadata"][@"lastChange"];
			
			if ([value isKindOfClass:[NSNumber class]])
				xIfModifiedSince = [(NSNumber *)value stringValue];
			else if ([value isKindOfClass:[NSString class]])
				xIfModifiedSince = (NSString *)value;
		}
	}
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlocks(nil, error);
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		AWSRegion region = userInfo.region;
		NSString *stage = userInfo.stage;
		if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		
		NSString *path = @"/billing/usage";
		
		NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
		
		urlComponents.queryItems = @[
		  [NSURLQueryItem queryItemWithName:@"v" value:@"1"]
		];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
		if (xIfModifiedSince)
		{
			[request setValue:xIfModifiedSince forHTTPHeaderField:@"X-If-Modified-Since"];
		}
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		[AWSSignature signRequest:request
		               withRegion:region
		                  service:AWSService_APIGateway
		              accessKeyID:auth.aws_accessKeyID
		                   secret:auth.aws_secret
		                  session:auth.aws_session];
		
		// Send request
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			NSInteger statusCode = response.httpStatusCode;
			
			NSDictionary *jsonDict = nil;
			
			if (statusCode == 304)
			{
				// No change since our last fetch.
				
				jsonDict = billing_last;
			}
			else
			{
				if ([responseObject isKindOfClass:[NSDictionary class]])
				{
					jsonDict = (NSDictionary *)responseObject;
				}
				else if ([responseObject isKindOfClass:[NSData class]])
				{
					jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
				}
				
				// Cache result in memory.
				// This helps us reduce lambda processing time & bandwidth usage.
				// 
				dispatch_sync(billing_queue, ^{
					
					billing_history[localUserID] = jsonDict;
				});
			}
			
			// Update response with "monthlyEstimate" values.
			//
			NSDictionary *billing = [self calculateMonthlyInfoForBilling:jsonDict user:localUserID];
			
			InvokeCompletionBlocks(billing, error);
		}];
		
		[task resume];
	}];
}

/**
 *
**/
- (void)fetchPreviousBilling:(NSString *)inLocalUserID
                    withYear:(int)year
                       month:(int)month
             completionQueue:(nullable dispatch_queue_t)inCompletionQueue
             completionBlock:(void (^)(NSDictionary *billing, NSError *error))inCompletionBlock
{
	DDLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	if (!inCompletionBlock)
		return;
	
	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();
	
	NSString *requestKey = [NSString stringWithFormat:@"%@|%@|%d|%d",
	                          NSStringFromSelector(_cmd), localUserID, year, month];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue:inCompletionQueue
	                               completionBlock:inCompletionBlock
	                                        forKey:requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	void (^InvokeCompletionBlocks)(NSDictionary*, NSError*) = ^(NSDictionary *response, NSError *error) {
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
		                            completionBlocks:&completionBlocks
		                                      forKey:requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSDictionary *response, NSError *error) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(response, error);
			}});
		}
	};
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
	
		[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
		                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
		                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		#if TARGET_OS_IPHONE
			AFURLSessionManager *session = sessionInfo.foregroundSession;
		#else
			AFURLSessionManager *session = sessionInfo.session;
		#endif
			ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
			
			AWSRegion region = userInfo.region;
			NSString *stage = userInfo.stage;
			if (!stage)
			{
				stage = DEFAULT_AWS_STAGE;
			}
			
			NSString *path = @"/billing/usage";
			
			NSURLComponents *urlComponents = [self apiGatewayForRegion:region stage:stage path:path];
			
			urlComponents.queryItems = @[
			  [NSURLQueryItem queryItemWithName:@"v" value:@"1"],
			  [NSURLQueryItem queryItemWithName:@"year" value:[NSString stringWithFormat:@"%d", year]],
			  [NSURLQueryItem queryItemWithName:@"month" value:[NSString stringWithFormat:@"%d", month]]
			];
			
			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
			[request setHTTPMethod:@"GET"];
			
		#if DEBUG && robbie_hanson
			DDLogDonut(@"%@", [request s4Description]);
		#endif
			
			[AWSSignature signRequest:request
			               withRegion:region
			                  service:AWSService_APIGateway
			              accessKeyID:auth.aws_accessKeyID
			                   secret:auth.aws_secret
			                  session:auth.aws_session];
			
			// Send request
			
			NSURLSessionDataTask *task =
			  [session dataTaskWithRequest: request
			                uploadProgress: nil
			              downloadProgress: nil
			             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
			{
				NSDictionary *jsonDict = nil;
				
				if ([responseObject isKindOfClass:[NSDictionary class]])
				{
					jsonDict = (NSDictionary *)responseObject;
				}
				else if ([responseObject isKindOfClass:[NSData class]])
				{
					jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
				}
				
				if (jsonDict)
				{
					BOOL isFinalized = [jsonDict[@"metadata"][@"final"] boolValue];
					if (isFinalized)
					{
						// Cache result in database.
						// This helps us reduce lambda processing time & bandwidth usage.
						
						NSData *data = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
						NSTimeInterval timeout = (60 * 60 * 24 * 30); // 30 days
						
						ZDCCachedResponse *cachedResponse = [[ZDCCachedResponse alloc] initWithData:data timeout:timeout];
						
						YapDatabaseConnection *rwDatabaseConnection = zdc.databaseManager.rwDatabaseConnection;
						[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
							
							[transaction setObject:cachedResponse forKey:requestKey inCollection:kZDCCollection_CachedResponse];
						}];
					}
				}
				
				NSDictionary *billing = [self calculateMonthlyInfoForBilling:jsonDict user:localUserID];
				InvokeCompletionBlocks(billing, error);
			}];
			
			[task resume];
		}];
	}};
	
	__block NSData *cachedResponseData = nil;
	
	[zdc.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCCachedResponse *cachedResponse =
		  [transaction objectForKey:requestKey inCollection:kZDCCollection_CachedResponse];
		
		cachedResponseData = cachedResponse.data;
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
		
		NSDictionary *jsonDict = nil;
		
		if (cachedResponseData)
		{
			jsonDict = [NSJSONSerialization JSONObjectWithData:cachedResponseData options:0 error:nil];
		}
		
		if (jsonDict)
		{
			NSDictionary *billing = [self calculateMonthlyInfoForBilling:jsonDict user:localUserID];
			InvokeCompletionBlocks(billing, nil);
		}
		else
		{
			requestBlock();
		}
	}];
}

/**
 * The billing object is broken into sections:
 * - totals
 * - apps
 * 
 * This method calculates & adds the following to each section:
 *
 * - accumulatedStorageBytes
 * - accumulatedBandwidthBytes
 * - accumulatedStorageCost
 * - accumulatedBandwidthCost
 * - accumulatedOtherCost
 * - accumulatedOtherCost_S3
 * - accumulatedOtherCost_Lambda
 * - accumulatedOtherCost_SNS
 * - accumulatedDiscount
 * - accumulatedTotalCost
 * 
 * - estimatedStorageBytes
 * - estimatedBandwidthBytes
 * - estimatedStorageCost
 * - estimatedBandwidthCost
 * - estimatedOtherCost
 * - estimatedOtherCost_S3
 * - estimatedOtherCost_Lambda
 * - estimatedOtherCost_SNS
 * - estimatedDiscount
 * - estimatedTotalCost
 * 
 * - finalStorageBytes
 * - finalBandwidthBytes
 * - finalStorageCost
 * - finalBandwidthCost
 * - finalOtherCost      (S3 get/put & lambda)
 * - finalOtherCost_S3
 * - finalOtherCost_Lambda
 * - finalOtherCost_SNS
 * - finalDiscount
 * - finalTotalCost
**/
- (NSDictionary *)calculateMonthlyInfoForBilling:(NSDictionary *)inBilling user:(NSString *)localUserID
{
	DDLogAutoTrace();
	
	if (inBilling == nil) return nil;
	
	NSMutableDictionary *billing = [inBilling deepCopyWithOptions:S4DeepCopy_MutableContainers];
	
	if (billing == nil) return nil;
	
	// At the very end of the month, the hourly cron job sets a "final: true" flag in the metadata section.
	
	NSUInteger version = 0;
	
	NSUInteger year = 0;
	NSUInteger month = 0;
	NSUInteger timezoneOffset = 0;
	
	BOOL isFinalized = NO;
	
	NSDictionary *metadata = billing[@"metadata"];
	if (metadata)
	{
		version = [metadata[@"version"] unsignedIntegerValue];
		
		year = [metadata[@"year"] unsignedIntegerValue];
		month = [metadata[@"month"] unsignedIntegerValue];
		timezoneOffset = [metadata[@"timezoneOffset"] unsignedIntegerValue];
		
		isFinalized = [metadata[@"final"] boolValue];
	}
	
	NSDateComponents *dateComponents = [[NSDateComponents alloc] init];
	dateComponents.year = year;
	dateComponents.month = (month + 1); // Javascript: 0-based, NSDateComponents: 1-based
	dateComponents.day = 1;
	dateComponents.hour = 0;
	dateComponents.minute = 0;
	dateComponents.second = 0;
	dateComponents.nanosecond = 0;
	
	NSCalendar *calendar = [NSCalendar currentCalendar];
	calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:(timezoneOffset * 60)];
	
	NSDate *beginningOfMonth = [calendar dateFromComponents:dateComponents];
	NSDate *endOfMonth = [calendar dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:beginningOfMonth options:0];
	
	uint64_t ts_beginningOfMonth = (uint64_t)([beginningOfMonth timeIntervalSince1970] * 1000);
	uint64_t ts_endOfMonth = (uint64_t)([endOfMonth timeIntervalSince1970] * 1000);
	
	uint64_t ts_monthSpan = ts_endOfMonth - ts_beginningOfMonth;
	
	double hours_in_month = ts_monthSpan / (1000 * 60 * 60);
	
	NSDictionary *rates = billing[@"rates"];
	
	const uint64_t KB_in_bytes  = 1000;
	const uint64_t MB_in_bytes  = 1000 * KB_in_bytes;
	const uint64_t GB_in_bytes  = 1000 * MB_in_bytes;
	const uint64_t TB_in_bytes  = 1000 * GB_in_bytes;
	const uint64_t PB_in_bytes  = 1000 * TB_in_bytes;
	
	const uint64_t KiB_in_bytes  = 1024;
	const uint64_t MiB_in_bytes  = 1024 * KiB_in_bytes;
	const uint64_t GiB_in_bytes  = 1024 * MiB_in_bytes;
	const uint64_t TiB_in_bytes  = 1024 * GiB_in_bytes;
	const uint64_t PiB_in_bytes  = 1024 * TiB_in_bytes;
	
	typedef NS_ENUM(NSInteger, PrefixType) {
		PrefixType_Unknown,
		PrefixType_Binary,
		PrefixType_Decimal
	};
	
	PrefixType (^valueToPrefixType)(id) = ^PrefixType (id value) {
		
		if ([value isKindOfClass:[NSNumber class]]) {
			return PrefixType_Unknown;
		}
		
		if (![value isKindOfClass:[NSString class]]) {
			return PrefixType_Unknown;
		}
		
		NSString *str = (NSString *)value;
		
		if ([str isEqualToString:@"∞"])
			return PrefixType_Unknown;
		
		NSArray<NSString *> *split = [str componentsSeparatedByString:@" "];
		
		if (split.count == 1)
		{
			return PrefixType_Unknown;
		}
		else
		{
			NSString *type = split[1];
			
			if ([type hasPrefix:@"KB"]) { return PrefixType_Decimal; } // "KB", "KBM"
			if ([type hasPrefix:@"MB"]) { return PrefixType_Decimal; }
			if ([type hasPrefix:@"GB"]) { return PrefixType_Decimal; }
			if ([type hasPrefix:@"TB"]) { return PrefixType_Decimal; }
			if ([type hasPrefix:@"PB"]) { return PrefixType_Decimal; }
			
			if ([type hasPrefix:@"KiB"]) { return PrefixType_Binary; } // "KiB", "KiBM"
			if ([type hasPrefix:@"MiB"]) { return PrefixType_Binary; }
			if ([type hasPrefix:@"GiB"]) { return PrefixType_Binary; }
			if ([type hasPrefix:@"TiB"]) { return PrefixType_Binary; }
			if ([type hasPrefix:@"PiB"]) { return PrefixType_Binary; }
			
			return PrefixType_Unknown;
		}
	};
	
	double (^valueToDouble)(id) = ^double (id value){
		
		if ([value isKindOfClass:[NSNumber class]]) {
			return [(NSNumber *)value doubleValue];
		}
		
		if (![value isKindOfClass:[NSString class]]) {
			return 0.0;
		}
		
		NSString *str = (NSString *)value;
		
		if ([str isEqualToString:@"∞"])
			return UINT64_MAX;
		
		NSArray<NSString *> *split = [str componentsSeparatedByString:@" "];
		
		// Caution: commas break strtoull function.
		// strtoull("10,000", NULL, 10) => 10 !
		//
		NSString *numStr = [split[0] stringByReplacingOccurrencesOfString:@"," withString:@""];
		uint64_t number = strtoull([numStr UTF8String], NULL, 10);
		
		if (split.count == 1)
		{
			return number;
		}
		else
		{
			uint64_t multiplier = 1;
			NSString *type = split[1];
			
			     if ([type isEqualToString:@"KB"]) { multiplier =  KB_in_bytes; }
			else if ([type isEqualToString:@"MB"]) { multiplier =  MB_in_bytes; }
			else if ([type isEqualToString:@"GB"]) { multiplier =  GB_in_bytes; }
			else if ([type isEqualToString:@"TB"]) { multiplier =  TB_in_bytes; }
			else if ([type isEqualToString:@"PB"]) { multiplier =  PB_in_bytes; }
			
			else if ([type isEqualToString:@"KiB"]) { multiplier =  KiB_in_bytes; }
			else if ([type isEqualToString:@"MiB"]) { multiplier =  MiB_in_bytes; }
			else if ([type isEqualToString:@"GiB"]) { multiplier =  GiB_in_bytes; }
			else if ([type isEqualToString:@"TiB"]) { multiplier =  TiB_in_bytes; }
			else if ([type isEqualToString:@"PiB"]) { multiplier =  PiB_in_bytes; }
			
			return number * multiplier;
		}
	};
	
	PrefixType (^calculatePrefixType)(NSDictionary *) = ^NSInteger (NSDictionary *rateContainer) {

		NSArray *flat_pricing  = rateContainer[@"flat"];
		NSArray *range_pricing = rateContainer[@"range"];

		if (flat_pricing)
		{
			// [price_per_unit, unit_size]
			//
			// Examples:
			// - [0.004, 10000] => 0.4 cents per 10,000 => So 5,000 would cost 0.2 cents (i.e. $0.002)
			// - [0.50, 1000000] => 50 cents per 1 million = > So 100 would cost $0.00005
			
			id unit_size = flat_pricing[1];
			
			PrefixType prefix_type;
			
			if ((prefix_type = valueToPrefixType(unit_size)) != PrefixType_Unknown) {
				return prefix_type;
			}
		}
		else if (range_pricing)
		{
			// [
			//   [price_per_unit, unit_size, first_range_size],
			//   [price_per_unit, unit_size, second_range_size],
			//   ...
			// ]
			
			for (NSArray *range in range_pricing)
			{
				id unit_size  = range[1];
				id range_size = range[2];
			
				PrefixType prefix_type;
				
				if ((prefix_type = valueToPrefixType(unit_size)) != PrefixType_Unknown) {
					return prefix_type;
				}
				
				if ((prefix_type = valueToPrefixType(range_size)) != PrefixType_Unknown) {
					return prefix_type;
				}
			}
		}

		return PrefixType_Unknown;
	};
	
	double (^calculateServiceCost)(double, NSDictionary *) = ^double (double value, NSDictionary *rateContainer){
		
		NSArray *flat_pricing  = rateContainer[@"flat"];
		NSArray *range_pricing = rateContainer[@"range"];
		
		if (flat_pricing)
		{
			// [price_per_unit, unit_size]
			//
			// Examples:
			// - [0.004, 10000] => 0.4 cents per 10,000 => So 5,000 would cost 0.2 cents (i.e. $0.002)
			// - [0.50, 1000000] => 50 cents per 1 million = > So 100 would cost $0.00005
			
			double price_per_unit = valueToDouble(flat_pricing[0]);
			double unit_size      = valueToDouble(flat_pricing[1]);
			
			return ((value / unit_size) * price_per_unit);
		}
		else if (range_pricing)
		{
			// [
			//   [price_per_unit, unit_size, first_range_size],
			//   [price_per_unit, unit_size, second_range_size],
			//   ...
			// ]
			//
			// Example: (bandwidth)
			//
			// [0.09,  "1 GB", "10 TB"],
			// [0.085, "1 GB", "40 TB"],
			// [0.070, "1 GB", "100 TB"],
			// [0.050, "1 GB", "∞"]
			//
			// Translation:
			// - The first 10 terabytes of bandwidth are charged a 9 cents per gigabyte.
			// - After that, the next 40 terabytes of bandwidth are charged at 8.5 cents per gigabyte.
			//   In other words, the range: 10 TB - 50 TB
			// - After that, the next 100 terabytes of bandwidth are charged at 7 cents per gigabyte.
			//   In other words, the range: 50 TB - 150 TB
			// - After that, every gigabyte is charged at 5 cents per gigabyte.
			//   In other words, the range: 150 TB - Infinity
			
			double cost = 0.0;
			NSUInteger range_index = 0;
			
			while (value > 0)
			{
				NSArray *range = range_pricing[range_index];
				
				double price_per_unit = valueToDouble(range[0]);
				double unit_size      = valueToDouble(range[1]);
				double range_size     = valueToDouble(range[2]);
				
				if (value > range_size)
				{
					cost += ((range_size / unit_size) * price_per_unit);
					value -= range_size;
				}
				else
				{
					cost += ((value / unit_size) * price_per_unit);
					value = 0;
				}
				
				range_index++;
			}
			
			return cost;
		}
		else
		{
			return 0.0;
		}
	};
	
	void (^calculateMonthlyInfo)(NSMutableDictionary *) = ^(NSMutableDictionary *item){ @autoreleasepool {
		
		if (item == nil) return;
		
		NSDictionary * rate_s3_storage          = rates[@"s3"][@"gigabyteMonths"];
		if (!rate_s3_storage) rate_s3_storage   = rates[@"s3"][@"byteHours"];      // Old server name
		
		NSDictionary * rate_s3_getCount         = rates[@"s3"][@"getCount"];
		NSDictionary * rate_s3_putCount         = rates[@"s3"][@"putCount"];
		NSDictionary * rate_sns_publishCount    = rates[@"sns"][@"publishCount"];
		NSDictionary * rate_sns_mobilePushCount = rates[@"sns"][@"mobilePushCount"];
		NSDictionary * rate_lambda_requestCount = rates[@"lambda"][@"requestCount"];
		NSDictionary * rate_lambda_millisCount  = rates[@"lambda"][@"millisCount"];
		NSDictionary * rate_bandwidth_byteCount = rates[@"bandwidth"][@"byteCount"];
		
		double item_s3_byteHours = 0;
		double item_s3_byteCount = 0;
		
		if (version == 0)
		{
			item_s3_byteHours += valueToDouble(item[@"s3"][@"byteHours"]);
			item_s3_byteCount += valueToDouble(item[@"s3"][@"byteCount"]);
		}
		else
		{
			NSDictionary *storage_items   = item[@"s3"][@"storage"];
			NSDictionary *multipart_items = item[@"s3"][@"multipart"];
			
			for (NSString *storage_type in storage_items)
			{
				item_s3_byteHours += valueToDouble(storage_items[storage_type][@"byteHours"]);
				item_s3_byteCount += valueToDouble(storage_items[storage_type][@"byteCount"]);
			}
			
			for (NSString *multipart_id in multipart_items)
			{
				item_s3_byteHours += valueToDouble(multipart_items[multipart_id][@"byteHours"]);
				item_s3_byteCount += valueToDouble(multipart_items[multipart_id][@"byteCount"]);
			}
			
			// Simplify process for UI.
			
			item[@"s3"][@"byteCount"] = @(item_s3_byteCount);
		}
		
		double item_s3_getCount         = valueToDouble(item[@"s3"][@"getCount"]);
		double item_s3_putCount         = valueToDouble(item[@"s3"][@"putCount"]);
		double item_sns_publishCount    = valueToDouble(item[@"sns"][@"publishCount"]);
		double item_sns_mobilePushCount = valueToDouble(item[@"sns"][@"mobilePushCount"]);
		double item_lambda_requestCount = valueToDouble(item[@"lambda"][@"requestCount"]);
		double item_lambda_millisCount  = valueToDouble(item[@"lambda"][@"millisCount"]);
		double item_bandwidth_byteCount = valueToDouble(item[@"bandwidth"][@"byteCount"]);
		
		if (isFinalized)
		{
			double finalGBMonths         = 0.0;
			double finalStorageCost      = 0.0;
			double finalBandwidthCost    = 0.0;
			double finalOtherCost_S3     = 0.0;
			double finalOtherCost_Lambda = 0.0;
			double finalOtherCost_SNS    = 0.0;
			double finalOtherCost        = 0.0;
			double finalDiscount         = 0.0;
			double finalTotalCost        = 0.0;
			
			finalGBMonths = item_s3_byteHours / hours_in_month / GB_in_bytes; // always in decimal for macOS/iOS
			
			if (item[@"cost_storage"])
			{
				finalStorageCost = [item[@"cost_storage"] doubleValue];
			}
			else
			{
				double GxB_months = 0;
				if (calculatePrefixType(rate_s3_storage) == PrefixType_Binary) {
					GxB_months = item_s3_byteHours / hours_in_month / GiB_in_bytes;
				}
				else {
					GxB_months = item_s3_byteHours / hours_in_month / GB_in_bytes;
				}
				
				finalStorageCost += calculateServiceCost(GxB_months, rate_s3_storage);
			}
			
			if (item[@"cost_bandwidth"]) {
				finalBandwidthCost = [item[@"cost_bandwidth"] doubleValue];
			}
			else {
				finalBandwidthCost = calculateServiceCost(item_bandwidth_byteCount, rate_bandwidth_byteCount);
			}
			
			finalOtherCost_S3 += calculateServiceCost(item_s3_getCount, rate_s3_getCount);
			finalOtherCost_S3 += calculateServiceCost(item_s3_putCount, rate_s3_putCount);
			
			finalOtherCost_Lambda += calculateServiceCost(item_lambda_requestCount, rate_lambda_requestCount);
			finalOtherCost_Lambda += calculateServiceCost(item_lambda_millisCount,  rate_lambda_millisCount);
			
			finalOtherCost_SNS += calculateServiceCost(item_sns_publishCount,    rate_sns_publishCount);
			finalOtherCost_SNS += calculateServiceCost(item_sns_mobilePushCount, rate_sns_mobilePushCount);
			
			if (item[@"cost_other"]) {
				finalOtherCost = [item[@"cost_other"] doubleValue];
			}
			else {
				finalOtherCost = finalOtherCost_S3 + finalOtherCost_Lambda + finalOtherCost_SNS;
			}
			
			NSDictionary *discounts = item[@"discounts"];
			if ([discounts isKindOfClass:[NSDictionary class]])
			{
				for (NSNumber *value in discounts.objectEnumerator)
				{
					if ([value isKindOfClass:[NSNumber class]])
					{
						finalDiscount += [value doubleValue];
					}
				}
			}
			
			if (item[@"cost"]) {
				finalTotalCost = [item[@"cost"] doubleValue];
			}
			else {
				finalTotalCost = finalStorageCost + finalBandwidthCost + finalOtherCost;
			}
			
			item[@"finalStorageBytes"]     = @(finalGBMonths * GB_in_bytes);
			item[@"finalBandwidthBytes"]   = @(item_bandwidth_byteCount);
			
			item[@"finalStorageCost"]      = @(finalStorageCost);
			item[@"finalBandwidthCost"]    = @(finalBandwidthCost);
			item[@"finalOtherCost"]        = @(finalOtherCost);
			item[@"finalOtherCost_S3"]     = @(finalOtherCost_S3);
			item[@"finalOtherCost_Lambda"] = @(finalOtherCost_Lambda);
			item[@"finalOtherCost_SNS"]    = @(finalOtherCost_SNS);
			item[@"finalDiscount"]         = @(finalDiscount);
			item[@"finalTotalCost"]        = @(finalTotalCost);
		}
		else
		{
			uint64_t ts = [item[@"timestamp"] unsignedIntegerValue];
			
			item[@"startingTimestamp"] = @(ts_beginningOfMonth);
			item[@"endingTimestamp"]   = @(ts_endOfMonth);
			
			int64_t elapsed   = (int64_t)(ts - ts_beginningOfMonth);
			int64_t remaining = (int64_t)(ts_endOfMonth - ts);
			
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wambiguous-macro"
			elapsed   = CLAMP(0, elapsed,   (int64_t)ts_monthSpan); // careful: casting is required !
			remaining = CLAMP(0, remaining, (int64_t)ts_monthSpan); // careful: casting is required !
		#pragma clang pop
			
			item[@"elapsedTime"]   = @(elapsed);
			item[@"remainingTime"] = @(remaining);
			
			double accumulatedGBMonths         = 0.0;
			double accumulatedStorageCost      = 0.0;
			double accumulatedBandwidthCost    = 0.0;
			double accumulatedOtherCost_S3     = 0.0;
			double accumulatedOtherCost_Lambda = 0.0;
			double accumulatedOtherCost_SNS    = 0.0;
			double accumulatedOtherCost        = 0.0;
			double accumulatedDiscount         = 0.0;
			double accumulatedTotalCost        = 0.0;
			
			accumulatedGBMonths = item_s3_byteHours / hours_in_month / GB_in_bytes; // always in decimal for macOS/iOS
			
			if (item[@"cost_storage"])
			{
				accumulatedStorageCost = [item[@"cost_storage"] doubleValue];
			}
			else
			{
				double accumulated_GxB_months;
				if (calculatePrefixType(rate_s3_storage) == PrefixType_Binary) {
					accumulated_GxB_months = item_s3_byteHours / hours_in_month / GiB_in_bytes;
				}
				else {
					accumulated_GxB_months = item_s3_byteHours / hours_in_month / GB_in_bytes;
				}
				
				accumulatedStorageCost = calculateServiceCost(accumulated_GxB_months, rate_s3_storage);
			}
			
			if (item[@"cost_bandwidth"]) {
				accumulatedBandwidthCost = [item[@"cost_bandwidth"] doubleValue];
			}
			else {
				accumulatedBandwidthCost = calculateServiceCost(item_bandwidth_byteCount, rate_bandwidth_byteCount);
			}
			
			accumulatedOtherCost_S3 += calculateServiceCost(item_s3_getCount, rate_s3_getCount);
			accumulatedOtherCost_S3 += calculateServiceCost(item_s3_putCount, rate_s3_putCount);
			
			accumulatedOtherCost_Lambda += calculateServiceCost(item_lambda_requestCount, rate_lambda_requestCount);
			accumulatedOtherCost_Lambda += calculateServiceCost(item_lambda_millisCount,  rate_lambda_millisCount);
			
			accumulatedOtherCost_SNS += calculateServiceCost(item_sns_publishCount,    rate_sns_publishCount);
			accumulatedOtherCost_SNS += calculateServiceCost(item_sns_mobilePushCount, rate_sns_mobilePushCount);
			
			if (item[@"cost_other"]) {
				accumulatedOtherCost = [item[@"cost_other"] doubleValue];
			}
			else {
				accumulatedOtherCost = accumulatedOtherCost_S3 + accumulatedOtherCost_Lambda + accumulatedOtherCost_SNS;
			}
			
			if (item[@"cost"]) {
				accumulatedTotalCost = [item[@"cost"] doubleValue];
			}
			else {
				accumulatedTotalCost = accumulatedStorageCost + accumulatedBandwidthCost + accumulatedOtherCost;
			}
			
			item[@"accumulatedStorageBytes"]     = @(accumulatedGBMonths * GB_in_bytes);
			item[@"accumulatedBandwidthBytes"]   = @(item_bandwidth_byteCount);
			
			item[@"accumulatedStorageCost"]      = @(accumulatedStorageCost);
			item[@"accumulatedBandwidthCost"]    = @(accumulatedBandwidthCost);
			item[@"accumulatedOtherCost_S3"]     = @(accumulatedOtherCost_S3);
			item[@"accumulatedOtherCost_Lambda"] = @(accumulatedOtherCost_Lambda);
			item[@"accumulatedOtherCost_SNS"]    = @(accumulatedOtherCost_SNS);
			item[@"accumulatedOtherCost"]        = @(accumulatedOtherCost);
			item[@"accumulatedDiscount"]         = @(accumulatedDiscount);
			item[@"accumulatedTotalCost"]        = @(accumulatedTotalCost);
			
			// Project current usage patterns to the end of the month.
			
			double remaining_hours = (double)remaining / (double)(1000 * 60 * 60);
			
			double remaining_s3_byteHours = item_s3_byteCount * remaining_hours;
			double estimated_s3_byteHours = item_s3_byteHours + remaining_s3_byteHours;
			
			double multiplier = 1.0 + ((double)remaining / (double)elapsed);
			
			double estimated_s3_getCount         = item_s3_getCount         * multiplier;
			double estimated_s3_putCount         = item_s3_putCount         * multiplier;
			double estimated_sns_publishCount    = item_sns_publishCount    * multiplier;
			double estimated_sns_mobilePushCount = item_sns_mobilePushCount * multiplier;
			double estimated_lambda_requestCount = item_lambda_requestCount * multiplier;
			double estimated_lambda_millisCount  = item_lambda_millisCount  * multiplier;
			double estimated_bandwidth_byteCount = item_bandwidth_byteCount * multiplier;
			
			double estimatedGBMonths         = 0.0;
			double estimatedStorageCost      = 0.0;
			double estimatedBandwidthCost    = 0.0;
			double estimatedOtherCost_S3     = 0.0;
			double estimatedOtherCost_Lambda = 0.0;
			double estimatedOtherCost_SNS    = 0.0;
			double estimatedOtherCost        = 0.0;
			double estimatedDiscount         = 0.0;
			double estimatedTotalCost        = 0.0;
			
			estimatedGBMonths = estimated_s3_byteHours / hours_in_month / GB_in_bytes; // always in decimal for macOS/iOS
			
			double estimated_GxB_months;
			if (calculatePrefixType(rate_s3_storage) == PrefixType_Binary) {
				estimated_GxB_months = estimated_s3_byteHours / hours_in_month / GiB_in_bytes;
			}
			else {
				estimated_GxB_months = estimated_s3_byteHours / hours_in_month / GB_in_bytes;
			}
			
			estimatedStorageCost += calculateServiceCost(estimated_GxB_months, rate_s3_storage);
			
			estimatedBandwidthCost += calculateServiceCost(estimated_bandwidth_byteCount, rate_bandwidth_byteCount);
			
			estimatedOtherCost_S3 += calculateServiceCost(estimated_s3_getCount, rate_s3_getCount);
			estimatedOtherCost_S3 += calculateServiceCost(estimated_s3_putCount, rate_s3_putCount);
			
			estimatedOtherCost_Lambda += calculateServiceCost(estimated_lambda_requestCount, rate_lambda_requestCount);
			estimatedOtherCost_Lambda += calculateServiceCost(estimated_lambda_millisCount,  rate_lambda_millisCount);
			
			estimatedOtherCost_SNS += calculateServiceCost(estimated_sns_publishCount,    rate_sns_publishCount);
			estimatedOtherCost_SNS += calculateServiceCost(estimated_sns_mobilePushCount, rate_sns_mobilePushCount);
			
			estimatedOtherCost = estimatedOtherCost_S3 + estimatedOtherCost_Lambda + estimatedOtherCost_SNS;
			
			estimatedTotalCost = estimatedStorageCost + estimatedBandwidthCost + estimatedOtherCost - estimatedDiscount;
			
			item[@"estimatedStorageBytes"]     = @(estimatedGBMonths * GB_in_bytes);
			item[@"estimatedBandwidthBytes"]   = @(estimated_bandwidth_byteCount);
			
			item[@"estimatedStorageCost"]      = @(estimatedStorageCost);
			item[@"estimatedBandwidthCost"]    = @(estimatedBandwidthCost);
			item[@"estimatedOtherCost_S3"]     = @(estimatedOtherCost_S3);
			item[@"estimatedOtherCost_Lambda"] = @(estimatedOtherCost_Lambda);
			item[@"estimatedOtherCost_SNS"]    = @(estimatedOtherCost_SNS);
			item[@"estimatedOtherCost"]        = @(estimatedOtherCost);
			item[@"estimatedDiscount"]         = @(estimatedDiscount);
			item[@"estimatedTotalCost"]        = @(estimatedTotalCost);
		}
	}};
	
#if DEBUG && robbie_hanson && 0
	// <screenshot_hack>
	
	void (^manipulateValue)(NSArray *, NSString *, double);
	manipulateValue = ^(NSArray *paths, NSString *op, double manipulator){ @autoreleasepool {
		
		id prvValue = nil;
		id value = billing;
		
		for (NSString *path in paths)
		{
			prvValue = value;
			value = value[path];
		}
		
		if ([value isKindOfClass:[NSNumber class]])
		{
			double oldValue = [value doubleValue];
			double newValue = oldValue;
			
			if ([op isEqualToString:@"mul"]) {
				newValue = oldValue * manipulator;
			}
			else if ([op isEqualToString:@"div"]) {
				newValue = oldValue / manipulator;
			}
			else if ([op isEqualToString:@"set"]) {
				newValue = manipulator;
			}
			
			prvValue[[paths lastObject]] = @(newValue);
		}
		
	}};
	
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"s3", @"byteCount"], @"mul", 8);
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"s3", @"byteHours"], @"mul", 8);
	
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"s3", @"getCount"], @"div", 16);
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"s3", @"putCount"], @"div", 16);
	
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"lambda", @"millisCount"], @"div", 16);
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"lambda", @"requestCount"], @"div", 16);
	
	manipulateValue(@[@"apps", @"com.4th-a.storm4", @"bandwidth", @"byteCount"], @"div", 10);
	
	// </screenshot_hack>
#endif
	
	NSMutableDictionary *totals = billing[@"totals"];
	calculateMonthlyInfo(totals);
	
	NSDictionary *apps = billing[@"apps"];
	for (NSMutableDictionary *app in [apps objectEnumerator])
	{
		calculateMonthlyInfo(app);
	}
	
	return billing;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Blockchain
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchMerkleTreeFile:(NSString *)root
                requesterID:(NSString *)localUserID
            completionQueue:(dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))inCompletionBlock
{
	DDLogAutoTrace();
	NSParameterAssert(root != nil);
	NSParameterAssert(localUserID != nil);
	
	root = [root copy];
	localUserID = [localUserID copy];
	
	if (!inCompletionBlock)
		return;
	
	if (!inCompletionQueue)
		inCompletionQueue = dispatch_get_main_queue();
	
	// rootPath sanitation
	if ([root hasPrefix:@"0x"]) {
		root = [root substringFromIndex:2];
	}
	
	NSString *rootPath = [NSString stringWithFormat:@"/%@.json", root];
	
	[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
	                                    completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{

		ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.foregroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
		urlComponents.scheme = @"https";
		urlComponents.host = @"blockchain.storm4.cloud";
		urlComponents.path = rootPath;
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
                    completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
		//	if (error) {
		//		NSLog(@"fetchBlockChainEntry: error: %@", error);
		//	}
		//	else {
		//		NSLog(@"fetchBlockChainEntry: %ld: %@", (long)response.httpStatusCode, responseObject);
		//	}
			
			if (inCompletionBlock)
			{
				dispatch_async(inCompletionQueue, ^{ @autoreleasepool {
					inCompletionBlock(response, responseObject, error);
				}});
			}
		}];
		
		[task resume];
	}];
}

#pragma clang diagnostic pop

@end
