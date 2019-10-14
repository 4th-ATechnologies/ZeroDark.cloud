/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCSyncManager.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCSyncManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (void)enqueuePullCompletionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(ZDCPullResult))completionBlock
                    forLocalUserID:(NSString *)localUserID;

/**
 * The PullManager invokes these methods directly.
 */

- (void)notifyPullStartedForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID;
- (void)notifyPullFoundChangesForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID;
- (void)notifyPullStoppedForLocalUserID:(NSString *)localUserID
                                 treeID:(NSString *)treeID
                             withResult:(ZDCPullResult)result;

@end

NS_ASSUME_NONNULL_END
