/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
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
