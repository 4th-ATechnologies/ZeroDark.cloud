/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "Auth0APIManager.h"

#import "ZDCConstants.h"
#import "ZDCAsyncCompletionDispatch.h"

// Categories
#import "NSError+Auth0API.h"
#import "NSURLResponse+ZeroDark.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h> // For [[UIDevice currentDevice] name]
#endif

#pragma mark - Auth0APIManager

#define TRACK_DEVICE 1

@implementation Auth0APIManager

static ZDCAsyncCompletionDispatch *pendingRequests;

/// Auth0 values
static NSString * const A0ParameterClientID = @"client_id";
static NSString * const A0ParameterEmail = @"email";
static NSString * const A0ParameterUsername = @"username";
static NSString * const A0ParameterPassword = @"password";
static NSString * const A0ParameterScope = @"scope";
static NSString * const A0ParameterDevice = @"device";
static NSString * const A0ParameterGrantType = @"grant_type";
static NSString * const A0ParameterAPIType = @"api_type";
static NSString * const A0ParameterRefreshToken = @"refresh_token";
static NSString * const A0ParameterIdToken = @"id_token";
static NSString * const A0ParameterRealm = @"realm";

// for social login
static NSString * const A0ParameterState = @"state";
static NSString * const A0ParameterRedirectURI = @"redirect_uri";
static NSString * const A0ParameterResponseType = @"response_type";

static NSString * const A0ParameterConnection = @"connection";

/* extern */ NSString *const Auth0APIManagerErrorDomain = @"Auth0APIManager";


static Auth0APIManager *sharedInstance = nil;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		sharedInstance = [[Auth0APIManager alloc] init];

		pendingRequests = [[ZDCAsyncCompletionDispatch alloc] init];
	});
}

+ (Auth0APIManager *)sharedInstance
{
	return sharedInstance;
}

- (Auth0APIManager *)init
{
	NSAssert(sharedInstance == nil, @"You MUST use the sharedInstance - class is a singleton");

	if ((self = [super init])) {}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description)
		userInfo = @{ NSLocalizedDescriptionKey: description };

	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

