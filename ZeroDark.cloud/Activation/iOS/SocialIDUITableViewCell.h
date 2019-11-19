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
@class KGHitTestingButton;

extern NSString *const kSocialIDCellIdentifier;

@class SocialIDUITableViewCell;

@protocol SocialIDUITableViewCellDelegate <NSObject>
@optional

- (void)tableView:(UITableView * _Nonnull)tableView rightButtonTappedAtCell:(SocialIDUITableViewCell* _Nonnull)cell;

@end

@interface SocialIDUITableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel        *lbLeftTag;
@property (nonatomic, weak) IBOutlet UIImageView    *imgAvatar;
@property (nonatomic, weak) IBOutlet UILabel        *lblUserName;
@property (nonatomic, weak) IBOutlet UIImageView    *imgProvider;
@property (nonatomic, weak) IBOutlet UILabel        *lbProvider;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint  *cnstRightTextOffest;
@property (nonatomic,weak)  IBOutlet KGHitTestingButton *btnRight;

@property (nonatomic, copy) NSString *Auth0ID;
@property (nonatomic, copy) NSString *uuid;	// optional value

@property (nonatomic, weak) id<SocialIDUITableViewCellDelegate>    delegate;

-(void)showRightButton:(BOOL)shouldShow;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;
+ (CGSize)avatarSize;
+ (CGFloat)imgProviderHeight;
@end

NS_ASSUME_NONNULL_END
