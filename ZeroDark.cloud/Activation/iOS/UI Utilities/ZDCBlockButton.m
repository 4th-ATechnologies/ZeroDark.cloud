/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCBlockButton.h"

@implementation ZDCBlockButton {
	
	ZDCBlockButtonActionBlock _actionBlock;
}

- (void)handleControlEvent:(UIControlEvents)event withBlock:(ZDCBlockButtonActionBlock)action
{
	_actionBlock = action;
	[self addTarget:self action:@selector(callActionBlock:) forControlEvents:event];
}

- (void)callActionBlock:(id)sender
{
	_actionBlock();
}

@end
