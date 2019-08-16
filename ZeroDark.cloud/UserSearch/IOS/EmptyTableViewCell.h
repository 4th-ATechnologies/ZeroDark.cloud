/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kEmptyTableViewCellIdentifier;

@class EmptyTableViewCell;

@protocol EmptyTableViewCellDelegate <NSObject>
@optional

- (void)tableView:(UITableView * _Nonnull)tableView emptyCellButtonTappedAtCell:(EmptyTableViewCell* _Nonnull)cell;

@end

@interface EmptyTableViewCell : UITableViewCell

@property (nonatomic, weak) id<EmptyTableViewCellDelegate>    delegate;

@property (nonatomic, weak) IBOutlet UILabel        *lblText;
@property (nonatomic, weak) IBOutlet UIButton       *btn;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;

@end

NS_ASSUME_NONNULL_END
