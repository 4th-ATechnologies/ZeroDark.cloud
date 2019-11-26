//
//  AccountCloneUnlockController_IOSViewController.m
//  ZeroDarkCloud
//
//  Created by vinnie on 3/13/19.
//

#import "AccountCloneUnlockController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCSecureTextField.h"
#import "ZDCAccessCode.h"

#import "ZDCLogging.h"

// Categories
#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"
#import "UIButton+Activation.h"
#import "NSError+S4.h"

// Libraries
#import <AudioToolbox/AudioToolbox.h>

// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation AccountCloneUnlockController_IOS
{
	IBOutlet __weak UIView*             _viewContainer;

	IBOutlet __weak NSLayoutConstraint *_containerViewBottomConstraint;
	CGFloat                             originalContainerViewBottomConstraint;

	IBOutlet __weak UIImageView*        _imgProvider;
	IBOutlet __weak UILabel*            _lblDisplayName;
	IBOutlet __weak UIImageView*        _imgQRCode;

	IBOutlet __weak ZDCSecureTextField* _txtPwdField;
	IBOutlet __weak UIButton *          _btnUnlock;
	IBOutlet __weak UILabel *           _lblFail;

	NSUInteger                     		failedTries;

	Auth0ProviderManager	*providerManager;

}
@synthesize accountSetupVC = accountSetupVC;
@synthesize cloneString = cloneString;

static const NSUInteger max_tries = 4;

- (void)viewDidLoad {
	[super viewDidLoad];

	providerManager = accountSetupVC.zdc.auth0ProviderManager;

	void (^PrepContainer)(UIView *) = ^(UIView *container){
		container.layer.cornerRadius   = 16;
		container.layer.masksToBounds  = YES;
		container.layer.borderColor    = [UIColor whiteColor].CGColor;
		container.layer.borderWidth    = 1.0f;
		container.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];
	};
	PrepContainer(_viewContainer);

	originalContainerViewBottomConstraint = CGFLOAT_MAX;

	[_btnUnlock zdc_colorize];

	_lblFail.layer.cornerRadius   = 16;
	_lblFail.layer.masksToBounds  = YES;
	_lblFail.backgroundColor      = [UIColor redColor];
	_lblFail.hidden = YES;
}

-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	if(originalContainerViewBottomConstraint == CGFLOAT_MAX)
		originalContainerViewBottomConstraint = _containerViewBottomConstraint.constant;

	[accountSetupVC setHelpButtonHidden:NO];
	accountSetupVC.btnBack.hidden = NO;

 	ZDCLocalUser* localUser = accountSetupVC.user;

	NSString* displayName = localUser.displayName;

	_lblDisplayName.text = displayName;

	NSArray* comps = [localUser.preferredIdentityID componentsSeparatedByString:@"|"];
	NSString* provider = comps.firstObject;

	OSImage* image = [providerManager providerIcon:Auth0ProviderIconType_64x64 forProvider:provider];
	if(image)
	{
		_imgProvider.image = image;
	}

	_txtPwdField.placeholder = @"access key passcode";
	_txtPwdField.text = @"";
	_txtPwdField.delegate = (id <UITextFieldDelegate >)self;

	_btnUnlock.enabled = NO;
	failedTries = 0;

	_imgQRCode.image = [OSImage QRImageWithString:cloneString
										 withSize:_imgQRCode.frame.size];


	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(keyboardWillShow:)
												 name:UIKeyboardWillShowNotification
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(keyboardWillHide:)
												 name:UIKeyboardWillHideNotification
											   object:nil];

}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

}

-(void) viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	_txtPwdField.text = @"";
	_btnUnlock.enabled = NO;
}


-(void)flashErrorText:(NSString*) errorText
{
	__weak typeof(self) weakSelf = self;

	_lblFail.alpha = 0.;
	_lblFail.hidden = NO;
	_lblFail.text = errorText;

	AudioServicesPlayAlertSoundWithCompletion(kSystemSoundID_Vibrate, nil);

//	_btnUnlock.hidden = YES;
	_btnUnlock.alpha = 0;

	[UIView animateWithDuration:0.3   animations:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		strongSelf->_lblFail.alpha = 1.0;

	} completion:^(BOOL finished) {

		[UIView animateWithDuration:0.35 delay:1.0 options:0 animations:^{
			
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;

			strongSelf->_lblFail.alpha = 0.;
			strongSelf->_btnUnlock.alpha = 1;

		}completion:^(BOOL finished) {
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;

			strongSelf->_lblFail.hidden = YES;
		}];
	}];
}

#pragma mark - actions

