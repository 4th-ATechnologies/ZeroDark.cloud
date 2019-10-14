/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "A0UserProfile.h"
#import "Auth0API.h"

@class Auth0LoginResult;
@class Auth0LoginProfileResult;

NS_ASSUME_NONNULL_BEGIN

@interface Auth0APIManager : NSObject

+ (Auth0APIManager *)sharedInstance;

/**
 * Uses the '/dbconnections/signup' API to create a new traditional user,
 * using a username & password.
 */
- (void)createUserWithEmail:(NSString *)email
                   username:(NSString *)username
                   password:(NSString *)password
            auth0Connection:(NSString *)auth0Connection
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSString *_Nullable auth0ID,
                                      NSError *_Nullable error))completionBlock;

/**
 * Attempts to login using the given credentials.
 *
 * On success, a refreshToken is returned (via the completionBlock).
 * Otherwise an error returned.
 */
- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
          auth0Connection:(NSString *)auth0Connection
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(void (^)(Auth0LoginResult *_Nullable result,
                                    NSError *_Nullable error))completionBlock;

/**
 * Combines login with the standard flow of fetching the user's profile.
 */
- (void)loginAndGetProfileWithUsername:(NSString *)username
                              password:(NSString *)password
                       auth0Connection:(NSString *)auth0Connection
                       completionQueue:(nullable dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(Auth0LoginProfileResult *_Nullable result,
                                                 NSError *_Nullable error))completionBlock;

/**
 * Trades a refreshToken for an idToken.
 *
 * A refreshToken is an opaque token that doesn't expire (although it can be revoked).
 * An idToken is a JWT - signed by auth0, and has an expiration date.
 * The idToken is only used for one think: it can be exchanged for AWS credentials.
 */
- (void)getIDTokenWithRefreshToken:(NSString *)auth0_refreshToken
                   completionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(NSString * _Nullable auth0_idToken,
                                             NSError *_Nullable error))completionBlock;

/**
 * Trades a refreshToken for an accessToken.
 *
 * A refreshToken is an opaque token that doesn't expire (although it can be revoked).
 * An accessToken is another opaque token, but does expire.
 * The accessToken is only used for one thing: it's required to fetch the user profile.
 */
- (void)getAccessTokenWithRefreshToken:(NSString *)auth0_refreshToken
                       completionQueue:(nullable dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(NSString * _Nullable auth0_accessToken,
                                                 NSError *_Nullable error))completionBlock;

/**
 * Fetches the user's profile (which requires a valid accessToken).
 */
- (void)getUserProfileWithAccessToken:(NSString *)auth0_accessToken
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(A0UserProfile *_Nullable profile,
                                                NSError *_Nullable error))completionBlock;

/**
 * Scheduled for deprecation...
 */
- (void)getAWSCredentialsWithRefreshToken:(NSString *)auth0_refreshToken
                          completionQueue:(nullable dispatch_queue_t)inCompletionQueue
                          completionBlock:(void (^)(NSDictionary *_Nullable delegation,
                                                    NSError *_Nullable error))completionBlock;
/**
 * Extracts callback URL scheme from Info.plist.
 */
- (NSString *)callbackURLscheme;

/**
 * Returns the URL used for Authorization Code Flow with Proof Key for Code Exchange (PKCE).
 * More information can be found [here](https://auth0.com/docs/flows/concepts/auth-code-pkce).
 */
- (NSURL *)socialQueryURLforStrategyName:(NSString *)strategyName
                       callBackURLScheme:(NSString *)callBackURLScheme
                               csrfState:(NSString *)csrfState
                                pkceCode:(NSString *)pkceCode;

/**
 * Parses the given social query string into a standard dictionary format.
 */
- (NSDictionary *)parseQueryString:(NSString *)queryString;

/**
 *
 */
- (void)exchangeAuthorizationCode:(NSString *)code
                         pkceCode:(NSString *)pkceCode
                  completionQueue:(nullable dispatch_queue_t)completionQueue
                  completionBlock:(void (^)(NSDictionary *_Nullable dict, NSError *_Nullable error))completionBlock;

-(BOOL) decodeSocialQueryString:(NSString*)queryString
						a0Token:(A0Token * _Nullable*_Nullable) a0TokenOut
					  CSRFState:(NSString * _Nullable*_Nullable) CSRFStateOut
						  error:(NSError ** _Nullable)errorOut;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface Auth0LoginResult: NSObject

/**
 * The refreshToken is a persistent token that never expires (although it can be manually revoked).
 * It can be used in the future to fetch either an idToken (JWT) or an accessToken.
 */
@property (nonatomic, copy, readonly) NSString *refreshToken;

/**
 * An idToken is a JWT with an expiration.
 * This can be used to fetch AWS credentials.
 */
@property (nonatomic, copy, readonly) NSString *idToken;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface Auth0LoginProfileResult : Auth0LoginResult

/**
 * The Auth0 user profile, including all linked identities.
 */
@property (nonatomic, strong, readonly) A0UserProfile *profile;

@end

NS_ASSUME_NONNULL_END
