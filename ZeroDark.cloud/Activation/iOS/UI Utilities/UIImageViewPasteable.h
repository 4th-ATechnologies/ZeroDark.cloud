/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
