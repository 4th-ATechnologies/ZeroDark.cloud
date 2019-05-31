//
//  SocialIDUITableViewCell.m
//  storm4
//
//  Created by vinnie on 8/7/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "SocialIDUITableViewCell.h"
#import "KGHitTestingButton.h"

@implementation SocialIDUITableViewCell

NSString *const kSocialIDCellIdentifier = @"SocialIDCell";

@synthesize lbLeftTag;
@synthesize lblUserName;
@synthesize imgAvatar;
@synthesize imgProvider;
@synthesize lbProvider;
@synthesize cnstRightTextOffest;
@synthesize btnRight;
@synthesize delegate;

@synthesize Auth0ID;
@synthesize uuid;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
	UINib *buttonCellNib = [UINib nibWithNibName:@"SocialIDUITableViewCell" bundle:bundle];
	[tableView registerNib:buttonCellNib forCellReuseIdentifier:kSocialIDCellIdentifier];

}

+ (CGFloat)heightForCell
{
    return 60;
}

+ (CGFloat)imgProviderHeight
{
	return 12;
}

+ (CGSize)avatarSize
{
	return CGSizeMake(38, 38);
}

- (void)awakeFromNib {
    [super awakeFromNib];
	[self showRightButton:NO];
}


- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


- (UITableView *)tableView
{
    UIView *tableView = self.superview;
    while (tableView)
    {
        if (![tableView isKindOfClass:[UITableView class]]) {
            tableView = tableView.superview;
        }
        else {
            return (UITableView *)tableView;
        }
    }
    return nil;
}

-(void)showRightButton:(BOOL)shouldShow
{
    if(shouldShow)
    {
        btnRight.minimumHitTestWidth = 48;
        btnRight.minimumHitTestHeight = 48;
        cnstRightTextOffest.constant = 40;
        btnRight.hidden = NO;
    }
    else
    {
        cnstRightTextOffest.constant = 8;
        btnRight.hidden = YES;
     }
}


- (IBAction)rightButtonTapped:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(tableView:rightButtonTappedAtCell:)])
    {
        UITableView *tableView = [self tableView];
        
        [(id <SocialIDUITableViewCellDelegate>)self.delegate tableView:tableView
                                          rightButtonTappedAtCell:self];
    }
}


@end
