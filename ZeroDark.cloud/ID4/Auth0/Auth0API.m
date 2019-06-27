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

#import "Auth0API.h"


NSString * const A0StrategyNameGoogleOpenId = @"google-openid";
NSString * const A0StrategyNameGoogleApps = @"google-apps";
NSString * const A0StrategyNameGooglePlus = @"google-oauth2";
NSString * const A0StrategyNameFacebook = @"facebook";
NSString * const A0StrategyNameWindowsLive = @"windowslive";
NSString * const A0StrategyNameLinkedin = @"linkedin";
NSString * const A0StrategyNameGithub = @"github";
NSString * const A0StrategyNamePaypal = @"paypal";
NSString * const A0StrategyNameTwitter = @"twitter";
NSString * const A0StrategyNameAmazon = @"amazon";
NSString * const A0StrategyNameVK = @"vkontakte";
NSString * const A0StrategyNameYandex = @"yandex";
NSString * const A0StrategyNameOffice365 = @"office365";
NSString * const A0StrategyNameWaad = @"waad";
NSString * const A0StrategyNameADFS = @"adfs";
NSString * const A0StrategyNameSAMLP = @"samlp";
NSString * const A0StrategyNamePingFederate = @"pingfederate";
NSString * const A0StrategyNameIP = @"ip";
NSString * const A0StrategyNameMSCRM = @"mscrm";
NSString * const A0StrategyNameActiveDirectory = @"ad";
NSString * const A0StrategyNameCustom = @"custom";
NSString * const A0StrategyNameAuth0 = @"auth0";
NSString * const A0StrategyNameAuth0LDAP = @"auth0-adldap";
NSString * const A0StrategyName37Signals = @"thirtysevensignals";
NSString * const A0StrategyNameBox = @"box";
NSString * const A0StrategyNameSalesforce = @"salesforce";
NSString * const A0StrategyNameSalesforceSandbox = @"salesforce-sandbox";
NSString * const A0StrategyNameFitbit = @"fitbit";
NSString * const A0StrategyNameBaidu = @"baidu";
NSString * const A0StrategyNameRenRen = @"renren";
NSString * const A0StrategyNameYahoo = @"yahoo";
NSString * const A0StrategyNameAOL = @"aol";
NSString * const A0StrategyNameYammer = @"yammer";
NSString * const A0StrategyNameWordpress = @"wordpress";
NSString * const A0StrategyNameDwolla = @"dwolla";
NSString * const A0StrategyNameShopify = @"shopify";
NSString * const A0StrategyNameMiicard = @"miicard";
NSString * const A0StrategyNameSoundcloud = @"soundcloud";
NSString * const A0StrategyNameEBay = @"ebay";
NSString * const A0StrategyNameEvernote = @"evernote";
NSString * const A0StrategyNameEvernoteSandbox = @"evernote-sandbox";
NSString * const A0StrategyNameSharepoint = @"sharepoint";
NSString * const A0StrategyNameWeibo = @"weibo";
NSString * const A0StrategyNameInstagram = @"instagram";
NSString * const A0StrategyNameTheCity = @"thecity";
NSString * const A0StrategyNameTheCitySandbox = @"thecity-sandbox";
NSString * const A0StrategyNamePlanningCenter = @"planningcenter";
NSString * const A0StrategyNameSMS = @"sms";
NSString * const A0StrategyNameEmail = @"email";

#pragma mark - A0Token

@implementation A0Token

- (instancetype)initWithAccessToken:(NSString *)accessToken
							idToken:(NSString *)idToken
						  tokenType:(NSString *)tokenType
					   refreshToken:(NSString *)refreshToken {
	self = [super init];
	if (self) {
		NSAssert(tokenType.length > 0, @"Must have a valid token type");
		_accessToken = [accessToken copy];
		_idToken = [idToken copy];
		_tokenType = [tokenType copy];
		_refreshToken = [refreshToken copy];
	}
	return self;
}

+(A0Token*) tokenFromAccessToken:(NSString *)access_token
				   refreshToken:(NSString *)refresh_token
{
	A0Token* token = nil;

	if(refresh_token  || access_token)
	{
		token = [[A0Token alloc] initWithAccessToken:access_token
											 idToken:nil
										   tokenType:@"Bearer"
										refreshToken:refresh_token];
	}


	return token;
}


+(A0Token* __nullable) tokenFromDictionary:(NSDictionary*) dict
{
	NSString* access_token    = dict[@"access_token"];
	NSString*  id_token       = dict [@"id_token"];
	NSString*  refresh_token  = dict [@"refresh_token"];
	NSString*  token_type     = dict [@"token_type"];

	A0Token* token = nil;

	if(token_type && (id_token || access_token))
	{
		token = [[A0Token alloc] initWithAccessToken:access_token
											 idToken:id_token
										   tokenType:token_type
										refreshToken:refresh_token];
	}
	return token;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
	return [self initWithAccessToken:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(accessToken))]
							 idToken:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(idToken))]
						   tokenType:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(tokenType))]
						refreshToken:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(refreshToken))]];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
	if (self.accessToken) {
		[aCoder encodeObject:self.accessToken forKey:NSStringFromSelector(@selector(accessToken))];
	}
	if (self.refreshToken) {
		[aCoder encodeObject:self.refreshToken forKey:NSStringFromSelector(@selector(refreshToken))];
	}
	[aCoder encodeObject:self.idToken forKey:NSStringFromSelector(@selector(idToken))];
	[aCoder encodeObject:self.tokenType forKey:NSStringFromSelector(@selector(tokenType))];
}

+ (BOOL)supportsSecureCoding {
	return YES;
}

-(NSString *) description
{
	NSString *description = [NSString stringWithFormat:@"<%@: %#x (\naccessToken: %@ \nidToken: %@ \ntokenType: %@ \nrefreshToken: %@\n)>",
							 NSStringFromClass([self class]), (unsigned int) self,
							 _accessToken,_idToken,_tokenType,_refreshToken
							 ];
	return description;
}

@end
