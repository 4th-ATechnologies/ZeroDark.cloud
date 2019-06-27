/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 *
 * These classes were copied from Auth0's framework.
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


///----------------------------------------
/// @name Strategy Names
///----------------------------------------

FOUNDATION_EXPORT NSString * const A0StrategyNameGoogleOpenId;
FOUNDATION_EXPORT NSString * const A0StrategyNameGoogleApps;
FOUNDATION_EXPORT NSString * const A0StrategyNameGooglePlus;
FOUNDATION_EXPORT NSString * const A0StrategyNameFacebook;
FOUNDATION_EXPORT NSString * const A0StrategyNameWindowsLive;
FOUNDATION_EXPORT NSString * const A0StrategyNameLinkedin;
FOUNDATION_EXPORT NSString * const A0StrategyNameGithub;
FOUNDATION_EXPORT NSString * const A0StrategyNamePaypal;
FOUNDATION_EXPORT NSString * const A0StrategyNameTwitter;
FOUNDATION_EXPORT NSString * const A0StrategyNameAmazon;
FOUNDATION_EXPORT NSString * const A0StrategyNameVK;
FOUNDATION_EXPORT NSString * const A0StrategyNameYandex;
FOUNDATION_EXPORT NSString * const A0StrategyNameOffice365;
FOUNDATION_EXPORT NSString * const A0StrategyNameWaad;
FOUNDATION_EXPORT NSString * const A0StrategyNameADFS;
FOUNDATION_EXPORT NSString * const A0StrategyNameSAMLP;
FOUNDATION_EXPORT NSString * const A0StrategyNamePingFederate;
FOUNDATION_EXPORT NSString * const A0StrategyNameIP;
FOUNDATION_EXPORT NSString * const A0StrategyNameMSCRM;
FOUNDATION_EXPORT NSString * const A0StrategyNameActiveDirectory;
FOUNDATION_EXPORT NSString * const A0StrategyNameCustom;
FOUNDATION_EXPORT NSString * const A0StrategyNameAuth0;
FOUNDATION_EXPORT NSString * const A0StrategyNameAuth0LDAP;
FOUNDATION_EXPORT NSString * const A0StrategyName37Signals;
FOUNDATION_EXPORT NSString * const A0StrategyNameBox;
FOUNDATION_EXPORT NSString * const A0StrategyNameSalesforce;
FOUNDATION_EXPORT NSString * const A0StrategyNameSalesforceSandbox;
FOUNDATION_EXPORT NSString * const A0StrategyNameFitbit;
FOUNDATION_EXPORT NSString * const A0StrategyNameBaidu;
FOUNDATION_EXPORT NSString * const A0StrategyNameRenRen;
FOUNDATION_EXPORT NSString * const A0StrategyNameYahoo;
FOUNDATION_EXPORT NSString * const A0StrategyNameAOL;
FOUNDATION_EXPORT NSString * const A0StrategyNameYammer;
FOUNDATION_EXPORT NSString * const A0StrategyNameWordpress;
FOUNDATION_EXPORT NSString * const A0StrategyNameDwolla;
FOUNDATION_EXPORT NSString * const A0StrategyNameShopify;
FOUNDATION_EXPORT NSString * const A0StrategyNameMiicard;
FOUNDATION_EXPORT NSString * const A0StrategyNameSoundcloud;
FOUNDATION_EXPORT NSString * const A0StrategyNameEBay;
FOUNDATION_EXPORT NSString * const A0StrategyNameEvernote;
FOUNDATION_EXPORT NSString * const A0StrategyNameEvernoteSandbox;
FOUNDATION_EXPORT NSString * const A0StrategyNameSharepoint;
FOUNDATION_EXPORT NSString * const A0StrategyNameWeibo;
FOUNDATION_EXPORT NSString * const A0StrategyNameInstagram;
FOUNDATION_EXPORT NSString * const A0StrategyNameTheCity;
FOUNDATION_EXPORT NSString * const A0StrategyNameTheCitySandbox;
FOUNDATION_EXPORT NSString * const A0StrategyNamePlanningCenter;
FOUNDATION_EXPORT NSString * const A0StrategyNameSMS;
FOUNDATION_EXPORT NSString * const A0StrategyNameEmail;

/**
 *  `A0Token` holds all token information for a user.
 */
@interface A0Token : NSObject<NSSecureCoding>
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

/**
 ** bridge from new Auth0 to old Auth0 API
 **/

+(instancetype __nullable) tokenFromDictionary:(NSDictionary*) dict;

+(A0Token*) tokenFromAccessToken:(NSString *)access_token
					refreshToken:(NSString *)refresh_token;

@end

NS_ASSUME_NONNULL_END
