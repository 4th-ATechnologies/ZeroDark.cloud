/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>
#import "ZDCCheckMark.h"
#import "ZDCBadgedBarButtonItem.h"

#import <JGProgressView/JGProgressView.h>
#import <KGHitTestingViews/KGHitTestingButton.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kRemoteUserTableViewCellIdentifier;
@class RemoteUserTableViewCell;

@protocol RemoteUserTableViewCellDelegate <NSObject>
@optional

- (void)tableView:(UITableView * _Nonnull)tableView disclosureButtonTappedAtCell:(RemoteUserTableViewCell* _Nonnull)cell;

@end

@interface RemoteUserTableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet ZDCCheckMark    *checkMark;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint  *cnstAvatarLeadingWidth;

@property (nonatomic, weak) IBOutlet UIImageView    *imgAvatar;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView    *actAvatar;

@property (nonatomic, weak) IBOutlet UILabel        *lblUserName;
@property (nonatomic, weak) IBOutlet UIImageView    *imgProvider;
@property (nonatomic, weak) IBOutlet UILabel    	*lblProvider;
@property (nonatomic, weak) IBOutlet JGProgressView *progress;
@property (nonatomic, weak) IBOutlet KGHitTestingButton  *btnDisclose;
@property (nonatomic, weak) IBOutlet ZDCBadgedBarLabel   *lblBadge;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *cnstlblBadgeWidth;

@property (nonatomic, weak) id<RemoteUserTableViewCellDelegate>    delegate;

@property (nonatomic) BOOL          showCheckMark;
@property (nonatomic) BOOL          checked;
@property (nonatomic) BOOL          enableCheck;

@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *auth0ID;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;
+ (CGSize)avatarSize;
+ (CGFloat)imgProviderHeight;
@end

NS_ASSUME_NONNULL_END
