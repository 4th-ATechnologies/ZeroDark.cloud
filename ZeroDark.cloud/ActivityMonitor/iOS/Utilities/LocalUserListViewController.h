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

NS_ASSUME_NONNULL_BEGIN

@protocol LocalUserListViewController_Delegate;

@interface LocalUserListViewController_IOS : UIViewController  <UIPopoverPresentationControllerDelegate>

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
							delegate:(nullable id <LocalUserListViewController_Delegate>)inDelegate
					 currentUserID:(NSString*)currentUserID;


@property (nonatomic, weak, readonly, nullable) id <LocalUserListViewController_Delegate> delegate;

-(CGFloat) preferedWidth;

@end

@protocol LocalUserListViewController_Delegate <NSObject>

@optional

- (void)localUserListViewController:(LocalUserListViewController_IOS *)sender
					  didSelectUserID:(NSString* __nullable) userID;
@end


NS_ASSUME_NONNULL_END