- (NSError *)errorWithDescription:(NSString *)description a0Code:(NSString*)a0Code
{
	NSMutableDictionary *userInfo = nil;

	if (description || a0Code)
	{
		userInfo = NSMutableDictionary.dictionary;

		if(description)
			[userInfo setObject:description forKey:NSLocalizedDescriptionKey];

		if(a0Code)
			[userInfo setObject:a0Code forKey:Auth0APIManagerErrorDataKey];

 	}

	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

- (NSError *)errorWithStatusCode:(NSInteger)statusCode responseData:(id)responseData
{
	NSDictionary *details = nil;
	NSString *responseString = nil;

	if ([responseData isKindOfClass:[NSData class]])
	{
		responseString = [[NSString alloc] initWithData:(NSData *)responseData encoding:NSUTF8StringEncoding];
	}

	if (responseString || responseData)
	{
		details = @{ NSUnderlyingErrorKey: (responseString ?: responseData) };
	}

	NSString *domain = NSStringFromClass([self class]);

	return [NSError errorWithDomain:domain code:statusCode userInfo:details];
}

- (NSError *)errorWithStatusCode:(NSInteger)statusCode description:(NSString *)description
{
	NSDictionary *details = nil;

	if (description)
	{
		details = @{ NSUnderlyingErrorKey: description };
	}

	NSString *domain = NSStringFromClass([self class]);

	return [NSError errorWithDomain:domain code:statusCode userInfo:details];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)deviceName
{
#if TARGET_OS_IPHONE
	return [[UIDevice currentDevice] name];
#else
	return [[NSHost currentHost] localizedName];
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Auth0 Login (traditional)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)loginAndGetProfileWithUsername:(NSString *)username
                              password:(NSString *)password
                       auth0Connection:(NSString *)auth0Connection
                       completionQueue:(nullable dispatch_queue_t)inCompletionQueue
                       completionBlock:(void (^)(NSString *_Nullable auth0_refreshToken,
                                                 NSString *_Nullable auth0_accessToken,
                                                 A0UserProfile *_Nullable profile,
                                                 NSError *_Nullable error))completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(completionBlock != nil);
#else
	if (completionBlock == nil) return;
#endif
	
	dispatch_queue_t completionQueue = inCompletionQueue ?: dispatch_get_main_queue();

	void (^Fail)(NSError*) = ^(NSError *error){
		
		NSParameterAssert(error != nil);
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(nil, nil, nil, error);
		}});
	};
	
	void (^Succeed)(NSString*, NSString*, A0UserProfile*) =
	^(NSString *refreshToken, NSString *accessToken, A0UserProfile *profile){
		
		NSParameterAssert(refreshToken != nil);
		NSParameterAssert(accessToken != nil);
		NSParameterAssert(profile != nil);
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(refreshToken, accessToken, profile, nil);
		}});
	};
	
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	[self loginWithUsername: username
	               password: password
	        auth0Connection: auth0Connection
	        completionQueue: backgroundQueue
	        completionBlock:^(NSString *refreshToken, NSError *error)
	{
		if (error)
		{
			Fail(error);
			return;
		}

		[self getAccessTokenWithRefreshToken: refreshToken
		                     completionQueue: backgroundQueue
		                     completionBlock:^(NSString *accessToken, NSError *error)
		{
			if (error)
			{
				Fail(error);
				return;
			}
			
			[self getUserProfileWithAccessToken: accessToken
			                    completionQueue: backgroundQueue
			                    completionBlock:^(A0UserProfile *profile, NSError *error)
			{
				if (error)
					Fail(error);
				else
					Succeed(refreshToken, accessToken, profile);
				
			}];
		}];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - Auth0 Login (low level)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
          auth0Connection:(NSString *)auth0Connection
          completionQueue:(nullable dispatch_queue_t)inCompletionQueue
          completionBlock:(void (^)(NSString *refreshToken, NSError *error))completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(username != nil);
	NSParameterAssert(password != nil);
	NSParameterAssert(completionBlock != nil);
#else
	if (completionBlock == nil) return;
#endif
	
	dispatch_queue_t completionQueue = inCompletionQueue ?: dispatch_get_main_queue();

	void (^Fail)(NSError*) = ^(NSError *error){
		
		NSParameterAssert(error != nil);
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(nil, error);
		}});
	};
	
	void (^Succeed)(NSString*) = ^(NSString *refreshToken){
		
		NSParameterAssert(refreshToken != nil);
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(refreshToken, nil);
		}});
	};

	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = kAuth04thADomain;
	urlComponents.path = @"/oauth/token";

	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:8];
	jsonDict[A0ParameterClientID]  = kAuth04thA_AppClientID;
	jsonDict[A0ParameterUsername]  = username;
	jsonDict[A0ParameterPassword]  = password;
	jsonDict[A0ParameterGrantType] = @"http://auth0.com/oauth/grant-type/password-realm";
	jsonDict[A0ParameterRealm]     = auth0Connection;
	jsonDict[A0ParameterScope]     = @"openid offline_access";
#if TRACK_DEVICE
	jsonDict[A0ParameterDevice]    = [self deviceName];
#endif

	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;

	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest: request
	             completionHandler:^(NSData *responseObject, NSURLResponse *response, NSError *error)
	{
		if (error)
		{
			Fail(error);
			return;
		}
		
		NSDictionary * jsonDict = nil;
		NSString     * refreshToken = nil;
		
		if ([responseObject isKindOfClass:[NSData class]]
		 && (responseObject.length > 0))
		{
			jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
			
			if (![jsonDict isKindOfClass:[NSDictionary class]]) {
				jsonDict = nil;
			}
		}

		if (jsonDict)
		{
			if (jsonDict[@"error"])
			{
				NSString *description = jsonDict[@"error_description"];
				
				if ([description isKindOfClass:[NSString class]]) {
					error = [self errorWithDescription:description];
				}
			}
			else
			{
				refreshToken = jsonDict[@"refresh_token"];
				
				if (![refreshToken isKindOfClass:[NSString class]]) {
					refreshToken = nil;
				}
			}
		}

		if (!error && !refreshToken)
		{
			NSInteger statusCode = response.httpStatusCode;
			error = [self errorWithStatusCode:statusCode description:@"Invalid response from server"];
		}

		if (error)
		{
			Fail(error);
		}
		else
		{
			Succeed(refreshToken);
		}
	}];

	[task resume];

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - Auth0 Create User
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)createUserWithEmail:(NSString *)email
                   username:(NSString *)username
                   password:(NSString *)password
            auth0Connection:(NSString *)auth0Connection
            completionQueue:(nullable dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(NSString *auth0ID, NSError *error))completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(email != nil);
	NSParameterAssert(username != nil);
	NSParameterAssert(password != nil);
	NSParameterAssert(auth0Connection != nil);
	NSParameterAssert(completionBlock != nil);
