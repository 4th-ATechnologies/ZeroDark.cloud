/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "BackupShareUITableViewCell.h"

@implementation BackupShareUITableViewCell

NSString *const kBackupShareCellIdentifier = @"BackupShareCell";

@synthesize uuid;
@synthesize lblTitle;
@synthesize lblDetails;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
	UINib *buttonCellNib = [UINib nibWithNibName:@"BackupShareUITableViewCell" bundle:bundle];
	[tableView registerNib:buttonCellNib forCellReuseIdentifier:kBackupShareCellIdentifier];
	
}

+ (CGFloat)heightForCell
{
	return 60;
}


@end
