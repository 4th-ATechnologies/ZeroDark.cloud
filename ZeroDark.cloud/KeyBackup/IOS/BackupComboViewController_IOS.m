/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "BackupComboViewController_IOS.h"

#import "LanguageListViewController_IOS.h"
#import "PasswordStrengthUIView.h"
#import "ZDCSecureTextField.h"
#import "ZDCAccessCode.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZDCPasswordStrengthCalculator.h"
#import "ZeroDarkCloudPrivate.h"

#import "RKTagsView.h"

// Categories
#import "NSString+ZeroDark.h"
#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"
#import "UIImageViewPasteable.h"

// Libraries
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


#define USE_CUSTOM_ACTIVITY 0

#if USE_CUSTOM_ACTIVITY

@interface ZDCActivityTypeCopyImageToPasteboard : UIActivity
@property (nonatomic, strong) NSArray *activityItems;
@end

@implementation ZDCActivityTypeCopyImageToPasteboard

- (NSString *)activityType {
	
	// a unique identifier
	return @"com.4th-a.ZeroDark.copyImage";
}

- (NSString *)activityTitle {
	
	// a title shown in the sharing menu
	return @"Copy Image";
}

- (UIImage *)activityImage {
	
	UIImage* image = [UIImage imageNamed:@"copy-activity"
												inBundle:[ZeroDarkCloud frameworkBundle]
					compatibleWithTraitCollection:nil];
	
	// an image to go with our option
	return image;
}

