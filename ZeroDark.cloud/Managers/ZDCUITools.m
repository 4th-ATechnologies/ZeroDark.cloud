/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUIToolsPrivate.h"
#import "ZeroDarkCloudPrivate.h"
#import "NSError+ZeroDark.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelInfo | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


#if TARGET_OS_IPHONE
#import "AccountSetupViewController_IOS.h"
#import "KeyBackupViewController_IOS.h"
#import "VerifyPublicKey_IOS.h"
#import "RemoteUsersViewController_IOS.h"
#import "FixSettingsViewController_IOS.h"
#import "LocalUserSettingsViewController_IOS.h"
#import "ActivityMonitor_IOS.h"
#import "SimulatePushNotificationViewController_IOS.h"

#import "ZDCPopoverTransition.h"

#else // OSX

#endif

@implementation ZDCUITools {
@private

	__weak ZeroDarkCloud *zdc;
	
#if TARGET_OS_IPHONE
	ZDCPopoverTransition *popoverTransition;
#endif
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
	}
	return self;
}

#if TARGET_OS_IPHONE
//MARK: IOS

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUITools.html
 */
- (ZDCAccountSetupViewControllerProxy *)accountSetupViewControllerWithInitialViewController:(UIViewController* __nullable) viewController
																				  canDismissWithoutNewAccount:(BOOL)canDismiss
																								completionHandler:(accountSetupViewCompletionHandler __nullable )completionHandler
{
	AccountSetupViewController_IOS* vc = [[AccountSetupViewController_IOS alloc]
													  initWithOwner:zdc
													  canDismissWithoutNewAccount:canDismiss
													  completionHandler:completionHandler];
	
	if(viewController)
	{
		[vc pushInitialViewController:viewController];
	}
	else
	{
		[vc pushIntro];
	}
	
	return (ZDCAccountSetupViewControllerProxy*)vc;
}

- (UIViewController*)accountResumeSetupForLocalUserID:(NSString*)localUserID
												completionHandler:(accountSetupViewCompletionHandler __nullable )completionHandler;
{
	AccountSetupViewController_IOS* vc = [[AccountSetupViewController_IOS alloc]
													  initWithOwner:zdc
													  canDismissWithoutNewAccount:YES
													  completionHandler:completionHandler];

	[vc pushResumeActivationForUserID:localUserID];
	
	return vc;

}

- (void)pushSettingsForLocalUserID:(NSString *)localUserID
          withNavigationController:(UINavigationController*)navigationController
{
	LocalUserSettingsViewController_IOS *vc =
	  [[LocalUserSettingsViewController_IOS alloc] initWithOwner: zdc
	                                                 localUserID: localUserID];
	
	[navigationController pushViewController:vc animated:YES];
}

- (void)pushSocialIdMgmtWithUserID:(NSString* __nonnull)userID
		  withNavigationController:(UINavigationController*)navigationController
{

	AccountSetupViewController_IOS* vc = [[AccountSetupViewController_IOS alloc]
										  initWithOwner:zdc];

	[vc pushSocialIdMgmtWithUserID:userID
 		  withNavigationController:navigationController];
}

- (void)pushBackupAccessForLocalUserID:(NSString* __nonnull)localUserID
               withNavigationController:(UINavigationController*)navigationController
{
	KeyBackupViewController_IOS* vc = [[KeyBackupViewController_IOS alloc]
												  initWithOwner:zdc];

	[vc pushBackupAccessKeyWithUserID:localUserID
			 withNavigationController:navigationController];

}

- (void)pushVerifyPublicKeyForUserID:(NSString* __nonnull)userID
                         localUserID:(NSString* __nonnull)localUserID
            withNavigationController:(UINavigationController*)navigationController
{
	
	
	VerifyPublicKey_IOS* vc = [[VerifyPublicKey_IOS alloc]
										initWithOwner:zdc
										remoteUserID:userID
										localUserID:localUserID];
	
	[navigationController pushViewController:vc animated:YES];
}

 - (void)pushSharedUsersViewForLocalUserID:(NSString *)localUserID
                             remoteUserIDs:(NSSet<NSString*> *_Nullable)remoteUserIDs
                                     title:(NSString *_Nullable)title
                      navigationController:(UINavigationController *)navigationController
                         completionHandler:(SharedUsersViewCompletionHandler)completionHandler
{
	RemoteUsersViewController_IOS *vc =
	  [[RemoteUsersViewController_IOS alloc] initWithOwner: zdc
	                                           localUserID: localUserID
	                                         remoteUserIDs: remoteUserIDs
	                                                 title: title
	                                     completionHandler: completionHandler];

	[navigationController pushViewController:vc animated:YES];
}


