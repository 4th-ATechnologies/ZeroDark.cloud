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
@protocol UserSearchViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface UserSearchViewController_IOS : UIViewController

- (instancetype)initWithDelegate:(id<UserSearchViewControllerDelegate>)delegate
                           owner:(ZeroDarkCloud *)owner
                     localUserID:(NSString *)localUserID
                   sharedUserIDs:(NSArray<NSString *> *)sharedUserIDs;

@property (nonatomic, weak) id<UserSearchViewControllerDelegate> delegate;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol UserSearchViewControllerDelegate <NSObject>
@optional

- (void)userSearchViewController:(id)sender
              selectedRecipients:(NSArray<NSArray* /* [userID , auth0ID ]>*/> * )recipients;

- (void)userSearchViewController:(id)sender
               removedRecipients:(NSArray <NSString* /* [userID */> * )recipients;

@end

NS_ASSUME_NONNULL_END
