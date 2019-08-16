/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, ZDCPopoverTransitionOrigin) {
	ZDCPopoverTransitionOrigin_Top    = 1 << 0,
	ZDCPopoverTransitionOrigin_Bottom = 1 << 1,
	ZDCPopoverTransitionOrigin_Left   = 1 << 2,
	ZDCPopoverTransitionOrigin_Right  = 1 << 3,
};

@interface ZDCPopoverTransition : NSObject <UIViewControllerAnimatedTransitioning>

@property (nonatomic, assign, readwrite) BOOL reverse;
@property (nonatomic, assign, readwrite) NSTimeInterval duration;
@property (nonatomic, assign, readwrite) ZDCPopoverTransitionOrigin origin;

@end
