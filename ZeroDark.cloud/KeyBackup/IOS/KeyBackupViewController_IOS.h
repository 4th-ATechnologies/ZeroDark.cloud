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
 
- (void)showWait:(NSString *)title
         message:(nullable NSString *)message
  viewController:(nullable UIViewController *)viewController
 completionBlock:(nullable dispatch_block_t)completionBlock;

- (void)showError:(NSString *)title
          message:(nullable NSString *)message
   viewController:(nullable UIViewController *)viewController
  completionBlock:(nullable dispatch_block_t)completionBlock;

-(void)createBackupDocumentWithQRCodeString:(NSString * _Nullable)qrCodeString
										  hasPassCode:(BOOL)hasPassCode
								completionBlock:(void (^_Nullable)(NSURL *_Nullable url,
																			  UIImage* _Nullable image,
																			  NSError *_Nullable error ))completionBlock;

- (void)pushBackupAccessKeyWithUserID:(NSString* __nonnull)userID
		withNavigationController:(UINavigationController*)navigationController;

- (void)pushCloneDeviceWithUserID:(NSString* __nonnull)userID
				 withNavigationController:(UINavigationController*)navigationController;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol KeyBackupViewController_IOS_Child_Delegate <NSObject>
@optional

- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KeyBackupSubViewController_Base : UIViewController <KeyBackupViewController_IOS_Child_Delegate>

@property (nonatomic, readwrite) KeyBackupViewController_IOS * keyBackupVC;

@end

NS_ASSUME_NONNULL_END
