/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "ZDCBadgedBarButtonItem.h"

@interface UIImage (ZDCBadgedBarButtonItem)
+ (CGFloat)pointsToPixels:(CGFloat)points;
@end


@implementation UIImage (ZDCBadgedBarButtonItem)
+ (CGFloat)pointsToPixels:(CGFloat)points {
	CGFloat pointsPerInch = 72.0; // see: http://en.wikipedia.org/wiki/Point%5Fsize#Current%5FDTP%5Fpoint%5Fsystem
	CGFloat scale = 1;
	float pixelPerInch; // DPI
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		pixelPerInch = 132 * scale;
	} else if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
		pixelPerInch = 163 * scale;
	} else {
		pixelPerInch = 160 * scale;
	}
	CGFloat px = points / pointsPerInch * pixelPerInch;
	return px;
}

@end

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

@implementation ZDCBadgedBarButtonItem
{
	CATransition *transition;
	UIView 		*vwButton;
	UIImageView *imgImage;
	UILabel		*lblBadge;
	ZDCBadgedBarButtonItem_Offset mode;

	UITapGestureRecognizer *tap;

	ZDCBadgedBarButtonItemActionBlock  actionBlock;
}

-(id)initWithImage:(UIImage *)image
			  mode:(ZDCBadgedBarButtonItem_Offset)modeIn
	   actionBlock:(ZDCBadgedBarButtonItemActionBlock)actionBlockIn
{
	if (self = [self initWithImage:image
							  mode:modeIn
							target:self
							action:@selector(handleAction:)])
	{
		actionBlock = actionBlockIn;
	}
	return self;
}

- (void)handleAction:(UIButton *)backButton
{
	if(actionBlock)
		actionBlock();
}


-(id)initWithImage:(UIImage *)image
			  mode:(ZDCBadgedBarButtonItem_Offset)modeIn
			target:(id)target action:(SEL)action

{


	// make the bg bigger and clickable
	UIView *v = [[UIView alloc] initWithFrame:(CGRect){
									.origin.x = 0,
									.origin.y = 0,
									.size.width = [UIImage pointsToPixels:14],
									.size.height = [UIImage pointsToPixels:18]
								}];
				 
	UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
	imageView.frame = (CGRect){
								.origin.x = 0,
								.origin.y = (v.frame.size.height * .5) -  (image.size.height * .5),
								.size.width = image.size.width,
								.size.height = image.size.height
							};
	[v addSubview:imageView];

 	transition =  [CATransition animation];
	transition.type = kCATransitionFade;
	transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	transition.duration = .4;

	ZDCBadgedBarLabel *label = [[ZDCBadgedBarLabel alloc] initWithFrame: (CGRect)
					  {
						  .origin.x = v.frame.size.width - 14,
						  .origin.y = 0,
						  .size.width = 18,
						  .size.height = 18
					  } ];

	label.backgroundColor = [UIColor redColor];
	label.userInteractionEnabled = NO;
	label.font = [UIFont systemFontOfSize:14];
	label.edgeInsets
			= (UIEdgeInsets) {	.top = 3,
								.left = 4,
								.bottom = 3,
								.right = 4};

	label.layer.cornerRadius = label.frame.size.height/2;
	label.textColor = [UIColor whiteColor];
 	label.textAlignment = NSTextAlignmentCenter;
	label.clipsToBounds = YES;

	label.text = @"";
	label.hidden = YES;
 
	[v addSubview:label];

	// for debugging
//	v.layer.borderColor = UIColor.redColor.CGColor;
//	v.layer.borderWidth = 1;

	self = [super initWithCustomView:v];
	if (self)
	{
		vwButton = v;
		imgImage = imageView;
		lblBadge = label;
		mode = modeIn;

		tap = [[UITapGestureRecognizer alloc] initWithTarget:target action:action];
		tap.numberOfTapsRequired = 1;

		[vwButton addGestureRecognizer:tap];
		vwButton.userInteractionEnabled = YES; //if you want touch on your image you'll need this

	}

	return self;
}

-(NSString *)badgeText
{
	if (lblBadge.hidden)
		return nil;

	return lblBadge.text;
}

-(void)setBadgeText:(NSString *)text
{

	[lblBadge.layer addAnimation:transition forKey:kCATransitionFade];

	if (text.length < 1)
	{
		lblBadge.hidden = YES;
 	}
	else
	{
		lblBadge.text = text;

		CGRect imageFrame = imgImage.frame;

		CGSize newSize = [lblBadge sizeThatFits:CGSizeMake(vwButton.frame.size.width, 18)];
		newSize.width += 10;
		CGRect badgeFrame = lblBadge.frame;
		badgeFrame.origin.x = imageFrame.origin.x +  imageFrame.size.width;
		badgeFrame.size.width = MAX(18,newSize.width);

		if(mode == kZDCBadgedBarButtonItem_Offset_Top)
		{
			badgeFrame.origin.x =   imageFrame.origin.x + (imageFrame.size.width * .8);
			badgeFrame.origin.y =   imageFrame.origin.y -  (badgeFrame.size.height / 2 );

		}
		else if(mode == kZDCBadgedBarButtonItem_Offset_Center)
		{
			badgeFrame.origin.y =  (vwButton.frame.size.height/2) -  (imageFrame.size.height /2) ;
		}
		else if(mode == kZDCBadgedBarButtonItem_Offset_Bottom)
		{
			badgeFrame.origin.x += 4;
			badgeFrame.origin.y =  imageFrame.size.height /2 - (newSize.height / 2 ) ;
		}

		lblBadge.frame = badgeFrame;
		lblBadge.layer.cornerRadius = lblBadge.frame.size.height/2;
		lblBadge.hidden = NO;

		[vwButton setNeedsDisplay];
	}
}

- (void)setBadgeColor:(UIColor *)badgeColor
{
	lblBadge.backgroundColor = badgeColor;
}

-(UIColor*) badgeColor
{
	return lblBadge.backgroundColor;
}


@end