#else
	if (completionBlock == nil) return;
#endif
	
	dispatch_queue_t completionQueue = inCompletionQueue ?: dispatch_get_main_queue();

	void (^Fail)(NSError*) = ^(NSError *error){
		
		NSParameterAssert(error != nil);
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(nil, error);
		}});
	};
	
	void (^Succeed)(NSString*) = ^(NSString *auth0ID){
		
		NSParameterAssert(auth0ID != nil);
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(auth0ID, nil);
		}});
	};

	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = kAuth04thADomain;
	urlComponents.path = @"/dbconnections/signup";

	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionaryWithCapacity:8];
	jsonDict[A0ParameterClientID]   = kAuth04thA_AppClientID;
	jsonDict[A0ParameterEmail]      = email;
	jsonDict[A0ParameterUsername]   = username;
	jsonDict[A0ParameterPassword]   = password;
	jsonDict[A0ParameterGrantType]  = @"password";
	jsonDict[A0ParameterScope]      = @"openid offline_access";
#if TRACK_DEVICE
	jsonDict[A0ParameterDevice]     = [self deviceName];
#endif
	jsonDict[A0ParameterConnection] = auth0Connection;

	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;

	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSURLSessionDataTask *task =
	  [session dataTaskWithRequest: request
	             completionHandler:^(NSData *responseObject, NSURLResponse *response, NSError *error)
	{
		if (error)
		{
			Fail(error);
			return;
		}
		  
		NSDictionary *jsonDict = nil;
		NSString *auth0ID = nil;

		if ([responseObject isKindOfClass:[NSData class]]
		 && (responseObject.length > 0))
		{
			jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
			
			if (![jsonDict isKindOfClass:[NSDictionary class]]) {
				jsonDict = nil;
			}
		}

		if (jsonDict)
		{
			NSString *code = jsonDict[@"code"];
			if (code)
			{
				// {
				//   code = "user_exists";
				//   description = "The user already exists.";
				//   name = BadRequestError;
				//   statusCode = 400;
				// }

				NSString *description = jsonDict[@"description"];
				
				if ([description isKindOfClass:[NSString class]]) {
					error = [self errorWithDescription:description a0Code:code];
				}
			}
			else
			{
				NSString *rawID = jsonDict[@"_id"];
				
				if ([rawID isKindOfClass:[NSString class]]) {
					auth0ID = [NSString stringWithFormat:@"auth0|%@", rawID];
				}
			}
		}

		if (!error && !auth0ID)
		{
			NSInteger statusCode = response.httpStatusCode;
			
			error = [self errorWithStatusCode: statusCode
			                      description: @"Invalid response from server"];
		}

		if (error)
		{
			Fail(error);
		}
		else
		{
			Succeed(auth0ID);
		}
	}];

	[task resume];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - Auth0 Get User Profile
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void) getUserProfileWithAccessToken:(NSString*)auth0_accessToken
							  withKey:(NSString *)requestKey
{
	void (^InvokePendingCompletions)(A0UserProfile * _Nullable a0Profile,
									 NSError *_Nullable error);
	InvokePendingCompletions = ^(A0UserProfile * _Nullable a0Profile, NSError *error){

		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[pendingRequests popCompletionQueues:&completionQueues
							completionBlocks:&completionBlocks
									  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(A0UserProfile * _Nullable a0Profile, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {

				completionBlock(a0Profile, error);
			}});
		}
	};


	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = kAuth04thADomain;
	urlComponents.path = @"/userinfo";
	
	NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithCapacity:1];
	[queryItems addObject:[NSURLQueryItem queryItemWithName:@"access_token" value:auth0_accessToken]];

	urlComponents.queryItems = queryItems;

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"GET";

	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSURLSessionDataTask *task =
	[session dataTaskWithRequest:request
			   completionHandler:^(NSData *responseObject, NSURLResponse *response, NSError *error)
	 {
		 NSError *jsonError = nil;
		 NSDictionary *jsonDict = nil;
		 A0UserProfile* profile = nil;

		 NSInteger statusCode = response.httpStatusCode;

		 if ([responseObject isKindOfClass:[NSData class]])
		 {
			 jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&jsonError];
		 }

		 if (jsonDict && !error)
		 {
			 if(jsonDict[@"error"])
			 {
				 NSString* errorDescription  = jsonDict[@"error_description"];
				 error = [self errorWithDescription:errorDescription];
			 }
			 else
			 {
				 profile = [[A0UserProfile alloc] initWithDictionary:jsonDict];
			 }
		 }

		 if (!jsonDict && !error && !jsonError)
		 {
			 error = [self errorWithStatusCode:statusCode
								   description:@"Invalid response from server"];
		 }

		 if (error || jsonError)
		 {
			 InvokePendingCompletions(nil, (error ?: jsonError));
		 }
		 else
		 {
			 InvokePendingCompletions(profile,nil);
		 }
	 }];

	[task resume];
}

