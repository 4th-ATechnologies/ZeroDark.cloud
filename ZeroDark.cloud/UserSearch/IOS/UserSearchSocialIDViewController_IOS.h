/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>

@class ZeroDarkCloud;
@class ZDCSearchResult;
@protocol UserSearchSocialIDViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface UserSearchSocialIDViewController_IOS : UIViewController

- (instancetype)initWithDelegate:(nullable id<UserSearchSocialIDViewControllerDelegate>)delegate
                           owner:(ZeroDarkCloud *)inOwner
                     localUserID:(NSString *)localUserID
                    searchResult:(ZDCSearchResult *)searchResult;

@property (nonatomic, weak) id<UserSearchSocialIDViewControllerDelegate> delegate;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol UserSearchSocialIDViewControllerDelegate <NSObject>
@optional

- (void)userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
                     didSelectIdentityID:(NSString *)identityID
                               forUserID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
