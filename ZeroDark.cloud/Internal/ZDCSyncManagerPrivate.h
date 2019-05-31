/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCSyncManager.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCSyncManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * The PullManager invokes these methods directly.
 */

- (void)notifyPullStartedForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;
- (void)notifyPullFoundChangesForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;
- (void)notifyPullStoppedForLocalUserID:(NSString *)localUserID
                                 zAppID:(NSString *)zAppID
                             withResult:(ZDCPullResult)result;

@end

NS_ASSUME_NONNULL_END
