/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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
