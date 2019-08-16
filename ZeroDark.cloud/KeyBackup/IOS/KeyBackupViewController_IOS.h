/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>
#import "ZDCUITools.h"
#import "KeyBackup_Base.h"

NS_ASSUME_NONNULL_BEGIN

 

@interface KeyBackupViewController_IOS : KeyBackup_Base <UINavigationControllerDelegate>

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner;
 
// private IOS API
-(void) showWait:(NSString* __nonnull)title
		 message:(NSString* __nullable)message
  viewController:(UIViewController* __nullable)viewController
 completionBlock:(dispatch_block_t __nullable)completionBlock;

-(void) showError:(NSString* __nonnull)title
		  message:(NSString* __nullable)message
   viewController:(UIViewController* __nullable)viewController
  completionBlock:(dispatch_block_t __nullable)completionBlock;


-(void)createBackupDocumentWithQRCodeString:(NSString * _Nullable)qrCodeString
										  hasPassCode:(BOOL)hasPassCode
								completionBlock:(void (^_Nullable)(NSURL *_Nullable url,
																			  UIImage* _Nullable image,
																			  NSError *_Nullable error ))completionBlock;

// IOS versions of keyBackup

- (void)pushBackupAccessKeyWithUserID:(NSString* __nonnull)userID
		withNavigationController:(UINavigationController*)navigationController;

- (void)pushCloneDeviceWithUserID:(NSString* __nonnull)userID
				 withNavigationController:(UINavigationController*)navigationController;

@end



@protocol KeyBackupViewController_IOS_Child_Delegate <NSObject>
@required
@optional

- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender;
@end



@interface KeyBackupSubViewController_Base : UIViewController <KeyBackupViewController_IOS_Child_Delegate>

@property (nonatomic, readwrite) KeyBackupViewController_IOS * keyBackupVC;
@end

NS_ASSUME_NONNULL_END
