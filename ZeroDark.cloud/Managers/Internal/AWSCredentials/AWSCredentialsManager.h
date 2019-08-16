/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZeroDarkCloud.h"
#import "ZDCLocalUserAuth.h"

/**
 * If an error occurs (i.e. an error is returned via completionBlock),
 * and the NSError.domain is AWSCredentialsManager,
 * then the NSError.code will be set to one of the following values.
 */
typedef NS_ENUM(NSInteger, AWSCredentialsErrorCode) {
	AWSCredentialsErrorCode_MissingInvalidUser,
	AWSCredentialsErrorCode_NoRefreshTokens
};

/**
 * Most of the ZeroDark REST API's require valid AWS credentials.
 *
 * These are provided via a standard delegation system.
 * A refreshToken is used to request temporary AWS credentials.
 * As long as the refreshToken hasn't been revoked, the server will return AWS credentials.
 * The temporary credentials are only valid for a short period of time (a few hours).
 *
 * This manager is responsible for caching these temporary credentials,
 * and automatically refreshing them on demand.
 */
@interface AWSCredentialsManager : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Fetches the AWS credentials for the given ZDCLocalUser.uuid.
 *
 * If cached credentials are available (and not expired), they'll be used.
 * Otherwise the manager will attempt to refresh the AWS credentials using the refreshToken.
 */
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
 * Utility method for parsing the delegation dictionary returned from the server.
 */
- (BOOL)parseLocalUserAuth:(ZDCLocalUserAuth **)localUserAuth
                      uuid:(NSString **)uuid
       fromDelegationToken:(NSDictionary *)delegationToken
          withRefreshToken:(NSString *)refreshToken;

@end
