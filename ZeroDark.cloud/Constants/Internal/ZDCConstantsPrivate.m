/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCConstantsPrivate.h"

NSString *const kZDCDirPrefix_Fake = @"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";

NSString *const kZDCContext_Conflict = @"ZDC:Conflict";

NSString *const ZDCSkippedOperationsNotification = @"ZDCSkippedOperationsNotification";
NSString *const ZDCSkippedOperationsNotification_UserInfo_Ops = @"ops";

//
// Dictionary keys used in "*.rcrd" files.
// See header file for explanation.
// 

NSString *const kZDCCloudRcrd_Version  = @"version";
NSString *const kZDCCloudRcrd_FileID   = @"fileID";
NSString *const kZDCCloudRcrd_Sender   = @"sender";
NSString *const kZDCCloudRcrd_Keys     = @"keys";
NSString *const kZDCCloudRcrd_Children = @"children";
NSString *const kZDCCloudRcrd_Meta     = @"metadata";
NSString *const kZDCCloudRcrd_Data     = @"data";
NSString *const kZDCCloudRcrd_BurnDate = @"burnDate";

NSString *const kZDCCloudRcrd_Keys_Perms               = @"perms";
NSString *const kZDCCloudRcrd_Keys_Burn                = @"burn";
NSString *const kZDCCloudRcrd_Keys_Key                 = @"key";

NSString *const kZDCCloudRcrd_Keys_Deprecated_Perms    = @"Share";
NSString *const kZDCCloudRcrd_Keys_Deprecated_Burn     = @"BurnDate";
NSString *const kZDCCloudRcrd_Keys_Deprecated_PubKeyID = @"pubKeyID";
NSString *const kZDCCloudRcrd_Keys_Deprecated_SymKey   = @"symKey";

NSString *const kZDCCloudRcrd_Children_Prefix = @"prefix";

NSString *const kZDCCloudRcrd_Meta_Filename       = @"filename";
NSString *const kZDCCloudRcrd_Meta_DirSalt        = @"dirSalt";

NSString *const kZDCCloudRcrd_Data_Pointer        = @"pointer";

NSString *const kZDCCloudRcrd_Data_Pointer_Owner   = @"owner";
NSString *const kZDCCloudRcrd_Data_Pointer_Path    = @"path";
NSString *const kZDCCloudRcrd_Data_Pointer_CloudID = @"cloudID";

// Dictionary keys used in .pubKey/.privKey files

NSString *const kZDCCloudKey_UserID  = @"userID";
NSString *const kZDCCloudKey_Auth0ID = @"auth0ID";

// ZDC activation code file extension

NSString *const kZDCFileExtension_ActivationCode = @"zdcactivationcode";

// Names of special files found at resourcesURL

NSString *const kSupportedConfigurations = @"supportedconfig.json";

// KEYS USED IN fetchConfigWithCompletionQueue

NSString *const kSupportedConfigurations_Key_AWSRegions            = @"supportedAWSRegionNumbers";
NSString *const kSupportedConfigurations_Key_AWSRegions_ComingSoon = @"commingSoonAWSRegionNumbers";
NSString *const kSupportedConfigurations_Key_Providers             = @"supportedIdentityProviders";
NSString *const kSupportedConfigurations_Key_AppleIAP              = @"supportedAppleIap";

// Auth0 API

NSString *const kAuth04thA_AppClientID        = @"iLjaFx3CHIyzaXYjrundOOzmYIvS1nbu";
NSString *const kAuth04thA_Domain              = @"4th-a.auth0.com";

// Auth0 Database acccount

NSString *const kAuth04thAUserDomain          = @"users.4th-a.com";
NSString *const kAuth04thARecoveryDomain      = @"recovery.4th-a.com";

NSString *const kAuth0DBConnection_UserAuth   = @"Username-Password-Authentication";
NSString *const kAuth0DBConnection_Recovery   = @"Storm4-Recovery";

// Auth0 Error codes

NSString *const kAuth0Error_RateLimit           = @"too_many_requests";
NSString *const kAuth0Error_Unauthorized        = @"unauthorized";
NSString *const kAuth0Error_InvalidRefreshToken = @"invalid_refresh_token";
NSString *const kAuth0Error_InvalidGrant        = @"invalid_grant";
NSString *const kAuth0Error_UserExists 			= @"user_exists";
NSString *const kAuth0Error_UserNameExists 		= @"username_exists";

NSString *const kAuth0ErrorDescription_Blocked  = @"user is blocked";


@implementation ZDCConstants

static BOOL isIPhone = NO;
static BOOL isIPad = NO;
static BOOL isOSX = NO;

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		
#if TARGET_OS_IPHONE
		
		UIUserInterfaceIdiom userInterfaceIdiom = [[UIDevice currentDevice] userInterfaceIdiom];
		
		isIPhone = (userInterfaceIdiom == UIUserInterfaceIdiomPhone);
		isIPad   = (userInterfaceIdiom == UIUserInterfaceIdiomPad);
		
#else
		
		isIPhone = NO;
		isIPad = NO;
		isOSX = YES;
		
#endif
	}
}

+ (BOOL)isSimulator
{
	BOOL result = NO;
#if TARGET_OS_SIMULATOR
	result = YES;
#endif
	return result;
}

+ (BOOL)isIPhone
{
	return isIPhone;
}

+ (BOOL)isIPad
{
	return isIPad;
}

+ (BOOL)isOSX
{
	return isOSX;
}

+ (BOOL)appHasPhotosPermission
{
	static BOOL appHasPhotosPermission = NO;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		appHasPhotosPermission = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPhotoLibraryUsageDescription"] != nil;
	});
	
	return appHasPhotosPermission;
}

+ (BOOL)appHasCameraPermission
{
	static BOOL appHasCameraPermission;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		appHasCameraPermission  = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSCameraUsageDescription"] != nil;
	});
	
	return appHasCameraPermission;
}

+ (NSURL *)ZDCsplitKeyBlogPostURL
{
	return [NSURL URLWithString:@"https://zerodarkcloud.readthedocs.io/en/latest/"];
}

+ (NSURL *)ZDCaccessKeyBlogPostURL
{
	return [NSURL URLWithString:@"https://zerodarkcloud.readthedocs.io/en/latest/"];
}

+ (NSURL *)ZDCblockchainVerifyURLForUserID:(NSString*)userID
{
	NSString *const urlStr = [NSString stringWithFormat:@"https://users.storm4.cloud/id/%@", userID];
	return [NSURL URLWithString:urlStr];
}


@end
