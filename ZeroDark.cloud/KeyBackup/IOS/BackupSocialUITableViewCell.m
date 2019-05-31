/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "BackupSocialUITableViewCell.h"

@implementation BackupSocialUITableViewCell

NSString *const kBackupSocialCellIdentifier = @"BackupSocialCell";

@synthesize uuid;
@synthesize lblSplit;
@synthesize lblTitle;
@synthesize lblDetails;
@synthesize lblDate;
@synthesize lblTitleCenterOffset;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
	UINib *buttonCellNib = [UINib nibWithNibName:@"BackupSocialUITableViewCell" bundle:bundle];
	[tableView registerNib:buttonCellNib forCellReuseIdentifier:kBackupSocialCellIdentifier];
	
}

+ (CGFloat)heightForCell
{
	return 66;
}


@end
