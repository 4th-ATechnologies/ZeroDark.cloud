//
//  UIBlockButton.h
//  storm4_iOS
//
//  Created by vinnie on 12/28/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void (^UIBlockButtonActionBlock)(void);

@interface UIBlockButton : UIButton {
    UIBlockButtonActionBlock _actionBlock;
}

-(void) handleControlEvent:(UIControlEvents)event
                 withBlock:(UIBlockButtonActionBlock) action;
@end