- (IBAction)btnUnlockClicked:(id)sender
{
	ZDCLogAutoTrace();
	//
	NSError* error = NULL;
	
	__weak typeof(self) weakSelf = self;
	
	NSData* salt = [accountSetupVC.user.syncedSalt dataUsingEncoding:NSUTF8StringEncoding];
	
	// try and unlock it with built in code
	NSData* accessKeyData = [ZDCAccessCode accessKeyDataFromString:cloneString
																	  withPasscode:_txtPwdField.text
																				 salt:salt
																				error:&error];
	if(!error && accessKeyData)
	{
		[accountSetupVC unlockUserWithAccessKey:accessKeyData
									 completionBlock:^(NSError *error)
		 {
			 __strong typeof(self) strongSelf = weakSelf;
			 if(!strongSelf) return;

			 if(error)
			 {
				 
				 [strongSelf->accountSetupVC showError:@"Cloning Failed"
								   message:error.localizedDescription
						   completionBlock:^{
								
								__strong typeof(self) strongSelf = weakSelf;
								if(!strongSelf) return;

							   [strongSelf->accountSetupVC popFromCurrentView];
							   
						   }];
				 
			 }
			 else
			 {
				 [strongSelf->accountSetupVC pushAccountReady ];
			 }
		 }];
		
	}
	else
	{
		if ([error.domain isEqualToString:S4FrameworkErrorDomain] && (error.code == kS4Err_BadIntegrity))
		{
			failedTries++;
			
			if (failedTries >= max_tries)
			{
				[accountSetupVC popFromCurrentView];
			}
			else if (failedTries > 1)
			{
				NSString *txt = [NSString stringWithFormat:@ "%lu failed password attempts ",(unsigned long) failedTries];
				[self flashErrorText:txt];
			}
			else
			{
				[self flashErrorText: @"Incorrect password"];
			}
		}
		else
		{
			
			[accountSetupVC showError:@"Cloning Failed"
							  message:error.localizedDescription
					  completionBlock:^{
						  
						  __strong typeof(self) strongSelf = weakSelf;
						  if (strongSelf) {
							  [strongSelf.accountSetupVC popFromCurrentView];
						  }
						  
					  }];
		}
		
	}
	
}


- (BOOL)textFieldShouldReturn:(UITextField *)aTextField
{
	[self btnUnlockClicked:_btnUnlock];
	return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
	BOOL result = YES;

	if(textField == _txtPwdField )
	{
		NSString * proposedString = [textField.text stringByReplacingCharactersInRange:range withString:string];


		BOOL canSend = proposedString.length > 0;;

		_btnUnlock.enabled = canSend;
	}


	return result;
}

#pragma mark - Keyboard/TextField Navigation


-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event{

	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];

	if ( [_txtPwdField pointInside:locationPoint withEvent:event]) return;

	[_txtPwdField resignFirstResponder];
}

#pragma mark - Keyboard show/Hide Notifications

static inline UIViewAnimationOptions AnimationOptionsFromCurve(UIViewAnimationCurve curve)
{
	UIViewAnimationOptions opt = (UIViewAnimationOptions)curve;
	return opt << 16;
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;

	// With multitasking on iPad, all visible apps are notified when the keyboard appears and disappears.
	// The value of [UIKeyboardIsLocalUserInfoKey] is YES for the app that caused the keyboard to appear
	// and NO for any other apps.

	BOOL isKeyboardForOurApp = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];
	if (!isKeyboardForOurApp)
	{
		return;
	}

	// Extract info from notification

	CGRect keyboardEndFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];

	NSTimeInterval animationDuration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationCurve animationCurve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue];

	// Perform animation

	CGFloat keyboardHeight = keyboardEndFrame.size.height;

	[UIView animateWithDuration:animationDuration
						  delay:0.0
						options:AnimationOptionsFromCurve(animationCurve)
					 animations:
	 ^{

		 __strong typeof(self) strongSelf = weakSelf;
		 if (strongSelf) {

		strongSelf->_containerViewBottomConstraint.constant =
			 strongSelf->originalContainerViewBottomConstraint +  keyboardHeight + 8;
		 [strongSelf.view layoutIfNeeded]; // animate constraint change
		 }

	 } completion:^(BOOL finished) {

	 }];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	ZDCLogAutoTrace();

	// With multitasking on iPad, all visible apps are notified when the keyboard appears and disappears.
	// The value of [UIKeyboardIsLocalUserInfoKey] is YES for the app that caused the keyboard to appear
	// and NO for any other apps.

	BOOL isKeyboardForOurApp = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];
	if (!isKeyboardForOurApp)
	{
		return;
	}


	// Extract info from notification

	NSTimeInterval animationDuration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationCurve animationCurve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue];

	// Perform animation

	[self _keyboardWillHideWithAnimationDuration:animationDuration animationCurve:animationCurve];
}

- (void)_keyboardWillHideWithAnimationDuration:(NSTimeInterval)animationDuration
								animationCurve:(UIViewAnimationCurve)animationCurve
{
	__weak typeof(self) weakSelf = self;


	[UIView animateWithDuration:animationDuration
						  delay:0.0
						options:AnimationOptionsFromCurve(animationCurve)
					 animations:
	 ^{
		 __strong typeof(self) strongSelf = weakSelf;
		 if (strongSelf) {
			 strongSelf->_containerViewBottomConstraint.constant
			 	= strongSelf->originalContainerViewBottomConstraint;

			 [strongSelf.view layoutIfNeeded]; // animate constraint change

		 }


	 } completion:^(BOOL finished) {

		 // Nothing to do
	 }];
}


@end
