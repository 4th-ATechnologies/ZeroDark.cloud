/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <UIKit/UIKit.h>

typedef void (^ZDCBlockButtonActionBlock)(void);

@interface ZDCBlockButton : UIButton

- (void)handleControlEvent:(UIControlEvents)event withBlock:(ZDCBlockButtonActionBlock) action;

@end
