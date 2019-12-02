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
#import "ZDCBadgedBarLabel.h"

#import <JGProgressView/JGProgressView.h>
#import <KGHitTestingViews/KGHitTestingButton.h>

@protocol RemoteUserTableViewCellDelegate;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kRemoteUserTableViewCellIdentifier;


@interface RemoteUserTableViewCell : UITableViewCell

+ (void)registerViewsforTable:(UITableView *)tableView bundle:(nullable NSBundle *)bundle;

+ (CGFloat)heightForCell;
+ (CGSize)avatarSize;
+ (CGFloat)imgProviderHeight;

@property (nonatomic, weak) id<RemoteUserTableViewCellDelegate> delegate;

@property (nonatomic, weak) IBOutlet ZDCCheckMark       * checkMark;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint * cnstAvatarLeadingWidth;

@property (nonatomic, weak) IBOutlet UIImageView        * imgAvatar;

@property (nonatomic, weak) IBOutlet UILabel            * lblUserName;
@property (nonatomic, weak) IBOutlet UIImageView        * imgProvider;
@property (nonatomic, weak) IBOutlet UILabel    	     * lblProvider;
@property (nonatomic, weak) IBOutlet JGProgressView     * progress;
@property (nonatomic, weak) IBOutlet KGHitTestingButton * btnDisclose;
@property (nonatomic, weak) IBOutlet ZDCBadgedBarLabel  * lblBadge;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint * cnstlblBadgeWidth;

@property (nonatomic, assign, readwrite) BOOL showCheckMark;

@property (nonatomic, copy, readwrite) NSString *userID;
@property (nonatomic, copy, readwrite, nullable) NSString *identityID;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol RemoteUserTableViewCellDelegate <NSObject>
@optional

- (void)tableView:(UITableView *)tableView disclosureButtonTappedAtCell:(RemoteUserTableViewCell *)cell;

@end

NS_ASSUME_NONNULL_END
