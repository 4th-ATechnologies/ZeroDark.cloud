//
//  BadgedBarButtonItem.h
//  storm4_iOS
//
//  Created by vinnie on 8/29/18.
//  Copyright © 2018 4th-A Technologies, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BadgedBarButtonItem : UIBarButtonItem

typedef void (^BadgedBarButtonItemActionBlock)(void);

typedef NS_ENUM(NSInteger, BadgedBarButtonItem_Offset)
{
	kBadgedBarButtonItem_Offset_Top   = 0,
	kBadgedBarButtonItem_Offset_Center= 1,
	kBadgedBarButtonItem_Offset_Bottom = 2,
};
@property (nonatomic, strong) NSString 		*badgeText;
@property (nonatomic, strong) UIColor	 	*badgeColor;

-(id)initWithImage:(UIImage *)image
			mode:(BadgedBarButtonItem_Offset)mode
			target:(id)target action:(SEL)action;


-(id)initWithImage:(UIImage *)image
			  mode:(BadgedBarButtonItem_Offset)mode
	   actionBlock:(BadgedBarButtonItemActionBlock)actionBlock;


@end

@interface BadgedBarLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets edgeInsets;
@end
