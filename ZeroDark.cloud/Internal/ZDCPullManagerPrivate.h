/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPullManager.h"
#import "ZeroDarkCloud.h"
#import "ZDCPushInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPullManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/** Forwarded from ZeroDarkCloud. */
- (void)processPushNotification:(ZDCPushInfo *)pushInfo
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(void (^)(BOOL needsPull))completionBlock;

@end

NS_ASSUME_NONNULL_END
