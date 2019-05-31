/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCContainerNode.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCContainerNode ()

- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             zAppID:(NSString *)zAppID
								  container:(ZDCTreesystemContainer)container;

@end

NS_ASSUME_NONNULL_END