+ (UIActivityCategory)activityCategory {
	
	// which row our activity is shown in
	// top row is sharing, bottom row is action
	return UIActivityCategoryAction;
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
	
	// return YES for anything that our activity can deal with
	for (id item in activityItems) {
		
		// we can deal with strings and images
		if ([item isKindOfClass:[UIImage class]]) {
			return YES;
		}
	}
	// for everything else, return NO
	return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems {
	
	// anything we need to prepare, now's the chance
	// custom UI, long running calculations, etc
	
	// also: grab a reference to the objects our user wants to share/action
	self.activityItems = activityItems;
}

# pragma mark - optional methods we can override

- (UIViewController *)activityViewController {
	
	// return a custom UI if we need it,
	// or the standard activity view controller if we don't
	return nil;
}

- (void)performActivity {
	
	// the main thing our activity does
	
	// act upon each item here
	for (id item in self.activityItems) {
		NSLog(@"YEY - someone wants to use our activity!");
		NSLog(@"They used this object: %@", [item description]);
	}
	
	// notify iOS that we're done here
	// return YES if we were successful, or NO if we were not
	[self activityDidFinish:YES];
}
@end

@interface ZDCActivityTypeCopyTextToPasteboard : UIActivity
@property (nonatomic, strong) NSArray *activityItems;
@end

@implementation ZDCActivityTypeCopyTextToPasteboard

- (NSString *)activityType {
	
	// a unique identifier
	return @"com.4th-a.ZeroDark.copyText";
}

- (NSString *)activityTitle {
	
	// a title shown in the sharing menu
	return @"Copy Words";
}

- (UIImage *)activityImage {
	
	UIImage* image = [UIImage imageNamed:@"copy-activity"
										 inBundle:[ZeroDarkCloud frameworkBundle]
			 compatibleWithTraitCollection:nil];
	
	// an image to go with our option
	return image;
}

+ (UIActivityCategory)activityCategory {
	
	// which row our activity is shown in
	// top row is sharing, bottom row is action
	return UIActivityCategoryAction;
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
	
	// return YES for anything that our activity can deal with
	for (id item in activityItems) {
		
		// we can deal with strings and images
		if ([item isKindOfClass:[UIImage class]]) {
			return YES;
		}
	}
	// for everything else, return NO
	return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems {
	
	// anything we need to prepare, now's the chance
	// custom UI, long running calculations, etc
	
	// also: grab a reference to the objects our user wants to share/action
	self.activityItems = activityItems;
}

# pragma mark - optional methods we can override

- (UIViewController *)activityViewController {
	
	// return a custom UI if we need it,
	// or the standard activity view controller if we don't
	return nil;
}

- (void)performActivity {
	
	// the main thing our activity does
	
	// act upon each item here
	for (id item in self.activityItems) {
		NSLog(@"YEY - someone wants to use our activity!");
		NSLog(@"They used this object: %@", [item description]);
	}
	
	// notify iOS that we're done here
	// return YES if we were successful, or NO if we were not
	[self activityDidFinish:YES];
}
@end

#endif

@implementation BackupComboViewController_IOS
{
	UIBarButtonItem* 				globeBbn;
	
	IBOutlet __weak UIImageViewPasteable*	_imgQRCode;
	
	IBOutlet __weak UILabel*           		_lblEnterPasscode;
	
	IBOutlet __weak ZDCSecureTextField      *_txtPwdField;
	IBOutlet __weak PasswordStrengthUIView  *_strengthField;
	IBOutlet __weak UILabel                 *_lblStrength;
	
	ZDCPasswordStrength							*pwdStrength;
	
	IBOutlet  NSLayoutConstraint *	_bottomPWDConstraintKBShow;
 
	IBOutlet __weak UILabel*			_lblWordsTitle;
	IBOutlet __weak RKTagsView  *   	_tagView;
	IBOutlet  NSLayoutConstraint *	_tagViewHeightConstraint;
	
	IBOutlet __weak UITextView*		_txtExplain;
	IBOutlet  NSLayoutConstraint*		_txtExplainHeightConstraint;
	
	IBOutlet __weak UIView*				_vwWordsNotAvailable;

	IBOutlet __weak UIBarButtonItem  	*_bbnNext;
	IBOutlet __weak UIBarButtonItem  	*_bbnAction;
	IBOutlet __weak UIBarButtonItem  	*_bbnCopyWords;
	IBOutlet __weak UIBarButtonItem  	*_bbnCopyImage;
	
	NSTimer *                       		refreshTimer;
	BOOL 											requireCloneCode;
	UIImage*					   				defaultQRcodeImage;
	NSString*              		   		qrCodeString;
	UISwipeGestureRecognizer 				*swipeRight;
	
	BOOL didCopyImage;
	BOOL didCopyWords;

	// the UIActivityViewController  <UIActivityItemSource> protocol isnt very modern.
	// we need to keep some data lying around to tell the UIActivityViewController what to share.
	NSArray* itemsToSend;
}


@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

	_tagView.lineSpacing = 4;
	_tagView.interitemSpacing = 4;
	_tagView.allowCopy = NO;
	_tagView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];

	_tagView.layer.cornerRadius   = 8;
	_tagView.layer.masksToBounds  = YES;
	_tagView.layer.borderColor    = self.view.tintColor.CGColor;
	_tagView.layer.borderWidth    = 1.0f;
	_tagView.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//
	
	_tagView.tagsEdgeInsets  = UIEdgeInsetsMake(8, 8, 8, 8);
	//	_tagView.userInteractionEnabled = NO;
	_tagView.allowCopy = YES;
	_tagView.editable = NO;
	_tagView.selectable = NO;
	_tagView.tintAdjustmentMode =  UIViewTintAdjustmentModeNormal;
	_tagView.tintColor = UIColor.darkGrayColor;

	_tagView.layer.cornerRadius   = 8;
	_tagView.layer.masksToBounds  = YES;
	_tagView.layer.borderColor    = self.view.tintColor.CGColor;
	_tagView.layer.borderWidth    = 1.0f;
	_tagView.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//

	_vwWordsNotAvailable.layer.cornerRadius   = 8;
	_vwWordsNotAvailable.layer.masksToBounds  = YES;
	_vwWordsNotAvailable.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//

	// setup for clickable URL
	_txtExplain.scrollEnabled = NO;
	_txtExplain.editable = NO;
	_txtExplain.textContainer.lineFragmentPadding = 0;
	_txtExplain.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
	_txtExplain.delegate =  (id <UITextViewDelegate>)self;
	_txtExplain.backgroundColor = UIColor.clearColor;

	_imgQRCode.canCopy = YES;
	_imgQRCode.canPaste = NO;

	defaultQRcodeImage  = [UIImage imageNamed:@"qrcode-default"
												inBundle:[ZeroDarkCloud frameworkBundle]
					compatibleWithTraitCollection:nil];

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

	_txtExplain.attributedText = self.createAccessWordsNotAvailableString;

	_tagView.alpha = 1.0;
	_lblWordsTitle.alpha = 1.0;
	_vwWordsNotAvailable.alpha = 0;
}

