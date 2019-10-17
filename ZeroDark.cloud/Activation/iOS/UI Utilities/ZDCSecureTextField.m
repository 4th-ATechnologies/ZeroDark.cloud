/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCSecureTextField.h"
#import "ZDCBlockButton.h"

static CGFloat const EYE_WIDTH  = 22.F;
static CGFloat const EYE_HEIGHT = 22.F;

@implementation ZDCSecureTextField {
	
	ZDCBlockButton *btnEye;

	UIImage *_openImage_useLazyLoaderMethod;
	UIImage *_closedImage_useLazyLoaderMethod;
}

@dynamic secureInput;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]))
	{
		btnEye = [ZDCBlockButton buttonWithType:UIButtonTypeSystem];
		btnEye.frame = CGRectMake(0, 0, EYE_WIDTH, EYE_HEIGHT);
		btnEye.titleLabel.text = @"";
		btnEye.imageEdgeInsets = UIEdgeInsetsMake(0, -EYE_WIDTH, 0, 0);
		btnEye.imageView.contentMode = UIViewContentModeScaleAspectFit;

		__weak typeof(self) weakSelf = self;
		[btnEye handleControlEvent:UIControlEventTouchUpInside withBlock:^{
		
			[weakSelf toggleSecureInput];
		}];

		self.rightView = btnEye;
		[self setBorderStyle:UITextBorderStyleRoundedRect];
		self.rightViewMode = UITextFieldViewModeWhileEditing;
		
		self.secureInput = YES;
	}
	return self;
}

- (CGRect)rightViewRectForBounds:(CGRect)bounds
{
	// This method is required as of iOS 13:
	//
	// More information can be found here:
	// https://stackoverflow.com/questions/58335586/uitextfield-leftview-and-rightview-overlapping-issue-ios13
	
	return (CGRect){
		.origin.x = bounds.size.width - EYE_WIDTH - 4,
		.origin.y = (bounds.size.height - EYE_HEIGHT) / 2.0,
		.size.width = EYE_WIDTH,
		.size.height = EYE_HEIGHT
	};
}

- (void)toggleSecureInput
{
	self.secureInput = !self.secureInput;
}

- (UIImage *)openImage
{
	if (_openImage_useLazyLoaderMethod == nil)
	{
		_openImage_useLazyLoaderMethod =
		            [UIImage imageNamed: @"Eye_Open"
		                       inBundle: [NSBundle bundleForClass:[self class]]
		  compatibleWithTraitCollection: nil];
	}
	
	return _openImage_useLazyLoaderMethod;
}

- (UIImage *)closedImage
{
	if (_closedImage_useLazyLoaderMethod == nil)
	{
		_closedImage_useLazyLoaderMethod =
		            [UIImage imageNamed: @"Eye_Closed"
		                       inBundle: [NSBundle bundleForClass:[self class]]
		  compatibleWithTraitCollection: nil];
	}
	
	return _closedImage_useLazyLoaderMethod;
}

- (BOOL)secureInput
{
	BOOL isSecure = btnEye.tag == 1;
	return isSecure;
}

- (void)setSecureInput:(BOOL)isSecure
{
	if (isSecure)
	{
		[self setSecureTextEntry:YES];
		[btnEye setImage:[self closedImage] forState:UIControlStateNormal];
		btnEye.tag = 1;
	}
	else
	{
		[self setSecureTextEntry:NO];
		[btnEye setImage:[self openImage] forState:UIControlStateNormal];
		btnEye.tag = 0;
	}
}

@end
