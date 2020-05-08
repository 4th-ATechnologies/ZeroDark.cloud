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
	
	/** The ZDCLocalUser doesn't exist, or isn't properly configured. */
	CredentialsErrorCode_MissingInvalidUser,
	
	/**
	 * The ZDCLocalUserAuth doesn't have a valid refreshToken.
	 * Ultimately this means the user will have to re-login.
	 */
	CredentialsErrorCode_MissingRefreshToken,
	
	/**
	 * The user's refreshToken has been revoked.
	 * Ultimately this means the user will have to re-login.
	 */
	CredentialsErrorCode_RevokedRefreshToken,
	
	/**
	 * The ZDCLocalUserAuth doesn't have a valid JWT.
	 * This is only used by the low-level `refreshAWSCredentials`,
	 * which expects the ZDCLocalUserAuth parameter to already have a valid JWT.
	 */
	CredentialsErrorCode_MissingJWT,
	
	/**
	 * The server returned a response that we were unable to parse.
	 */
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
 * Returns a copy of the given auth, with updated JWT credentials.
 */
- (void)refreshJWTCredentials:(ZDCLocalUserAuth *)auth
                      forUser:(ZDCLocalUser *)localUser
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(void (^)(ZDCLocalUserAuth *_Nullable auth, NSError *_Nullable error))completionBlock;

/**
 * Given an auth with a non-nil JWT, will refresh the associated AWS credentials (if needed).
 * Returns a copy of the given auth, with updated AWS credentials.
 */
- (void)refreshAWSCredentials:(ZDCLocalUserAuth *)auth
                        stage:(NSString *)stage
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(void (^)(ZDCLocalUserAuth *_Nullable auth, NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