-(NSAttributedString*)createAccessWordsNotAvailableString
{
	
	NSURL* blogURL = [ZDCConstants ZDCaccessKeyBlogPostURL];
	
	NSString* explainationText =
	NSLocalizedString(
							@"Access Key words are not allowed when you use a passphrase. ",
							@"Access Key words are not allowed when you use a passphrase ");
	
	
	UIFont* textFont =  [ UIFont  preferredFontForTextStyle: UIFontTextStyleFootnote];
	NSMutableAttributedString *atrStr1 	= [[NSMutableAttributedString alloc] initWithString:explainationText
																										  attributes:@{ NSFontAttributeName: textFont  }];
	
	NSString* blogText = NSLocalizedString(
														@"To learn more about how this process works, check out our <blog post>",
														@"Split key blog post text");
	
	NSRange openingRange = [blogText rangeOfString:@"<"];
	blogText = [blogText stringByReplacingOccurrencesOfString:@"<" withString:@""];
	NSRange closingRange = [blogText rangeOfString:@">"];
	blogText = [blogText stringByReplacingOccurrencesOfString:@">" withString:@""];
	NSRange textRange = NSMakeRange(openingRange.location, closingRange.location  - openingRange.location);
	
	NSMutableAttributedString *atrStr2 	= [[NSMutableAttributedString alloc] initWithString:blogText
																										  attributes:@{ NSFontAttributeName: textFont  }];
	
	[atrStr2 beginEditing];
	[atrStr2 addAttribute:NSLinkAttributeName value:[blogURL absoluteString] range:textRange];
	
	// make the text appear in blue
	[atrStr2 addAttribute:NSForegroundColorAttributeName
						 value:self.view.tintColor
						 range:textRange];
	[atrStr2 addAttribute:
	 NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:textRange];
	
	[atrStr2 endEditing];
	
	[atrStr1 appendAttributedString:atrStr2];
	
	return atrStr1;
	
}
-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	self.navigationItem.title = @"Backup Access Key";
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																					 style:UIBarButtonItemStylePlain
																					target:self
																					action:@selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
	
	UIImage* globeImage = [[UIImage imageNamed:@"globe"
												 inBundle:[ZeroDarkCloud frameworkBundle]
					 compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIButton *globeButton = [[UIButton alloc]init];
	[globeButton setImage:globeImage forState:UIControlStateNormal];
	[globeButton addTarget:self
						 action:@selector(handleGlobeButton:)
			forControlEvents:UIControlEventTouchUpInside];
	UIBarButtonItem* globeButtonItem = [[UIBarButtonItem alloc] initWithCustomView:globeButton];
	[globeButtonItem.customView.widthAnchor constraintEqualToConstant:22].active = YES;
	[globeButtonItem.customView.heightAnchor constraintEqualToConstant:22].active = YES;
	globeBbn = globeButtonItem;
	self.navigationItem.rightBarButtonItem = globeBbn;
	
	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	swipeRight.direction = UISwipeGestureRecognizerDirectionRight  ;
	[self.view addGestureRecognizer:swipeRight];
	
	_bottomPWDConstraintKBShow.active = NO;
	_txtExplainHeightConstraint.constant = _txtExplain.contentSize.height;

	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillShow:)
																name:UIKeyboardWillShowNotification
															 object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillHide:)
																name:UIKeyboardWillHideNotification
															 object:nil];
	[self refreshView];
	
	BOOL hasPasscode = (_txtPwdField.text.length > 0);
	BOOL shouldShowCloneWords = !(hasPasscode || requireCloneCode);
	
	[self showCloneWords: shouldShowCloneWords];
	
	didCopyImage = NO;
	didCopyWords = NO;
}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	itemsToSend = nil;

	_txtPwdField.text = @"";
	_strengthField.hidden = YES;
	_lblStrength.hidden = YES;
	
	if(refreshTimer) {
		[refreshTimer invalidate];
	}

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_tagViewHeightConstraint.constant = _tagView.contentSize.height;
	
}


- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;
	
}
-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[self handleNavigationBack:NULL];
}

- (void)handleGlobeButton:(id)sender
{
	LanguageListViewController_IOS* langVC =
	[[LanguageListViewController_IOS alloc]initWithDelegate:(id<LanguageListViewController_Delegate>) self
															languageCodes:BIP39Mnemonic.availableLanguages
															  currentCode:keyBackupVC.currentLanguageId
													 shouldShowAutoPick:NO];
	
	langVC.modalPresentationStyle = UIModalPresentationPopover;
	
	UIPopoverPresentationController *popover =  langVC.popoverPresentationController;
	popover.delegate = langVC;
	popover.sourceView = self.view;
	
	popover.barButtonItem = globeBbn;
	popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
	
	[self presentViewController:langVC animated:YES completion:^{
		//		currentVC = langVC;
		//		[self refreshTitleBar];
	}];
}



-(void) refreshInstuctions
{
	requireCloneCode =  NO; //S4Preferences_si.requireCloningPasscode;
	
	if(requireCloneCode)
	{
		//		cloneCodeInstructions2 = @" You must enter a passphrase before saving.";
		_txtPwdField.placeholder = @"enter passphrase";
	}
	else
	{
		//		cloneCodeInstructions2 = @" You may enter an optional passphrase.";
		_txtPwdField.placeholder = @"optional passphrase";
		
	}
	
}


-(void) refreshView
{
	__weak typeof(self) weakSelf = self;
	NSError* error = nil;
	
	P2K_Algorithm p2kAlgorithm = kP2K_Algorithm_Argon2i;
	qrCodeString = nil;

	BOOL hasPasscode = (_txtPwdField.text.length > 0);

	if(hasPasscode)
	{
		qrCodeString = [self.keyBackupVC accessKeyStringWithPasscode:_txtPwdField.text
																 p2kAlgorithm:p2kAlgorithm
																		  error:&error];
	}
	else if(!requireCloneCode)
	{
		qrCodeString = [self.keyBackupVC accessKeyStringWithPasscode:keyBackupVC.user.syncedSalt
																 p2kAlgorithm:p2kAlgorithm
																		  error:&error];
	}else {
		qrCodeString = nil;
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
	
	NSArray<NSString*> * wordList = [BIP39Mnemonic mnemonicFromKey:keyBackupVC.accessKeyData
																		 passphrase:keyBackupVC.user.syncedSalt
																		 languageID:keyBackupVC.currentLanguageId
																		  algorithm:Mnemonic_Storm4
																				error:&error];
	
	[_tagView removeAllTags];
	
	for(NSString* tag in wordList)
		[_tagView addTag:tag];
	
}

-(void)showCloneWords:(BOOL)shouldShow
{
	__weak typeof(self) weakSelf = self;
	
	[UIView animateWithDuration:0.1 animations:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		if(shouldShow)
		{
			strongSelf->_tagView.alpha = 1.0;
			strongSelf->_lblWordsTitle.alpha = 1.0;
			strongSelf->_vwWordsNotAvailable.alpha = 0;
		}
		else
		{
			strongSelf->_tagView.alpha = 0.0;
			strongSelf->_lblWordsTitle.alpha = 0.0;
			strongSelf->_vwWordsNotAvailable.alpha = 1.0;
		}
	} completion:^(BOOL finished) {
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		strongSelf->_bbnCopyWords.enabled = shouldShow;
		strongSelf->globeBbn.enabled = shouldShow;
		}];
}


