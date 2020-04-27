#import "AWSCredentialsManager.h"

#import "AWSDate.h"
#import "JWTUtilities.h"
#import "ZDCConstants.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCDatabaseManager.h"
#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCLocalUser.h"
#import "ZDCLocalUserAuth.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSDate+ZeroDark.h"
#import "NSError+Auth0API.h"
#import "NSError+ZeroDark.h"


@implementation AWSCredentialsManager
{
	__weak ZeroDarkCloud *zdc;
	
	ZDCAsyncCompletionDispatch *pendingRequests;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.awsCredentialsManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		pendingRequests = [[ZDCAsyncCompletionDispatch alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)getAWSCredentialsForUser:(NSString *)userID
                 completionQueue:(dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock
{
	NSParameterAssert(userID != nil);
	
	if (userID == nil)
	{
		if (completionBlock)
		{
			NSError *error = [self missingInvalidUserError:@"Invalid parameter: userID == nil"];
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(nil, error);
			}});
		}
		return;
	}
	
	NSString *requestKey = [NSString stringWithFormat:@"%@-%@", NSStringFromSelector(_cmd), userID];
	
	NSUInteger requestCount =
	  [pendingRequests pushCompletionQueue: completionQueue
	                       completionBlock: completionBlock
	                                forKey: requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	[self getAWSCredentialsForUserID:userID requestKey:requestKey];
}

- (void)getAWSCredentialsForUserID:(NSString *)userID
                        requestKey:(NSString *)requestKey
{
	__weak typeof(self) weakSelf = self;
	
	void (^Fail)(NSError*) = ^(NSError *error) {
	
		NSParameterAssert(error != nil);
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[strongSelf->pendingRequests popCompletionQueues: &completionQueues
		                                completionBlocks: &completionBlocks
		                                          forKey: requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCLocalUserAuth *auth, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {

				completionBlock(nil, error);
			}});
		}
	};
	
	void (^Succeed)(ZDCLocalUserAuth*) = ^(ZDCLocalUserAuth *auth) {
	
		NSParameterAssert(auth != nil);
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[strongSelf->pendingRequests popCompletionQueues: &completionQueues
		                                completionBlocks: &completionBlocks
		                                          forKey: requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCLocalUserAuth *auth, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {

				completionBlock(auth, nil);
			}});
		}
	};
	
	__block ZDCLocalUser *localUser = nil;
	__block ZDCLocalUserAuth *auth = nil;
	
	ZDCDatabaseManager *databaseManager = zdc.databaseManager;
	[databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		localUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		auth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{

		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		// Sanity check: localUser is configured
		if (!localUser || ![localUser hasCompletedActivation])
		{
			Fail([strongSelf missingInvalidUserError:@"The localUser has completed activation."]);
			return;
		}
		
		// Sanity check: localUserAuth is non-nil
		if (!auth || ![auth isKindOfClass:[ZDCLocalUserAuth class]])
		{
			Fail([strongSelf missingInvalidUserError:@"No matching ZDCLocalUserAuth for userID."]);
			return;
		}

		// Sanity check: localUserAuth has non-nil refresh_token
		if (!auth.coop_refreshToken)
		{
			NSError *noRefreshTokensError = [strongSelf noRefreshTokensError];
			
			if (!localUser.accountNeedsA0Token)
			{
				[strongSelf setNeedsRefreshTokenForUser: userID
				                        completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
				                        completionBlock:^
				{
					Fail(noRefreshTokensError);
				}];
			}
			else
			{
				Fail(noRefreshTokensError);
			}
			
			return;
		}

		NSDate *nowPlusBuffer = [[NSDate date] dateByAddingTimeInterval:30.0];
		
		// Check for unexpired credentials
		//
		if (auth.aws_expiration && [auth.aws_expiration isAfter:nowPlusBuffer])
		{
			Succeed(auth);
			return;
		}
		
		BOOL needsRefreshJWT = YES;
		
		// Check for unexpired JWT
		//
		if (auth.coop_jwt)
		{
			NSDate *expiration = [JWTUtilities expireDateFromJWTString:auth.coop_jwt error:nil];
			if (expiration && [expiration isAfter:nowPlusBuffer])
			{
				needsRefreshJWT = NO;
			}
		}
		
		dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		if (needsRefreshJWT)
		{
			[strongSelf refreshIDTokenForUserID: userID
			                   withRefreshToken: auth.coop_refreshToken
			                    completionQueue: backgroundQueue
			                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
			{
				if (error)
				{
					Fail(error);
					return;
				}
				
				[weakSelf refreshAWSCredentialsForUserID: userID
				                                 idToken: auth.coop_jwt
				                                   stage: localUser.aws_stage
				                         completionQueue: backgroundQueue
				                         completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
				{
					if (error)
						Fail(error);
					else
						Succeed(auth);
				}];
			}];
		}
		else
		{
			[strongSelf refreshAWSCredentialsForUserID: userID
			                                   idToken: auth.coop_jwt
			                                     stage: localUser.aws_stage
			                           completionQueue: backgroundQueue
			                           completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
			{
				if (error)
					Fail(error);
				else
					Succeed(auth);
			}];
		}
	}];
}

