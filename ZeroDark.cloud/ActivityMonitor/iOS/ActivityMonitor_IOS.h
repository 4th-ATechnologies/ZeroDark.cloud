
/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import <UIKit/UIKit.h>
@class ZeroDarkCloud;

NS_ASSUME_NONNULL_BEGIN

@interface ActivityMonitor_IOS : UIViewController

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
						localUserID:(NSString* __nullable)inLocalUserID;

@end

NS_ASSUME_NONNULL_END
