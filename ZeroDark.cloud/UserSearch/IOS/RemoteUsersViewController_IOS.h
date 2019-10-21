/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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
						localUserID:(NSString *)inLocalUserID
					 remoteUserIDs:(NSSet <NSString*> *_Nullable)remoteUserIDs
								title:(NSString *_Nullable)title
				completionHandler:(SharedUsersViewCompletionHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
