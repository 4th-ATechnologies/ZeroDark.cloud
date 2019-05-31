/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "KeyBackupViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>

#import "BackupIntroViewController_IOS.h"
#import "BackupAsTextViewController_IOS.h"
#import "BackupAsImageViewController_IOS.h"
#import "VerifyTextViewController_IOS.h"
#import "VerifyImageViewController_IOS.h"
#import "BackupSuccessViewController_IOS.h"
#import "UnlockAccessCodeViewController_IOS.h"
#import "BackupSocialViewController_IOS.h"
#import "KeyBackupPrintViewController_IOS.h"
#import "CloneDeviceViewController_IOS.h"
#import "BackupComboViewController_IOS.h"

#import "ZDCPanTransition.h"
#import "SCLAlertView.h"
#import "UIColor+Crayola.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int ddLogLevel = DDLogLevelWarning;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

@implementation KeyBackupSubViewController_Base
@synthesize keyBackupVC = keyBackupVC;
@end


@implementation KeyBackupViewController_IOS {
	
	BackupIntroViewController_IOS	*    	vc_BackupIntro;
	BackupAsTextViewController_IOS	*		vc_BackupAsText;
	BackupAsImageViewController_IOS	*		vc_BackupAsImage;
	BackupComboViewController_IOS		*		vc_BackupAsCombo;
	
	VerifyTextViewController_IOS	*		vc_VerifyText;
	VerifyImageViewController_IOS	*		vc_VerifyImage;
	UnlockAccessCodeViewController_IOS*     vc_UnlockAccessCode;
	BackupSuccessViewController_IOS *       vc_Success;
	BackupSocialViewController_IOS*         vc_Social;
	KeyBackupPrintViewController_IOS*		vc_Print;
	CloneDeviceViewController_IOS*			vc_Clone;
	
	UINavigationController *containedNavigationController;
	UIViewController* vcToPushTo;
	UIViewController* vcToPopTo;        // remember the vc we came in with -- pop out when done.
	
	NSTimer *       showWaitBoxTimer;
	SCLAlertView *  errorAlert;
	SCLAlertView *  waitingAlert;
	
	BOOL isSetup;
	
}

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"KeyBackup_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"KeyBackupViewController"];
	if (self)
	{
		[self commonInit];
		self.owner = inOwner;
		vcToPopTo = nil;
	}
	return self;

}


