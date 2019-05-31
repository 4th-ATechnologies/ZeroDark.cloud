//
//  UITextView.m
//  storm4_iOS
//
//  Created by Robbie Hanson on 11/6/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "UITextView+CustomFont.h"

@implementation UITextView (CustomFont)

- (void)setCustomFont:(NSString *)fontName
{
	CGFloat currentFontSize = self.font.pointSize;
	
	UIFont *customFont = [UIFont fontWithName:fontName size:currentFontSize];
	if (customFont) {
		self.font = customFont;
	}
}

@end
