/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <UIKit/UIKit.h>
@class ZeroDarkCloud;

NS_ASSUME_NONNULL_BEGIN

@class UserSearchViewController_IOS;

@protocol UserSearchViewControllerDelegate <NSObject>
@optional

- (void)userSearchUserViewController:(id)sender
                      selectedRecipients:(NSArray <NSArray* /* [userID , auth0ID ]>*/> * )recipients;

- (void)userSearchUserViewController:(id)sender
                       removedRecipients:(NSArray <NSString* /* [userID */> * )recipients;


@end

@interface UserSearchViewController_IOS : UIViewController

@property (nonatomic, weak) id<UserSearchViewControllerDelegate>    delegate;

- (instancetype)initWithDelegate:(nullable id <UserSearchViewControllerDelegate>)inDelegate
                           owner:(ZeroDarkCloud*)inOwner
                     localUserID:(NSString* __nonnull)inLocalUserID
                 sharedUserIDs:(NSArray <NSString* /* [userID */> *)sharedUserIDs;

@end

NS_ASSUME_NONNULL_END
