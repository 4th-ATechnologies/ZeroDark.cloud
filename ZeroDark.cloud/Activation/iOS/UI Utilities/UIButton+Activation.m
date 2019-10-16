//
//  UIButton+S4Activation.m
//  storm4
//
//  Created by vinnie on 12/21/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import "UIButton+Activation.h"

@implementation UIButton (Activation)

/**
 * Standard colors for buttons throughout activation screens.
 */
- (void)zdc_colorize
{
	[self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
}

// We no longer do this for text buttons.
// It's not common practice on iOS anymore.
/*
- (void)zdc_outline
{
	self.layer.cornerRadius  = 8.0f;
	self.layer.masksToBounds = YES;
	self.layer.borderWidth   = 1.0f;
	self.layer.borderColor   = [UIColor whiteColor].CGColor;
	
	self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	self.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 12, 10); // top, left, bottom, right
}
*/
@end
