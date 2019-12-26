/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCBadgedBarLabel.h"

@implementation ZDCBadgedBarLabel

- (id)initWithFrame:(CGRect)frame{
	self = [super initWithFrame:frame];
	if (self) {
		self.edgeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
	}
	return self;
}

- (void)drawTextInRect:(CGRect)rect {
	[super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.edgeInsets)];
}

- (CGSize)intrinsicContentSize
{
	CGSize size = [super intrinsicContentSize];
	size.width  += self.edgeInsets.left + self.edgeInsets.right;
	size.height += self.edgeInsets.top + self.edgeInsets.bottom;
	return size;
}

@end
