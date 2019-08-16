/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCTrunkNode.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCTrunkNode ()

/**
 * ZDCTrunkNode instances get created for you automatically.
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             zAppID:(NSString *)zAppID
                              trunk:(ZDCTreesystemTrunk)trunk;

@end

NS_ASSUME_NONNULL_END
