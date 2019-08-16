
/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>
@class ZeroDarkCloud;

NS_ASSUME_NONNULL_BEGIN

@interface ActivityMonitor_IOS : UIViewController

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
						localUserID:(NSString* __nullable)inLocalUserID;

@end

NS_ASSUME_NONNULL_END
