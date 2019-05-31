/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import "A0UserProfile.h"
#import "Auth0API.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const Auth0APIManagerErrorDomain;

@interface Auth0APIManager : NSObject

+ (Auth0APIManager *)sharedInstance;

- (void)createUserWithEmail:(NSString *)email
                   username:(NSString *)username
                   password:(NSString *)password
            auth0Connection:(nullable NSString *)auth0Connection  // defaults to kAuth0DBConnection_UserAuth
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSString *_Nullable auth0ID, NSError *_Nullable error))completionBlock;

- (void)loginWithUserName:(NSString *)userName
                 password:(NSString *)password
          auth0Connection:(NSString *)auth0Connection
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(void (^)(NSString *_Nullable auth0_refreshToken,
                                     NSError *_Nullable error))completionBlock;

- (void)loginAndGetProfileWithUserName:(NSString *)userName
                              password:(NSString *)password
                       auth0Connection:(NSString *)auth0Connection
                       completionQueue:(nullable dispatch_queue_t)completionQueue
                       completionBlock:(void (^)(NSString *_Nullable auth0_refreshToken,
                                                 A0UserProfile *_Nullable profile,
                                                 NSError *_Nullable error))completionBlock;

-(void) getAccessTokenWithRefreshToken:(NSString *)auth0_refreshToken
					   completionQueue:(nullable dispatch_queue_t)inCompletionQueue
					   completionBlock:(void (^)(NSString * _Nullable auth0_accessToken,
												 NSDate*	_Nullable 	auth0_expiration,
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
