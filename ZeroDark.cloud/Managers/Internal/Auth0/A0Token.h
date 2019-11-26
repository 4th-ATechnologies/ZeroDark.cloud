/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  `A0Token` holds all token information for a user.
 */
@interface A0Token : NSObject <NSSecureCoding>

/**
 * bridge from new Auth0 to old Auth0 API
 */
+ (instancetype __nullable)tokenFromDictionary:(NSDictionary *)dict;

+ (A0Token *)tokenFromAccessToken:(NSString *)access_token
                     refreshToken:(NSString *)refresh_token;

/**
 *  User's accessToken for Auth0 API
 */
@property (readonly, nullable, nonatomic) NSString *accessToken;

/**
 *  User's JWT token
 */
@property (readonly, nonatomic) NSString *idToken;

/**
 *  Type of token return by Auth0 API
 */
@property (readonly, nonatomic) NSString *tokenType;

/**
 *  Refresh token used to obtain new JWT tokens. Can be nil if no offline access was requested
 */
@property (readonly, nullable, nonatomic) NSString *refreshToken;

@end

NS_ASSUME_NONNULL_END
