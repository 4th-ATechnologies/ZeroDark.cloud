/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "ZDCPullManager.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZDCPullErrorReason) {
	
	ZDCPullErrorReason_None = 0,
	
	ZDCPullErrorReason_Auth0Error,
	ZDCPullErrorReason_AwsAuthError,
	ZDCPullErrorReason_ExceededMaxRetries,
	ZDCPullErrorReason_BadData,
	ZDCPullErrorReason_HttpStatusCode,
	ZDCPullErrorReason_LocalTreesystemChanged
};

/**
 * Used by ZDCPullManager as a parameter for completionBlocks.
 */
@interface ZDCPullTaskResult : NSObject

+ (ZDCPullTaskResult *)success;

@property (nonatomic, readwrite) ZDCPullResult pullResult;
@property (nonatomic, readwrite) ZDCPullErrorReason pullErrorReason;
@property (nonatomic, readwrite) NSInteger httpStatusCode;
@property (nonatomic, readwrite) NSError *underlyingError;

@end

NS_ASSUME_NONNULL_END
