/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import <UIKit/UIKit.h>
#import "ZDCUITools.h"

@class ZeroDarkCloud;

NS_ASSUME_NONNULL_BEGIN

@class RemoteUsersViewController_IOS;
@class ZDCSearchUserResult;

@protocol RemoteUsersViewController_IOSDelegate <NSObject>
@optional

- (void)remoteUserViewController:(id)sender
      completedWithNewRecipients:(NSArray <NSString* /* [userID */> * __nullable)recipients
                    userObjectID:(NSString* __nullable)userObjectID;

@end


@interface RemoteUsersViewController_IOS : UIViewController

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
						localUserID:(NSString* __nonnull)inLocalUserID
					 remoteUserIDs:(nullable NSSet <NSString*> * )remoteUserIDs
								title:(NSString * __nullable)title
				completionHandler:(sharedUsersViewCompletionHandler __nullable )completionHandler;

@end

NS_ASSUME_NONNULL_END
