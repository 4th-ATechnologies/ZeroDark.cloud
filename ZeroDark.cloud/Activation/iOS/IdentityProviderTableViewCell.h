/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kIdentityProviderTableCellIdentifier;

@interface IdentityProviderTableViewCell : UITableViewCell

+ (void)registerViewsforTable:(UITableView *)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;

@property (nonatomic, copy) NSString *provider;
@property (nonatomic, weak) IBOutlet UIImageView *_imgProvider;

@end

NS_ASSUME_NONNULL_END
