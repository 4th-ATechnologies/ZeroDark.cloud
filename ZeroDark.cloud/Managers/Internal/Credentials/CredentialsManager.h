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

NS_ASSUME_NONNULL_BEGIN

/**
 * If an error occurs (i.e. an error is returned via completionBlock),
 * and the NSError.domain is CredentialsManager,
 * then the NSError.code will be set to one of the following values.
 */
typedef NS_ENUM(NSInteger, CredentialsErrorCode) {
	CredentialsErrorCode_MissingInvalidUser,
	CredentialsErrorCode_MissingRefreshToken,
	CredentialsErrorCode_RevokedRefreshToken,
	CredentialsErrorCode_InvalidServerResponse
};

/**
 * Most of the ZeroDark REST API's require valid credentials.
 *
 * The HTTP APIs require a JWT.
 * And the S3 APIs require AWS credentials.
 *
 * Both the JWT & AWS credentials are only valid for a short period of time (a few hours).
 * The user's refreshToken can be used to refresh them as needed (assuming it hasn't been revoked).
 *
 * This manager is responsible for caching these temporary credentials,
 * and automatically refreshing them on demand.
 */
@interface CredentialsManager : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark JWT
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the JWT credentials for the given ZDCLocalUser.uuid.
 *
 * If cached credentials are available (and not expired), they'll be used.
 * Otherwise the manager will attempt to refresh the credentials using the user's refreshToken.
 *
 * On success, the completionBlock will be invoked with a ZDCLocalUserAuth instance
 * whose `coop_jwt` or `partner_jwt` is non-nil and not expired.
 */
- (void)getJWTCredentialsForUser:(NSString *)userID
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCLocalUserAuth *_Nullable auth, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AWS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the AWS credentials for the given ZDCLocalUser.uuid.
 *
 * If cached credentials are available (and not expired), they'll be used.
 * Otherwise the manager will attempt to refresh the credentials using the user's refreshToken.
 */
- (void)getAWSCredentialsForUser:(NSString *)userID
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCLocalUserAuth *_Nullable auth, NSError *_Nullable error))completionBlock;

/**
 * Deletes the user's AWS credentials, by deleting the corresponding properties in ZDCLocalUserAuth.
 *
 * If the `deleteRefreshToken` parameter is TRUE, then:
 * - ZDCLocalUserAuth.coop_refreshToken will be deleted
 * - ZDCLocalUser.accountNeedsA0Token will be set to TRUE
 *
 * Use this as a way to force-logout the user, without actually deleting the localUser account.
 * This might be done, for example, if the user's account is blocked due to non-payment.
 */
- (void)flushAWSCredentialsForUser:(NSString *)userID
                deleteRefreshToken:(BOOL)deleteRefreshToken
                   completionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(dispatch_block_t)completionBlock;

/**
 * After the user logs back into the system, this can be used to reset & restart the authentication flow.
 */
- (void)resetAWSCredentialsForUser:(NSString *)userID
                  withRefreshToken:(NSString *)refreshToken
                   completionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(ZDCLocalUserAuth *_Nullable auth, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Low-Level API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Given an auth with a non-nil refreshToken, will refresh the associated JWT (if needed).
 * Returns a new auth with a valid JWT.
 */
- (void)refreshJWT:(ZDCLocalUserAuth *)auth
           forUser:(ZDCLocalUser *)localUser
   completionQueue:(nullable dispatch_queue_t)completionQueue
   completionBlock:(void (^)(ZDCLocalUserAuth *_Nullable auth, NSError *_Nullable error))completionBlock;

/**
 * Low-level API.
 *
 * Fetches the AWS credentials using the non-expired idToken (JWT).
 */
- (void)fetchAWSCredentialsWithJWT:(NSString *)idToken
                             stage:(NSString *)stage
                   completionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(NSDictionary *_Nullable delegation, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Utility method for parsing the delegation dictionary returned from the server.
 */
- (nullable ZDCLocalUserAuth *)parseAWSDelegation:(NSDictionary *)delegation;

@end

NS_ASSUME_NONNULL_END
