/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
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
