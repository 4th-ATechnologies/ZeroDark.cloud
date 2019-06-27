/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "RemoteUserTableViewCell.h"

@implementation RemoteUserTableViewCell

NSString *const kRemoteUserTableViewCellIdentifier = @"RemoteUserTableViewCell";

@synthesize showCheckMark;
@synthesize checked;
@synthesize enableCheck;

@synthesize lblUserName;
@synthesize imgAvatar;
@synthesize actAvatar;
@synthesize imgProvider;
@synthesize auth0ID;
@synthesize userID;
@synthesize lblBadge;
@synthesize btnDisclose;
@synthesize cnstlblBadgeWidth;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
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

-(void)setShowCheckMark:(BOOL)showCheckMarkIn
{
	showCheckMark = showCheckMarkIn;
	[self.checkMark setHidden:!showCheckMark];

    self.cnstAvatarLeadingWidth.constant = showCheckMark?20:0;
}

-(void)setChecked:(BOOL)isCheckedIn
{
	self.checkMark.checked = isCheckedIn;
}

-(void)setEnableCheck:(BOOL)enabled
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

- (void)awakeFromNib {
	[super awakeFromNib];
}


- (BOOL)canBecomeFirstResponder {
	return YES;
}


- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
	[super setSelected:selected animated:animated];

	// Configure the view for the selected state
}


@end
