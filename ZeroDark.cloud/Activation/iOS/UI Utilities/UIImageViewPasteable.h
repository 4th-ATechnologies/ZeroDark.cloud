//
//  UIImageView+UIImageViewPastable.h
//  storm4
//
//  Created by vinnie on 4/5/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//
/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import <UIKit/UIKit.h>
@protocol UIImageViewPasteableDelegate;
 
@interface UIImageViewPasteable : UIImageView

@property (nonatomic, weak, readwrite) id<UIImageViewPasteableDelegate> delegate;
@property (nonatomic) BOOL canCopy;
@property (nonatomic) BOOL canPaste;

@end

#pragma mark -

@protocol UIImageViewPasteableDelegate <NSObject>
@required

- (void)imageViewPasteable:(UIImageViewPasteable *)sender pasteImage:(UIImage *)image;

- (void)imageViewPasteable:(UIImageViewPasteable *)sender didCopyImage:(UIImage *)copiedImage;

@end
