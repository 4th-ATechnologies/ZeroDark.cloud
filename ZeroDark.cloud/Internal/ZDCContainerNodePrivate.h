/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCContainerNode.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCContainerNode ()

- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             zAppID:(NSString *)zAppID
								  container:(ZDCTreesystemContainer)container;

@end

NS_ASSUME_NONNULL_END