/**
 * See header file for description.
 */
- (void)flushAWSCredentialsForUser:(NSString *)userID
                deleteRefreshToken:(BOOL)deleteRefreshToken
                   completionQueue:(dispatch_queue_t)completionQueue
                   completionBlock:(dispatch_block_t)completionBlock
{
	ZDCDatabaseManager *databaseManager = zdc.databaseManager;
	[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCLocalUserAuth *localUserAuth = nil;
		ZDCLocalUser *localUser = nil;

		localUserAuth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
		localUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];

		if (localUser && localUserAuth )
		{
			localUserAuth = [localUserAuth copy];

			localUserAuth.aws_accessKeyID = nil;
			localUserAuth.aws_secret      = nil;
			localUserAuth.aws_session     = nil;
			localUserAuth.aws_expiration  = nil;

			if (deleteRefreshToken)
			{
				localUserAuth.coop_refreshToken = nil;
				
				localUser = [localUser copy];
				localUser.accountNeedsA0Token = YES;
				
				[transaction setObject:localUser forKey:userID inCollection:kZDCCollection_Users];
			}

			[transaction setObject:localUserAuth forKey:userID inCollection:kZDCCollection_UserAuth];
		}
		
	} completionQueue:completionQueue completionBlock:completionBlock];
}

/**
 * See header file for description.
 */