-(void) getUserProfileWithAccessToken:(NSString*)auth0_accessToken
				   completionQueue:(nullable dispatch_queue_t)inCompletionQueue
				   completionBlock:(void (^)(A0UserProfile * _Nullable  a0Profile ,
											 NSError *_Nullable error))inCompletionBlock
{
	__block dispatch_queue_t completionQueue = inCompletionQueue;
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();

	NSParameterAssert(inCompletionBlock);
	NSParameterAssert(auth0_accessToken);


	NSString *requestKey = [NSString stringWithFormat:@"%@-%@", NSStringFromSelector(_cmd), auth0_accessToken];

	NSUInteger requestCount =
	[pendingRequests pushCompletionQueue:inCompletionQueue
						 completionBlock:inCompletionBlock
								  forKey:requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	[self getUserProfileWithAccessToken:auth0_accessToken
								 withKey:requestKey];

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - Auth0 Get Access Token
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)getAccessTokenWithRefreshToken:(NSString *)auth0_refreshToken
                               withKey:(NSString *)requestKey
{
	void (^InvokePendingCompletions)(NSString *_Nullable auth0_accessToken,
	                                 NSDate   *_Nullable auth0_expiration,
	                                 NSError  *_Nullable error);
	
	InvokePendingCompletions = ^(NSString * _Nullable auth0_accessToken,
								 NSDate* _Nullable auth0_expiration,
								 NSError * _Nullable error){

		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[pendingRequests popCompletionQueues:&completionQueues
							completionBlocks:&completionBlocks
									  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSString * _Nullable auth0_accessToken,
									NSDate* _Nullable auth0_expiration,
									NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {

				completionBlock(auth0_accessToken, auth0_expiration, error);
			}});
		}
	};

	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = kAuth04thADomain;
	urlComponents.path = @"/oauth/token";

	NSDictionary *jsonDict = @{
		A0ParameterClientID     : kAuth04thA_AppClientID,
		A0ParameterGrantType    : @"refresh_token",
		A0ParameterRefreshToken : auth0_refreshToken,
		A0ParameterScope        : @"profile"
	};

	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];


	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;

	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSURLSessionDataTask *task =
	[session dataTaskWithRequest:request
			   completionHandler:^(NSData *responseObject, NSURLResponse *response, NSError *error)
	 {
		 NSError *jsonError = nil;
		 NSDictionary *jsonDict = nil;
		 NSString*  accessToken = nil;
		 NSDate* auth0_expiration = nil;

		 NSInteger statusCode = response.httpStatusCode;
		 if(!error
			&& (statusCode != 200)
			&& (statusCode != 401)
			&& (statusCode != 403))
		 {
			 error = [self errorWithStatusCode:statusCode description:@"Bad Status response"];
		 }

		 if (!error
			 && [responseObject isKindOfClass:[NSData class]]
			 && (responseObject.length > 0))
		 {
			 jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&jsonError];
		 }

		 if (jsonDict && !error)
		 {
			 if(jsonDict[@"error"])
			 {
				 NSString* errorDescription  = jsonDict[@"error_description"];
				 
				 error = [self errorWithDescription:errorDescription
											 a0Code:jsonDict[@"error"] ];
			 }
			 else
			 {
				 NSNumber* expires_in = jsonDict[@"expires_in"];
				 if(expires_in)
					 auth0_expiration = [NSDate dateWithTimeIntervalSinceNow:expires_in.doubleValue];
				 accessToken = jsonDict[@"access_token"];
			 }
		 }

		 if (!jsonDict && !error && !jsonError)
		 {
			 error = [self errorWithStatusCode:500 description:@"Invalid response from server"];
		 }

		 if (error || jsonError)
		 {
			 InvokePendingCompletions(nil, nil, (error ?: jsonError));
		 }
		 else
		 {
			 InvokePendingCompletions(accessToken,auth0_expiration,nil);
		 }
	 }];

	[task resume];

}

