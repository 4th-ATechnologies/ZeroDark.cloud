//
//  UIBlockButton.m
//  storm4_iOS
//
//  Created by vinnie on 12/28/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "UIBlockButton.h"

@implementation UIBlockButton

-(void) handleControlEvent:(UIControlEvents)event
withBlock:(UIBlockButtonActionBlock) action
{
    _actionBlock = action;
    [self addTarget:self action:@selector(callActionBlock:) forControlEvents:event];
}

-(void) callActionBlock:(id)sender{
    _actionBlock();
}
@end

