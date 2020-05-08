/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCRestManagerPrivate.h"

#import "AWSPayload.h"
#import "AWSSignature.h"
#import "CredentialsManager.h"
#import "S3Request.h"
#import "S4DeepCopy.h"
#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCCachedResponse.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCDirectoryManager.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLocalUserAuth.h"
#import "ZDCLogging.h"
#import "ZDCUserBillPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+ZeroDark.h"
#import "NSMutableURLRequest+ZeroDark.h"
#import "NSURLRequest+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

//#ifndef robbie_hanson
//  #define robbie_hanson 1
//#endif

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelInfo | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

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
	NSMutableDictionary<NSString*, ZDCUserBill*> *billing_history;
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
#pragma mark API Gateway v0
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSString *)apiGatewayIDV0ForRegion:(AWSRegion)region stage:(NSString *)stage
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSURLComponents *)apiGatewayV0ForRegion:(AWSRegion)region stage:(NSString *)stage path:(NSString *)path
{
	NSString *apiGatewayID = [self apiGatewayIDV0ForRegion:region stage:stage];
	if (apiGatewayID == nil) {
		return nil;
	}
	
	NSString *regionStr = [AWSRegions shortNameForRegion:region];
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
#pragma mark API Gateway v1
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable NSString *)apiGatewayIDV1ForRegion:(AWSRegion)region stage:(NSString *)stage
{
	switch(region)
	{
		case AWSRegion_US_West_2:
		{
			if ([stage isEqualToString:@"dev"])  return @"j1n0wvoo16";
			if ([stage isEqualToString:@"test"]) return @"mzmbqmbwl5";
			if ([stage isEqualToString:@"prod"]) return @"xx08iqr297";
		}
		case AWSRegion_EU_West_1:
		{
			if ([stage isEqualToString:@"dev"])  return @"bdpp5w5aqg";
			if ([stage isEqualToString:@"test"]) return @"atmztx3z50";
			if ([stage isEqualToString:@"prod"]) return @"mnh0vvlszl";
		}
		default: break;
	}
	
	return nil;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable NSURLComponents *)apiGatewayV1ForRegion:(AWSRegion)region
                                              stage:(NSString *)stage
                                             domain:(ZDCDomain)domain
                                               path:(NSString *)path
{
	NSString *apiGatewayID = [self apiGatewayIDV1ForRegion:region stage:stage];
	if (apiGatewayID == nil) {
		return nil;
	}
	
	NSString *regionStr = [AWSRegions shortNameForRegion:region];
	NSString *host = [NSString stringWithFormat:@"%@.execute-api.%@.amazonaws.com", apiGatewayID, regionStr];
	
	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = host;
	
	NSString *domainStr;
	switch (domain)
	{
		case ZDCDomain_UserCoop    : domainStr = @"authdUsrCoop"; break;
		case ZDCDomain_UserPartner : domainStr = @"authdUsrPtnr"; break;
		default                    : domainStr = @"public";       break;
	}
	
	NSString *pathPrefix = [path hasPrefix:@"/"] ? @"" : @"/";
	
	urlComponents.path = [NSString stringWithFormat:@"/v1/%@%@%@", domainStr, pathPrefix, path];
	
	return urlComponents;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchCoopConfigWithCompletionQueue:(nullable dispatch_queue_t)inCompletionQueue
                           completionBlock:(void(^)(NSDictionary *_Nullable config,
                                                    NSError *_Nullable error))inCompletionBlock
{
	ZDCLogAutoTrace();

	if (!inCompletionBlock)
		return;

	NSString *requestKey = NSStringFromSelector(_cmd);

	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	void (^NotifyListeners)(NSDictionary*, NSError*) = ^(NSDictionary* config, NSError *error) {

		if (config) {
			NSParameterAssert(error == nil);
		} else {
			NSParameterAssert(error != nil);
		}
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
									completionBlocks:&completionBlocks
											  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSDictionary*, NSError*) = completionBlocks[i];

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
			NSError *jsonError = nil;
			json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
			
			if (jsonError) {
				ZDCLogError(@"Error parsing JSON: %@", jsonError);
			}
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

	dispatch_block_t PerformRequest = ^{ @autoreleasepool {
		
		AWSRegion region = AWSRegion_Master;
	//	NSString *stage = DEFAULT_AWS_STAGE;
		NSString *stage = @"dev";

		NSURLComponents *urlComponents =
		  [self apiGatewayV1ForRegion: region
		                        stage: stage
		                       domain: ZDCDomain_Public
		                         path: @"/coop/config"];

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
			
			if (config) {
				NotifyListeners(config, nil);
			} else if (error) {
				NotifyListeners(nil, error);
			} else {
				
				NSString *msg = @"Server returned unrecognized response";
				error = [NSError errorWithClass:[self class] code:500 description:msg];
				
				NotifyListeners(nil, error);
			}
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

		if (cachedResponseData) {
			cachedConfig = ParseResponse(cachedResponseData);
		}

		if (cachedConfig) {
			NotifyListeners(cachedConfig, nil);
		}
		else {
			PerformRequest();
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Account Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)setupAccountForLocalUser:(ZDCLocalUser *)localUser
								withAuth:(ZDCLocalUserAuth *)auth
								 treeIDs:(NSArray<NSString*> *)treeIDs
					  completionQueue:(nullable dispatch_queue_t)completionQueue
					  completionBlock:(void (^)(NSString *_Nullable bucket,
														 NSString *_Nullable stage,
														 NSString *_Nullable syncedSalt,
														 NSDate *_Nullable activationDate,
														 NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(localUser != nil);
	NSParameterAssert(auth != nil);
	NSParameterAssert(treeIDs.count > 0);
	
	NSParameterAssert(localUser.auth0_primary != nil);            // User not configured properly
	NSParameterAssert(localUser.aws_region != AWSRegion_Invalid); // User not configured properly
	
	NSParameterAssert(auth.aws_accessKeyID != nil); // Need this to sign request
	NSParameterAssert(auth.aws_secret != nil);      // Need this to sign request
	NSParameterAssert(auth.aws_session != nil);     // Need this to sign request
	
	// Create JSON for request
	
	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:4];
	
	jsonDict[@"app_id"] = treeIDs[0];
	jsonDict[@"auth0_id"] = localUser.auth0_primary;
	jsonDict[@"region"] = [AWSRegions shortNameForRegion:localUser.aws_region];
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
	
	// Generate request
	
	AWSRegion request_region = AWSRegion_Master; // Activation always goes through Oregon
	
	NSString *request_stage = localUser.aws_stage;
	if (!request_stage)
	{
		request_stage = DEFAULT_AWS_STAGE;
	}

	NSString *path = @"/activation/setup";
	NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:request_region stage:request_stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;
	
	[request setJSONContentTypeHeader];
	
	[AWSSignature signRequest: request
	               withRegion: request_region
	                  service: AWSService_APIGateway
	              accessKeyID: auth.aws_accessKeyID
	                   secret: auth.aws_secret
	                  session: auth.aws_session];
	
	// Send request
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest:request
	             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		NSString *bucket = nil;
		NSString *syncedSalt = nil;
		NSString *stage = nil;
		NSDate   *activationDate = nil;
		
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
					
					ZDCLogError(@"REST API Error (%ld): %@ %@ %@: %@",
						(long)statusCode, [AWSRegions shortNameForRegion:request_region], request_stage, path, json);
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)registerPushTokenForLocalUser:(ZDCLocalUser *)localUser
                      completionQueue:(dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUser != nil);
	
	localUser = [localUser copy];
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUser.uuid
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
	//	if (!stage)
		{
			stage = DEFAULT_AWS_STAGE;
		}
		stage = @"dev";
		
		NSString *path = @"/registerPushToken";
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSString *treeID = zdc.primaryTreeID;
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
		
		NSMutableDictionary *bodyDict = [NSMutableDictionary dictionaryWithCapacity:4];
		
		bodyDict[@"app_id"]     = treeID;
		bodyDict[@"tree_ids"]   = @[treeID];
		bodyDict[@"platform"]   = platform;
		bodyDict[@"push_token"] = localUser.pushToken;
		
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)unregisterPushToken:(NSString *)pushToken
                  forUserID:(NSString *)userID
                     region:(AWSRegion)region
            completionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSURLResponse *response, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
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
	NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
	
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
	
	NSMutableDictionary *bodyDict = [NSMutableDictionary dictionaryWithCapacity:3];
	
	bodyDict[@"user_id"]    = userID;
	bodyDict[@"push_token"] = pushToken;
	bodyDict[@"platform"]   = platform;
	
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = bodyData;
	
	NSURLSessionDataTask *task =
	[session dataTaskWithRequest:request
	          completionHandler:^(NSData *data, NSURLResponse *response, NSError *sessionError)
	{
		ZDCLogInfo(@"/unregisterPushToken => %lu", (unsigned long)response.httpStatusCode);
		
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchInfoForLocalUser:(ZDCLocalUser *)localUser
                     withAuth:(ZDCLocalUserAuth *)auth
              completionQueue:(dispatch_queue_t)completionQueue
              completionBlock:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
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
	
	NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"GET";
	
	[AWSSignature signRequest:request
	               withRegion:region
	                  service:AWSService_APIGateway
	              accessKeyID:auth.aws_accessKeyID
	                   secret:auth.aws_secret
	                  session:auth.aws_session];
	
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchInfoForRemoteUserID:(NSString *)remoteUserID
                     requesterID:(NSString *)localUserID
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUserID != nil);
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(completionBlock != nil);
	
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];

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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchUserExists:(NSString *)userID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(BOOL exists, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(userID != nil);
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	// Generate request
	
	AWSRegion region = AWSRegion_Master; // Account status always goes through Oregon
	NSString *stage = DEFAULT_AWS_STAGE;
	
	NSString *path = [NSString stringWithFormat:@"/users/exists/%@", userID];
	
	NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"GET";
	
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchPubKeyForUser:(ZDCUser *)user
               requesterID:(NSString *)localUserID
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(void (^)(ZDCPublicKey *_Nullable pubKey, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	[zdc.networkTools downloadDataAtPath: kZDCCloudFileName_PublicKey
	                            inBucket: user.aws_bucket
	                              region: user.aws_region
	                            withETag: nil
	                               range: nil
	                         requesterID: localUserID
	                       canBackground: NO
	                     completionQueue: completionQueue
	                     completionBlock:^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (error)
		{
			completionBlock(nil, error);
			return;
		}

		ZDCPublicKey *pubKey = nil;
		
		if ([responseObject isKindOfClass:[NSString class]])
		{
			NSString *pubKeyJSON = (NSString *)responseObject;
			pubKey = [[ZDCPublicKey alloc] initWithUserID:user.uuid pubKeyJSON:pubKeyJSON];
		}
		else if ([responseObject isKindOfClass:[NSData class]])
		{
			NSData *data = (NSData *)responseObject;
			NSString *pubKeyJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			pubKey = [[ZDCPublicKey alloc] initWithUserID:user.uuid pubKeyJSON:pubKeyJSON];
		}
		else if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *pubKeyDict = (NSDictionary *)responseObject;
			pubKey = [[ZDCPublicKey alloc] initWithUserID: user.uuid
			                                   pubKeyDict: pubKeyDict];
		}
			
		if (![pubKey checkKeyValidityWithError:nil])
		{
			error = [NSError errorWithClass:[self class] code:0 description:@"Unreadable pubKey for user"];
				
			completionBlock(nil, error);
			return;
		}
		
		completionBlock(pubKey, nil);
	}];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)uploadEncryptedPrivKey:(NSData *)privKey
                        pubKey:(NSData *)pubKey
                  forLocalUser:(ZDCLocalUser *)localUser
                      withAuth:(ZDCLocalUserAuth *)auth
               completionQueue:(dispatch_queue_t)completionQueue
               completionBlock:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(privKey.length > 0);
	NSParameterAssert(pubKey.length > 0);
	
	NSParameterAssert(localUser.aws_region != AWSRegion_Invalid); // Need this to create request
	NSParameterAssert(localUser.aws_stage != nil);                // Need this to create request
	
	void (^Notify)(NSData*, NSURLResponse*, NSError*) = ^(NSData *data, NSURLResponse *response, NSError *error) {
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
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
		Notify(nil, nil, jsonError);
		return;
	}
	
	// Fetch JWT
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	[zdc.credentialsManager refreshJWTCredentials: auth
	                                      forUser: localUser
	                              completionQueue: bgQueue
	                              completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			Notify(nil, nil, error);
			return;
		}
		
		NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
		NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
		
		// Generate request
		
		BOOL isCoop;
		NSString *jwt;
		
		if (auth.coop_jwt) {
			isCoop = YES;
			jwt = auth.coop_jwt;
		} else {
			isCoop = NO;
			jwt = auth.partner_jwt;
		}
		
		NSURLComponents *urlComponents =
			[self apiGatewayV1ForRegion: localUser.aws_region
			                      stage: localUser.aws_stage
			                     domain: isCoop ? ZDCDomain_UserCoop : ZDCDomain_UserPartner
			                       path: @"/users/privPubKey"];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setJSONContentTypeHeader];
		[request setBearerAuthorization:jwt];
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest:request
		             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
		{
			Notify(data, response, error);
		}];
	
		[task resume];
	}];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)updatePubKeySigs:(NSData *)pubKey
          forLocalUserID:(NSString *)localUserID
         completionQueue:(dispatch_queue_t)completionQueue
         completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
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
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setJSONContentTypeHeader];
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)updateAvatar:(NSData *)rawAvatarData
         contentType:(NSString *)contentType
        previousETag:(NSString *)previousETag
      forLocalUserID:(NSString *)localUserID
             auth0ID:(NSString *)auth0ID
     completionQueue:(nullable dispatch_queue_t)completionQueue
     completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();

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

	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];

		if (jsonData)
		{
			request.HTTPMethod = @"POST";
			request.HTTPBody = jsonData;
			[request setJSONContentTypeHeader];
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
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
	
	NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
	
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
	
	[request setJSONContentTypeHeader];
	
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSMutableURLRequest *)listProxyWithPaths:(NSArray<NSString *> *)paths
                                     treeID:(NSString *)treeID
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
	
	NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	
	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:16];
	
	jsonDict[@"file_paths"] = paths;
	jsonDict[@"app_prefix"] = treeID;
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
	
	[request setJSONContentTypeHeader];
	
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)lostAndFound:(NSString *)cloudID
              bucket:(NSString *)bucket
              region:(AWSRegion)region
         requesterID:(NSString *)localUserID
     completionQueue:(nullable dispatch_queue_t)completionQueue
     completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
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
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
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
		[request setJSONContentTypeHeader];
		
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

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
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

	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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

		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];

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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchFilteredAuth0Profile:(NSString *)remoteUserID
                      requesterID:(NSString *)localUserID
                  completionQueue:(dispatch_queue_t)completionQueue
                  completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
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
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)searchUserMatch:(NSString *)queryString
               provider:(nullable NSString *)providerString
                 treeID:(NSString *)treeID
            requesterID:(NSString *)localUserID
        completionQueue:(dispatch_queue_t)completionQueue
        completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	queryString = [queryString copy];
	localUserID = [localUserID copy];
	treeID      = [treeID copy];
	
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
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		// Currently this method only support sending a query that matches based on the name.
		// However the server also supports limiting the search to a particular social provider.
		//

		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];

		jsonDict[@"query"]    = queryString;
		jsonDict[@"provider"] = providerString.length ? providerString : @"*";
		jsonDict[@"app_id"]   = treeID;

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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)linkAuth0ID:(NSString *)linkAuth0ID
       toRecoveryID:(NSString *)recoveryAuth0ID
            forUser:(NSString *)inLocalUserID
    completionQueue:(nullable dispatch_queue_t)completionQueue
    completionBlock:(nullable void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];
		
		jsonDict[@"auth0_id"] = recoveryAuth0ID;
		jsonDict[@"link"]     = linkAuth0ID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		
		NSURL *url = [urlComponents URL];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setJSONContentTypeHeader];
		
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
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)linkAuth0ID:(NSString *)linkAuth0ID
            forUser:(ZDCLocalUser *)localUser
    completionQueue:(dispatch_queue_t)completionQueue
    completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
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
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];
		
		jsonDict[@"auth0_id"] = auth0ID;
		jsonDict[@"link"] = linkAuth0ID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setJSONContentTypeHeader];
		
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

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)unlinkAuth0ID:(NSString *)unlinkAuth0ID
              forUser:(ZDCLocalUser *)localUser
      completionQueue:(dispatch_queue_t)completionQueue
      completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
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
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:2];
		jsonDict[@"auth0_id"] = auth0ID;
		jsonDict[@"unlink"] = unlinkAuth0ID;
		
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;
		
		[request setJSONContentTypeHeader];
		
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

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchIsCustomer:(NSString *)inLocalUserID
        completionQueue:(nullable dispatch_queue_t)inCompletionQueue
        completionBlock:(void (^)(BOOL isPayingCustomer, NSError *_Nullable error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
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
			void (^completionBlock)(BOOL, NSError *) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(result, error);
			}});
		}
	};
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
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
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchCurrentBalance:(NSString *)inLocalUserID
            completionQueue:(nullable dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(double credit, NSError *_Nullable error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
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
			void (^completionBlock)(double, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(credit, error);
			}});
		}
	};
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
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
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchCurrentBilling:(NSString *)inLocalUserID
            completionQueue:(dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(ZDCUserBill *bill, NSError *error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	if (!inCompletionBlock) {
		return;
	}
	
	NSString *requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), localUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	void (^InvokeCompletionBlocks)(ZDCUserBill*, NSError*) = ^(ZDCUserBill *result, NSError *error) {
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
		                            completionBlocks:&completionBlocks
		                                      forKey:requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCUserBill*, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(result, error);
			}});
		}
	};
	
	__block ZDCUserBill *billing_last = nil;
	dispatch_sync(billing_queue, ^{
		
		billing_last = billing_history[localUserID];
	});
	
	NSString *xIfModifiedSince = nil;
	
	if (billing_last)
	{
		NSUInteger billing_year = billing_last.metadata.year;
		NSUInteger billing_month = billing_last.metadata.month;
		
		NSDate *now = [NSDate date];
		
		NSCalendar *calendar = [NSCalendar currentCalendar];
		
		NSUInteger now_year  = [calendar component:NSCalendarUnitYear fromDate:now];
		NSUInteger now_month = [calendar component:NSCalendarUnitMonth fromDate:now];
		
		if ((billing_year == now_year) && (billing_month == now_month))
		{
			NSDate *lastChange = billing_last.metadata.timestamp;
			uint64_t millis = (uint64_t)[lastChange timeIntervalSince1970] * (uint64_t)1000;
			
			xIfModifiedSince = [NSString stringWithFormat:@"%llu", millis];
		}
	}
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
	                                 completionQueue: bgQueue
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
		
		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
		
		urlComponents.queryItems = @[
		  [NSURLQueryItem queryItemWithName:@"v" value:@"1"],
		  [NSURLQueryItem queryItemWithName:@"rates" value:@"aws"]
		];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
		if (xIfModifiedSince)
		{
			[request setValue:xIfModifiedSince forHTTPHeaderField:@"X-If-Modified-Since"];
		}
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
		// Send request
		
		NSURLSessionDataTask *task =
		  [session dataTaskWithRequest: request
		                uploadProgress: nil
		              downloadProgress: nil
		             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			ZDCUserBill *result = nil;
			
			NSInteger statusCode = response.httpStatusCode;
			if (statusCode == 304)
			{
				// No change since our last fetch.
				
				result = billing_last;
			}
			else
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
					result = [[ZDCUserBill alloc] initWithDictionary:jsonDict];
					
					// Cache result in memory.
					// This helps us reduce lambda processing time & bandwidth usage.
					//
					dispatch_sync(billing_queue, ^{
					
						billing_history[localUserID] = result;
					});
				}
				else if (!error) // no JSON parsing errors
				{
					NSString *msg = @"Server returned non-json-dictionary response";
					error = [NSError errorWithClass:[self class] code:500 description:msg];
				}
			}
			
			InvokeCompletionBlocks(result, error);
		}];
		
		[task resume];
	}];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchPreviousBilling:(NSString *)inLocalUserID
                    withYear:(NSInteger)year
                       month:(NSInteger)month
             completionQueue:(nullable dispatch_queue_t)inCompletionQueue
             completionBlock:(void (^)(ZDCUserBill *bill, NSError *error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	
	if (!inCompletionBlock) {
		return;
	}
	
	NSString *requestKey = [NSString stringWithFormat:@"%@|%@|%ld|%ld",
	                          NSStringFromSelector(_cmd), localUserID, (long)year, (long)month];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	void (^InvokeCompletionBlocks)(ZDCUserBill*, NSError*) = ^(ZDCUserBill *bill, NSError *error) {
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
		                            completionBlocks:&completionBlocks
		                                      forKey:requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCUserBill*, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(bill, error);
			}});
		}
	};
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
	
		[zdc.credentialsManager getAWSCredentialsForUser: localUserID
		                                 completionQueue: bgQueue
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
			
			NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];
			
			urlComponents.queryItems = @[
			  [NSURLQueryItem queryItemWithName:@"v" value:@"1"],
			  [NSURLQueryItem queryItemWithName:@"rates" value:@"aws"],
			  [NSURLQueryItem queryItemWithName:@"year" value:[NSString stringWithFormat:@"%ld", (long)year]],
			  [NSURLQueryItem queryItemWithName:@"month" value:[NSString stringWithFormat:@"%ld", (long)(month-1)]]
			];
			
			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
			[request setHTTPMethod:@"GET"];
			
			[AWSSignature signRequest: request
			               withRegion: region
			                  service: AWSService_APIGateway
			              accessKeyID: auth.aws_accessKeyID
			                   secret: auth.aws_secret
			                  session: auth.aws_session];
			
			// Send request
			
			NSURLSessionDataTask *task =
			  [session dataTaskWithRequest: request
			                uploadProgress: nil
			              downloadProgress: nil
			             completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
			{
				if (error)
				{
					InvokeCompletionBlocks(nil, error);
					return;
				}
				
				NSDictionary *jsonDict = nil;
				if ([responseObject isKindOfClass:[NSDictionary class]])
				{
					jsonDict = (NSDictionary *)responseObject;
				}
				else if ([responseObject isKindOfClass:[NSData class]])
				{
					jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
				}
				
				ZDCUserBill *bill = nil;
				if (jsonDict)
				{
					bill = [[ZDCUserBill alloc] initWithDictionary:jsonDict];
					
					if (bill.metadata.isFinal)
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
				else if (!error) // no JSON parsing errors
				{
					NSString *msg = @"Server returned non-json-dictionary response";
					error = [NSError errorWithClass:[self class] code:500 description:msg];
				}
				
				InvokeCompletionBlocks(bill, error);
			}];
			
			[task resume];
		}];
	}};
	
	__block NSData *cachedResponseData = nil;
	
	[zdc.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCCachedResponse *cachedResponse =
		  [transaction objectForKey:requestKey inCollection:kZDCCollection_CachedResponse];
		
		cachedResponseData = cachedResponse.data;
		
	} completionQueue:bgQueue completionBlock:^{
		
		NSDictionary *jsonDict = nil;
		
		if (cachedResponseData)
		{
			jsonDict = [NSJSONSerialization JSONObjectWithData:cachedResponseData options:0 error:nil];
		}
		
		if (jsonDict)
		{
			ZDCUserBill *bill = [[ZDCUserBill alloc] initWithDictionary:jsonDict];
			InvokeCompletionBlocks(bill, nil);
		}
		else
		{
			requestBlock();
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Purchase
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)productPurchasedByUser:(NSString *)inLocalUserID
             productIdentifier:(NSString *)productIdentifier
         transactionIdentifier:(NSString *)transactionIdentifier
               appStoreReceipt:(NSData *)appStoreReceipt
               completionQueue:(nullable dispatch_queue_t)inCompletionQueue
               completionBlock:(void (^)(NSURLResponse *response,
                                         id _Nullable responseObject,
                                         NSError *_Nullable error))inCompletionBlock
{
	ZDCLogAutoTrace();

	NSParameterAssert(inLocalUserID != nil);
	NSParameterAssert(productIdentifier != nil);
	NSParameterAssert(appStoreReceipt != nil);

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

	void (^InvokeCompletionBlocks)(NSURLResponse*, id, NSError*) =
		^(NSURLResponse *response, id responseObject, NSError *error)
	{
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[asyncCompletionDispatch popCompletionQueues:&completionQueues
									completionBlocks:&completionBlocks
											  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSURLResponse*, id, NSError*) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(response, responseObject,error);
			}});
		}
	};

	[zdc.credentialsManager getAWSCredentialsForUser: localUserID
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

		NSURLComponents *urlComponents = [self apiGatewayV0ForRegion:region stage:stage path:path];

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"POST";
		request.HTTPBody = jsonData;

		[request setJSONContentTypeHeader];
		
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Blockchain
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)fetchMerkleTreeFile:(NSString *)merkleTreeRoot
            completionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSURLResponse * response,
                                      ZDCMerkleTree * merkleTree,
                                      NSError       * error))completionBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(merkleTreeRoot != nil);
	
	if (!completionBlock) {
		return;
	}
	
	void (^InvokeCompletionBlock)(NSURLResponse*, ZDCMerkleTree*, NSError*) =
	^(NSURLResponse *response, ZDCMerkleTree *merkleTree, NSError *error){
		
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			completionBlock(response, merkleTree, error);
		}});
	};
	
	// Sanitize rootPath sanitation
	if ([merkleTreeRoot hasPrefix:@"0x"] || [merkleTreeRoot hasPrefix:@"0X"]) {
		merkleTreeRoot = [merkleTreeRoot substringFromIndex:2];
	}
	
	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = @"blockchain.storm4.cloud";
	urlComponents.path = [NSString stringWithFormat:@"/%@.json", merkleTreeRoot];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"GET";
	
	[request setJSONContentTypeHeader];
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest:request
	             completionHandler:^(NSData *data, NSURLResponse *urlResponse, NSError *networkError)
	{
		if (networkError)
		{
			InvokeCompletionBlock(urlResponse, nil, networkError);
			return;
		}
		  
		NSInteger statusCode = [urlResponse httpStatusCode];
		if (statusCode != 200)
		{
			NSString *msg = [NSString stringWithFormat:@"Server returned status code %ld", (long)statusCode];
			NSError *error = [NSError errorWithClass:[self class] code:statusCode description:msg];
			
			InvokeCompletionBlock(urlResponse, nil, error);
			return;
		}
		  
		NSDictionary *jsonDict = nil;
		if (data)
		{
			jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		}
		
		if (![jsonDict isKindOfClass:[NSDictionary class]])
		{
			NSString *msg = @"Server returned non-json-dictionary response";
			NSError *error = [NSError errorWithClass:[self class] code:500 description:msg];
			
			InvokeCompletionBlock(urlResponse, nil, error);
			return;
		}
		  
		NSError *parseError = nil;
		ZDCMerkleTree *merkleTree = [ZDCMerkleTree parseFile:jsonDict error:&parseError];
		  
		if (parseError) {
			InvokeCompletionBlock(urlResponse, nil, parseError);
		} else {
			InvokeCompletionBlock(urlResponse, merkleTree, nil);
		}
	}];
		
	[task resume];
}

#pragma clang diagnostic pop

@end
