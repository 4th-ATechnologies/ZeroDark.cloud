/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
