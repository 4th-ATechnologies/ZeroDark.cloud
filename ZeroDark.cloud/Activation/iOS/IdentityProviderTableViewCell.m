/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
