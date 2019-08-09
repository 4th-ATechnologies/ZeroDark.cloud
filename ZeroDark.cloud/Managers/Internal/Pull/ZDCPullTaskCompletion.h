/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCPullTaskResult.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Standard completionBlock used by ZDCPullManager.
 */
typedef void(^ZDCPullTaskCompletion)(YapDatabaseReadWriteTransaction *_Nullable transaction,
                                                   ZDCPullTaskResult *_Nonnull  result);

/**
 * Extended completionBlock used by ZDCPullTaskMultiCompletion.
 */
typedef void(^ZDCPullTaskSingleCompletion)(YapDatabaseReadWriteTransaction *_Nullable transaction,
                                                         ZDCPullTaskResult *_Nonnull  result,
                                                                      uint            remaining);

/**
 * A MultiCompletion is a wrapper around ZDCPullTaskCompletion that's used when multiple tasks
 * need to complete before a final completionBlock can be invoked.
 */
@interface ZDCPullTaskMultiCompletion : NSObject

/**
 * @param pendingCount
 *   The initial count to start with.
 *   This value can be incremented via the `incrementPendingCount:` method.
 *
 * @param taskCompletionBlock
 *   This block gets invoked everytime the wrapper is invoked.
 *
 * @param finalCompletionBlock
 *   This block gets invoked after the wrapper has been invoked enough that
 *   the pendingCount has been decremented all the way to zero.
 */
- (instancetype)initWithPendingCount:(uint)pendingCount
                 taskCompletionBlock:(nullable ZDCPullTaskSingleCompletion)taskCompletionBlock
                finalCompletionBlock:(ZDCPullTaskCompletion)finalCompletionBlock;

- (void)incrementPendingCount:(uint)increment;

@property (nonatomic, readonly) ZDCPullTaskCompletion wrapper;

@end

NS_ASSUME_NONNULL_END
