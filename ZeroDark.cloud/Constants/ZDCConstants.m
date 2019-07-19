/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCConstants.h"

// YapDatabase collection constants

NSString *const kZDCCollection_CachedResponse  = @"ZDCCachedResponse";
NSString *const kZDCCollection_CloudNodes      = @"ZDCCloudNodes";
NSString *const kZDCCollection_Nodes           = @"ZDCNodes";
NSString *const kZDCCollection_Prefs           = @"ZDCPrefs";
NSString *const kZDCCollection_PublicKeys      = @"ZDCPublicKeys";
NSString *const kZDCCollection_PullState       = @"ZDCSyncState";
NSString *const kZDCCollection_Reminders       = @"ZDCReminders";
NSString *const kZDCCollection_SessionStorage  = @"ZDCSessionStorage";
NSString *const kZDCCollection_SymmetricKeys   = @"ZDCSymmetricKeys";
NSString *const kZDCCollection_Tasks           = @"ZDCTasks";
NSString *const kZDCCollection_Users           = @"ZDCUsers";
NSString *const kZDCCollection_UserAuth        = @"ZDCUserAuth";
NSString *const kZDCCollection_SplitKeys       = @"ZDCSplitKeys";
NSString *const kZDCCollection_SplitKeyShares  = @"ZDCSplitKeyShare";

// Names of special cloud files & file extensions

NSString *const kZDCCloudFileName_PrivateKey = @".privKey";
NSString *const kZDCCloudFileName_PublicKey  = @".pubKey";

NSString *const kZDCCloudFileExtension_Rcrd  = @"rcrd";
NSString *const kZDCCloudFileExtension_Data  = @"data";

// Names of special local files & file extensions

NSString *const kZDCDirPrefix_Home    = @"00000000000000000000000000000000";
NSString *const kZDCDirPrefix_Prefs   = @"prefs";
NSString *const kZDCDirPrefix_MsgsIn  = @"msgsIn";
NSString *const kZDCDirPrefix_MsgsOut = @"msgsOut";
NSString *const kZDCDirPrefix_Avatar  = @"avatar";

NSString *const kZDCDirPrefix_Deprecated_Msgs   = @"msgs";
NSString *const kZDCDirPrefix_Deprecated_Inbox  = @"inbox";
NSString *const kZDCDirPrefix_Deprecated_Outbox = @"outbox";

// Dictionary keys used in .rcrd files

/* extern */ NSString *const kZDCCloudRcrd_Version  = @"version";
/* extern */ NSString *const kZDCCloudRcrd_FileID   = @"fileID";
/* extern */ NSString *const kZDCCloudRcrd_Sender   = @"sender";
/* extern */ NSString *const kZDCCloudRcrd_Keys     = @"keys";
/* extern */ NSString *const kZDCCloudRcrd_Children = @"children";
/* extern */ NSString *const kZDCCloudRcrd_Meta     = @"metadata";
/* extern */ NSString *const kZDCCloudRcrd_Data     = @"data";
/* extern */ NSString *const kZDCCloudRcrd_BurnDate = @"burnDate";

/* extern */ NSString *const kZDCCloudRcrd_Keys_Perms               = @"perms";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Burn                = @"burn";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Key                 = @"key";

/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_Perms    = @"Share";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_Burn     = @"BurnDate";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_PubKeyID = @"pubKeyID";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_SymKey   = @"symKey";

/* extern */ NSString *const kZDCCloudRcrd_Children_Prefix = @"prefix";

/* extern */ NSString *const kZDCCloudRcrd_Meta_Filename       = @"filename";
/* extern */ NSString *const kZDCCloudRcrd_Meta_DirSalt        = @"dirSalt";
/* extern */ NSString *const kZDCCloudRcrd_Meta_Pointer        = @"pointer";

/* extern */ NSString *const kZDCCloudRcrd_Meta_Pointer_Owner  = @"owner";
/* extern */ NSString *const kZDCCloudRcrd_Meta_Pointer_Path   = @"path";

// Dictionary keys used in .pubKey/.privKey files

NSString *const kZDCCloudRcrd_UserID  = @"userID";
NSString *const kZDCCloudRcrd_Auth0ID = @"auth0ID";

// Auth0 API

//4th-A App ID
NSString *const kAuth04thA_AppClientID   		= @"iLjaFx3CHIyzaXYjrundOOzmYIvS1nbu";
NSString *const kAuth04thADomain     		    = @"4th-a.auth0.com";

// Auth0 Database acccount

NSString *const kAuth04thAUserDomain          = @"users.4th-a.com";
NSString *const kAuth04thARecoveryDomain      = @"recovery.4th-a.com";

NSString *const kAuth0DBConnection_UserAuth   = @"Username-Password-Authentication";
NSString *const kAuth0DBConnection_Recovery   = @"Storm4-Recovery";

// Auth0 Error codes

NSString *const kAuth0Error_RateLimit           = @"too_many_requests";
NSString *const kAuth0Error_Unauthorized        = @"unauthorized";
NSString *const kAuth0Error_InvalidRefreshToken = @"invalid_refresh_token";
NSString *const kAuth0Error_InvalidGrant 		= @"invalid_grant";
NSString *const kAuth0Error_UserExists 			= @"user_exists";
NSString *const kAuth0Error_UserNameExists 		= @"username_exists";

NSString *const kAuth0ErrorDescription_Blocked  = @"user is blocked";


// ZDC activation code file extension
NSString *const kZDCFileExtension_ActivationCode = @"zdcactivationcode";


@implementation ZDCConstants

static BOOL isIPhone;
static BOOL isIPad;
static BOOL isOSX;
static BOOL appHasPhotosPermission;
static BOOL appHasCameraPermission;


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

		appHasPhotosPermission  = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPhotoLibraryUsageDescription"] != nil;
		appHasCameraPermission  = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSCameraUsageDescription"] != nil;

	}
}

+ (BOOL)isSimulator
{
    BOOL result = NO;

#if  TARGET_OS_SIMULATOR
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
	return appHasPhotosPermission;
}

+ (BOOL)appHasCameraPermission
{
	return appHasCameraPermission;
}

// imnportant URLS - we might calculate
+ (NSURL *)ZDCsplitKeyBlogPostURL
{
	return [NSURL URLWithString:@"https://zerodarkcloud.readthedocs.io/en/latest/"];

}

+ (NSURL *)ZDCaccessKeyBlogPostURL
{
	return [NSURL URLWithString:@"https://zerodarkcloud.readthedocs.io/en/latest/"];
	
}

@end
