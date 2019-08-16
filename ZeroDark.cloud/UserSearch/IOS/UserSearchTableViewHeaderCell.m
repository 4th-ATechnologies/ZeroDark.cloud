/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "UserSearchTableViewHeaderCell.h"

NSString *const kUserSearchTableViewHeaderCellIdentifier = @"UserSearchTableViewHeaderCell";

@implementation UserSearchTableViewHeaderCell
@synthesize lblText;

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
    UINib *buttonCellNib = [UINib nibWithNibName:@"UserSearchTableViewHeaderCell" bundle:bundle];
    [tableView registerNib:buttonCellNib forCellReuseIdentifier:kUserSearchTableViewHeaderCellIdentifier];
}

+ (CGFloat)heightForCell
{
	return 32;
}

@end
