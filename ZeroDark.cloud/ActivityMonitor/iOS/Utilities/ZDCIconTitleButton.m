/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "ZDCIconTitleButton.h"

@implementation ZDCIconTitleButton

+ (instancetype)buttonWithType:(UIButtonType)buttonType
{
	ZDCIconTitleButton *button = [super buttonWithType:buttonType];
	[button postButtonWithTypeInit];
	return button;
}

/// Because we can't override init on a uibutton, do init steps here.
- (void)postButtonWithTypeInit
{
	self.frame = CGRectMake(0, 0, 200, 44);
	self.titleLabel.numberOfLines = 1;
	self.titleLabel.adjustsFontSizeToFitWidth = YES;
	self.titleLabel.lineBreakMode = NSLineBreakByClipping; //  MAGIC LINE
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	self.titleEdgeInsets = UIEdgeInsetsMake(0.0, 8, 0, 0); // top, left, bottom, right
}

- (void)setImage:(UIImage *)image forState:(UIControlState)state
{
	[super setImage:image forState:state];
	self.imageView.layer.cornerRadius = image.size.width /2;
	self.imageView.layer.masksToBounds = YES;
}

@end