- (void)resetAWSCredentialsForUser:(NSString *)userID
                  withRefreshToken:(NSString *)refreshToken
                   completionQueue:(dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock
{
	ZDCDatabaseManager *databaseManager = zdc.databaseManager;
	[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCLocalUserAuth *localUserAuth = nil;
		ZDCLocalUser *localUser = nil;

		localUserAuth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
		localUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];

		if (localUser && localUserAuth)
		{
			localUserAuth = [localUserAuth copy];
			localUser = [localUser copy];

			localUserAuth.aws_accessKeyID = nil;
			localUserAuth.aws_secret      = nil;
			localUserAuth.aws_session     = nil;
			localUserAuth.aws_expiration  = nil;

			localUserAuth.coop_refreshToken = refreshToken;

			if (refreshToken) {
				localUser.accountNeedsA0Token = NO;
			}
			else {
				localUser.accountNeedsA0Token = YES;
			}

			[transaction setObject:localUser forKey:userID inCollection:kZDCCollection_Users];
			[transaction setObject:localUserAuth forKey:userID inCollection:kZDCCollection_UserAuth];
		}
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
		
		[self getAWSCredentialsForUser: userID
		               completionQueue: completionQueue
		               completionBlock: completionBlock];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Refresh
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Performs the following:
 *
 * - fetches new idToken from auth0 servers
 * - updates the ZDCLocalUserAuth object in the database
 */
- (void)refreshIDTokenForUserID:(NSString *)userID
               withRefreshToken:(NSString *)refreshToken
                completionQueue:(dispatch_queue_t)completionQueue
                completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock
{
	NSParameterAssert(userID != nil);
	NSParameterAssert(refreshToken != nil);
	NSParameterAssert(completionQueue != nil);
	NSParameterAssert(completionBlock != nil);
	
	__weak typeof(self) weakSelf = self;
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	[zdc.auth0APIManager getIDTokenWithRefreshToken: refreshToken
	                                completionQueue: backgroundQueue
	                                completionBlock:^(NSString *idToken, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		if (error)
		{
			NSString *auth0Code = error.auth0API_error;
			if ([auth0Code isEqualToString:kAuth0Error_InvalidRefreshToken])
			{
				// The refreshToken has been revoked.
				// So the user will need to re-login to their account.
				//
				NSError *noRefreshTokensError = [strongSelf noRefreshTokensError];
				[strongSelf setNeedsRefreshTokenForUser: userID
				                        completionQueue: completionQueue
				                        completionBlock:^
				{
					completionBlock(nil, noRefreshTokensError);
				}];
			}
			else
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(nil, error);
				}});
			}
			
			return;
		}
		
		__block ZDCLocalUserAuth *auth = nil;
		
		YapDatabaseConnection *rwConnection = [strongSelf->zdc.databaseManager rwDatabaseConnection];
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			auth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
			auth = [auth copy];
			
			auth.coop_jwt = idToken;
			
			[transaction setObject:auth forKey:userID inCollection:kZDCCollection_UserAuth];
			
		} completionQueue:completionQueue completionBlock:^{
			
			if (auth)
				completionBlock(auth, nil);
			else
				completionBlock(nil, [weakSelf missingInvalidUserError:@"No matching ZDCLocalUserAuth for userID."]);
		}];
		
	}];
}

/**
 * Performs the following:
 *
 * - fetches new aws credentials from the server
 * - updates the ZDCLocalUserAuth object in the database
 */
- (void)refreshAWSCredentialsForUserID:(NSString *)userID
                               idToken:(NSString *)idToken
                                 stage:(NSString *)stage
                       completionQueue:(dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock
{
	NSParameterAssert(userID != nil);
	NSParameterAssert(idToken != nil);
	NSParameterAssert(stage != nil);
	NSParameterAssert(completionQueue != nil);
	NSParameterAssert(completionBlock != nil);
	
	__weak typeof(self) weakSelf = self;
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	[self fetchAWSCredentialsWithIDToken: idToken
	                               stage: stage
	                     completionQueue: backgroundQueue
	                     completionBlock:^(NSDictionary *delegation, NSError *error)
	{
		if (error)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(nil, error);
			}});
			return;
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		NSString *aws_accessKeyID = nil;
		NSString *aws_secret = nil;
		NSString *aws_session = nil;
		NSDate *aws_expiration = nil;
		NSString *aws_userID = nil;
		
		[strongSelf parseAccessKeyID: &aws_accessKeyID
		                      secret: &aws_secret
		                     session: &aws_session
		                  expiration: &aws_expiration
		                      userID: &aws_userID
		              fromDelegation: delegation];
		
		__block ZDCLocalUserAuth *auth = nil;
		
		YapDatabaseConnection *rwConnection = [strongSelf->zdc.databaseManager rwDatabaseConnection];
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			auth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
			auth = [auth copy];
			
			auth.aws_accessKeyID = aws_accessKeyID;
			auth.aws_secret      = aws_secret;
			auth.aws_session     = aws_session;
			auth.aws_expiration  = aws_expiration;

			[transaction setObject:auth forKey:userID inCollection:kZDCCollection_UserAuth];
			
		} completionQueue:completionQueue completionBlock:^{
			
			if (auth)
				completionBlock(auth, nil);
			else
				completionBlock(nil, [weakSelf missingInvalidUserError:@"No matching ZDCLocalUserAuth for userID."]);
		}];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Low Level
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchAWSCredentialsWithIDToken:(NSString *)idToken
                                 stage:(NSString *)stage
                       completionQueue:(dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(NSDictionary *delegation, NSError *error))completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(idToken != nil);
	NSParameterAssert(stage != nil);
	NSParameterAssert(completionBlock != nil);
