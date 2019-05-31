/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "IdentityProviderTableViewCell.h"

@implementation IdentityProviderTableViewCell

NSString *const kIdentityProviderTableCellIdentifier = @"IdentityProviderTableViewCell";

@synthesize _imgProvider;


+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
    UINib *buttonCellNib = [UINib nibWithNibName:@"IdentityProviderTableViewCell" bundle:bundle];
    [tableView registerNib:buttonCellNib forCellReuseIdentifier:kIdentityProviderTableCellIdentifier];

}

+ (CGFloat)heightForCell
{
    return 48;
}

@end
