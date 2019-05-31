//
//  UIButton+S4Activation.m
//  storm4
//
//  Created by vinnie on 12/21/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import "UIButton+Activation.h"

@implementation UIButton (Activation)

- (void)setup
{
	self.layer.cornerRadius  = 8.0f;
	self.layer.masksToBounds = YES;
	self.layer.borderWidth   = 1.0f;
	self.layer.borderColor   = [UIColor whiteColor].CGColor;
	
	[self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
	
	self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	self.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 12, 10); // top, left, bottom, right
}

@end
