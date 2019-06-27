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

@class UserSearchSocialIDViewController_IOS;
@class ZDCSearchUserResult;

@protocol UserSearchSocialIDViewControllerDelegate <NSObject>
@optional


- (void) userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
                            didSelectAuth0ID:(NSString*)auth0ID
                                   forUserID:(NSString*)userID;

@end


@interface UserSearchSocialIDViewController_IOS : UIViewController

@property (nonatomic, weak) id<UserSearchSocialIDViewControllerDelegate>    delegate;

- (instancetype)initWithDelegate:(nullable id <UserSearchSocialIDViewControllerDelegate>)inDelegate
                           owner:(ZeroDarkCloud*)inOwner
                     localUserID:(NSString* __nonnull)inLocalUserID
                searchResultInfo:(ZDCSearchUserResult* __nonnull)searchResultInfo;

@end

NS_ASSUME_NONNULL_END
