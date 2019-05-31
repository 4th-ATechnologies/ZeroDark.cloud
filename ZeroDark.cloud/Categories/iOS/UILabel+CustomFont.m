//
//  UILabel+UILabel_CustomFont.m
//  storm4_iOS
//
//  Created by Robbie Hanson on 10/30/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "UILabel+CustomFont.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>

@implementation UILabel (CustomFont)

- (void)setCustomFont:(NSString *)fontName
{
	CGFloat currentFontSize = self.font.pointSize;
//	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];

	UIFont *customFont = [UIFont fontWithName:fontName size:currentFontSize];
	if (customFont) {
		self.font = customFont;
	}
}

@end
