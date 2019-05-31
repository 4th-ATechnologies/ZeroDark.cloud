//
//  UISecureTextField.m
//  storm4
//
//  Created by vinnie on 1/5/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "UISecureTextField.h"

@implementation UISecureTextField
{
    UIBlockButton* btnEye;

	UIImage* closedImage;
	UIImage* openImage;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
	
	__weak typeof(self) weakSelf = self;

    if (self = [super initWithCoder:aDecoder])
    {
		closedImage = [UIImage imageNamed:@"Eye_Closed"
									inBundle:[NSBundle bundleForClass:self.class]
			   compatibleWithTraitCollection:nil];

		openImage = [UIImage imageNamed:@"Eye_Open"
								 inBundle:[NSBundle bundleForClass:self.class]
			compatibleWithTraitCollection:nil];

        btnEye  = [UIBlockButton buttonWithType:UIButtonTypeSystem];
        btnEye.frame = CGRectMake(0, 0, 18, 18);
        btnEye.titleLabel.text = @"";
        btnEye.imageEdgeInsets = UIEdgeInsetsMake(0, -18, 0, 0);
        btnEye.imageView.contentMode = UIViewContentModeScaleAspectFit;

		[btnEye handleControlEvent:UIControlEventTouchUpInside withBlock:^{
		
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;

            if(strongSelf->btnEye.tag == 0)
            {
	            [self setSecureTextEntry:YES];
                [strongSelf->btnEye setImage:strongSelf->closedImage  forState:UIControlStateNormal];
                strongSelf->btnEye.tag = 1;
            }
            else
            {
				[self setSecureTextEntry:NO];
                [strongSelf->btnEye setImage:strongSelf->openImage forState:UIControlStateNormal];
                strongSelf->btnEye.tag = 0;
            }
        }];


        self.rightView = btnEye;
        [self setBorderStyle:UITextBorderStyleRoundedRect];
        self.rightViewMode = UITextFieldViewModeWhileEditing;

        btnEye.tag = 0;
        [btnEye sendActionsForControlEvents:UIControlEventTouchUpInside];
    }


    return self;
}


- (BOOL)secureInput
{
    BOOL isSecure = btnEye.tag == 1;

    return isSecure;
}

-(void) setSecureInput:(BOOL) isSecure
{
    if(isSecure)
    {
        [self setSecureTextEntry:YES];
        [btnEye setImage:closedImage forState:UIControlStateNormal];
        btnEye.tag = 1;
    }
    else
    {
        [self setSecureTextEntry:NO];
        [btnEye setImage:openImage forState:UIControlStateNormal];
        btnEye.tag = 0;
    }
}

@end
