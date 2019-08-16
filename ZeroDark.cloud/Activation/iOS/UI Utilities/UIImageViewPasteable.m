/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "UIImageViewPasteable.h"
 
@implementation UIImageViewPasteable

@synthesize delegate = delegate;
@synthesize canCopy = canCopy;
@synthesize canPaste = canPaste;

- (id)init
{
    return [self initWithFrame:CGRectZero];
}

- (id)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        [self commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    if ((self = [super initWithCoder:decoder]))
    {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
	UILongPressGestureRecognizer *hold =
	  [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
	
	[self addGestureRecognizer:hold];
	self.userInteractionEnabled = YES;
}



- (void)longPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
	if (gestureRecognizer.state == UIGestureRecognizerStateBegan)
	{
		NSMutableArray *menuItems = [[NSMutableArray alloc] initWithCapacity:1];
		
		UIMenuController *menuController = [UIMenuController sharedMenuController];
		
		[self becomeFirstResponder];
        
		[menuController setMenuItems:menuItems];
		
		CGRect rect = (CGRect){
			.origin.x = 0,
			.origin.y = 0,
			.size = self.frame.size
		};
		
		[menuController setTargetRect:rect inView:self];
		[menuController setMenuVisible:YES animated:YES];
	}
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    BOOL canAcceptPaste = canPaste
            && [delegate respondsToSelector:@selector(imageViewPasteable:pasteImage:)];
    
    if (action == @selector(copy:))
    {
        return canCopy;
    }
	else if (action == @selector(paste:))
		return [[UIPasteboard generalPasteboard] image] ? canAcceptPaste : NO;
	else
		return [super canPerformAction:action withSender:sender];
}

- (void)copy:(id)sender
{
    UIImage *copiedImage = self.image;
    if ([copiedImage isKindOfClass:[UIImage class]])
    {
        [[UIPasteboard generalPasteboard] setImage:copiedImage];
    }
    
    if([delegate respondsToSelector:@selector(imageViewPasteable:didCopyImage:)])
    {
        [delegate imageViewPasteable:self didCopyImage:copiedImage];
    }
 }

- (void)paste:(id)sender
{
	UIImage *image = [[UIPasteboard generalPasteboard] image];
    
    BOOL canAcceptPaste = canPaste
        && [delegate respondsToSelector:@selector(imageViewPasteable:pasteImage:)];

	if (image && canAcceptPaste)
	{
		[delegate imageViewPasteable:self pasteImage:image];
	}
}

@end
