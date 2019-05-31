/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import "ZDCConstants.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kZDCDirPrefix_Fake; // Used for "static" nodes with a fixed set of children

extern NSString *const ZDCSkippedOperationsNotification;
extern NSString *const ZDCSkippedOperationsNotification_UserInfo_Ops;

// Names of special files found at resourcesURL

extern NSString *const kSupportedConfigurations;

// KEYS USED IN fetchConfigWithCompletionQueue

extern NSString *const kSupportedConfigurations_Key_AWSRegions;
extern NSString *const kSupportedConfigurations_Key_AWSRegions_ComingSoon;
extern NSString *const kSupportedConfigurations_Key_Providers;
extern NSString *const kSupportedConfigurations_Key_AppleIAP;


@interface ZDCConstants (private)

+ (BOOL)isIPhone;      // if (ZDCConstants.isIPhone) ...
+ (BOOL)isIPad;        // if (ZDCConstants.isIPad) ...
+ (BOOL)isOSX;         // if (ZDCConstants.isOSX) ...
+ (BOOL)isSimulator;   // if (ZDCConstants.isSimulator) ...

+ (BOOL)appHasPhotosPermission;
+ (BOOL)appHasCameraPermission;


// important URLS
+ (NSURL *)ZDCsplitKeyBlogPostURL;
+ (NSURL *)ZDCaccessKeyBlogPostURL;


@end

NS_ASSUME_NONNULL_END
