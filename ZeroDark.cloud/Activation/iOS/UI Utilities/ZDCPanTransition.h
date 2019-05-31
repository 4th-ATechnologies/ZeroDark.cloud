/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import <UIKit/UIKit.h>

@interface ZDCPanTransition : NSObject <UIViewControllerAnimatedTransitioning>

@property (nonatomic, assign) BOOL reverse;

@property (nonatomic, assign) NSTimeInterval duration;

@end
