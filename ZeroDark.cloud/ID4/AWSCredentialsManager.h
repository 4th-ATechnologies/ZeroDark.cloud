/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import "ZDCLocalUserAuth.h"
//@class A0UserProfile;

/**
 * If an error occurs (is returned in completionBlock),
 * and the NSError.domain is CredentialsManagerErrorDomain,
 * then the NSError.code will be set to one of the following values.
**/
typedef NS_ENUM(NSInteger, S4CredentialsErrorCode) {
	S4MissingInvalidUser,
	S4NoRefreshTokens
};


@interface AWSCredentialsManager : NSObject

/**
 * Fetches the AWS credentials for the given S4LocalUser.uuid.
**/
- (void)getAWSCredentialsForUser:(NSString *)userID
                 completionQueue:(dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock;

- (void)flushAWSCredentialsForUserID:(NSString *)userID
                  deleteRefreshToken:(BOOL)deleteRefreshToken
                     completionQueue:(dispatch_queue_t)completionQueue
                     completionBlock:(dispatch_block_t)completionBlock;

- (void)reauthorizeAWSCredentialsForUserID:(NSString *)userID
                          withRefreshToken:(NSString *)refreshToken
                           completionQueue:(dispatch_queue_t)completionQueue
                           completionBlock:(void (^)(ZDCLocalUserAuth *auth, NSError *error))completionBlock;

#pragma mark Utilities

/**
 * Utility method.
 * Helpful to create a S4LocalUserAuth from Auth0APIManager getAWSCredentialsWithRefreshToken
**/
- (BOOL)parseLocalUserAuth:(ZDCLocalUserAuth **)localUserAuth
                      uuid:(NSString **)uuid
       fromDelegationToken:(NSDictionary *)delegationToken
          withRefreshToken:(NSString *)refreshToken;

@end
