/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCData.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCDataPromise ()

/**
 * Adds a listener for the promise.
 *
 * The completionBlock will be invoked asynchronously,
 * even if the promise is already fulfilled/rejected.
 */
- (void)pushCompletionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(ZDCData *_Nullable nodeData))completionBlock;

@end

NS_ASSUME_NONNULL_END
