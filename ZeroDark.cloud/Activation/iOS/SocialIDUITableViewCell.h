/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <UIKit/UIKit.h>

@class KGHitTestingButton;
@protocol SocialIDUITableViewCellDelegate;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kSocialIDCellIdentifier;


@interface SocialIDUITableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel        *lbLeftTag;
@property (nonatomic, weak) IBOutlet UIImageView    *imgAvatar;
@property (nonatomic, weak) IBOutlet UILabel        *lblUserName;
@property (nonatomic, weak) IBOutlet UIImageView    *imgProvider;
@property (nonatomic, weak) IBOutlet UILabel        *lbProvider;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint  *cnstRightTextOffest;
@property (nonatomic,weak)  IBOutlet KGHitTestingButton *btnRight;

@property (nonatomic, weak) id<SocialIDUITableViewCellDelegate> delegate;

@property (nonatomic, copy) NSString *uuid;	// optional value
@property (nonatomic, copy) NSString *identityID;

- (void)showRightButton:(BOOL)shouldShow;

+ (void)registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;
+ (CGSize)avatarSize;
+ (CGFloat)imgProviderHeight;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol SocialIDUITableViewCellDelegate <NSObject>
@optional

- (void)tableView:(UITableView *)tableView rightButtonTappedAtCell:(SocialIDUITableViewCell *)cell;

@end

NS_ASSUME_NONNULL_END
