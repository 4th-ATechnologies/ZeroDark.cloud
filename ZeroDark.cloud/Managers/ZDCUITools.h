/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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
 * Returns a UIViewController that can be used for sign-in & sign-up.
 *
 * It walks users through the processing of either:
 * - logging-in & restoring their private key
 * - creating a new account
 *
 * @param viewController
 *   An optional initial view controler for app customization.
 *   This is the first screen that's displayed.
 *   If nil, then a generic view is displayed with the app name (+ sign-in & sign-up buttons).
 *
 * @param canDismiss
 *   Indicates whether or not the user can dismiss the activation view before completing activation.
 *   Typically this is set to false if there aren't other logged-in users,
 *   and the app requires a logged-in user to work properly.
 *
 * @param completionHandler
 *   Called once the user has completed interaction with the view controller.
 *   This is always called on the main thread.
 */
- (ZDCAccountSetupViewControllerProxy *)accountSetupViewControllerWithInitialViewController:(UIViewController* __nullable) viewController
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


#if TARGET_OS_IPHONE

/**
 * return a UIViewController for that simulates push notifcations for debugging
 *
*/
- (UIViewController* __nullable)simulatePushNotificationViewController;
#endif

@end

NS_ASSUME_NONNULL_END
