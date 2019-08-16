/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "ZDCPopoverTransition.h"

@implementation ZDCPopoverTransition {
	
	UIImageView *dimmedBackgroundView;
}

@synthesize reverse = reverse;
@synthesize duration = duration;
@synthesize origin = origin;

- (id)init
{
	if ((self = [super init]))
	{
		duration = 0.4;
		origin = ZDCPopoverTransitionOrigin_Bottom;
	}
	return self;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
	return self.duration;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
	__weak typeof(self) weakSelf = self;

	UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
	UIViewController *toVC = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
	
	UIView *containerView = [transitionContext containerView];
	
	UIView *toView = toVC.view;
	UIView *fromView = fromVC.view;
	
	// Create dimmedBackgroundView & add to containerView.
	
	if (!self.reverse)
	{
		UIImage *image = [UIImage imageNamed:@"StormCloudsBackground.jpg"];
	
		dimmedBackgroundView = [[UIImageView alloc] initWithImage:image];
		dimmedBackgroundView.contentMode = UIViewContentModeScaleAspectFill;
		
		dimmedBackgroundView.frame = containerView.bounds;
		dimmedBackgroundView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
		
		[containerView addSubview:dimmedBackgroundView];
	}
	
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
	
	// Perform animations
	
	if (!self.reverse)
	{
		dimmedBackgroundView.alpha = 0.0F;
	}
	
	[UIView animateWithDuration:self.duration
	                 animations:
	^{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		if (strongSelf.reverse)
			strongSelf->dimmedBackgroundView.alpha = 0.0f;
		else
			strongSelf->dimmedBackgroundView.alpha = 0.5f;
	}];
	
	CGRect offscreenFrame;
	offscreenFrame.size = containerView.frame.size;
	
	if (origin & ZDCPopoverTransitionOrigin_Left)
		offscreenFrame.origin.x = -containerView.frame.size.width;
	else if (origin & ZDCPopoverTransitionOrigin_Right)
		offscreenFrame.origin.x = containerView.frame.size.width;
	else
		offscreenFrame.origin.x = 0.0F;
	
	if (origin & ZDCPopoverTransitionOrigin_Top)
		offscreenFrame.origin.y = -containerView.frame.size.height;
	else if (origin & ZDCPopoverTransitionOrigin_Bottom)
		offscreenFrame.origin.y = containerView.frame.size.height;
	else
		offscreenFrame.origin.y = 0.0F;
	
	if (!self.reverse)
	{
		toView.frame = offscreenFrame;
	}
	
	[UIView animateWithDuration:self.duration
	                      delay:0.0f
	                    options:UIViewAnimationOptionCurveEaseOut
	                 animations:^
	{
		if (self.reverse)
			fromView.frame = offscreenFrame;
		else
			toView.frame = containerView.frame;
		
	} completion:^(BOOL finished) {
		
		[transitionContext completeTransition:YES];
		
	}];
}

@end