//MARK: actions


-(IBAction)nextButtonTapped:(id)sender
{
	// depending on didCopyImage or didCopyWords
	
	if(didCopyWords && !didCopyImage)
		[self.keyBackupVC pushVerifyText];
	
	else if(!didCopyWords && didCopyImage)
		[self.keyBackupVC pushVerifyImage];
	
	else // ask user
	{
		__weak typeof(self) weakSelf = self;

		UIAlertController *alertController =
		[UIAlertController alertControllerWithTitle:nil
														message:nil
											  preferredStyle:UIAlertControllerStyleActionSheet];
		
		UIAlertAction *imageAction =
		[UIAlertAction actionWithTitle:NSLocalizedString(@"Verify with QR Code", @"Verify with QR Code")
										 style:UIAlertActionStyleDefault
									  handler:^(UIAlertAction *action)
		 {
			__strong typeof(self) strongSelf = weakSelf;
			 if (strongSelf == nil) return;
			 
			 [strongSelf.keyBackupVC pushVerifyImage];
		 }];
		
		UIAlertAction *wordsAction  =
		[UIAlertAction actionWithTitle:NSLocalizedString(@"Verify with Words", @"Verify with Words")
										 style:UIAlertActionStyleDefault
									  handler:^(UIAlertAction *action)
		 {
			 __strong typeof(self) strongSelf = weakSelf;
			 if (strongSelf == nil) return;
			 
			 [strongSelf.keyBackupVC pushVerifyText];
		 }];
		
		UIAlertAction *cancelAction =
		[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action")
										 style:UIAlertActionStyleCancel
									  handler:nil];
		
		[alertController addAction:imageAction];
		[alertController addAction:wordsAction];
		[alertController addAction:cancelAction];
		
		if([ZDCConstants isIPad])
		{
			alertController.popoverPresentationController.barButtonItem = _bbnNext;
			alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
		}
		
		[self presentViewController:alertController animated:YES
							  completion:^{
							  }];
		
	}
}

- (IBAction)actionButtonTapped:(id)sender
{
	if(ZDCConstants.appHasPhotosPermission)
	{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			
			dispatch_async(dispatch_get_main_queue(), ^{
				
				switch (status) {
						
					case PHAuthorizationStatusAuthorized:
						[self saveQRCodeFromBBN:sender
									  canAccessPhotos:YES];
						break;
						
					case PHAuthorizationStatusRestricted:
					{
						[self saveQRCodeFromBBN:sender
									  canAccessPhotos:NO];
					}
						break;
						
					case PHAuthorizationStatusDenied:
					{
						[self saveQRCodeFromBBN:sender
									  canAccessPhotos:NO];
					}
						break;
						
					default:
						break;
				}
			});
			
		}];
		
	}else
	{
		[self saveQRCodeFromBBN:sender
					  canAccessPhotos:YES];
	}
}

-(IBAction)copyWordsButtonTapped:(id)sender
{
	NSString* accessString = [_tagView.tags componentsJoinedByString:@" "];
	accessString =  [accessString stringByAppendingString:@" "];        // add a space at end to help with insert

	[[UIPasteboard generalPasteboard]  setString:accessString];
	
	didCopyWords = YES;
}

-(IBAction)copyImageButtonTapped:(id)sender
{
	if(qrCodeString)
	{
		UIImage* image = [OSImage QRImageWithString:qrCodeString  withSize:CGSizeMake(400, 400)];
		[[UIPasteboard generalPasteboard] setImage:image];
		
		didCopyImage = YES;
	}
}



