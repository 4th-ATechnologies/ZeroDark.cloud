/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserManager.h"
#import "ZeroDarkCloud.h"

@class ZDCSearchResult;

NS_ASSUME_NONNULL_BEGIN

@interface ZDCUserManager (Private)

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

@end

NS_ASSUME_NONNULL_END
