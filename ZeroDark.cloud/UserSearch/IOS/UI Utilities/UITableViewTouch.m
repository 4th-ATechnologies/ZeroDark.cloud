/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import "UITableViewTouch.h"

@implementation UITableViewTouch
@synthesize touchDelegate = touchDelegate;

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	//send it to super class
	[super touchesBegan:touches withEvent:event];

	if([self.touchDelegate respondsToSelector:@selector(tableview:touchesBegan:withEvent:)])
	{
		[self.touchDelegate tableview:self touchesBegan:touches withEvent:event];
	}
}

@end