-(void)displayPhotoAccessSettingsAlert
{
    UIViewController* frontVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    NSString* titleText =  NSLocalizedString(@"Photo Access Off", @"Photo Access Off");
    
    
    NSString* informativeText =  NSLocalizedString(@"Change your settings to allow Storm4 access to Photos.",
                                                   @"Change your settings to allow Storm4 access to Photos");
    
    UIImage* imgSwitch =  [UIImage imageNamed:@"switch_ios"
                                      inBundle:[ZeroDarkCloud frameworkBundle]
                 compatibleWithTraitCollection:nil];
    
    UIImage* imgSetting =  [UIImage imageNamed:@"settings_ios"
                                      inBundle:[ZeroDarkCloud frameworkBundle]
                 compatibleWithTraitCollection:nil];
    
    UIImage* imgPhotos =  [UIImage imageNamed:@"photos_ios"
                                     inBundle:[ZeroDarkCloud frameworkBundle]
                compatibleWithTraitCollection:nil];
    
    
    NSArray* steps = @[
                       @[imgSetting,  @"Go to Settings."],
                       @[imgPhotos,  @"Tap Photos."],
                       @[imgSwitch,  @"Set \"Allow Photo Access\" to Read and Write."],
                       ];
    
    FixSettingsViewController_IOS* covc =  [[FixSettingsViewController_IOS alloc]
                                        initWithDelegate:(id<FixSettingsViewControllerDelegate>)self
                                        title:titleText
                                        informational:informativeText
                                        steps:steps];
    
    covc.modalPresentationStyle = UIModalPresentationCustom;
     covc.transitioningDelegate = (id <UIViewControllerTransitioningDelegate>) self;
    
    [frontVC presentViewController:covc animated:YES completion:^{
    }];
    
}


-(void)displayCameraAccessSettingsAlert
{
    UIViewController* frontVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    NSString* titleText =  NSLocalizedString(@"Camera Access Off", @"Camera Access Off");
    
    
    NSString* informativeText =  NSLocalizedString(@"Change your settings to allow Storm4 access to Camera.",
                                                   @"Change your settings to allow Storm4 access to Camera");
    
    
    UIImage* imgSetting =  [UIImage imageNamed:@"settings_ios"
                                   inBundle:[ZeroDarkCloud frameworkBundle]
              compatibleWithTraitCollection:nil];

    UIImage* imgCamera =  [UIImage imageNamed:@"camera_ios"
                                      inBundle:[ZeroDarkCloud frameworkBundle]
                 compatibleWithTraitCollection:nil];

 
    NSArray* steps = @[
                       @[imgSetting,  @"Go to Settings."],
                       @[imgCamera,  @"Set \"Camera\" to On."],
                       ];
    
    FixSettingsViewController_IOS* covc =  [[FixSettingsViewController_IOS alloc]
                                        initWithDelegate:(id<FixSettingsViewControllerDelegate>)self
                                        title:titleText
                                        informational:informativeText
                                        steps:steps];
    
    covc.modalPresentationStyle = UIModalPresentationCustom;
    covc.transitioningDelegate = (id <UIViewControllerTransitioningDelegate>) self;
    
    [frontVC presentViewController:covc animated:YES completion:^{
    }];
}

//MARK: FixSettingsViewControllerDelegate

- (void)fixSettingsViewController:(FixSettingsViewController_IOS *)sender dismissViewControllerAnimated:(BOOL) animated
{
    ZDCLogAutoTrace();
    
    [sender dismissViewControllerAnimated:YES
                               completion:^{  }];
}


- (void)fixSettingsViewController:(FixSettingsViewController_IOS *)sender showSettingsHit:(UIButton *)btn
{
    if (UIApplicationOpenSettingsURLString != nil)
    {
		 NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
		 NSDictionary *options = @{};
		 [[UIApplication sharedApplication] openURL:url options:options completionHandler:nil];
    }
    
}

//MARK:  UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source
{
    popoverTransition = [[ZDCPopoverTransition alloc] init];
    popoverTransition.reverse = NO;
    popoverTransition.duration = 0.25;
    popoverTransition.origin = ZDCPopoverTransitionOrigin_Bottom;
    
    return popoverTransition;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    ZDCPopoverTransition *transition = popoverTransition;
    transition.reverse = YES;
    
    popoverTransition = nil;
    return transition;
}


- (void)pushActivityViewForLocalUserID:(NSString* __nullable)localUserID
				  withNavigationController:(UINavigationController*)navigationController
{
	ActivityMonitor_IOS* vc = [[ActivityMonitor_IOS alloc]
										initWithOwner:zdc
										localUserID:localUserID];
	
	[navigationController pushViewController:vc animated:YES];

}

- (UIViewController* __nullable)simulatePushNotificationViewController
{
	SimulatePushNotificationViewController_IOS*  vc = [[SimulatePushNotificationViewController_IOS alloc]
																		initWithOwner:zdc ];
	
	return vc;
}

 #else // OSX

//MARK: OSX

#endif

//MARK: Common

- (void)deleteRefreshTokenforUserID:(NSString *)localUserID
                    completionBlock:(dispatch_block_t __nullable )completionBlock
{
	[zdc.awsCredentialsManager flushAWSCredentialsForUser: localUserID
	                                   deleteRefreshToken: YES
	                                      completionQueue: nil
	                                      completionBlock: completionBlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(nullable NSString *)description
{
	return [self errorWithCode:0 description:description];
}

- (NSError *)errorWithCode:(NSInteger)code description:(nullable NSString *)description
{
	return [NSError errorWithClass:[self class] code:code description:description];
}

@end
