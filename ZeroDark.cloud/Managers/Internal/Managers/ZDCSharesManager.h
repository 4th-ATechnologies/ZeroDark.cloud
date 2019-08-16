/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZeroDarkCloud.h"

@class ZDCLocalUser;
@class ZDCSplitKey;

NS_ASSUME_NONNULL_BEGIN

@interface ZDCSharesManager : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (ZDCSplitKey *)splitKeyForLocalUserID:(NSString *)localUserID
                           withSplitNum:(NSUInteger)splitNum;

@end

NS_ASSUME_NONNULL_END