-(KeyBackupSubViewController_Base*)viewControllerForViewID:(KeyBackupViewID)viewID
{
	KeyBackupSubViewController_Base* vc = NULL;

	switch(viewID)
	{
		case KeyBackupViewID_CloneDevice:
			if(!vc_Clone)
			{
				NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
				UIStoryboard *cloneStoryboard = [UIStoryboard storyboardWithName:@"CloneDevice_IOS" bundle:bundle];

				vc_Clone        = (CloneDeviceViewController_IOS *)
				[cloneStoryboard instantiateViewControllerWithIdentifier:@"CloneDeviceViewController_IOS"];
			}
			vc = vc_Clone;
			break;
	 
		case KeyBackupViewID_BackupIntro:
			if(!vc_BackupIntro)
			{
				vc_BackupIntro        = (BackupIntroViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"BackupIntroViewController_IOS"];
			}
			vc = vc_BackupIntro;
			break;
			
			case KeyBackupViewID_BackupAsCombo:
			if(!vc_BackupAsCombo)
			{
				vc_BackupAsCombo        = (BackupComboViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"BackupComboViewController_IOS"];
			}
			vc = vc_BackupAsCombo;
			break;
			
		case KeyBackupViewID_BackupAsImage:
			if(!vc_BackupAsImage)
			{
				vc_BackupAsImage        = (BackupAsImageViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"BackupAsImageViewController_IOS"];
			}
			vc = vc_BackupAsImage;
			break;
			
		case KeyBackupViewID_BackupAsText:
			if(!vc_BackupAsText)
			{
				vc_BackupAsText        = (BackupAsTextViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"BackupAsTextViewController_IOS"];
			}
			vc = vc_BackupAsText;
			break;
			
		case KeyBackupViewID_VerifyText:
			if(!vc_VerifyText)
			{
				vc_VerifyText       = (VerifyTextViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"VerifyTextViewController_IOS"];
			}
			vc = vc_VerifyText;
			break;
			
		case KeyBackupViewID_VerifyImage:
			if(!vc_VerifyImage)
			{
				vc_VerifyImage        = (VerifyImageViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"VerifyImageViewController_IOS"];
			}
			vc = vc_VerifyImage;
			break;
			
			
		case KeyBackupViewID_UnlockAccessCode:
			if(!vc_UnlockAccessCode)
			{
				vc_UnlockAccessCode        = (UnlockAccessCodeViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"UnlockAccessCodeViewController_IOS"];
			}
			vc = vc_UnlockAccessCode;
			break;
			
		case KeyBackupViewID_Success:
			if(!vc_Success)
			{
				vc_Success        = (BackupSuccessViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"BackupSuccessViewController_IOS"];
			}
			vc = vc_Success;
			break;
			
		case KeyBackupViewID_Social_Intro:
			if(!vc_Social)
			{
				vc_Social   = [( BackupSocialViewController_IOS *) [BackupSocialViewController_IOS alloc] initViewController];
			}
			vc = vc_Social;
			break;
			
		case KeyBackupViewID_Print:
		if(!vc_Print)
		{
			vc_Print        = (KeyBackupPrintViewController_IOS *)
			[self.storyboard instantiateViewControllerWithIdentifier:@"KeyBackupPrintViewController_IOS"];
		}
		vc = vc_Print;
		break;

		default:;
			
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
													 reason:[NSString stringWithFormat:@"internal error viewControllerForViewID (%ld)", (long)viewID ]  userInfo:nil];
	}

	vc.keyBackupVC = self;

	return vc;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Progress
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void) showError:(NSString* __nonnull)title
		  message:(NSString* __nullable)message
   viewController:(UIViewController* __nullable)viewController
  completionBlock:(dispatch_block_t __nullable)completionBlock
{
	[self cancelWait];

    UIViewController* vc = viewController;
    if(!vc)
        vc = containedNavigationController.viewControllers.lastObject;
    
    if(!vc)
        vc = self;

    errorAlert = [[SCLAlertView alloc] initWithNewWindowWidth: vc.view.frame.size.width -40];
 	errorAlert.showAnimationType = SCLAlertViewShowAnimationFadeIn;

	__weak typeof(self) weakSelf = self;

	[errorAlert addButton:@"OK" actionBlock:^(void) {

		if(completionBlock) {
			completionBlock();
		}

		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf) {
			strongSelf->errorAlert = nil;
		}
	}];
    
 
	[errorAlert showError:vc
					title:title
				 subTitle:message
		 closeButtonTitle:nil
				 duration:0.f];


}

-(void) showError:(NSString*)title
		  message:(NSString*)message
  completionBlock:(dispatch_block_t __nullable)completionBlock

{
	[self showError:title message:message viewController:nil completionBlock:completionBlock];
}

-(void) showWait:(NSString* __nonnull)title
		 message:(NSString* __nullable)message
  viewController:(UIViewController* __nullable)viewController
 completionBlock:(dispatch_block_t __nullable)completionBlock
{
	[self cancelWait];

	NSMutableDictionary * userInfo =    @{  @"title":   title?:@"",
											@"message": message?:@""
											}.mutableCopy;

	if(viewController)
		[userInfo setObject:viewController forKey:@"viewController"];

	if(completionBlock)
		[userInfo setObject:completionBlock forKey:@"completionBlock"];

	showWaitBoxTimer =  [NSTimer scheduledTimerWithTimeInterval:.7
														 target:self
													   selector:@selector(showWaitBox:)
													   userInfo:userInfo
														repeats:NO];

}

-(void) showWait:(NSString*)title
		 message:(NSString*)message
 completionBlock:(dispatch_block_t __nullable) completionBlock
{
	[self showWait:title
           message:message
    viewController:nil
   completionBlock:completionBlock];
}


- (void)showWaitBox:(NSTimer*)sender
{
	NSDictionary* userInfo = sender.userInfo;

	NSString* title = userInfo[@"title"];
	NSString* message = userInfo[@"message"];
	dispatch_block_t completionBlock =  userInfo[@"completionBlock"];
	UIViewController* vc = userInfo[@"viewController"];

	if(waitingAlert)
	{
		[waitingAlert hideView];
		waitingAlert = nil;
	}

	waitingAlert = [[SCLAlertView alloc] init];
	waitingAlert.customViewColor = [UIColor crayolaBlueJeansColor];
	waitingAlert.showAnimationType = SCLAlertViewShowAnimationFadeIn;

	__weak typeof(self) weakSelf = self;

	if(completionBlock)
	{
		[waitingAlert addButton:@"Cancel"
					actionBlock:^(void)
		 {
			 if(completionBlock) {
				 completionBlock();
			 }

			 __strong typeof(self) strongSelf = weakSelf;
			 if (strongSelf) {
				 [strongSelf cancelWait];
			 }
		 }];
	}

	[waitingAlert showWaiting:vc?vc:self
						title:title
					 subTitle:message
			 closeButtonTitle:nil
					 duration:0.f];


}


