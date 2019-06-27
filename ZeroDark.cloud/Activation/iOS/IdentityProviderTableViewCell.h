/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

extern NSString * _Nonnull const kIdentityProviderTableCellIdentifier;

@interface IdentityProviderTableViewCell : UITableViewCell
@property (nonatomic, weak)     IBOutlet UIImageView*               _imgProvider;


@property (nonatomic, copy) NSString *provider;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;
NS_ASSUME_NONNULL_END

@end
