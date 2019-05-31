/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import <UIKit/UIKit.h>

@interface ZDCBadgedBarButtonItem : UIBarButtonItem

typedef void (^ZDCBadgedBarButtonItemActionBlock)(void);

typedef NS_ENUM(NSInteger, ZDCBadgedBarButtonItem_Offset)
{
	kZDCBadgedBarButtonItem_Offset_Top   = 0,
	kZDCBadgedBarButtonItem_Offset_Center= 1,
	kZDCBadgedBarButtonItem_Offset_Bottom = 2,
};
@property (nonatomic, strong) NSString 		*badgeText;
@property (nonatomic, strong) UIColor	 	*badgeColor;

-(id)initWithImage:(UIImage *)image
			mode:(ZDCBadgedBarButtonItem_Offset)mode
			target:(id)target action:(SEL)action;


-(id)initWithImage:(UIImage *)image
			  mode:(ZDCBadgedBarButtonItem_Offset)mode
	   actionBlock:(ZDCBadgedBarButtonItemActionBlock)actionBlock;


@end

@interface ZDCBadgedBarLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets edgeInsets;
@end