-(void) cancelWait
{
	if(showWaitBoxTimer) {
		[showWaitBoxTimer invalidate];
	}

	if(waitingAlert)
	{
		[waitingAlert hideView];
		waitingAlert = nil;
	}

}


-(void) handleFail
{
    if (vcToPopTo)
    {
        [containedNavigationController popToViewController:vcToPopTo animated:NO];
    }
}

-(void) handleDone
{
    if (vcToPopTo)
    {
       [containedNavigationController popToViewController:vcToPopTo animated:NO];
    }
 }


#pragma mark - view control



-(void) popFromCurrentView
{
 
}


- (void)pushHelpWithTag:(NSString*)tag
{
//	[self viewControllerForViewID:AccountSetupViewID_Help];
//	vc_Help.helpTag = tag;
//	[containedNavigationController pushViewController:vc_Help animated:YES];

}

#pragma mark - IOS versions of keyBackup

- (void)pushCloneDeviceWithUserID:(NSString* __nonnull)userID
			withNavigationController:(UINavigationController*)navigationController
{
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	containedNavigationController = navigationController;
	
	vcToPopTo = containedNavigationController.viewControllers.lastObject;
	
	[self viewControllerForViewID:KeyBackupViewID_CloneDevice];
	[navigationController pushViewController:vc_Clone animated:YES];

}

- (void)pushBackupAccessKeyWithUserID:(NSString* __nonnull)userID
			 withNavigationController:(UINavigationController*)navigationController
{
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}

	containedNavigationController = navigationController;

    vcToPopTo = containedNavigationController.viewControllers.lastObject;
    
	[self viewControllerForViewID:KeyBackupViewID_BackupIntro];
	[navigationController pushViewController:vc_BackupIntro animated:YES];
}

- (void)pushBackupAsText
{
	[self viewControllerForViewID:KeyBackupViewID_BackupAsText];
	[containedNavigationController pushViewController:vc_BackupAsText animated:YES];

}

- (void)pushBackupAsImage
{
	[self viewControllerForViewID:KeyBackupViewID_BackupAsImage];
	[containedNavigationController pushViewController:vc_BackupAsImage animated:YES];

}
- (void)pushBackupAsCombo
{
	[self viewControllerForViewID:KeyBackupViewID_BackupAsCombo];
	[containedNavigationController pushViewController:vc_BackupAsCombo animated:YES];
	
}



- (void)pushVerifyText
{
	[self viewControllerForViewID:KeyBackupViewID_VerifyText];
	[containedNavigationController pushViewController:vc_VerifyText animated:YES];

}


- (void)pushVerifyImage
{
	[self viewControllerForViewID:KeyBackupViewID_VerifyImage];
	[containedNavigationController pushViewController:vc_VerifyImage animated:YES];
}

- (void)pushUnlockAccessCode:(NSString* __nullable)cloneString
{
    [self viewControllerForViewID:KeyBackupViewID_UnlockAccessCode];
    vc_UnlockAccessCode.cloneString = cloneString;
    [containedNavigationController pushViewController:vc_UnlockAccessCode animated:YES];
}


- (void)pushBackupSuccess
{
    [self viewControllerForViewID:KeyBackupViewID_Success];
    [containedNavigationController pushViewController:vc_Success animated:YES];
}

- (void)pushBackupSocial
{
    [self viewControllerForViewID:KeyBackupViewID_Social_Intro];
	[vc_Social resetOnWillAppear];
   [containedNavigationController pushViewController:vc_Social animated:YES];

}


-(void)createBackupDocumentWithQRCodeString:(NSString * _Nullable)qrCodeString
										  hasPassCode:(BOOL)hasPassCode
									 completionBlock:(void (^_Nullable)(NSURL *_Nullable url,
																					UIImage* _Nullable image,
																					NSError *_Nullable error ))completionBlock
{
	[self viewControllerForViewID:KeyBackupViewID_Print];
	[vc_Print createBackupDocumentWithQRCodeString:qrCodeString
												  hasPassCode:(BOOL)hasPassCode
										completionBlock:completionBlock];

}
@end
