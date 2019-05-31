/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
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