#else
	if (completionBlock == nil) return;
#endif
	
	if (idToken == nil)
	{
		NSError *error = [self invalidIDTokenError];
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			
			completionBlock(nil, error);
		}});
		return;
	}
	
	NSString *requestKey = [NSString stringWithFormat:@"%@-%@", NSStringFromSelector(_cmd), idToken];

	NSUInteger requestCount =
	  [pendingRequests pushCompletionQueue: completionQueue
	                       completionBlock: completionBlock
	                                forKey: requestKey];

	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}
	
	[self fetchAWSCredentialsWithIDToken:idToken stage:stage requestKey:requestKey];
}

- (void)fetchAWSCredentialsWithIDToken:(NSString *)idToken
                                 stage:(NSString *)stage
                            requestKey:(NSString *)requestKey
{
	__weak typeof(self) weakSelf = self;
	
	void (^InvokeCompletionBlocks)(NSDictionary*, NSError*) = ^(NSDictionary *delegation, NSError *error){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[strongSelf->pendingRequests popCompletionQueues: &completionQueues
		                                completionBlocks: &completionBlocks
		                                          forKey: requestKey];

		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSDictionary *delegationToken, NSError *error) = completionBlocks[i];

			dispatch_async(completionQueue, ^{ @autoreleasepool {

				completionBlock(delegation, error);
			}});
		}
	};
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLComponents *urlComponents =
	  [zdc.restManager apiGatewayForRegion: AWSRegion_US_West_2
	                                 stage: @"dev" // stage ?: @"prod"
	                                  path: @"/delegation"];

	NSDictionary *jsonDict = @{
		@"token" : (idToken ?: @"")
	};

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
			InvokeCompletionBlocks(nil, error);
			return;
		}
		  
		NSDictionary *delegation = nil;
		
		if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			delegation = (NSDictionary *)responseObject;
		}
		else if ([responseObject isKindOfClass:[NSData class]])
		{
			id jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
			
			if ([jsonDict isKindOfClass:[NSDictionary class]])
			{
				delegation = (NSDictionary *)jsonDict;
			}
		}
		  
		if (delegation) {
			InvokeCompletionBlocks(delegation, nil);
		}
		else {
			InvokeCompletionBlocks(nil, error ?: [weakSelf invalidServerResponseError]);
		}
	}];
	
	[task resume];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setNeedsRefreshTokenForUser:(NSString *)userID
                    completionQueue:(dispatch_queue_t)completionQueue
                    completionBlock:(dispatch_block_t)completionBlock
{
	ZDCDatabaseManager *databaseManager = zdc.databaseManager;
	[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCLocalUser *refreshedLocalUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		if (refreshedLocalUser)
		{
			refreshedLocalUser = [refreshedLocalUser copy];
			refreshedLocalUser.accountNeedsA0Token = YES;

			[transaction setObject:refreshedLocalUser forKey:userID inCollection:kZDCCollection_Users];
		}
		
	} completionQueue:completionQueue completionBlock:completionBlock];
}

