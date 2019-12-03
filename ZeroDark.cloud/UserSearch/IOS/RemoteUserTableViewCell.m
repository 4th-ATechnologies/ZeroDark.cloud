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

@implementation RemoteUserTableViewCell {
	BOOL _showCheckMark;
}

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

@synthesize userID;
@synthesize identityID;

@dynamic showCheckMark;


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

- (BOOL)showCheckMark {
	return _showCheckMark;
}

- (void)setShowCheckMark:(BOOL)flag
{
	_showCheckMark = flag;
	self.checkMark.hidden = !_showCheckMark;
	self.cnstAvatarLeadingWidth.constant = _showCheckMark ? 20 : 0;
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
