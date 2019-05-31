/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kUserSearchTableViewHeaderCellIdentifier;

@interface UserSearchTableViewHeaderCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel        *lblText;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;

@end

NS_ASSUME_NONNULL_END
