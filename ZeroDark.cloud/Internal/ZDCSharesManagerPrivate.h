/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "ZDCSharesManager.h"
#import "ZeroDarkCloud.h"

@class ZDCLocalUser;
@class ZDCSplitKey;

NS_ASSUME_NONNULL_BEGIN

@interface ZDCSharesManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

-(ZDCSplitKey*) splitKeyForLocalUserID:(NSString *)localUserID
								  withSplitNum:(NSUInteger) splitNum;

@end

NS_ASSUME_NONNULL_END