//MARK: LanguageListViewController_Delegate

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
					  didSelectLanguage:(NSString* __nullable) languageID
{
	keyBackupVC.currentLanguageId = languageID;
	[self refreshView];
	
}



//MARK: Keyboard/TextField Navigation

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
		
		BOOL hasPasscode = (_txtPwdField.text.length > 0);
		BOOL shouldShowCloneWords = !(hasPasscode || requireCloneCode);

		[self showCloneWords: shouldShowCloneWords];
		[self updatePasswordStrengthWithString:_txtPwdField.text];

		// allow user to some type ahead
		refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
																		target:self
																	 selector:@selector(refreshView)
																	 userInfo:nil
																	  repeats:NO];
	}
}

//MARK: Keyboard


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
	
	
//	_lblCloneCodeInstructions.text  = cloneCodeInstructions2 ;
// 	[_lblEnterPasscode sizeToFit];
	
	[UIView animateWithDuration:animationDuration
								 delay:0.2
							  options:AnimationOptionsFromCurve(animationCurve)
						  animations:
	 ^{
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_bottomPWDConstraintKBShow.constant =  keyboardHeight + 2;
 		 	 strongSelf->_bottomPWDConstraintKBShow.active = YES;
			 
			 strongSelf->_tagView.alpha = 0.0;
			 strongSelf->_lblWordsTitle.alpha = 0.0;
			 strongSelf->_vwWordsNotAvailable.alpha = 0;
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
	
	
//	_lblCloneCodeInstructions.text  = [cloneCodeInstructions1 stringByAppendingString:cloneCodeInstructions2];
//	[_lblCloneCodeInstructions sizeToFit];
//
	BOOL hasPasscode = (_txtPwdField.text.length > 0);
	BOOL shouldShowCloneWords = !(hasPasscode || requireCloneCode);
	
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
			 strongSelf->_bottomPWDConstraintKBShow.active = NO;
		 	 [strongSelf showCloneWords: shouldShowCloneWords];
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

-(void)saveBackupDocumentFromBBN:(UIBarButtonItem*)bbn						  					canAccessPhotos:(BOOL)canAccessPhotos
										  url:(NSURL*)url
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

#if USE_CUSTOM_ACTIVITY
	ZDCActivityTypeCopyImageToPasteboard*  copyImage = [[ZDCActivityTypeCopyImageToPasteboard alloc]init];
	ZDCActivityTypeCopyTextToPasteboard*  copyText = [[ZDCActivityTypeCopyTextToPasteboard alloc]init];

	
	UIActivityViewController *avc = [[UIActivityViewController alloc]
												initWithActivityItems:objectsToShare
												applicationActivities: @[copyImage,copyText]];

#else
	UIActivityViewController *avc = [[UIActivityViewController alloc]
												initWithActivityItems:objectsToShare
												applicationActivities: nil];

#endif
	
	NSMutableArray* excludeTypes = [NSMutableArray arrayWithArray:
											  @[UIActivityTypeCopyToPasteboard,
												 UIActivityTypeAssignToContact,
												 UIActivityTypePostToFacebook,
												 UIActivityTypePostToTwitter,
												 UIActivityTypePostToWeibo,
												 UIActivityTypeAddToReadingList,
												 UIActivityTypePostToVimeo,
												 UIActivityTypePostToTencentWeibo,
												 ]];
	
	// prevent crashing , if the photo lib is not available dont show it
	if(!canAccessPhotos)
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
		avc.popoverPresentationController.barButtonItem = bbn;
		avc.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
		
	}
	
	[self presentViewController:avc
							 animated:YES
						  completion:nil];
}

-(void)saveQRCodeFromBBN:(UIBarButtonItem*)bbn
				 canAccessPhotos:(BOOL)canAccessPhotos
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
		 
		 [strongSelf saveBackupDocumentFromBBN:bbn
									  canAccessPhotos:canAccessPhotos
													  url:url
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
