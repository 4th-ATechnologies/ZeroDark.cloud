
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "BackupAsImageViewController_IOS.h"

#import "PasswordStrengthUIView.h"
#import "UIImageViewPasteable.h"
#import "UISecureTextField.h"
#import "ZDCAccessCode.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZDCPasswordStrengthCalculator.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "OSImage+QRCode.h"
#import "NSString+ZeroDark.h"

// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

 
@implementation BackupAsImageViewController_IOS
{
	IBOutlet __weak UIImageViewPasteable   *_imgQRCode;
	IBOutlet __weak UILabel*           _lblCloneCodeInstructions;

	NSString*   cloneCodeInstructions1;
	NSString*   cloneCodeInstructions2;

	IBOutlet __weak UILabel*           _lblEnterPasscode;

	IBOutlet __weak UISecureTextField       *_txtPwdField;
	IBOutlet __weak PasswordStrengthUIView  *_strengthField;
	IBOutlet __weak UILabel                 *_lblStrength;
	IBOutlet __weak NSLayoutConstraint *	_bottomConstraint;
	CGFloat                             	originalBottomConstraint;
 
	IBOutlet __weak UIBarButtonItem  	*_bbnNext;
	IBOutlet __weak UIBarButtonItem  	*_bbnAction;

	ZDCPasswordStrength					*pwdStrength;

	UISwipeGestureRecognizer 	    *swipeLeft;
	UISwipeGestureRecognizer        *swipeRight;

	YapDatabaseConnection *         databaseConnection;
	NSTimer *                       refreshTimer;

	UIImage*					    defaultQRcodeImage;
	NSString*              		    qrCodeString;
	
	// the UIActivityViewController  <UIActivityItemSource> protocol isnt very modern.
	// we need to keep some data lying around to tell the UIActivityViewController what to share.
	NSArray* itemsToSend;
}


@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

	_strengthField.hidden = YES;
	_strengthField.showZeroScore = YES;

	_lblStrength.hidden = YES;
	pwdStrength = NULL;
	_lblStrength.text = @"";

	_txtPwdField.delegate = (id <UITextFieldDelegate >)self;
	_txtPwdField.text = @"";

	[_txtPwdField addTarget:self
					 action:@selector(textFieldDidChange:)
		   forControlEvents:UIControlEventEditingChanged];

    _imgQRCode.delegate =  (id<UIImageViewPasteableDelegate>)self;
    
	originalBottomConstraint = CGFLOAT_MAX;
}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;

	if(originalBottomConstraint == CGFLOAT_MAX)
		originalBottomConstraint = _bottomConstraint.constant;

    self.navigationItem.title = NSLocalizedString(@"Backup as Image", @"Backup as Image");

    cloneCodeInstructions1 = NSLocalizedString(@"You can use this key to clone your Storm4 account to another device.  In addition you should make a backup of  this code.If this device is lost, it is impossible to access your data without a this access key.\n", @"cloneCodeInstructions1");
    
    [self refreshInstuctions];
    
    _lblCloneCodeInstructions.text  = [cloneCodeInstructions1 stringByAppendingString:cloneCodeInstructions2];
    [_lblCloneCodeInstructions sizeToFit];

	UIImage* image = [[UIImage imageNamed:@"backarrow"
								 inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																 style:UIBarButtonItemStylePlain
																target:self
																action:@selector(handleNavigationBack:)];

	self.navigationItem.leftBarButtonItem = backItem;


	swipeLeft = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeLeft:)];
	swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft  ;
	[self.view addGestureRecognizer:swipeLeft];

	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(keyboardWillShow:)
												 name:UIKeyboardWillShowNotification
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(keyboardWillHide:)
												 name:UIKeyboardWillHideNotification
											   object:nil];

	_lblEnterPasscode.hidden = YES;

    
	defaultQRcodeImage  = [UIImage imageNamed:@"qrcode-default"
						   inBundle:[ZeroDarkCloud frameworkBundle]
	  compatibleWithTraitCollection:nil];

	[self refreshView];
}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
	[self.view removeGestureRecognizer:swipeLeft]; swipeLeft = nil;

 	_txtPwdField.text = @"";
	_strengthField.hidden = YES;
	_lblStrength.hidden = YES;

	itemsToSend = nil;
	
	if(refreshTimer) {
		[refreshTimer invalidate];
	}

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}

-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[self handleNavigationBack:NULL];
}

-(void)swipeLeft:(UISwipeGestureRecognizer *)gesture
{
	[keyBackupVC pushVerifyImage];
}



- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

-(IBAction)nextButtonTapped:(id)sender
{
	[keyBackupVC pushVerifyImage];

}

- (IBAction)actionButtonTapped:(id)sender
{
    [self saveQRCode];
}


- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;

}


