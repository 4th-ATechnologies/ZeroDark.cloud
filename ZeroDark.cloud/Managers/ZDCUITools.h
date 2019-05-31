/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else // macOS
#import <Cocoa/Cocoa.h>
#endif

#import "OSPlatform.h"

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IPHONE

@interface ZDCAccountSetupViewControllerProxy : UIViewController
-(void)pushCreateAccount;
-(void)pushSignInToAccount;
@end

#endif

/**
 * The ZDCUITools is a series of functions that simpily the user interface needed for
 * creating, signing-in and managing ZDCLocalUsers
 */

@interface ZDCUITools : NSObject

#if TARGET_OS_IPHONE

typedef void(^accountSetupViewCompletionHandler)(NSString *__nullable localUserID,
																 BOOL completedActivation,
																 BOOL shouldBackupAccessKey);

/**
 * return a UIViewController for user activation activation
 *
 * @param viewController
 * an optional initial view controler for app customization
 *
 * @param canDismiss
 *   boolean indicating if the user can dismiss the activation view before completing activation
 *
 * @param completionHandler
 *   The completionHandler, to call once the user has completed it's interaction
 */
-(ZDCAccountSetupViewControllerProxy*)accountSetupViewControllerWithInitialViewController:(UIViewController* __nullable) viewController
																  canDismissWithoutNewAccount:(BOOL)canDismiss
																		completionHandler:(accountSetupViewCompletionHandler __nullable )completionHandler;

/**
 * return a UIViewController for resuming user activation
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param completionHandler
 *   The completionHandler, to call once the user has completed it's interaction
 */
- (UIViewController*)accountResumeSetupForLocalUserID:(NSString*)localUserID
												completionHandler:(accountSetupViewCompletionHandler __nullable )completionHandler;

/**
 * Push a UIViewController for managing a ZDCLocalUser settings.
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param navigationController
 * The app bar navigation controller instance that owns the view controller.
 */
-(void)pushSettingsForLocalUserID:(NSString* __nonnull)localUserID
		 withNavigationController:(UINavigationController*)navigationController;

/**
 * Push a UIViewController for managing a ZDCLocalUser socialIDs
 *
 * @param userID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param navigationController
 * The app bar navigation controller instance that owns the view controller.
 */
- (void)pushSocialIdMgmtWithUserID:(NSString* __nonnull)userID
		  withNavigationController:(UINavigationController*)navigationController;

/**
 * Push a UIViewController for backing up a ZDCLocalUser Access Key
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param navigationController
 * The app bar navigation controller instance that owns the view controller.
 */
- (void)pushBackupAccessForLocalUserID:(NSString* __nonnull)localUserID
				  withNavigationController:(UINavigationController*)navigationController;

/**
 * Push a UIViewController for veriying up a ZDCLocalUser Public key
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param navigationController
 * The app bar navigation controller instance that owns the view controller.
 */
- (void)pushVerifyPublicKeyForUserID:(NSString* __nonnull)userID
                         localUserID:(NSString* __nonnull)localUserID
            withNavigationController:(UINavigationController*)navigationController;


typedef void(^sharedUsersViewCompletionHandler)(NSSet <NSString*>  * _Nullable  addedUserIDs,
																NSSet <NSString*>  * _Nullable  removedUserIDs );

/**
 * Push a UIViewController for managing the list of users that an object is shared with.
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param remoteUserIDs
 *   An array of userIDs that this node is currently shared with
 *
 * @param title
 *   An optional title for the view
 *
 * @param navigationController
 * The app bar navigation controller instance that owns the view controller.
 *
 * @param completionHandler
 *   The completionHandler, to call once the user has completed it's interaction
 */
- (void)pushSharedUsersViewForLocalUserID:(NSString* __nonnull)localUserID
                            remoteUserIDs:(NSSet <NSString*> * __nullable)remoteUserIDs
												title:(NSString * __nullable)title
                     navigationController:(UINavigationController* __nonnull)navigationController
                        completionHandler:(sharedUsersViewCompletionHandler __nullable )completionHandler;


/**
 * Push a UIViewController displaying syncing activity
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *   or null for all users.
 *
 * @param navigationController
 * The app bar navigation controller instance that owns the view controller.
 */
- (void)pushActivityViewForLocalUserID:(NSString* __nullable)localUserID
				  withNavigationController:(UINavigationController*)navigationController;

#else // OSX

#endif


// MARK: useful for debugging

/**
 * Delete the Refresh token for a given Local User.
 * This will effectively log the user out and require them to reauthenticate.
 * mostly this is useful for debugging. and you would never do this.
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
  *
 * @param completionBlock
 *   The completionHandler, to call once the token is removed from the database
 */

- (void)deleteRefreshTokenforUserID:(NSString *)localUserID
                    completionBlock:(dispatch_block_t __nullable )completionBlock;

@end

NS_ASSUME_NONNULL_END
