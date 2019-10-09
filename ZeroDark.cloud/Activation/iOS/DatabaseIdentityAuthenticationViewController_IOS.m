/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "DatabaseIdentityAuthenticationViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"

#import "ZDCLogging.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "UISecureTextField.h"
#import "UIButton+Activation.h"

#import "SCLAlertView.h"
#import "SCLAlertViewStyleKit.h"

// Libraries
#import <AudioToolbox/AudioToolbox.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation DatabaseIdentityAuthenticationViewController_IOS
{
    IBOutlet __weak UIView              *_viewContainer;
//    IBOutlet __weak UIImageView         *_imgAvatar;
    IBOutlet __weak UIButton            * _btnSignIn;
    IBOutlet __weak UITextField    		* _txtUserNameField;
    IBOutlet __weak UISecureTextField         * _txtPwdField;
    IBOutlet __weak UIActivityIndicatorView   * _actBusy;
    IBOutlet __weak UILabel             *_lblFail;

    SCLAlertView *reauthAlert;

    BOOL                isInAuthDBView;
    
}
@synthesize accountSetupVC = accountSetupVC;

#pragma mark  - view

- (void)viewDidLoad {
	[super viewDidLoad];
	
	reauthAlert = nil;
	
	isInAuthDBView = [self.restorationIdentifier isEqualToString:@"DatabaseIdentityAuthenticationViewController_LOGIN_IOS"];
	
	if(isInAuthDBView)
	{
		void (^PrepContainer)(UIView *) = ^(UIView *container){
			container.layer.cornerRadius   = 4;
			container.layer.masksToBounds  = YES;
			container.layer.borderColor    = [UIColor blackColor].CGColor;
			container.layer.borderWidth    = 1.0f;
		};
		
		PrepContainer(_txtUserNameField);
		PrepContainer(_txtPwdField);
		
	}
	else
	{
		void (^PrepContainer)(UIView *) = ^(UIView *container){
			container.layer.cornerRadius   = 16;
			container.layer.masksToBounds  = YES;
			container.layer.borderColor    = [UIColor whiteColor].CGColor;
			container.layer.borderWidth    = 1.0f;
			container.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];
		};
		PrepContainer(_viewContainer);
		
		[_btnSignIn setup];
	}
	
	_lblFail.layer.cornerRadius   = 16;
	_lblFail.layer.masksToBounds  = YES;
	_lblFail.backgroundColor      = [UIColor redColor];
	_lblFail.hidden = YES;
	
	_txtUserNameField.delegate = (id <UITextFieldDelegate >)self;
	_txtUserNameField.text = @"";
	_txtUserNameField.placeholder = @"username";
	if (@available(iOS 11.0, *)) {
		_txtUserNameField.textContentType =  UITextContentTypeUsername;
	}
	_txtPwdField.delegate = (id <UITextFieldDelegate >)self;
	_txtPwdField.text = @"";
	_txtPwdField.placeholder = @"password";
	if (@available(iOS 11.0, *)) {
		_txtPwdField.textContentType =  UITextContentTypePassword;
	}
	
	//
	//    _imgAvatar.layer.cornerRadius = 64 / 2;
	//    _imgAvatar.layer.borderWidth = 2.0f;
	//    _imgAvatar.layer.borderColor = [UIColor whiteColor].CGColor;
	//    _imgAvatar.clipsToBounds = YES;
	//    _imgAvatar.image = [OSImage imageNamed:@"default_user"];
	
	_btnSignIn.enabled = NO;
	_lblFail.hidden = YES;
	[self showWait:NO];
}

-(void) viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
    _txtUserNameField.text = @"";
    _txtUserNameField.enabled = YES;
    _txtPwdField.text = @"";
    _lblFail.hidden = YES;

    _btnSignIn.enabled = NO;
    
    if(reauthAlert)
    {
        [reauthAlert hideView];
        reauthAlert = nil;
    }

    [self showWait:NO];

}

