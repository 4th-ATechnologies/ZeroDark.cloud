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
 * Represents a user's linked account. E.g. Facebook
 *
 * Part of this code is courtesy of Auth0.
 */
@interface A0UserIdentity : NSObject <NSCoding>

/**
 *  Name of the connection used to link this account
 */
@property (readonly, nonatomic) NSString *connection;

/**
 *  Name of the identity provider
 */
@property (readonly, nonatomic) NSString *provider;

/**
 *  User Id in the identity provider
 */
@property (readonly, nonatomic) NSString *userId;

/**
 *  Flag that indicates if the identity is `Social`. e.g: Facebook
 */
@property (readonly, nonatomic, getter = isSocial) BOOL social;

/**
 *  If the identity provider is OAuth2, you will find the access_token that can be used to call the provider API
 *  and obtain more information from the user (e.g: Facebook friends, Google contacts, LinkedIn contacts, etc.).
 */
@property (readonly, nonatomic) NSString *accessToken;

/**
 *  Identity id for Auth0 api. It has the format `provider|userId`
 */
@property (readonly, nonatomic) NSString *identityId;

/**
 *  If the identity provider is OAuth 1.0a, an access_token_secret property will be present
 *  and can be used to call the provider API and obtain more information from the user.
 *  Currently only for twitter.
 */
@property (readonly, nonatomic) NSString *accessTokenSecret;

/**
 *  User's profile data in the Identity Provider
 */
@property (readonly, nonatomic) NSDictionary *profileData;

/**
 ** bridge from new Auth0 to old Auth0 API
 **/

//-(instancetype) initWithA0Identity:(A0Identity*)ident;


/// fix this to init with identityFromDictionary

+ (instancetype)identityFromDictionary:(NSDictionary *)dict;


@end

NS_ASSUME_NONNULL_END