- (void)getAccessTokenWithRefreshToken:(NSString *)auth0_refreshToken
                       completionQueue:(nullable dispatch_queue_t)inCompletionQueue
                       completionBlock:(void (^)(NSString *_Nullable auth0_accessToken,
                                                 NSError *_Nullable error))inCompletionBlock
{
	NSParameterAssert(inCompletionBlock);
	NSParameterAssert(auth0_refreshToken);

	__block dispatch_queue_t completionQueue = inCompletionQueue;
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();

	NSString *requestKey = [NSString stringWithFormat:@"%@-%@", NSStringFromSelector(_cmd), auth0_refreshToken];

	NSUInteger requestCount =
	[pendingRequests pushCompletionQueue:inCompletionQueue
						 completionBlock:inCompletionBlock
								  forKey:requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	[self getAccessTokenWithRefreshToken:auth0_refreshToken
									withKey:requestKey];

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - Auth0 Get AWSCredentials
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void) getAWSCredentialsWithRefreshToken:(NSString *)auth0_refreshToken
								  withKey:(NSString *)requestKey
{
	void (^InvokePendingCompletions)(NSDictionary * _Nullable delegationToken,
									 NSError *_Nullable error);
	InvokePendingCompletions = ^(NSDictionary * _Nullable delegationToken, NSError *error){

		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[pendingRequests popCompletionQueues:&completionQueues
							completionBlocks:&completionBlocks
									  forKey:requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSDictionary * _Nullable delegationToken, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {

				completionBlock(delegationToken, error);
			}});
		}
	};

	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = kAuth04thADomain;
	urlComponents.path = @"/delegation";

	NSDictionary *jsonDict = @{ A0ParameterClientID		:kAuth04thA_AppClientID,
								A0ParameterGrantType	:@"urn:ietf:params:oauth:grant-type:jwt-bearer",
								A0ParameterScope		:@"openid offline_access",
								A0ParameterAPIType		:@"aws" ,
								A0ParameterRefreshToken	:auth0_refreshToken
								};

	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];


	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = jsonData;

	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSURLSessionDataTask *task =
	[session dataTaskWithRequest:request
			   completionHandler:^(NSData *responseObject, NSURLResponse *response, NSError *error)
	 {
		 NSError *jsonError = nil;
		 NSDictionary *jsonDict = nil;
		 NSDictionary* delegationToken = nil;

		 NSInteger statusCode = response.httpStatusCode;
		 if(!error
			&& (statusCode != 200)
			&& (statusCode != 401)
			&& (statusCode != 403)
			&& (statusCode != 429))
		 {
			 error = [self errorWithStatusCode:statusCode description:@"Bad Status response"];
		 }

		 if (!error
			 && [responseObject isKindOfClass:[NSData class]]
			 && (responseObject.length > 0))
		 {
			 jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&jsonError];
		 }

		 if (jsonDict && !error)
		 {
			 if(jsonDict[@"error"])
			 {
				 NSString* errorDescription  = jsonDict[@"error_description"];
				 error = [self errorWithDescription:errorDescription
											 a0Code:jsonDict[@"error"] ];
			 }
			 else
			 {
				 delegationToken = jsonDict;
			 }
		 }

		 if (!jsonDict && !error && !jsonError)
		 {
			 error = [self errorWithStatusCode:500 description:@"Invalid response from server"];
		 }

		 if (error || jsonError)
		 {
			 InvokePendingCompletions(nil, (error ?: jsonError));
		 }
		 else
		 {
			 InvokePendingCompletions(delegationToken,nil);
		 }
	 }];

	[task resume];

}

