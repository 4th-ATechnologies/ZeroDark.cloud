/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCConstantsPrivate.h"

NSString *const kZDCDirPrefix_Fake = @"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";

NSString *const kZDCContext_Conflict = @"ZDC:Conflict";

NSString *const ZDCSkippedOperationsNotification = @"ZDCSkippedOperationsNotification";
NSString *const ZDCSkippedOperationsNotification_UserInfo_Ops = @"ops";

// Names of special files found at resourcesURL

NSString *const kSupportedConfigurations = @"supportedconfig.json";

// KEYS USED IN fetchConfigWithCompletionQueue

NSString *const kSupportedConfigurations_Key_AWSRegions            = @"supportedAWSRegionNumbers";
NSString *const kSupportedConfigurations_Key_AWSRegions_ComingSoon = @"commingSoonAWSRegionNumbers";
NSString *const kSupportedConfigurations_Key_Providers             = @"supportedIdentityProviders";
NSString *const kSupportedConfigurations_Key_AppleIAP              = @"supportedAppleIap";

