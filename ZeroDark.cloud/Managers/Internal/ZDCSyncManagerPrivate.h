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