-(void) getAWSCredentialsWithRefreshToken:(NSString *)auth0_refreshToken
						  completionQueue:(nullable dispatch_queue_t)inCompletionQueue
						  completionBlock:(void (^)(NSDictionary * _Nullable delegationToken,
													NSError *_Nullable error))inCompletionBlock
{

	NSParameterAssert(inCompletionBlock);
	NSParameterAssert(auth0_refreshToken);

	__block dispatch_queue_t completionQueue = inCompletionQueue;
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();

	NSString *requestKey = [NSString stringWithFormat:@"%@-%@", NSStringFromSelector(_cmd), auth0_refreshToken];

	NSUInteger requestCount =
	[pendingRequests pushCompletionQueue:inCompletionQueue
						 completionBlock:inCompletionBlock
								  forKey:requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	[self getAWSCredentialsWithRefreshToken:auth0_refreshToken
						withKey:requestKey];

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - Auth0 Get Social media login tools
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)callbackURLscheme
{
	return [[NSString stringWithFormat:@"a0%@", kAuth04thA_AppClientID] lowercaseString];
}

-(NSURL*) socialQueryURLforStrategyName:(NSString*)strategyName
					  callBackURLScheme:(NSString*)callBackURLScheme
							  CSRFState:(NSString*)CSRFState
{
	NSParameterAssert(strategyName != nil);

	static NSString* const kCallbackURLString =  @"%@://%@.auth0.com/authorize";

	NSString *callbackURLString = [NSString stringWithFormat:kCallbackURLString,
								   callBackURLScheme,
								   strategyName].lowercaseString;

	NSURL* callbackURL = [NSURL URLWithString:callbackURLString];

	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	urlComponents.host = kAuth04thADomain;
	urlComponents.path = @"/authorize";

	NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithCapacity:8];
	
	[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterClientID     value:kAuth04thA_AppClientID]];
	[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterScope        value:@"offline_access"]];
	[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterResponseType value:@"token"]];
	[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterRedirectURI  value:callbackURL.absoluteString]];
	[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterConnection   value:strategyName]];
#if TRACK_DEVICE
	[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterDevice       value:[self deviceName]]];
#endif
	if (CSRFState) {
		[queryItems addObject:[NSURLQueryItem queryItemWithName:A0ParameterState value:CSRFState]];
	}
	
	urlComponents.queryItems = queryItems;

	return urlComponents.URL;
}


-(BOOL) decodeSocialQueryString:(NSString*)queryString
						a0Token:(A0Token * _Nullable*) a0TokenOut
						CSRFState:(NSString * _Nullable*) CSRFStateOut
						  error:(NSError ** _Nullable)errorOut
{
	BOOL success = NO;

	NSError * error = nil;
	A0Token* a0Token = nil;
	NSString* stateStr = nil;

	NSString *urlStr;
	if ([queryString hasPrefix:@"?"]) {
		urlStr = [NSString stringWithFormat:@"http://www.apple.com%@", queryString];
	}
	else {
		urlStr = [NSString stringWithFormat:@"http://www.apple.com?%@", queryString];
	}
	
	NSURLComponents *components = [NSURLComponents componentsWithString:urlStr];
	NSArray<NSURLQueryItem *> *queryItems = components.queryItems;

	NSURLQueryItem *item_error = nil;
	NSURLQueryItem *item_error_description = nil;
	
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:queryItems.count];
	
	for (NSURLQueryItem *item in queryItems)
	{
		if ([item.name isEqualToString:@"error"])
		{
			item_error = item;
		}
		else if ([item.name isEqualToString:@"error_description"])
		{
			item_error_description = item;
		}
		
		dict[item.name] = item.value ?: @"";
	}
	
	if (item_error)
	{
		NSString *description = item_error_description.value ?: item_error.value;
		error = [self errorWithDescription:description];
	}
	else
	{
		a0Token = [A0Token tokenFromDictionary:dict];
		if (a0Token) {
			success = YES;
		}
		
		stateStr = dict[A0ParameterState];
	}

	if (CSRFStateOut) *CSRFStateOut = stateStr;
	if (a0TokenOut) *a0TokenOut = a0Token;
	if (errorOut) *errorOut = error;
	
	return success;
}


@end
