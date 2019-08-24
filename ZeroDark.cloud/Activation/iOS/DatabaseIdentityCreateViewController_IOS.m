/**
* ZeroDark.cloud
* 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "DatabaseIdentityCreateViewController_IOS.h"

#import "Auth0APIManager.h"
#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "PasswordStrengthUIView.h"
#import "SCLAlertView.h"
#import "UISecureTextField.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZDCPasswordStrengthCalculator.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+Auth0API.h"
#import "UIButton+Activation.h"
#import "UIColor+Crayola.h"

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


@implementation DatabaseIdentityCreateViewController_IOS
{
	IBOutlet __weak UIView              *_viewContainer;

	IBOutlet __weak UIButton            * _btnCreate;
	IBOutlet __weak UIActivityIndicatorView   * _actBusy;


	IBOutlet __weak UITextField   		*_txtUserNameField;
	IBOutlet __weak UIImageView             *_imgUserNameOK;

	IBOutlet __weak UISecureTextField       *_txtPwdField;
	IBOutlet __weak PasswordStrengthUIView  *_strengthField;
	IBOutlet __weak UILabel                 *_lblStrength;
	IBOutlet __weak UIImageView             *_imgNewPwdOK;

	IBOutlet __weak UISecureTextField       *_txtVrfPwdField;
	IBOutlet __weak UIImageView             *_imgVrfPwdOK;

 	ZDCPasswordStrength					*pwdStrength;
	OSImage                         *checkImage;
	OSImage                         *failImage;
	BOOL                            newPassCodeOK;
	NSUInteger                      minScore;

	BOOL                isInAddDBView;
}

@synthesize accountSetupVC = accountSetupVC;

#pragma mark  - view

- (void)viewDidLoad {
	[super viewDidLoad];
	
	isInAddDBView = [self.restorationIdentifier isEqualToString:@"DatabaseIdentityCreateViewController_ADDIOS"];

	if(isInAddDBView)
	{
		void (^PrepContainer)(UIView *) = ^(UIView *container){
			container.layer.cornerRadius   = 4;
			container.layer.masksToBounds  = YES;
			container.layer.borderColor    = [UIColor blackColor].CGColor;
			container.layer.borderWidth    = 1.0f;
		};

		PrepContainer(_txtUserNameField);
		PrepContainer(_txtPwdField);
		PrepContainer(_txtVrfPwdField);
		[_btnCreate setup];
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

	}

	checkImage = [UIImage imageNamed:@"roundedGreenCheck"
							inBundle:[ZeroDarkCloud frameworkBundle]
	   compatibleWithTraitCollection:nil];

	failImage = [UIImage imageNamed:@"roundedRedX"
						   inBundle:[ZeroDarkCloud frameworkBundle]
	  compatibleWithTraitCollection:nil];

	_txtUserNameField.delegate = (id <UITextFieldDelegate >)self;
	_txtUserNameField.text = @"";
	_txtUserNameField.placeholder = @"username";
	if (@available(iOS 11.0, *)) {
		_txtUserNameField.textContentType =  UITextContentTypeUsername;
	} 

	_txtPwdField.delegate = (id <UITextFieldDelegate >)self;
	_txtPwdField.text = @"";
	_txtPwdField.placeholder = @"password";
	if (@available(iOS 12.0, *)) {
		_txtPwdField.textContentType =  UITextContentTypeNewPassword;
	}

	_txtVrfPwdField.delegate = (id <UITextFieldDelegate >)self;
	_txtVrfPwdField.text = @"";
	_txtVrfPwdField.placeholder = @"verify";
	_strengthField.showZeroScore = YES;

	[self resetFields];
	[self showWait:NO];
}

-(void)resetFields
{
	[self showWait:NO];
	_txtUserNameField.text = @"";
	_txtPwdField.text = @"";
	_txtVrfPwdField.text = @"";

	_imgUserNameOK.hidden = YES;
	_imgNewPwdOK.hidden = YES;
	_imgVrfPwdOK.hidden = YES;

	_strengthField.hidden = YES;
	_lblStrength.hidden = YES;
	pwdStrength = NULL;
	_lblStrength.text = @"";
	_btnCreate.enabled = NO;
}

-(void) viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	[self resetFields];

}

-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	if (self.accountSetupVC.identityMode == IdenititySelectionMode_NewAccount)
	{
		_btnCreate.layer.borderColor   = [UIColor whiteColor].CGColor;

		[_btnCreate setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[_btnCreate setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
	}
	else
	{
		_btnCreate.layer.borderColor   = [UIColor blackColor].CGColor;

		[_btnCreate setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
		[_btnCreate setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
	}

	[_txtUserNameField becomeFirstResponder];
	[accountSetupVC setHelpButtonHidden:NO];
	accountSetupVC.btnBack.hidden = NO;
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}



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



#pragma mark  - UITextFieldDelegate delegate


- (BOOL)textFieldShouldReturn:(UITextField *)aTextField
{
	[aTextField resignFirstResponder];
	return YES;
}



- (void)textFieldDidEndEditing:(UITextField *)textField reason:(UITextFieldDidEndEditingReason)reason
API_AVAILABLE(ios(10.0)){
	NSString * proposedString = nil;

	if(textField == _txtUserNameField )
	{
		NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
		NSString *trimmedString = [_txtUserNameField.text stringByTrimmingCharactersInSet:whitespace];
		_txtUserNameField.text = trimmedString;
		proposedString = trimmedString;
	}
	else if(textField == _txtPwdField)
		proposedString = _txtPwdField.text;
	else if(textField == _txtVrfPwdField)
		proposedString = _txtVrfPwdField.text;

	[self updateButtonsWithTextField:textField proposedString:proposedString];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string
{

	NSString * proposedString = [textField.text stringByReplacingCharactersInRange:range withString:string];
	[self updateButtonsWithTextField:textField proposedString:proposedString];

	return YES;
}

-(void)updateButtonsWithTextField:(UITextField *)textField proposedString:(NSString *)proposedString
{

	NSString* userNameText = (textField == _txtUserNameField)? proposedString:_txtUserNameField.text;
	NSString* newPwdText = (textField == _txtPwdField)? proposedString:_txtPwdField.text;
	NSString* vrfPwdText = (textField == _txtVrfPwdField)? proposedString:_txtVrfPwdField.text;

	BOOL userNameOK      = [Auth0Utilities isValid4thAUsername:userNameText] && userNameText.length > 0;
	BOOL passcodeMatches = newPwdText.length > 0 && [newPwdText isEqualToString:vrfPwdText];
	BOOL verifyOK        = vrfPwdText.length> 0;

	if(textField == _txtPwdField )
	{
		_strengthField.hidden = proposedString.length == 0;
		_lblStrength.hidden = proposedString.length == 0;

		pwdStrength = [ZDCPasswordStrengthCalculator strengthForPassword:proposedString];
		_strengthField.score = pwdStrength.score;
		_lblStrength.text = pwdStrength.scoreLabel;

		if(minScore > 0)
		{
			newPassCodeOK = pwdStrength.score >= minScore;
		}
		else
		{
			newPassCodeOK = proposedString.length > 0;
		}
	}

	_imgUserNameOK.image = checkImage;
	_imgUserNameOK.hidden = !(userNameOK);

	_imgVrfPwdOK.image = passcodeMatches?checkImage:failImage;
	_imgVrfPwdOK.hidden = !(verifyOK && newPassCodeOK);

	_imgNewPwdOK.image = checkImage;
	_imgNewPwdOK.hidden = !newPassCodeOK;;

	_btnCreate.enabled = (userNameOK && newPassCodeOK && passcodeMatches);
}


-(IBAction) btnCreateClicked:(id) sender
{
	_btnCreate.enabled = NO;
	[self.view endEditing:YES];

	[self showWait:YES];

	NSString* username = _txtUserNameField.text;
	NSString* password = _txtPwdField.text;

	__weak typeof(self) weakSelf = self;


	[accountSetupVC databaseAccountCreateWithUserName:username
									   password:password
								completionBlock:^(AccountState accountState, NSError * _Nullable error)
	 {

		 __strong typeof(self) strongSelf = weakSelf;

		 [self showWait:NO];

		 if (error)
		 {
			 [strongSelf accountCreationFailedWithError:error
										   accountState:accountState
											   username:username
											   password:password];
		 }
		 else
		 {
			 switch (accountState) {
 
				 case AccountState_LinkingID:
					 [strongSelf.accountSetupVC popToViewControllerForViewID:AccountSetupViewID_SocialidMgmt
											  withNavigationController:self.navigationController];
					 break;
                     
				 case AccountState_NeedsRegionSelection:
					 [strongSelf.accountSetupVC pushRegionSelection  ];
					 break;

				 default:
					 [strongSelf.accountSetupVC showError:@"Could not Authenticate"
												  message:@"internal error"
										  completionBlock:^{

											  __strong typeof(self) strongSelf = weakSelf;
											  if(!strongSelf) return;

											  [strongSelf->accountSetupVC popFromCurrentView];
										  }];
					 break;
			 }
		 }
	 }];

}

- (void)accountCreationFailedWithError:(NSError *)error
						  accountState:(AccountState)accountState
							  username:(NSString *)username
							  password:(NSString *)password
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Need to be on main thread for UI stuff");

	__weak typeof(self) weakSelf = self;
	[self showWait:NO];


	NSString* auth0Code =  error.auth0API_error;
	if([@[kAuth0Error_UserExists, kAuth0Error_UserNameExists] containsObject:auth0Code])
	{

		SCLAlertView*  alert = [[SCLAlertView alloc] init];
		alert.customViewColor = [UIColor crayolaBlueJeansColor];

		[alert addButton:@"Other Name" actionBlock:^(void) {

			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;

			[strongSelf resetFields];
			[strongSelf->_txtUserNameField becomeFirstResponder];
		}];

		if(!isInAddDBView)
		{
			[alert addButton:@"Login" actionBlock:^(void) {

				__strong typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;

				[strongSelf tryDatabaseLoginWithUserName:username
												password:password];
			}];
		}

		[alert addButton:@"Cancel" actionBlock:^(void) {

			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;

			if(accountState == AccountState_LinkingID)
			{
				[strongSelf.accountSetupVC popToViewControllerForViewID:AccountSetupViewID_SocialidMgmt
										 withNavigationController:self.navigationController];

			}
			else
			{
				[strongSelf.accountSetupVC popFromCurrentView];
 			}
		}];

		[alert showNotice:self
					title:@"The user already exists."
				 subTitle: (isInAddDBView
							?@"Please try another username"
							:@"Do you wish to try another username, or login to this one?")
		 closeButtonTitle:nil
				 duration:0.0f];


	}
	else if([accountSetupVC isAlreadyLinkedError:error])
	{
		
		NSString* errorString = @"This identity is already linked to a different account. To link it to this account, you must first unlink it from the other account.";

		[self.accountSetupVC showError: @"Can not complete Activation"
									 message:errorString
							  viewController:self
							 completionBlock:^{
								 __strong typeof(self) strongSelf = weakSelf;

								 [strongSelf.accountSetupVC popFromCurrentView];

							 }];
	}
	else
	{

		[accountSetupVC showError: @"Can not create account"
						  message:error.localizedDescription
				   viewController:self
				  completionBlock:^{

					  __strong typeof(self) strongSelf = weakSelf;

					  [strongSelf.accountSetupVC popFromCurrentView];
				  }];
	}

}


- (void)tryDatabaseLoginWithUserName:(NSString *)userName
							password:(NSString *)password
{
	ZDCLogAutoTrace();

	_btnCreate.enabled = NO;
	[self.view endEditing:YES];

	[self showWait:YES];

	__weak typeof(self) weakSelf = self;
	[accountSetupVC databaseAccountLoginWithUserName: [Auth0Utilities create4thAEmailForUsername: userName]
									password: password
							 completionBlock:^(AccountState accountState, NSError *error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;

		 [strongSelf showWait:NO];

		 if(error)
		 {

			 [strongSelf showWait:NO];

			 NSString* errorString = error.localizedDescription;

			 if([strongSelf->accountSetupVC isAlreadyLinkedError:error])
			 {
				 errorString = @"This identity is already linked to a different account. To link it to this account, you must first unlink it from the other account.";
			 }

			 [strongSelf.accountSetupVC showError: @"Can not complete Activation"
										  message:errorString
								   viewController:self
								  completionBlock:^{
								  }];

		 }
		 else
		 {

			 switch (accountState) {

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
					 [strongSelf.accountSetupVC showError:@"Could not Authenticate"
												  message:@"internal error"
										  completionBlock:^{
											  __strong typeof(self) strongSelf = weakSelf;
											  if(!strongSelf) return;

											  [strongSelf->accountSetupVC popFromCurrentView];
										  }];
					 break;
			 }
		 }
	 }];
}

@end