-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	if (self.accountSetupVC.identityMode == IdenititySelectionMode_NewAccount)
	{
		_btnSignIn.layer.borderColor   = [UIColor whiteColor].CGColor;
		[_btnSignIn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[_btnSignIn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
	}
	else
	{
		_btnSignIn.layer.borderColor   = [UIColor blackColor].CGColor;
		[_btnSignIn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
		[_btnSignIn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
	}

	_btnSignIn.layer.cornerRadius  = 8.0f;
	_btnSignIn.layer.masksToBounds = YES;
	_btnSignIn.layer.borderWidth   = 1.0f;

	[accountSetupVC setHelpButtonHidden:NO];
   accountSetupVC.btnBack.hidden = NO;

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark  - UITextField delegate

- (void)textFieldDidEndEditing:(UITextField *)textField reason:(UITextFieldDidEndEditingReason)reason
API_AVAILABLE(ios(10.0)){
    
    if(textField == _txtUserNameField )
    {
        NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *trimmedString = [_txtUserNameField.text stringByTrimmingCharactersInSet:whitespace];
        _txtUserNameField.text = trimmedString;
    }
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
    BOOL canSend = NO;
    
    NSString * proposedString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    if(textField == _txtPwdField )
    {
         canSend = [Auth0Utilities isValid4thAUsername:_txtUserNameField.text] && proposedString.length > 0;
    }
    else if(textField == _txtUserNameField )
    {
        NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *trimmedString = [proposedString stringByTrimmingCharactersInSet:whitespace];
        
        canSend = [Auth0Utilities isValid4thAUsername:trimmedString] && _txtPwdField.text.length > 0;
        
     }
    
    _btnSignIn.enabled = canSend;

    return result;
}


#pragma mark  - actions

- (IBAction)btnSignInClicked:(id)sender
{
	NSDictionary* identDict =  accountSetupVC.selectedProvider;
	if (identDict)
	{

		Auth0ProviderType strategyType = [identDict[kAuth0ProviderInfo_Key_Type] integerValue];

		NSParameterAssert(strategyType == Auth0ProviderType_Database);    // this cant happen


		[self tryDatabaseLoginWithEmail: [Auth0Utilities create4thAEmailForUsername:_txtUserNameField.text]
							   password: _txtPwdField.text];
	}
}


- (void)tryDatabaseLoginWithEmail:(NSString *)email
                         password:(NSString *)password
{
	ZDCLogAutoTrace();
	
	_lblFail.hidden = YES;
	_btnSignIn.enabled = NO;

	[self showWait:YES];
	
	__weak typeof(self) weakSelf = self;
	[accountSetupVC databaseAccountLoginWithUsername: email
	                                        password: password
	                                 completionBlock:^(AccountState accountState, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		[strongSelf showWait:NO];
		[strongSelf.accountSetupVC cancelWait];

		if (error)
		{
			 NSString* errorString = error.localizedDescription;

			 if([strongSelf->accountSetupVC isAlreadyLinkedError:error])
			 {
				 errorString = @"This identity is already linked to a different account. To link it to this account, you must first unlink it from the other account.";

				 [strongSelf->accountSetupVC showError:@"Account Linked"
								   message:errorString
							viewController:self
						   completionBlock:^{

								   [strongSelf->accountSetupVC popFromCurrentView   ];
						   }];
				 return;
			 }
			 [strongSelf flashErrorText:errorString];
		 }
		 else
		 {

			 switch (accountState) {
				 case AccountState_Reauthorized:
                     [strongSelf showReauthSuccess];
//					 [strongSelf.accountSetupVC popToNonAccountSetupView:self.navigationController];
					 break;

				 case AccountState_Ready:
					 [strongSelf.accountSetupVC pushAccountReady ];
					 break;

				 case AccountState_NeedsCloneClode:
					 [strongSelf.accountSetupVC pushScanClodeCode  ];
					 break;

				 case AccountState_NeedsRegionSelection:
					 [strongSelf.accountSetupVC pushRegionSelection  ];
					 break;

				 default:

					 [strongSelf->accountSetupVC showError:@"internal error"
									   message:[NSString stringWithFormat:@"%s:%d \n", __FILE__, __LINE__]
								viewController:self
							   completionBlock:^{

									
									__strong typeof(self) strongSelf = weakSelf;
									if(!strongSelf) return;

								   [strongSelf->accountSetupVC popFromCurrentView   ];
							   }];


					 break;
			 }
		 }
	 }];
 }

-(void)showReauthSuccess
{
    reauthAlert  = [[SCLAlertView alloc] init];
    
    __weak typeof(self) weakSelf = self;
    
    [reauthAlert addButton:@"OK" actionBlock:^(void) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
 
        [strongSelf.accountSetupVC popToNonAccountSetupView:strongSelf.navigationController];
        
        strongSelf->reauthAlert = nil;
    }];
    
    [reauthAlert showSuccess:self
                       title:@"Account reauthorized "
                    subTitle:@"Your account has been reauthorized."
            closeButtonTitle:nil
                    duration:0.0f];
    
}

-(void)flashErrorText:(NSString*) errorText
{
	__weak typeof(self) weakSelf = self;

	_lblFail.alpha = 0.;
	_lblFail.hidden = NO;
	_lblFail.text = errorText;

	AudioServicesPlayAlertSoundWithCompletion(kSystemSoundID_Vibrate, nil);

	//	_btnUnlock.hidden = YES;
	_btnSignIn.alpha = 0;

	[UIView animateWithDuration:0.3   animations:^{
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		strongSelf->_lblFail.alpha = 1.0;

	} completion:^(BOOL finished) {

		[UIView animateWithDuration:0.35 delay:1.0 options:0 animations:^{
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;

			strongSelf->_lblFail.alpha = 0.;
			strongSelf->_btnSignIn.alpha = 1;

		}completion:^(BOOL finished) {
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;

			strongSelf->_lblFail.hidden = YES;

			BOOL canSend = [Auth0Utilities isValid4thAUsername:strongSelf->_txtUserNameField.text]
				&& strongSelf->_txtPwdField.text.length > 0;

			strongSelf->_btnSignIn.enabled = canSend;
		}];
	}];
}

#pragma mark  - utilities

-(void)showWait:(BOOL) shouldShow
{
    if(shouldShow)
    {
        _actBusy.hidden = NO;
        [_actBusy startAnimating];
    }
    else
    {
        _actBusy.hidden = YES;
        [_actBusy stopAnimating];
        
    }
}

@end
