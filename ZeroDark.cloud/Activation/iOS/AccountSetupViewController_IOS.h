/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>
#import "AccountSetup_Base.h"
#import "ZDCUITools.h"

NS_ASSUME_NONNULL_BEGIN

@interface AccountSetupViewController_IOS : AccountSetup_Base <UINavigationControllerDelegate>

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner;

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
  canDismissWithoutNewAccount:(BOOL)canDismissWithoutNewAccount
				completionHandler:(accountSetupViewCompletionHandler __nullable )completionHandler;

@property (weak, nonatomic) IBOutlet UIButton *btnBack;
@property (weak, nonatomic) IBOutlet UIButton *btnNext;
@property (weak, nonatomic) IBOutlet UIButton *btnCancel;
@property (weak, nonatomic) IBOutlet UIButton *btnHelp;

@property (nonatomic, readonly)  UINavigationController *containedNavigationController;
@property (nonatomic, readonly) BOOL   canDismissWithoutNewAccount;


//// this is the token we are redeeming to activate the account, if we succeed we need to remove it from database.
//@property (nonatomic, readwrite,nullable) NSString*         activationToken;


-(void) showWait:(NSString* __nonnull)title
		 message:(NSString* __nullable)message
  viewController:(UIViewController* __nullable)viewController
 completionBlock:(dispatch_block_t __nullable)completionBlock;

-(void) showError:(NSString* __nonnull)title
		  message:(NSString* __nullable)message
   viewController:(UIViewController* __nullable)viewController
  completionBlock:(dispatch_block_t __nullable)completionBlock;

-(void)setHelpButtonHidden:(BOOL)hidden;

-(void)popToViewControllerForViewID:(AccountSetupViewID)viewID
		   withNavigationController:(UINavigationController*)navigationController;

-(void)popToNonAccountSetupView:(UINavigationController*)navigationController;

-(void)pushInitialViewController:(UIViewController* __nonnull)initialViewController;

// IOS versions of social ID mgmt

- (void)pushSocialIdMgmtWithUserID:(NSString* __nonnull)userID
		  withNavigationController:(UINavigationController*)navigationController;

-(void)pushUserAvatarWithUserID:(NSString *)userID
                     identityID:(NSString *)identityID
           navigationController:(UINavigationController*)navigationController;

- (void)pushAddIdentityWithUserID:(NSString* __nonnull)userID
		 withNavigationController:(UINavigationController*)navigationController;
 
- (void)pushSocialAuthenticate:(NSString* __nonnull)userID
					  provider:(NSDictionary* __nonnull)provider
	  withNavigationController:(UINavigationController*)navigationController;

- (void)pushDataBaseAccountCreate:(NSString* __nonnull)userID
		 withNavigationController:(UINavigationController*)navigationController;

- (void)pushDataBaseAccountLogin:(NSString* __nonnull)userID
		withNavigationController:(UINavigationController*)navigationController;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol AccountSetupViewController_IOS_Child_Delegate <NSObject>
@optional

- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface AccountSetupSubViewController_Base : UIViewController <AccountSetupViewController_IOS_Child_Delegate>

@property (nonatomic, readwrite) AccountSetupViewController_IOS *accountSetupVC;

@end

NS_ASSUME_NONNULL_END
