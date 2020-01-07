/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import "ZDCConstants.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kZDCDirPrefix_Fake; // Used for "static" nodes with a fixed set of children

extern NSString *const kZDCContext_Conflict;

extern NSString *const ZDCSkippedOperationsNotification;
extern NSString *const ZDCSkippedOperationsNotification_UserInfo_Ops;

//
// Dictionary keys within .rcrd files
//

extern NSString *const kZDCCloudRcrd_Version;
extern NSString *const kZDCCloudRcrd_FileID;
extern NSString *const kZDCCloudRcrd_Sender;
extern NSString *const kZDCCloudRcrd_Keys;
extern NSString *const kZDCCloudRcrd_Children;
extern NSString *const kZDCCloudRcrd_Meta;
extern NSString *const kZDCCloudRcrd_Data;
extern NSString *const kZDCCloudRcrd_BurnDate;

extern NSString *const kZDCCloudRcrd_Keys_Perms;
extern NSString *const kZDCCloudRcrd_Keys_Burn;
extern NSString *const kZDCCloudRcrd_Keys_Key;

extern NSString *const kZDCCloudRcrd_Keys_Deprecated_Perms;
extern NSString *const kZDCCloudRcrd_Keys_Deprecated_Burn;
extern NSString *const kZDCCloudRcrd_Keys_Deprecated_PubKeyID;
extern NSString *const kZDCCloudRcrd_Keys_Deprecated_SymKey;

extern NSString *const kZDCCloudRcrd_Children_Prefix;

extern NSString *const kZDCCloudRcrd_Meta_Filename;
extern NSString *const kZDCCloudRcrd_Meta_DirSalt;

extern NSString *const kZDCCloudRcrd_Data_Pointer;
extern NSString *const kZDCCloudRcrd_Data_Pointer_Owner;
extern NSString *const kZDCCloudRcrd_Data_Pointer_Path;
extern NSString *const kZDCCloudRcrd_Data_Pointer_CloudID;

//
// Dictionary keys used in .pubKey/.privKey files
//

extern NSString *const kZDCCloudKey_UserID;
extern NSString *const kZDCCloudKey_Auth0ID;

// ZDC activation code file extension

extern NSString *const kZDCFileExtension_ActivationCode;

// Names of special files found at resourcesURL

extern NSString *const kSupportedConfigurations;

//
// Keys used in fetchConfigWithCompletionQueue
//

extern NSString *const kSupportedConfigurations_Key_AWSRegions;
extern NSString *const kSupportedConfigurations_Key_AWSRegions_ComingSoon;
extern NSString *const kSupportedConfigurations_Key_Providers;
extern NSString *const kSupportedConfigurations_Key_AppleIAP;

// Auth0 API

extern NSString *const kAuth04thA_AppClientID;
extern NSString *const kAuth04thA_Domain;

// Auth0 Database acccount

extern NSString *const kAuth04thAUserDomain;
extern NSString *const kAuth04thARecoveryDomain;

extern NSString *const kAuth0DBConnection_UserAuth;
extern NSString *const kAuth0DBConnection_Recovery;

// Auth0 Error codes

extern NSString *const kAuth0Error_RateLimit;
extern NSString *const kAuth0Error_Unauthorized;
extern NSString *const kAuth0Error_InvalidRefreshToken;
extern NSString *const kAuth0Error_InvalidGrant;
extern NSString *const kAuth0Error_UserExists;
extern NSString *const kAuth0Error_UserNameExists;

extern NSString *const kAuth0ErrorDescription_Blocked; // extra qualifier for unauthorized


@interface ZDCConstants: NSObject

+ (BOOL)isIPhone;      // if (ZDCConstants.isIPhone) ...
+ (BOOL)isIPad;        // if (ZDCConstants.isIPad) ...
+ (BOOL)isOSX;         // if (ZDCConstants.isOSX) ...
+ (BOOL)isSimulator;   // if (ZDCConstants.isSimulator) ...

+ (BOOL)appHasPhotosPermission;
+ (BOOL)appHasCameraPermission;

// Important URLS
+ (NSURL *)ZDCsplitKeyBlogPostURL;
+ (NSURL *)ZDCaccessKeyBlogPostURL;
+ (NSURL *)ZDCblockchainVerifyURLForUserID:(NSString*)userID;

@end

NS_ASSUME_NONNULL_END
