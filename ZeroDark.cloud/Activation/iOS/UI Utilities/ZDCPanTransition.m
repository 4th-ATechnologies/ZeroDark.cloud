/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "ZDCPanTransition.h"

@implementation ZDCPanTransition

@synthesize reverse = reverse;
@synthesize duration = duration;

- (id)init
{
	if ((self = [super init]))
	{
		self.duration = 0.4;
	}
	return self;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
	return self.duration;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
//	NSLog(@"ZDCPanTransition: animateTransition");
	
	UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
	UIViewController *toVC = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
	
	UIView *containerView = [transitionContext containerView];
	
	UIView *toView = toVC.view;
	UIView *fromView = fromVC.view;
	
	// Do we add toView to the containerView ?
	// The rules seem to be different in the following situations:
	// - a view is being presented/dismissed
	// - a view is being pushed/popped in a navigation controller
	//
	// In the case of a view being presented/dismissed,
	// we only want to add the toView when first being presented.
	// In other words, don't remove the presenter from its existing view heirarchy.
	//
	// In the case of a view being pushed/popped in a naviagation controller,
	// it appears that we always want to add the toView.
	//
	// We can tell the different because the presented/dismissed flow
	// will be queryable via isBeingPresented/isBeingDismissed methods.
	
	BOOL addToContainer = NO;
	if (self.reverse)
		addToContainer = ![fromVC isBeingDismissed];
	else
		addToContainer = YES;
	
	if (addToContainer) {
		[containerView addSubview:toView];
	}
	
	toView.frame = (CGRect){
		.origin.x = self.reverse ? -containerView.frame.size.width : containerView.frame.size.width,
		.origin.y = toView.frame.origin.y,
		.size = fromView.frame.size // <- take on size of fromView (which we're replacing)
	};
	
	self.reverse ? [containerView sendSubviewToBack:toView] : [containerView bringSubviewToFront:toView];
	
	[UIView animateWithDuration:self.duration
	                      delay:0.0
	     usingSpringWithDamping:0.7
	      initialSpringVelocity:1.0
	                    options:UIViewAnimationOptionCurveEaseInOut
	                 animations:^
	{
	//	NSLog(@"ZDCPanTransition: animateTransition: start");
		
		fromView.frame = (CGRect){
			.origin.x = !self.reverse ? -containerView.frame.size.width : containerView.frame.size.width,
			.origin.y = fromView.frame.origin.y,
			.size = fromView.frame.size
		};
		toView.frame = (CGRect){
			.origin.x = 0,
			.origin.y = toView.frame.origin.y,
			.size = fromView.frame.size // <- take on size of fromView (which we're replacing)
		};
		
	} completion:^(BOOL finished) {
		
	//	NSLog(@"ZDCPanTransition: animateTransition: completion");
		
		if ([transitionContext transitionWasCancelled])
		{
			toView.frame = (CGRect){
				.origin.x = 0,
				.origin.y = toView.frame.origin.y,
				.size = toView.frame.size,
			};
			fromView.frame = (CGRect){
				.origin.x = 0,
				.origin.y = fromView.frame.origin.y,
				.size = fromView.frame.size
			};
		}
		else
		{
			fromView.frame = (CGRect){
				.origin.x = !self.reverse ? -containerView.frame.size.width : containerView.frame.size.width,
				.origin.y = fromView.frame.origin.y,
				.size = fromView.frame.size
			};
			toView.frame = (CGRect){
				.origin.x = 0,
				.origin.y = toView.frame.origin.y,
				.size = toView.frame.size
			};
		}
		 
		[transitionContext completeTransition:![transitionContext transitionWasCancelled]];
	}];
}

- (void)animationEnded:(BOOL)transitionCompleted
{
//	NSLog(@"ZDCPanTransition: animationEnded");
	
	// Just in case this method needs to exist
}

@end