- (BOOL)parseAccessKeyID:(NSString **)outAccessKeyID
                  secret:(NSString **)outSecret
                 session:(NSString **)outSession
              expiration:(NSDate **)outExpiration
                  userID:(NSString **)outUserID
          fromDelegation:(NSDictionary *)delegationDict
{
	NSString *accessKeyID = nil;
	NSString *secret = nil;
	NSString *session = nil;
	NSString *expirationString = nil;
	NSString *userID = nil;
	
	id value = delegationDict[@"Credentials"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *credentials = (NSDictionary *)value;
		
		value = credentials[@"AccessKeyId"];
		if ([value isKindOfClass:[NSString class]])
		{
			accessKeyID = (NSString *)value;
		}
		
		value = credentials[@"SecretAccessKey"];
		if ([value isKindOfClass:[NSString class]])
		{
			secret = (NSString *)value;
		}
		
		value = credentials[@"SessionToken"];
		if ([value isKindOfClass:[NSString class]])
		{
			session = (NSString *)value;
		}
		
		value = credentials[@"Expiration"];
		if ([value isKindOfClass:[NSString class]])
		{
			expirationString = (NSString *)value;
		}
	}
	
	value = delegationDict[@"AssumedRoleUser"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *role = (NSDictionary *)value;
		
		value = role[@"Arn"];
		if ([value isKindOfClass:[NSString class]])
		{
			NSString *userARN = value;
			
			// arn:aws:sts::823589531544:assumed-role/auth0-role/b3o8qh8gy4fzfiwrrho3wd9dtjypryue

			NSCharacterSet *seperators = [NSCharacterSet characterSetWithCharactersInString:@":/"];
			NSArray *array = [userARN componentsSeparatedByCharactersInSet:seperators];
			
			if (array.count) {
				userID = [array lastObject];
			}
		}
	}

	NSDate *expirationDate = nil;
	if (expirationString)
	{
		expirationDate = [AWSDate parseISO8601Timestamp:expirationString];
	}
	
	if (outAccessKeyID) *outAccessKeyID = accessKeyID;
	if (outSecret) *outSecret = secret;
	if (outSession) *outSession = session;
	if (outExpiration) *outExpiration = expirationDate;
	if (outUserID) *outUserID = userID;
	
	return (accessKeyID.length > 0) &&
	       (secret.length > 0) &&
	       (session.length > 0) &&
	       (expirationDate != nil) &&
	       (userID.length > 0);
}

- (BOOL)parseLocalUserAuth:(ZDCLocalUserAuth **)authOut
            fromDelegation:(NSDictionary *)delegationDict
              refreshToken:(NSString *)refreshToken
                   idToken:(NSString *)idToken
{
	NSString *accessKeyID = nil;
	NSString *secret = nil;
	NSString *session = nil;
	NSDate *expiration = nil;
	NSString *userID = nil;
	
	BOOL success =
	  [self parseAccessKeyID: &accessKeyID
	                  secret: &secret
	                 session: &session
	              expiration: &expiration
	                  userID: &userID
	          fromDelegation: delegationDict];
	
	ZDCLocalUserAuth *auth = nil;
	if (success)
	{
		auth = [[ZDCLocalUserAuth alloc] init];
		
		auth.localUserID = userID;
		
		auth.aws_accessKeyID = accessKeyID;
		auth.aws_secret = secret;
		auth.aws_session = session;
		auth.aws_expiration = expiration;
		
		auth.coop_refreshToken = refreshToken;
		auth.coop_jwt = idToken;
	}
	
	if (authOut) *authOut = auth;
	return success;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)missingInvalidUserError:(NSString *)description
{
	return [NSError errorWithClass: [self class]
	                          code: AWSCredentialsErrorCode_MissingInvalidUser
	                   description: description];
}

- (NSError *)noRefreshTokensError
{
	NSString *description = @"ZDCLocalUserAuth has no valid refreshToken.";
	return [NSError errorWithClass: [self class]
	                          code: AWSCredentialsErrorCode_NoRefreshTokens
	                   description: description];
}

- (NSError *)invalidIDTokenError
{
	NSString *description = @"The given idToken parameter is invalid.";
	return [NSError errorWithClass: [self class]
	                          code: AWSCredentialsErrorCode_InvalidIDToken
	                   description: description];
}

- (NSError *)invalidServerResponseError
{
	NSString *description = @"The server returned an invalid response.";
	return [NSError errorWithClass: [self class]
	                          code: AWSCredentialsErrorCode_InvalidServerResponse
	                   description: description];
}

@end
