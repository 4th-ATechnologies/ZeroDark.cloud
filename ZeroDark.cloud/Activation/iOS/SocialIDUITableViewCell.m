/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

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

@synthesize uuid;
@synthesize identityID;

+ (void)registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
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

- (void)showRightButton:(BOOL)shouldShow
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