-(void) refreshInstuctions
{
    BOOL requireCloneCode =  NO; //S4Preferences_si.requireCloningPasscode;
    
    if(requireCloneCode)
    {
        cloneCodeInstructions2 = @" You must enter a passphrase before saving.";
        _txtPwdField.placeholder = @"enter passphrase";
    }
    else
    {
        cloneCodeInstructions2 = @" You may enter an optional passphrase.";
        _txtPwdField.placeholder = @"optional passphrase";
        
    }
    
}

-(void) refreshView
{
	__weak typeof(self) weakSelf = self;
	NSError* error = NULL;
	
	BOOL requireCloneCode = NO; /// S4Preferences_si.requireCloningPasscode;
	
	qrCodeString = nil;
	
	P2K_Algorithm p2kAlgorithm = kP2K_Algorithm_Argon2i;
	
	if(_txtPwdField.text.length)
	{
		qrCodeString = [keyBackupVC accessKeyStringWithPasscode:_txtPwdField.text
																 p2kAlgorithm:p2kAlgorithm
																		  error:&error];
	}
	else if(!requireCloneCode)
	{
		qrCodeString = [keyBackupVC accessKeyStringWithPasscode:keyBackupVC.user.syncedSalt
																 p2kAlgorithm:p2kAlgorithm
																		  error:&error];
	}
	
	if(qrCodeString)
	{
		[OSImage QRImageWithString:qrCodeString
							 scaledSize:_imgQRCode.frame.size
					  completionQueue:nil
					  completionBlock:^(OSImage * _Nullable image) {
						  
						  __strong typeof(self) strongSelf = weakSelf;
						  if(strongSelf)
						  {
							  strongSelf->_imgQRCode.image = image;
							  strongSelf->_imgQRCode.canCopy = YES;
						  }
					  }];
		
	}
	else
	{
		_imgQRCode.canCopy = NO;
		_imgQRCode.image = defaultQRcodeImage;
	}
}


#pragma mark - Keyboard/TextField Navigation

- (BOOL)passwordIsValid:(NSString*)password
{
	return password.length > 0;
}


// Resign keyboard if _txtPwdField is firstResponder && tests Pass
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	// In all other cases, dismiss keyboard
	[textField resignFirstResponder];
	//
	//    if(textField == _txtPwdField )
	//    {
	//        if(refreshTimer) {
	//            [refreshTimer invalidate];
	//        }
	//
	//		[self updatePasswordStrengthWithString:@""];
	//
	//        [self refreshQRcodeString];
	//
	//    }

	return YES;
}

-(void) updatePasswordStrengthWithString:(NSString *)string
{
	_strengthField.hidden = NO;
	_strengthField.hidden = string.length == 0;
	_lblStrength.hidden = string.length == 0;

	pwdStrength = [ZDCPasswordStrengthCalculator strengthForPassword:string];
	_strengthField.score = pwdStrength.score;
	_lblStrength.text = pwdStrength.scoreLabel;
}

-(void)textFieldDidChange:(UITextField *)textField
{

	if(textField == _txtPwdField )
	{
		if(refreshTimer) {
			[refreshTimer invalidate];
		}

		[self updatePasswordStrengthWithString:_txtPwdField.text];

		// allow user to some type ahead
		refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
														target:self
													  selector:@selector(refreshView)
													  userInfo:nil
													   repeats:NO];
	}
}


#pragma mark - Keyboard show/Hide Notifications

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
	//	CGPoint containerPoint = [_vwCloneContainer convertPoint:locationPoint fromView:self.view];

	if(!CGRectContainsPoint(_txtPwdField.frame, locationPoint))
	{
		[_txtPwdField resignFirstResponder];
	}
}


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


 	_lblCloneCodeInstructions.text  = cloneCodeInstructions2 ;
 	[_lblCloneCodeInstructions sizeToFit];

	[UIView animateWithDuration:animationDuration
						  delay:0.2
						options:AnimationOptionsFromCurve(animationCurve)
					 animations:
	 ^{

		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {

			 strongSelf->_bottomConstraint.constant =  keyboardHeight + 2;
			 [self.view layoutIfNeeded]; // animate constraint change
		 }

	 } completion:^(BOOL finished) {

		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 // refresh the cloneview to get a better resultion image
//			 [strongSelf refreshView];
		 }
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


    _lblCloneCodeInstructions.text  = [cloneCodeInstructions1 stringByAppendingString:cloneCodeInstructions2];
    [_lblCloneCodeInstructions sizeToFit];


	[UIView animateWithDuration:animationDuration
						  delay:0.2
	 //	 		 usingSpringWithDamping:1
	 //	 		  initialSpringVelocity:0
						options:AnimationOptionsFromCurve(animationCurve)
					 animations:
	 ^{
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_bottomConstraint.constant = strongSelf->originalBottomConstraint;

			 [strongSelf.view layoutIfNeeded]; // animate constraint change
		 }

	 } completion:^(BOOL finished) {

		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 // refresh the cloneview to get a better resultion image
// 				 [strongSelf refreshView];
 		 }
	 }];
}

