
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "UnlockAccessCodeViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "UISecureTextField.h"

#import "ZDCAccessCode.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "OSImage+QRCode.h"
#import "NSError+S4.h"

// Libraries
#import <AudioToolbox/AudioToolbox.h>

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)



@implementation UnlockAccessCodeViewController_IOS
{
    IBOutlet __weak UIImageView *           _imgQRCode;
    IBOutlet __weak UISecureTextField*      _txtPwdField;
    IBOutlet __weak UIButton *              _bntUnlock;
    IBOutlet __weak UILabel *               _lblFail;

    IBOutlet __weak NSLayoutConstraint *    _bottomConstraint;
    CGFloat                                 originalBottomConstraint;
    
  
	UISwipeGestureRecognizer 				*swipeRight;
	YapDatabaseConnection *         databaseConnection;

}


@synthesize keyBackupVC = keyBackupVC;
@synthesize cloneString = cloneString;

- (void)viewDidLoad {
	[super viewDidLoad];
    
    _lblFail.layer.cornerRadius   = 16;
    _lblFail.layer.masksToBounds  = YES;
    _lblFail.backgroundColor      = [UIColor redColor];
    _lblFail.hidden = YES;

    _txtPwdField.delegate = (id <UITextFieldDelegate >)self;
    _txtPwdField.text = @"";
    _txtPwdField.placeholder = @"password";
	 
    if (@available(iOS 11.0, *)) {
        _txtPwdField.textContentType =  UITextContentTypePassword;
    } 

    _bntUnlock.enabled = NO;

    originalBottomConstraint = CGFLOAT_MAX;
}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
    if(originalBottomConstraint == CGFLOAT_MAX)
        originalBottomConstraint = _bottomConstraint.constant;

	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;

	self.navigationItem.title = @"Unlock Access Key";

	UIImage* image = [[UIImage imageNamed:@"backarrow"
								 inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																 style:UIBarButtonItemStylePlain
																target:self
																action:@selector(handleNavigationBack:)];

	self.navigationItem.leftBarButtonItem = backItem;


	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
 	[self.view addGestureRecognizer:swipeRight];

    
    _imgQRCode.image = [OSImage QRImageWithString:cloneString
                                         withSize:_imgQRCode.frame.size];
    
//    _bntUnlock.layer.borderColor   = self.view.tintColor.CGColor;
//    _bntUnlock.layer.cornerRadius  = 8.0f;
//    _bntUnlock.layer.masksToBounds = YES;
//    _bntUnlock.layer.borderWidth   = 1.0f;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

	[self refreshView];

}
-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
    _txtPwdField.text = @"";
    _lblFail.hidden = YES;

}


-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[keyBackupVC pushVerifyText];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}



- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;

}


-(void) refreshView
{

}


-(void)flashErrorText:(NSString*) errorText
{
    _lblFail.alpha = 0.;
    _lblFail.hidden = NO;
    _lblFail.text = errorText;
    
    __weak typeof(self) weakSelf = self;
    
    
    AudioServicesPlayAlertSoundWithCompletion(kSystemSoundID_Vibrate, nil);
    
    //    _btnUnlock.hidden = YES;
    _bntUnlock.alpha = 0;
    
    [UIView animateWithDuration:0.3   animations:^{
        __strong typeof(self) ss = weakSelf;
        if (!ss) return;

        ss->_lblFail.alpha = 1.0;
        
    } completion:^(BOOL finished) {
        
        [UIView animateWithDuration:0.35 delay:1.0 options:0 animations:^{
            __strong typeof(self) ss = weakSelf;
            if (!ss) return;
            
            ss->_lblFail.alpha = 0.;
            ss->_bntUnlock.alpha = 1;
            
        }completion:^(BOOL finished) {
            __strong typeof(self) ss = weakSelf;
            if (!ss) return;

            ss->_lblFail.hidden = YES;
            
            BOOL canUnlock = ss->_txtPwdField.text.length > 0;
            
            ss->_bntUnlock.enabled = canUnlock;
        }];
    }];
}

#pragma mark  - UITextField delegate

- (void)textFieldDidEndEditing:(UITextField *)textField reason:(UITextFieldDidEndEditingReason)reason
API_AVAILABLE(ios(10.0)){
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)aTextField
{
    [aTextField resignFirstResponder];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{
    BOOL result = YES;
    BOOL canUnlock = NO;
    
    NSString * proposedString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    if(textField == _txtPwdField )
    {
      canUnlock = proposedString.length > 0;
    }
    
    _bntUnlock.enabled = canUnlock;
    
    return result;
}


#pragma mark  - actions

- (IBAction)btnUnlockedClicked:(id)sender
{
	NSError* error = NULL;
	
	__weak typeof(self) weakSelf = self;
	
	NSData* salt = [keyBackupVC.user.syncedSalt dataUsingEncoding:NSUTF8StringEncoding];
	
	// try and unlock it with built in code
	NSData* accessKeyData = [ZDCAccessCode accessKeyDataFromString:cloneString
																	  withPasscode:_txtPwdField.text
																				 salt:salt
																				error:&error];
	if(!error
		&& accessKeyData
		&& [accessKeyData isEqual:keyBackupVC.accessKeyData])
	{
		// good key
		[keyBackupVC  setBackupVerifiedForUserID:keyBackupVC.user.uuid
										 completionBlock:^
		 {
			 __strong typeof(self) ss = weakSelf;
			 if (!ss) return;
			 [ss->keyBackupVC pushBackupSuccess];
		 }];
	}
	else
	{
		// BAD KEY
		NSString* errorString =  error.localizedDescription;
		
		if([error.domain isEqualToString:S4FrameworkErrorDomain]
			&& error.code == kS4Err_BadIntegrity)
		{
			// needs unlock
			[self flashErrorText:NSLocalizedString(@"Incorrect Passcode", @"Incorrect Passcode")];
			
		}
		else
		{
			[self flashErrorText:errorString];
		}
	}
}


#pragma mark - Keyboard show/Hide Notifications


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
     if(!CGRectContainsPoint(_txtPwdField.frame, locationPoint))
    {
        [_txtPwdField  endEditing:YES];
        
    }
 
}

static inline UIViewAnimationOptions AnimationOptionsFromCurve(UIViewAnimationCurve curve)
{
    UIViewAnimationOptions opt = (UIViewAnimationOptions)curve;
    return opt << 16;
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	__weak typeof(self) weakSelf = self;

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
		  if(!strongSelf) return;

         strongSelf->_bottomConstraint.constant =  (keyboardHeight + 8);
         [strongSelf.view layoutIfNeeded]; // animate constraint change
         
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
    
    _bottomConstraint.constant = originalBottomConstraint;
    [self.view layoutIfNeeded]; // animate constraint change
 }

@end
