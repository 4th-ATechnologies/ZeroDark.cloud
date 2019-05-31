//
//  UIButton+CustomFont.m
//  storm4_iOS
//
//  Created by Robbie Hanson on 11/6/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "UIButton+CustomFont.h"
#import "UILabel+CustomFont.h"

@implementation UIButton (CustomFont)

- (void)setCustomFont:(NSString *)fontName
{
	[self.titleLabel setCustomFont:fontName];
}

@end
