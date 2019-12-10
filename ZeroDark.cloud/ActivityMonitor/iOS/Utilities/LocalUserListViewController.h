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
@protocol LocalUserListViewController_Delegate;

NS_ASSUME_NONNULL_BEGIN

@interface LocalUserListViewController_IOS : UIViewController  <UIPopoverPresentationControllerDelegate>

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner
                     delegate:(nullable id <LocalUserListViewController_Delegate>)delegate
               selectedUserID:(NSString *)selectedUserID;

@property (nonatomic, weak, readonly, nullable) id<LocalUserListViewController_Delegate> delegate;

- (CGFloat)preferedWidth;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol LocalUserListViewController_Delegate <NSObject>
@optional

- (void)localUserListViewController:(LocalUserListViewController_IOS *)sender
                    didSelectUserID:(nullable NSString *) userID;
@end

NS_ASSUME_NONNULL_END
