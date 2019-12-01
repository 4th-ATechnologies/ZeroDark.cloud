/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "RemoteUserTableViewCell.h"

/* extern */ NSString *const kRemoteUserTableViewCellIdentifier = @"RemoteUserTableViewCell";

@implementation RemoteUserTableViewCell

@synthesize delegate;

@synthesize checkMark;
@synthesize cnstAvatarLeadingWidth;

@synthesize imgAvatar;

@synthesize lblUserName;
@synthesize imgProvider;
@synthesize lblProvider;
@synthesize progress;
@synthesize btnDisclose;
@synthesize lblBadge;
@synthesize cnstlblBadgeWidth;

@synthesize showCheckMark;
@synthesize checked;
@synthesize enableCheck;

@synthesize userID;
@synthesize identityID;


+ (void)registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
	UINib *buttonCellNib = [UINib nibWithNibName:@"RemoteUserTableViewCell" bundle:bundle];
	[tableView registerNib:buttonCellNib forCellReuseIdentifier:kRemoteUserTableViewCellIdentifier];
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

- (void)setShowCheckMark:(BOOL)showCheckMarkIn
{
	showCheckMark = showCheckMarkIn;
	[self.checkMark setHidden:!showCheckMark];

	self.cnstAvatarLeadingWidth.constant = showCheckMark?20:0;
}

- (void)setChecked:(BOOL)isCheckedIn
{
	self.checkMark.checked = isCheckedIn;
}

- (void)setEnableCheck:(BOOL)enabled
{
	self.checkMark.checkMarkStyle = enabled ? ZDCCheckMarkStyleOpenCircle: ZDCCheckMarkStyleGrayedOut;
}

- (IBAction)disclosureButtonTapped:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(tableView:disclosureButtonTappedAtCell:)])
    {
        UITableView *tableView = [self tableView];
        
        [(id <RemoteUserTableViewCellDelegate>)self.delegate tableView:tableView
                                          disclosureButtonTappedAtCell:self];
    }
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}

@end