//MARK: activity button

-(void)sendBackupDocumentWithActivityView:(NSURL*)url
											  image:(UIImage*)image
								 completionBlock:(void (^)(BOOL didSend,  NSError * error))completionBlock;
{

	__weak typeof(self) weakSelf = self;

//	NSData* data = [[NSData alloc] initWithBase64EncodedString:self.keyBackupVC.user.uuid
//																		options:0];
//	NSString* userIDb58  = [NSString base58WithData:data];
//
	// the UIActivityViewController  <UIActivityItemSource> protocol isnt very modern.
	// we need to keep some data lying around to tell the UIActivityViewController what to share.
	NSArray *objectsToShare = @[self ];
	itemsToSend = @[image,url];
	
	
	UIActivityViewController *avc = [[UIActivityViewController alloc]
												initWithActivityItems:objectsToShare
												applicationActivities: nil ];

	NSMutableArray* excludeTypes = [NSMutableArray arrayWithArray:
											  @[UIActivityTypeAssignToContact,
												 UIActivityTypePostToFacebook,
												 UIActivityTypePostToTwitter,
												 UIActivityTypePostToWeibo,
												 UIActivityTypeAddToReadingList,
												 UIActivityTypePostToVimeo,
												 UIActivityTypePostToTencentWeibo,
												 ]];
	
	// prevent crashing , if the photo lib is not available dont show it
	if(!ZDCConstants.appHasPhotosPermission)
		[excludeTypes addObject: UIActivityTypeSaveToCameraRoll];
	
	avc.excludedActivityTypes = excludeTypes;
	avc.completionWithItemsHandler = ^(NSString *activityType,
												  BOOL completed,
												  NSArray *returnedItems,
												  NSError *activityError)
	{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		strongSelf->itemsToSend = nil;
		
		// delete the share file item
		[NSFileManager.defaultManager removeItemAtURL:url
															 error:nil];
		
		if(completionBlock)
		{
			
			if([activityError.domain isEqualToString:NSCocoaErrorDomain]
				&& activityError.code == NSUserCancelledError)
			{
				completed = NO;
				activityError = nil;
			}
			
			completionBlock(completed, activityError);
		}
		
	};
	
	if([ZDCConstants isIPad])
	{
		avc.popoverPresentationController.barButtonItem = _bbnAction;
		avc.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
		
	}
	
	[self presentViewController:avc
							 animated:YES
						  completion:nil];
}

-(void) saveQRCode
{
     __weak typeof(self) weakSelf = self;
	
	BOOL hasPasscode = (_txtPwdField.text.length > 0);
	
	[self.keyBackupVC createBackupDocumentWithQRCodeString:qrCodeString
															 hasPassCode:hasPasscode
														completionBlock:^(NSURL * _Nullable url,
																				UIImage * _Nullable image,
																				NSError * _Nullable error)
	 {
	
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;
		 
		 
		 if(error)
		 {
			 [strongSelf.keyBackupVC showError: NSLocalizedString(@"Sending Key Failed", @"Sending Key Failed")
										message:error.localizedDescription
							 completionBlock:nil];
			 return;
		 }
		 
		 [strongSelf sendBackupDocumentWithActivityView:url
														image:image
										  completionBlock:^(BOOL didSend, NSError *error) {
											  
										  }];
		 
	 }];

}

- (id)activityViewController:(UIActivityViewController *)activityViewController
			itemForActivityType:(NSString *)activityType
{
	
	
	__block NSURL* pdfURL = nil;
	__block UIImage *image = nil;
	
	id returnObj = nil;
	
	[itemsToSend	enumerateObjectsUsingBlock:^(id  obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if([obj isKindOfClass:[NSURL class]])
		{
			pdfURL = (NSURL*) obj;
		}
		else if([obj isKindOfClass:[UIImage class]])
		{
			image = (UIImage*) obj;
		}
	}];
	
	if( [activityType isEqualToString:UIActivityTypeCopyToPasteboard]
		||  [activityType isEqualToString:UIActivityTypeSaveToCameraRoll])
	{
		returnObj = image;
	}
	else
	{
		returnObj = pdfURL;
	}
	
	return returnObj;
}

// UIActivityViewController protocol..
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
	__block UIImage *image = nil;
	
	[itemsToSend	enumerateObjectsUsingBlock:^(id  obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if([obj isKindOfClass:[UIImage class]])
		{
			image = (UIImage*) obj;
			*stop = YES;
		}
	}];
	
	return image;
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController subjectForActivityType:(NSString *)activityType
{
	
	NSString* displayName = keyBackupVC.user.displayName;
	NSString* title = [NSString stringWithFormat:@"Access key for %@" , displayName];
	return title;
	
}

@end
