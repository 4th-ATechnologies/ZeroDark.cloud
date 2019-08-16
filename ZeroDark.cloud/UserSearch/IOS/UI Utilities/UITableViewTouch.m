/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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
