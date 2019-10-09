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

NS_ASSUME_NONNULL_BEGIN

extern NSString *const Auth0APIManagerErrorDomain;

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
          completionBlock:(void (^)(NSString *_Nullable auth0_refreshToken,
                                    NSError *_Nullable error))completionBlock;

- (void)loginAndGetProfileWithUsername:(NSString *)username
                              password:(NSString *)password
                       auth0Connection:(NSString *)auth0Connection
                       completionQueue:(nullable dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(NSString *_Nullable auth0_refreshToken,
                                                 NSString *_Nullable auth0_accessToken,
                                                 A0UserProfile *_Nullable profile,
                                                 NSError *_Nullable error))completionBlock;

/**
 * Trades a refreshToken for an accessToken.
 *
 * A refreshToken is an opaque token that doesn't expire (although it can be revoked).
 * An accessToken is a JWT the expires after a set amount of time.
 */
- (void)getAccessTokenWithRefreshToken:(NSString *)auth0_refreshToken
                       completionQueue:(nullable dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(NSString * _Nullable auth0_accessToken,
                                                 NSError *_Nullable error))completionBlock;

-(void) getUserProfileWithAccessToken:(NSString*)auth0_accessToken
					  completionQueue:(nullable dispatch_queue_t)inCompletionQueue
					  completionBlock:(void (^)(A0UserProfile * _Nullable a0Profile ,
												NSError *_Nullable error))completionBlock;

-(void) getAWSCredentialsWithRefreshToken:(NSString *)auth0_refreshToken
						  completionQueue:(nullable dispatch_queue_t)inCompletionQueue
						  completionBlock:(void (^)(NSDictionary * _Nullable delegationToken,
													NSError *_Nullable error))completionBlock;

-(NSURL*) socialQueryURLforStrategyName:(NSString*)strategyName
					  callBackURLScheme:(NSString*)callBackURLScheme
							  CSRFState:(NSString* _Nullable)CSRFState;

-(NSString*) callbackURLscheme;

-(BOOL) decodeSocialQueryString:(NSString*)queryString
						a0Token:(A0Token * _Nullable*_Nullable) a0TokenOut
					  CSRFState:(NSString * _Nullable*_Nullable) CSRFStateOut
						  error:(NSError ** _Nullable)errorOut;
@end

NS_ASSUME_NONNULL_END
