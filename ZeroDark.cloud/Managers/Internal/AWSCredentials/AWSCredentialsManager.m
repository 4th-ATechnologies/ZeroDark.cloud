#import "AWSCredentialsManager.h"

#import "AWSDate.h"
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
#import "NSString+JWT.h"


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
#pragma mark Credentials
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)getAWSCredentialsForUser:(NSString *)userID
                 completionQueue:(dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	if (completionQueue == NULL && completionBlock) {
		completionQueue = dispatch_get_main_queue();
	}
	
	void (^InvokeCompletionBlock)(ZDCLocalUserAuth *auth, NSError *error);
	InvokeCompletionBlock = ^(ZDCLocalUserAuth *auth, NSError *error) {
	
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock(auth, error);
			}});
		}
	};
	
	__block ZDCLocalUser *localUser = nil;
	__block ZDCLocalUserAuth *localUserAuth = nil;
	
	ZDCDatabaseManager *databaseManager = zdc.databaseManager;
	[databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		localUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		localUserAuth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{

		// check for db objects
		if (!localUserAuth || ![localUserAuth isKindOfClass:[ZDCLocalUserAuth class]])
		{
			InvokeCompletionBlock(nil, [self missingInvalidUserError]);
			return;
		}

		// check for refresh token
		if (!localUserAuth.auth0_refreshToken)
		{
			NSError *noRefreshTokensError = [self noRefreshTokensError];
			
			if (!localUser.accountNeedsA0Token)
			{
				[self setNeedsRefreshTokenForUser: userID
				                  completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
				                  completionBlock:^
				{
					InvokeCompletionBlock(nil, noRefreshTokensError);
				}];
			}
			else
			{
				InvokeCompletionBlock(nil, noRefreshTokensError);
			}
			return;
		}

		// check for unexpired token
		NSDate *nowPlusBuffer = [[NSDate date] dateByAddingTimeInterval:15.0];
		if (localUserAuth.aws_expiration && [localUserAuth.aws_expiration isAfter:nowPlusBuffer])
		{
			InvokeCompletionBlock(localUserAuth, nil);
			return;
		}

		// fetch new token
		[zdc.auth0APIManager
			getAWSCredentialsWithRefreshToken: localUserAuth.auth0_refreshToken
			                  completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
			                  completionBlock:^(NSDictionary *delegation, NSError *error)
		{
			if (error)
			{
				NSString* auth0Code = error.auth0API_error;
				if ([auth0Code isEqualToString:kAuth0Error_InvalidRefreshToken])
				{
					// account needs login
					NSError *noRefreshTokensError = [self noRefreshTokensError];
					[self setNeedsRefreshTokenForUser: userID
					                  completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
					                  completionBlock:^
					{
						InvokeCompletionBlock(nil, noRefreshTokensError);
					}];
				}
				else
				{
					InvokeCompletionBlock(nil, error);
				}
				
				return;
			}
			
			NSString *aws_accessKeyID = nil;
			NSString *aws_secret = nil;
			NSString *aws_session = nil;
			NSDate *aws_expiration = nil;
			NSString *aws_userID = nil;
			
			[self parseAccessKeyID: &aws_accessKeyID
			                secret: &aws_secret
			               session: &aws_session
			            expiration: &aws_expiration
			                userID: &aws_userID
			        fromDelegation: delegation];
			
			__block ZDCLocalUserAuth *refreshedLocalUserAuth = nil;
			
			ZDCDatabaseManager *databaseManager = zdc.databaseManager;
			[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				refreshedLocalUserAuth = [transaction objectForKey:userID inCollection:kZDCCollection_UserAuth];
				if (refreshedLocalUserAuth == nil) {
					return; // from transactionBlock - goto completionBlock
				}
				
				refreshedLocalUserAuth = [refreshedLocalUserAuth copy];
				
				// Security Check
				//
				// The aws_userID should match our userID.
				//
				// If this isn't true, then we just fetched AWS credentials for a different account.
				// This would happen if we put a refreshToken into the wrong account.
				//
				if (![aws_userID isEqual:userID])
				{
					// Remove the auth0_id entry to ensure we don't ever use it again.
					
					refreshedLocalUserAuth.aws_accessKeyID = nil;
					refreshedLocalUserAuth.aws_secret      = nil;
					refreshedLocalUserAuth.aws_session     = nil;
					refreshedLocalUserAuth.aws_expiration  = nil;
					
					[transaction setObject:refreshedLocalUserAuth forKey:userID inCollection:kZDCCollection_UserAuth];
					refreshedLocalUserAuth = nil; // <- force caller to restart
				}
				else
				{
					// Update the auth information normally

					refreshedLocalUserAuth.aws_accessKeyID = aws_accessKeyID;
					refreshedLocalUserAuth.aws_secret      = aws_secret;
					refreshedLocalUserAuth.aws_session     = aws_session;
					refreshedLocalUserAuth.aws_expiration  = aws_expiration;

					[transaction setObject:refreshedLocalUserAuth forKey:userID inCollection:kZDCCollection_UserAuth];
				}
			
			} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
				
				InvokeCompletionBlock(refreshedLocalUserAuth, nil);
			}];
		}];
	}];
	
#pragma clang diagnostic pop
}

- (void)flushAWSCredentialsForUserID:(NSString *)userID
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
				localUserAuth.auth0_refreshToken = nil;
				
				localUser = [localUser copy];
				localUser.accountNeedsA0Token = YES;
				
				[transaction setObject:localUser forKey:userID inCollection:kZDCCollection_Users];
			}

			[transaction setObject:localUserAuth forKey:userID inCollection:kZDCCollection_UserAuth];
		}
		
	} completionQueue:completionQueue completionBlock:completionBlock];
}


- (void)reauthorizeAWSCredentialsForUserID:(NSString *)userID
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

			localUserAuth.auth0_refreshToken = refreshToken;

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
		
		auth.userID = userID;
		
		auth.aws_accessKeyID = accessKeyID;
		auth.aws_secret = secret;
		auth.aws_session = session;
		auth.aws_expiration = expiration;
		
		auth.auth0_refreshToken = refreshToken;
		auth.auth0_idToken = idToken;
	}
	
	if (authOut) *authOut = auth;
	return success;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)missingInvalidUserError
{
	NSString *description = @"No matching ZDCLocalUserAuth for userID.";
	return [NSError errorWithClass: [self class]
	                          code: AWSCredentialsErrorCode_MissingInvalidUser
	                   description: description];
}

- (NSError *)noRefreshTokensError
{
	NSString *description = @"ZDCLocalUserAuth has no valid auth0_refreshToken.";
	return [NSError errorWithClass: [self class]
	                          code: AWSCredentialsErrorCode_NoRefreshTokens
	                   description: description];
}

@end
