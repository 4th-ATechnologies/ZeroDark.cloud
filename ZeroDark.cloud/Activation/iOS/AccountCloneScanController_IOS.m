/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "AccountCloneScanController_IOS.h"

#import "Auth0Utilities.h"
#import "LanguageListViewController_IOS.h"
#import "QRcodeView.h"
#import "RKTagsView.h"
#import "SCShapeView.h"
#import "ZDCAccessCode.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCSound.h"
#import "ZDCUserAccessKeyManager.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+S4.h"
#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"
#import "UIButton+Activation.h"

// Libraries
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

@import CoreImage;
@import ImageIO;


// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose; // | ZDCLogFlagTrace;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


typedef enum {
	kCloneCodeViewTab_Invalid   = 0,
	
	kCloneCodeViewTab_QRCode      = 1,
	kCloneCodeViewTab_Words      = 2,
	
} CloneCodeViewTab;


@implementation AccountCloneScanController_IOS
{
	IBOutlet __weak UIView		*_vwCloneContainer;
	UIView 							*currentCloneView;
	
	IBOutlet        UIView  	*_vwCloneCodeScan;
	IBOutlet __weak NSLayoutConstraint *_containerViewBottomConstraint;
	CGFloat                             originalContainerViewBottomConstraint;
	
	IBOutlet __weak UIImageView *       _imgCloneCodeAvatar;
	IBOutlet __weak UILabel     *       _lblCloneCodeDisplayName;
	IBOutlet __weak UIImageView *       _imgCloneCodeProvider;
	IBOutlet __weak UILabel     *       _lblCloneCodeProvider;
	
	IBOutlet __weak UILabel*    _lblStatus;
	IBOutlet __weak UIButton*   _btnStatus;
	
	
	QRcodeView  *   _overlayView;
	IBOutlet __weak UIView *   _viewPreview;
	IBOutlet __weak UIView *   _portalPlaceholderView;
	IBOutlet __weak UIImageView* _imgNoCamera;
	
	SCShapeView *   _boundingBox;
	NSTimer *       _boxHideTimer;
	
	IBOutlet  __weak UIButton   *_btnPhoto;
	IBOutlet  __weak UIButton   *_btnPaste;
	
	IBOutlet        UIView  *           _vwCloneWordsInput;
	
	IBOutlet __weak UIView  *           _vwCloneWordsBox;
	IBOutlet __weak UIImageView *       _imgCloneWordsAvatar;
	IBOutlet __weak UILabel     *       _lblCloneWordsDisplayName;
	IBOutlet __weak UIImageView *       _imgCloneWordsProvider;
	IBOutlet __weak UILabel     *       _lblCloneWordsProvider;
	
	IBOutlet __weak RKTagsView  *       _tagView;
	IBOutlet __weak UIButton*  			 _btnLang;
	
	IBOutlet  __weak UIButton   *       _btnCloneWordsVerify;
	
	UIDocumentPickerViewController *docPicker;
	UIImagePickerController     *photoPicker;
	
	AVCaptureSession *          captureSession;
	AVCaptureVideoPreviewLayer *videoPreviewLayer;
	
	NSString*           lastQRCode;
	BOOL                isReading;
	
	IBOutlet __weak UITabBar*           _tabBar;
	IBOutlet __weak UITabBarItem*       _tabItemQR;
	IBOutlet __weak UITabBarItem*       _tabItemWords;
	CloneCodeViewTab                    selectedTab;
	
	NSString*				currentLanguageId;
	NSUInteger 				requiredbip39WordCount;
	BOOL					autoPickLanguage;
	
	NSSet*                  bip39Words;
	NSInteger               failCount;
	
	UIImage*                defaultUserImage;
	
	NSString*       		activationBlob;
	
	ZeroDarkCloud *zdc;
	YapDatabaseConnection *uiDatabaseConnection;
	
	BOOL isUsingCarmera;
	BOOL needsSetupView;
	
}

@synthesize accountSetupVC = accountSetupVC;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
	
	[super viewDidLoad];
	
	_vwCloneContainer.layer.cornerRadius   = 16;
	_vwCloneContainer.layer.masksToBounds  = YES;
	_vwCloneContainer.layer.borderColor    = [UIColor whiteColor].CGColor;
	_vwCloneContainer.layer.borderWidth    = 1.0f;
	_vwCloneContainer.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];
	
	void (^TintButtonImage)(UIButton *) = ^(UIButton *button){
		
		UIImage *image = [button imageForState:UIControlStateNormal];
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		
		[button setImage:image forState: UIControlStateNormal];
		button.tintColor = [UIColor whiteColor];
	};
	
	TintButtonImage(_btnPaste);
	TintButtonImage(_btnPhoto);
	
	[_btnCloneWordsVerify zdc_colorize];
	_btnCloneWordsVerify.enabled  = NO;
	
	_imgCloneCodeAvatar.layer.cornerRadius = 54 / 2;
	//	_imgCloneCodeAvatar.layer.borderWidth = 2.0f;
	//	_imgCloneCodeAvatar.layer.borderColor = [UIColor blackColor].CGColor;
	_imgCloneCodeAvatar.clipsToBounds = YES;
	
	_imgCloneCodeAvatar.hidden = YES;
	_imgCloneCodeProvider.hidden = YES;
	_lblCloneCodeDisplayName.hidden = YES;
	
	_imgCloneWordsAvatar.layer.cornerRadius = 54 / 2;
	//	_imgCloneWordsAvatar.layer.borderWidth = 2.0f;
	//	_imgCloneWordsAvatar.layer.borderColor = [UIColor blackColor].CGColor;
	_imgCloneWordsAvatar.clipsToBounds = YES;
	
	_imgCloneWordsAvatar.hidden = YES;
	_imgCloneWordsProvider.hidden = YES;
	_lblCloneWordsDisplayName.hidden = YES;
	_lblCloneWordsProvider.hidden = YES;
	
	_tagView.lineSpacing = 4;
	_tagView.interitemSpacing = 4;
	_tagView.allowCopy = NO;
	_tagView.tintAdjustmentMode =  UIViewTintAdjustmentModeNormal;
	
	_tagView.layer.cornerRadius   = 8;
	_tagView.layer.masksToBounds  = YES;
	_tagView.tagsEdgeInsets  = UIEdgeInsetsMake(8, 8, 8, 8);
	
	_tagView.textField.placeholder = @"Enter recovery phrase…";
	_tagView.delegate = (id <RKTagsViewDelegate>) self;
	_tagView.textField.autocorrectionType = UITextAutocorrectionTypeNo;
	
	NSString *localeIdentifier = [[NSLocale currentLocale] localeIdentifier];
	currentLanguageId = [BIP39Mnemonic languageIDForlocaleIdentifier: localeIdentifier];
	bip39Words = [NSSet setWithArray:[BIP39Mnemonic wordListForLanguageID:localeIdentifier
																						 error:nil]];
	
	[BIP39Mnemonic mnemonicCountForBits:256 mnemonicCount:&requiredbip39WordCount];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
														  selector: @selector(databaseConnectionDidUpdate:)
																name: UIDatabaseConnectionDidUpdateNotification
															 object: nil];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
														  selector: @selector(applicationDidResignActiveNotification)
																name: UIApplicationWillResignActiveNotification
															 object: NULL];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
														  selector: @selector(applicationDidBecomeActiveNotification)
																name: UIApplicationDidBecomeActiveNotification
															 object: NULL];
	
	originalContainerViewBottomConstraint  = CGFLOAT_MAX;
	needsSetupView = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	zdc = accountSetupVC.zdc;
	uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;
	
	defaultUserImage = zdc.imageManager.defaultUserAvatar;
	_imgCloneCodeAvatar.image = defaultUserImage;
	_imgCloneWordsAvatar.image = defaultUserImage;

	[[UITabBar appearance] setTintColor:[UIColor whiteColor ]];
	[[UITabBar appearance] setBarTintColor:[UIColor clearColor]];
	
	if(originalContainerViewBottomConstraint == CGFLOAT_MAX)
		originalContainerViewBottomConstraint = _containerViewBottomConstraint.constant;
	
	[[NSNotificationCenter defaultCenter] addObserver: self
														  selector: @selector(keyboardWillShow:)
																name: UIKeyboardWillShowNotification
															 object: nil];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
														  selector: @selector(keyboardWillHide:)
																name: UIKeyboardWillHideNotification
															 object: nil];
	
	accountSetupVC.btnBack.hidden = self.navigationController.viewControllers.count == 1;
	
	[_tagView removeAllTags];
	[self refreshCloneWordForCount:0 validWords:0];
	_btnCloneWordsVerify.enabled  = NO;
	
	NSString *msg_checking =
	  NSLocalizedString(@"Checking camera access…",
	                    @"Access key scanning window");
	
	_btnStatus.hidden = YES;
	[self setCameraStatusString: msg_checking
	                   isButton: NO
	                      color: UIColor.whiteColor];
	
	[self refreshView];
	
	_imgNoCamera.hidden = YES;
	
	[accountSetupVC setHelpButtonHidden:NO];
	accountSetupVC.btnBack.hidden = YES;  // cant go back from here
}

- (void)viewDidLayoutSubviews
{
	ZDCLogAutoTrace();
	[super viewDidLayoutSubviews];
	
	// This method is called multiple times.
	// But it's also called:
	// - after viewWillAppear
	// - before viewDidLoad
	
	if (needsSetupView)
	{
		needsSetupView = NO;
		
		// If we call this from viewWillAppear, it doesn't work properly.
		// If we call this from viewDidAppear, it's too late and looks goofy.
		[self switchViewsToTag:kCloneCodeViewTab_QRCode animated:NO];
	}
}

- (void)viewDidAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewDidAppear:animated];
	
	BOOL canPaste = [[UIPasteboard generalPasteboard] image] != nil;
	_btnPaste.enabled = canPaste;
	
//	[self switchViewsToTag: kCloneCodeViewTab_QRCode animated:NO];
}

/*
- (void)viewDidLayoutSubviews
{
	ZDCLogAutoTrace();
	[super viewDidLayoutSubviews];
}
*/

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillDisappear:animated];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	isUsingCarmera = NO;
	[self stopReading];
	
	[[UITabBar appearance] setTintColor:nil];
	[[UITabBar appearance] setBarTintColor:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)applicationDidResignActiveNotification
{
	ZDCLogAutoTrace();
	
	[self stopReading];
}

- (void)applicationDidBecomeActiveNotification
{
	ZDCLogAutoTrace();
	
	if (isUsingCarmera) {
		[self startReading];
	}
}

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	[self refreshView];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AccountSetupViewController_IOS_Child_Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return (self.navigationController.viewControllers.count > 1);
}

- (void)refreshView
{
	ZDCLogAutoTrace();
	
	NSString *const localUserID = accountSetupVC.user.uuid;
	__block ZDCLocalUser *localUser = nil;

	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];

	if (!localUser || !localUser.isLocal) {
		return;
	}
	
	NSString *displayName = localUser.displayName;
	
	_lblCloneCodeDisplayName.text = displayName;
	_lblCloneCodeDisplayName.hidden = NO;
	
	_lblCloneWordsDisplayName.text = displayName;
	_lblCloneWordsDisplayName.hidden = NO;
	
	ZDCUserIdentity *displayIdentity = localUser.displayIdentity;
	
	NSURL *pictureURL =
	  [Auth0Utilities pictureUrlForIdentity: displayIdentity
	                                 region: localUser.aws_region
	                                 bucket: localUser.aws_bucket];
	
	OSImage *providerImage =
	  [[zdc.auth0ProviderManager providerIcon: Auth0ProviderIconType_Signin
	                              forProvider: displayIdentity.provider]
	                           scaledToHeight: _imgCloneWordsProvider.frame.size.height];
	
	if (providerImage)
	{
		_imgCloneCodeProvider.hidden = NO;
		_imgCloneCodeProvider.image = providerImage;
		_lblCloneCodeProvider.hidden = YES;
		
		_imgCloneWordsProvider.hidden = NO;
		_imgCloneWordsProvider.image = providerImage;
		_lblCloneWordsProvider.hidden = YES;
	}
	else
	{
		_imgCloneCodeProvider.hidden = YES;
		_lblCloneWordsProvider.text = displayIdentity.provider;
		_lblCloneWordsProvider.hidden = NO;
		
		_imgCloneCodeProvider.hidden = YES;
		_lblCloneCodeProvider.text = displayIdentity.provider;
		_lblCloneCodeProvider.hidden = NO;
	}
	
	if (pictureURL)
	{
		__weak typeof(self) weakSelf = self;
		
		CGSize avatarSize = _imgCloneWordsAvatar.frame.size;
		
		UIImage* (^processingBlock)(UIImage *) = ^(UIImage *image){
			
			return [image imageWithMaxSize: avatarSize];
		};
		void (^preFetchBlock)(UIImage *_Nullable, BOOL) = ^(UIImage *image, BOOL willFetch){
			
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			image = image ?: strongSelf->defaultUserImage;
			
			strongSelf->_imgCloneCodeAvatar.hidden = NO;
			strongSelf->_imgCloneCodeAvatar.image = image;
			
			strongSelf->_imgCloneWordsAvatar.hidden = NO;
			strongSelf->_imgCloneWordsAvatar.image = image;
		};
		void (^postFetchBlock)(UIImage *_Nullable, NSError *_Nullable) = ^(UIImage *image, NSError *error){
			
			// The postFetchBlock is invoked LATER, possibly after downloading the avatar.
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			if (image)
			{
				strongSelf->_imgCloneCodeAvatar.image = image;
				strongSelf->_imgCloneWordsAvatar.image = image;
			}
		};
		
		ZDCFetchOptions *options = [[ZDCFetchOptions alloc] init];
		options.identityID = displayIdentity.identityID;
		
		[zdc.imageManager fetchUserAvatar: localUser
		                      withOptions: options
		                     processingID: NSStringFromClass([self class])
		                  processingBlock: processingBlock
		                    preFetchBlock: preFetchBlock
		                   postFetchBlock: postFetchBlock];
	}
	else
	{
		_imgCloneCodeAvatar.hidden = NO;
		_imgCloneWordsAvatar.hidden = NO;
		_imgCloneCodeAvatar.image = defaultUserImage;
		_imgCloneWordsAvatar.image = defaultUserImage;
	}
}


-(void)refreshCloneWordForCount:(NSUInteger)totalWords
							validWords:(NSUInteger)validWords
{
	_btnCloneWordsVerify.enabled = NO;
	
	if(totalWords == 0)
	{
		_tagView.textField.placeholder = [NSString stringWithFormat:
													 NSLocalizedString(@"Enter %ld words", @"Enter %ld words"),  requiredbip39WordCount];
	}
	else if(totalWords < requiredbip39WordCount) {
		
		_tagView.textField.placeholder = [NSString stringWithFormat:
													 NSLocalizedString(@"%ld more  words needed",@"%ld more  words needed"),
													 requiredbip39WordCount - totalWords];
	}
	else if(totalWords > requiredbip39WordCount) {
		_tagView.textField.placeholder =NSLocalizedString(@"Too many words…",@"Too many words…");
	}
	else if( validWords == requiredbip39WordCount){
		// correct number of valid  words
		_tagView.textField.placeholder  = @"";
		_btnCloneWordsVerify.enabled = YES;
	}
	
}

- (void)hideNoCamera:(BOOL)shouldHide
          completion:(dispatch_block_t)completion
{
	__weak typeof(self) weakSelf = self;

	[UIView animateWithDuration:0.1 animations:^{

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if(shouldHide)
		{
			strongSelf->_imgNoCamera.alpha = 0.0;
		}
		else
		{
			strongSelf->_imgNoCamera.alpha = 1.0;
		}
		
	} completion:^(BOOL finished) {
		if(completion)
			completion();
	}];
}

-(void)setCameraStatusString:(NSString*)string
						  isButton:(BOOL)isButton
							  color:(UIColor*)color
{
	if(isButton)
	{
		_lblStatus.hidden = YES;
		_btnStatus.hidden = NO;
		[_btnStatus setTitle:string forState:UIControlStateNormal];
		[_btnStatus.titleLabel  setTextAlignment: NSTextAlignmentCenter];
		[_btnStatus.titleLabel setTextColor:color];
	}
	else
	{
		_lblStatus.text = string;
		_lblStatus.textColor = color;
		_lblStatus.hidden = NO;
		_btnStatus.hidden = YES;
	}
}

-(void)displayInstructions:(NSString*)message withColor:(OSColor*)color forSeconds:(NSTimeInterval) seconds
{
	_btnStatus.hidden = YES;
	_lblStatus.hidden = NO;
	
	if([message isEqualToString:_lblStatus.text])
		return;
	
	NSString* savedMessage = _lblStatus.text;
	OSColor* savedColor = _lblStatus.textColor;
	
	[self setCameraStatusString:message
							 isButton:NO color:color];
	//	_lblStatus.text =  message;
	//	_lblStatus.textColor = color;
	
	CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
	pulseAnimation.duration = 0.25;
	pulseAnimation.toValue = [NSNumber numberWithFloat:1.2F];
	pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	pulseAnimation.autoreverses = YES;
	pulseAnimation.repeatCount = 1;
	[_lblStatus.layer addAnimation:pulseAnimation forKey:nil];
	
	dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC));
	dispatch_after(delay, dispatch_get_main_queue(), ^{
		
		[self setCameraStatusString:savedMessage
								 isButton:NO color:savedColor];
		
		//		_lblStatus.text =  savedMessage;
		//		_lblStatus.textColor = savedColor;
	});
}


- (void)refreshCloneCodeView
{
	ZDCLogAutoTrace();
	
	lastQRCode = nil;
	
	NSString *msg_accessDenied =
	  NSLocalizedString(@"Camera access is denied.",
	                    @"Access key scanning window");
	
	NSString *msg_notAvailableDevice =
	  NSLocalizedString(@"Camera is not available on this device.",
	                    @"Access key scanning window");
	
	NSString *msg_notAvailableSimulator =
	  NSLocalizedString(@"Camera is not available on the simulator.",
	                    @"Access key scanning window");
	
	NSString *msg_notEnabled =
	  NSLocalizedString(@"Camera access is not enabled by this application.",
	                    @"Access key scanning window");
	
	if (ZDCConstants.appHasCameraPermission)
	{
		BOOL hasCamera = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
		if (hasCamera)
		{
			// Check camera authorization status
			AVAuthorizationStatus cameraAuthStatus =
			  [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
			
			if (cameraAuthStatus == AVAuthorizationStatusAuthorized)
			{
				// camera authorized
				
				__weak typeof(self) weakSelf = self;
				[self hideNoCamera:YES completion:^{
					[weakSelf startReading];
				}];
			}
			else if (cameraAuthStatus == AVAuthorizationStatusNotDetermined)
			{
				// request authorization
				
				__weak typeof(self) weakSelf = self;
				void (^completionHandler)(BOOL) = ^(BOOL granted){
					
					__strong typeof(self) strongSelf = weakSelf;
					if(!strongSelf) return;

					if (granted)
					{
						[strongSelf hideNoCamera:YES completion:^{
							[weakSelf startReading];
						}];
					}
					else
					{
						strongSelf->_imgNoCamera.hidden = NO;
						[strongSelf setCameraStatusString: msg_accessDenied
						                         isButton:YES
													       color: strongSelf.view.tintColor];
					}
				};
				
				[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
					
					if ([NSThread isMainThread]) {
						completionHandler(granted);
					}
					else {
						dispatch_async(dispatch_get_main_queue(), ^{
							completionHandler(granted);
						});
					}
				}];
			}
			else
			{
				_imgNoCamera.hidden = NO;
				[self setCameraStatusString: msg_accessDenied
				                   isButton: YES
				                      color: self.view.tintColor];
			}
		}
		else
		{
			_imgNoCamera.hidden = NO;
			
			NSString *msg = ZDCConstants.isSimulator ? msg_notAvailableSimulator : msg_notAvailableDevice;
			[self setCameraStatusString: msg
			                   isButton: NO
			                      color: UIColor.whiteColor];
		}
	}
	else
	{
		_imgNoCamera.hidden = NO;
		
		NSString *msg = ZDCConstants.isSimulator ? msg_notAvailableSimulator : msg_notEnabled;
		[self setCameraStatusString: msg
		                   isButton: NO
		                      color: UIColor.whiteColor];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Check QRcode
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setQRCodeWithImage:(UIImage *)image
{
	__weak typeof(self) weakSelf = self;
	NSString *qrString = image.QRCodeString;
	
	BOOL isValid = [ZDCAccessCode isValidCodeString:qrString
													  forUserID:accountSetupVC.user.uuid];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if(isValid)
		{
			strongSelf->lastQRCode = qrString;
			
			strongSelf->isUsingCarmera = NO;
			[strongSelf stopReading];
			[strongSelf foundCloneString:strongSelf->lastQRCode];
		}
		else
		{
			[strongSelf displayInstructions:NSLocalizedString(@"These are not the clones I am looking for...",
																	  @"These are not the clones I am looking for...")
								 withColor:[OSColor redColor]
								forSeconds:2];
		}
	});
}


-(void) foundCloneString:(NSString*)cloneString
{
	NSError* error = NULL;
	__weak typeof(self) weakSelf = self;

	NSData* salt = [accountSetupVC.user.syncedSalt dataUsingEncoding:NSUTF8StringEncoding];

	// try and unlock it with built in code
	NSData* accessKeyData = [ZDCAccessCode accessKeyDataFromString:cloneString
																	  withPasscode:accountSetupVC.user.syncedSalt
																				 salt:salt
																				error:&error];
	
	if([error.domain isEqualToString:S4FrameworkErrorDomain]
		&& error.code == kS4Err_BadIntegrity)
	{
		// needs password
		[accountSetupVC pushUnlockCloneCode:cloneString];
	}
	else if(accessKeyData && !error)
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
		
		NSString* errorString =  error.localizedDescription;
		
		[self displayInstructions:errorString
							 withColor:UIColor.redColor
							forSeconds:2];
		
		[self startReading];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - IBActions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
	ZDCLogAutoTrace();
	
	CloneCodeViewTab newTag = (CloneCodeViewTab)item.tag;
	if (selectedTab != newTag)
	{
		[self switchViewsToTag:newTag animated:YES];
	}
}

- (void)switchViewsToTag:(CloneCodeViewTab)newTag animated:(BOOL)animated
{
	ZDCLogAutoTrace();

	for (UITabBarItem *item in _tabBar.items)
	{
		if (item.tag == newTag)
		{
			[_tabBar setSelectedItem:item];
			break;
		}
	}
	
	failCount = 0;
	
	switch (newTag)
	{
		case kCloneCodeViewTab_Words:
			currentCloneView = _vwCloneWordsInput;
			break;
			
		case kCloneCodeViewTab_QRCode:
			currentCloneView = _vwCloneCodeScan;
			break;
			
		default:
			currentCloneView = nil;
			break;
	}
	
	if (newTag != kCloneCodeViewTab_QRCode)
	{
		isUsingCarmera = NO;
		[self stopReading];
	}
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t animationsBlock = ^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		// Clear any old subviews
		for (UIView *subview in strongSelf->_vwCloneContainer.subviews) {
			[subview removeFromSuperview];
		}
		
		if (strongSelf->currentCloneView)
		{
			strongSelf->currentCloneView.frame = strongSelf->_vwCloneContainer.bounds;
			[strongSelf->_vwCloneContainer addSubview:strongSelf->currentCloneView];
		}
	};
	void (^completionBlock)(BOOL) = ^(BOOL finished){
		
		if (newTag == kCloneCodeViewTab_QRCode)
		{
			[weakSelf refreshCloneCodeView];
		}
		
	//	[self.view layoutIfNeeded]; // animate constraint change
	};
	
	if (animated)
	{
		[UIView transitionWithView: _vwCloneContainer
		                  duration: 0.2
		                   options: UIViewAnimationOptionCurveEaseInOut
		                animations: animationsBlock
		                completion: completionBlock];
	}
	else
	{
		animationsBlock();
		completionBlock(YES);
	}
	
	selectedTab  = newTag;
}


- (IBAction)cloneWordsVerifyButtonTapped:(id)sender
{
	__weak typeof(self) weakSelf = self;

	NSMutableArray* normalizedTagArray = [NSMutableArray array];
	
	for(NSString* tag in _tagView.tags)
	{
		NSArray* comps = [tag componentsSeparatedByString:@"\n"];
		NSString* normalizedTag = [[comps[0] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[normalizedTagArray addObject:normalizedTag];
	}
	
	
	if( [normalizedTagArray count] ==  requiredbip39WordCount)
	{
		ZDCLocalUser* localUser = accountSetupVC.user;
		
		NSError* error = NULL;
		
		NSData* accessKey = [BIP39Mnemonic keyFromMnemonic:normalizedTagArray
															 passphrase:localUser.syncedSalt
															 languageID:currentLanguageId
															  algorithm:Mnemonic_Storm4
																	error:&error];
		
		if(error)
		{
			NSString* failText = error.localizedDescription;
			
			if([error.domain isEqualToString:S4FrameworkErrorDomain]
				&& error.code == kS4Err_BadIntegrity)
			{
				failText = @"Recovery phrase Incorrect";
			}
			
			[accountSetupVC showError:@"Activation Failed"
									message: failText
						 completionBlock:^{
							 
							 //						  if(failCount++ >= 3)
							 //							  [accountSetupVC  pushUserOnboarding];
						 }];
			
			return;
		}
		
		[accountSetupVC unlockUserWithAccessKey:accessKey
										completionBlock:^(NSError *error)
		 {
			 __strong typeof(self) strongSelf = weakSelf;
			 if(!strongSelf) return;

			 if(error)
			 {
				 NSString* failText = error.localizedDescription;
				 
				 if([error.domain isEqualToString:S4FrameworkErrorDomain]
					 && error.code == kS4Err_CorruptData)
				 {
					 failText = @"Recovery phrase Incorrect";
					 strongSelf->failCount++;
				 }
				 else
					 strongSelf->failCount = 10;
				 
				 [strongSelf->accountSetupVC showError:@"Activation Failed"
										 message: failText
							  completionBlock:^{
								  
								  //															  if(failCount >= 3)
								  //																  [accountSetupVC  pushUserOnboarding];
							  }];
			 }
			 else
			 {
				 [strongSelf->accountSetupVC pushAccountReady ];
			 }
		 }];
		
	}
}


- (IBAction)pasteButtonTapped:(id)sender
{
	ZDCLogAutoTrace();
	UIImage *image = [[UIPasteboard generalPasteboard] image];
	if (image)
	{
		[self setQRCodeWithImage:image];
	}
	
}

-(IBAction)languageButtonTapped:(id)sender
{
	[_tagView  endEditing:YES];

	LanguageListViewController_IOS* langVC =
	[[LanguageListViewController_IOS alloc]initWithDelegate:(id<LanguageListViewController_Delegate>) self
															languageCodes:BIP39Mnemonic.availableLanguages
															  currentCode:currentLanguageId
													 shouldShowAutoPick:YES];
	
	langVC.modalPresentationStyle = UIModalPresentationPopover;
	
	UIPopoverPresentationController *popover =  langVC.popoverPresentationController;
	popover.delegate = langVC;
	
	popover.sourceView	 = _vwCloneWordsBox;
	popover.sourceRect 	= _btnLang.frame;
	
	popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
	
	[self presentViewController:langVC animated:YES completion:^{
		//		currentVC = langVC;
		//		[self refreshTitleBar];
	}];
	
}


-(void)displayCodeImportMenu:(id)sender
				 canAccessPhotos:(BOOL)canAccessPhotos
			 shouldAccessPhotos:(BOOL)shouldAccessPhotos

{
	__weak typeof(self) weakSelf = self;
	
	UIButton* btn = sender;
	
	UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Import Access Code"
																									 message:NULL
																							preferredStyle:UIAlertControllerStyleActionSheet];
	
	UIImage *photoImage = [[UIImage imageNamed:@"photos"
												 inBundle:[ZeroDarkCloud frameworkBundle]
					 compatibleWithTraitCollection:nil]  scaledToHeight:32];
	
	UIImage *documentsImage = [[UIImage imageNamed:@"files"
													  inBundle:[ZeroDarkCloud frameworkBundle]
						  compatibleWithTraitCollection:nil]  scaledToHeight:32];
	
	UIAlertAction *photoAction =
	[UIAlertAction actionWithTitle: NSLocalizedString(@"Photos", @"Photos")
									 style:UIAlertActionStyleDefault
								  handler:^(UIAlertAction *action)
	 {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if (strongSelf) {
			 [strongSelf showPhotoPicker];
		 }
	 }];
	[photoAction setValue:[photoImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
						forKey:@"image"];
	
	UIAlertAction *noPhotoAction =
	[UIAlertAction actionWithTitle: NSLocalizedString(@"Photos Access Off", @"Photos Access Off")
									 style:UIAlertActionStyleDefault
								  handler:^(UIAlertAction *action)
	{
		if (UIApplicationOpenSettingsURLString != nil)
		{
			NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
			NSDictionary *options = @{};
			[[UIApplication sharedApplication] openURL:url options:options completionHandler:nil];
		}
	}];
	
	[noPhotoAction setValue:[photoImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
						  forKey:@"image"];
	
	
	UIAlertAction *documentsAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Documents", @"Documents action")
									 style:UIAlertActionStyleDefault
								  handler:^(UIAlertAction * _Nonnull action) {
									  
									  __strong typeof(self) strongSelf = weakSelf;
									  if (strongSelf) {
										  [strongSelf showDocPicker];
									  }
									  
								  }];
	[documentsAction setValue:[documentsImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
							 forKey:@"image"];
	
	UIAlertAction *cancelAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action")
									 style:UIAlertActionStyleCancel
								  handler:^(UIAlertAction * _Nonnull action) {
									  
								  }];
	if(canAccessPhotos)
	{
		if(shouldAccessPhotos)
			[alertController addAction:photoAction];
		else
			[alertController addAction:noPhotoAction];
	}
	
	[alertController addAction:documentsAction];
	[alertController addAction:cancelAction];
	
	if(ZDCConstants.isIPad)
	{
		alertController.popoverPresentationController.sourceRect = btn.bounds;
		alertController.popoverPresentationController.sourceView = btn;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController:alertController animated:YES
						  completion:^{
						  }];
	
}

- (IBAction)photosButtonTapped:(id)sender
{
	ZDCLogAutoTrace();
	
	if(ZDCConstants.appHasPhotosPermission)
	{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			
			dispatch_async(dispatch_get_main_queue(), ^{
				
				switch (status) {
						
					case PHAuthorizationStatusAuthorized:
						[self displayCodeImportMenu:sender
										canAccessPhotos:YES
									shouldAccessPhotos:YES];
						break;
						
					case PHAuthorizationStatusRestricted:
					{
						[self displayCodeImportMenu:sender
										canAccessPhotos:YES
									shouldAccessPhotos:NO];
					}
						break;
						
					case PHAuthorizationStatusDenied:
					{
						[self displayCodeImportMenu:sender
										canAccessPhotos:YES
									shouldAccessPhotos:NO];
					}
						break;
					default:
						break;
				}
			});
			
		}];
		
	}else
	{
		[self displayCodeImportMenu:sender
						canAccessPhotos:NO
					shouldAccessPhotos:NO];
		
	}
}

- (IBAction)statusButtonTapped:(id)sender
{
	if (UIApplicationOpenSettingsURLString != nil)
	{
		NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
		NSDictionary *options = @{};
		[[UIApplication sharedApplication] openURL:url options:options completionHandler:nil];
	}
}

- (void)showPhotoPicker
{
	ZDCLogAutoTrace();
	
	photoPicker = [[UIImagePickerController alloc] init];
	photoPicker.delegate      = (id <UINavigationControllerDelegate, UIImagePickerControllerDelegate>)self;
	photoPicker.sourceType    = UIImagePickerControllerSourceTypePhotoLibrary;
	photoPicker.allowsEditing = NO;
	
	[self presentViewController:photoPicker animated:YES completion:NULL];
	
}

- (void)showDocPicker
{
	ZDCLogAutoTrace();
	docPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ (__bridge NSString *)kUTTypeImage]
																							 inMode:UIDocumentPickerModeImport];
	
	docPicker.delegate = (id <UIDocumentPickerDelegate>) self;
	[self presentViewController:docPicker animated:YES completion:NULL];
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIDocumentPickerViewControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)documentPicker:(UIDocumentPickerViewController *)documentPicker didPickDocumentAtURL:(NSURL *)url
{
	ZDCLogAutoTrace();
	
	if (url)
	{
		UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:url]];
		
		[self setQRCodeWithImage:image];
		
	}
	
	docPicker = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
	ZDCLogAutoTrace();
	
	docPicker = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIImagePickerControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)sender
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;
	
	[self dismissViewControllerAnimated:YES completion:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if (strongSelf->photoPicker == sender) {
			strongSelf->photoPicker = nil;
		}
	}];
}

- (void)imagePickerController:(UIImagePickerController *)sender didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;

	UIImage *image = nil;
	NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
	
	if (UTTypeConformsTo((__bridge CFStringRef)mediaType, kUTTypeImage))
	{
		image = [info objectForKey:UIImagePickerControllerOriginalImage];
	}
	
	[self dismissViewControllerAnimated:YES  completion:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if (strongSelf->photoPicker == sender) {
			strongSelf->photoPicker = nil;
		}
		
		if (image)
		{
			[strongSelf setQRCodeWithImage:image];
			
		}
	}];
}



- (void)startReading
{
	NSError *error;
	
	isReading  = YES;
	
	
	// Get an instance of the AVCaptureDevice class to initialize a device object and provide the video
	// as the media type parameter.
	AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	
	// Get an instance of the AVCaptureDeviceInput class using the previous device object.
	AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
	
	if(error)
	{
		//		[S4IOSSettingsManager displayCameraAccessSettingsAlert];
		return;
	}
	
	// Initialize the captureSession object.
	captureSession = [[AVCaptureSession alloc] init];
	// Set the input device on the capture session.
	[captureSession addInput:input];
	
	
	// Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
	AVCaptureMetadataOutput *captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
	[captureSession addOutput:captureMetadataOutput];
	
	// Create a new serial dispatch queue.
	//    dispatch_queue_t dispatchQueue;
	//    dispatchQueue = dispatch_queue_create("myQueue", NULL);
	[captureMetadataOutput setMetadataObjectsDelegate:(id<AVCaptureMetadataOutputObjectsDelegate>)self
															  queue:dispatch_get_main_queue()];
	[captureMetadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:AVMetadataObjectTypeQRCode]];
	
	// Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
	videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
	[videoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
	[videoPreviewLayer setFrame:_viewPreview.layer.bounds];
	[_viewPreview.layer addSublayer:videoPreviewLayer];
	_viewPreview.layer.cornerRadius    = 8.0f;
	_viewPreview.layer.masksToBounds    = YES;
	
	// Add the view to draw the bounding box for the UIView
	_boundingBox = [[SCShapeView alloc] initWithFrame:_viewPreview.bounds];
	_boundingBox.backgroundColor = [UIColor clearColor];
	_boundingBox.hidden = YES;
	[_viewPreview addSubview:_boundingBox];
	
	//
	_overlayView = [[QRcodeView alloc] initWithFrame:_viewPreview.bounds];
	_overlayView.backgroundColor = [UIColor clearColor];
	_overlayView.portalRect = _portalPlaceholderView.frame;
	_overlayView.hidden = NO;
	[_viewPreview addSubview:_overlayView];
	
	// Start video capture.
	[captureSession startRunning];
	//
	//	_btnStatus.hidden = YES;
	//	_lblStatus.text = NSLocalizedString(@"Place the code in the center of the screen. It will be scanned automatically.", @"Place the code in the center of the screen. It will be scanned automatically.");
	//	_lblStatus.hidden = NO;
	
	[self setCameraStatusString:@"Place the code in the center of the screen. It will be scanned automatically."
							 isButton:NO
								 color:UIColor.whiteColor];
	
	isUsingCarmera = YES;
}


-(void)stopReading{
	
	if(captureSession)
	{
		// Stop video capture and make the capture session object nil.
		[captureSession stopRunning];
		captureSession = nil;
	}
	
	// Remove the video preview layer from the viewPreview view's layer.
	if(videoPreviewLayer)
		[videoPreviewLayer removeFromSuperlayer];
}

- (void)startOverlayHideTimer
{
	// Cancel it if we're already running
	if(_boxHideTimer) {
		[_boxHideTimer invalidate];
	}
	
	// Restart it to hide the overlay when it fires
	_boxHideTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
																	 target:self
																  selector:@selector(foundQRCodeInOverlay:)
																  userInfo:nil
																	repeats:NO];
}



- (void)foundQRCodeInOverlay:(id)sender
{
	__weak typeof(self) weakSelf = self;
	

	// Hide the box and remove the decoded text
	_boundingBox.hidden = YES;
	
	if (lastQRCode)
	{
		BOOL isValid = [ZDCAccessCode isValidCodeString:lastQRCode
														  forUserID:accountSetupVC.user.uuid];
		if (isValid)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
			
				__strong typeof(self) strongSelf = weakSelf;
				if(!strongSelf) return;

				[strongSelf foundCloneString:strongSelf->lastQRCode];
			});
		}
	}
}


- (NSArray *)translatePoints:(NSArray *)points fromView:(UIView *)fromView toView:(UIView *)toView
{
	NSMutableArray *translatedPoints = [NSMutableArray new];
	
	// The points are provided in a dictionary with keys X and Y
	for (NSDictionary *point in points) {
		// Let's turn them into CGPoints
		CGPoint pointValue = CGPointMake([point[@"X"] floatValue], [point[@"Y"] floatValue]);
		// Now translate from one view to the other
		CGPoint translatedPoint = [fromView convertPoint:pointValue toView:toView];
		// Box them up and add to the array
		[translatedPoints addObject:[NSValue valueWithCGPoint:translatedPoint]];
	}
	
	return [translatedPoints copy];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AVCaptureMetadataOutputObjectsDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
		 fromConnection:(AVCaptureConnection *)connection
{
	
	for (AVMetadataObject *metadata in metadataObjects)
	{
		if ([metadata.type isEqualToString:AVMetadataObjectTypeQRCode])
		{
			// Transform the meta-data coordinates to screen coords
			AVMetadataMachineReadableCodeObject *transformed
			= (AVMetadataMachineReadableCodeObject *)[videoPreviewLayer transformedMetadataObjectForMetadataObject:metadata];
			
			// Update the frame on the _boundingBox view, and show it
			_boundingBox.frame = transformed.bounds;
			_boundingBox.hidden = NO;
			
			// Now convert the corners array into CGPoints in the coordinate system
			//  of the bounding box itself
			NSArray *translatedCorners = [self translatePoints:transformed.corners
																	fromView:_viewPreview
																	  toView:_boundingBox];
			
			// Set the corners array
			_boundingBox.corners = translatedCorners;
			
			// Start the timer which will hide the overlay
			[self startOverlayHideTimer];
			
			// only do this once
			if(isReading)
			{
				BOOL isValid = [ZDCAccessCode isValidCodeString:transformed.stringValue
																  forUserID:accountSetupVC.user.uuid];
				
				if(isValid)
				{
					
					[ZDCSound playBeepSound];
					
					// Update the view with the decoded text
					
					[self displayInstructions:NSLocalizedString(@"key found",
																			  @"key found")
										 withColor:[OSColor greenColor]
										forSeconds:2];
					
					
					lastQRCode = transformed.stringValue;
					
					// stop capture
					isUsingCarmera = NO;
					[self stopReading];
				}
				else
				{
					[self displayInstructions:NSLocalizedString(@"These are not the clones I am looking for...",
																			  @"These are not the clones I am looking for...")
										 withColor:[OSColor redColor]
										forSeconds:2];
					
				}
			}
		}
	}
}

#pragma mark - RKTagsViewDelegate

- (NSString *)languageForString:(NSString *) text{
	
	NSString* langString = (NSString *) CFBridgingRelease(CFStringTokenizerCopyBestStringLanguage((CFStringRef)text, CFRangeMake(0, text.length)));
	
	return langString;
}

-(void)updateTagsToLanguageID:(NSString*)newLangID
{
	
	currentLanguageId = newLangID;
	bip39Words = [NSSet setWithArray:[BIP39Mnemonic wordListForLanguageID:currentLanguageId
																						 error:nil]];
	NSMutableArray* newTagArray = [NSMutableArray array];
	
	for(NSString* tag in _tagView.tags)
	{
		NSString* newTag = nil;
		
		NSArray* comps = [tag componentsSeparatedByString:@"\n"];
		NSString* normalizedTag = [[comps[0] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if(normalizedTag.length == 0) continue;
		
		if([bip39Words containsObject: normalizedTag ])
		{
			newTag = normalizedTag;
		}
		else if( normalizedTag.length >4)
		{
			normalizedTag = [normalizedTag substringWithRange:NSMakeRange(0, 4)];
		}
		
		NSString* mnemonic = [BIP39Mnemonic matchingMnemonicForString:normalizedTag
																			languageID:currentLanguageId
																				  error:nil];
		if(mnemonic.length > 0)
		{
			newTag = mnemonic;
		}
		
		if(newTag == nil)
		{
			newTag = [NSString stringWithFormat:@"%@%@",normalizedTag, kRKTagsColorSuffix_Red];
		}
		
		[newTagArray addObject:newTag];
		
	}
	
	[_tagView removeAllTags];
	
	for(NSString* tag in newTagArray)
		[_tagView addTag:tag];
	
}

- (void)tagsViewDidChange:(RKTagsView *)tagsView
{
	NSMutableArray* newTagArray = [NSMutableArray array];
	NSUInteger bip39WordCount = 0;
	
	if(autoPickLanguage)
	{
		// Attempt to auto pick language
		
		NSString* str = [_tagView.tags componentsJoinedByString:@" "];
		NSString* lang = [self languageForString:str];
		if(lang)
		{
			NSLocale *newLocale = [NSLocale localeWithLocaleIdentifier:lang];
			if(newLocale)
			{
				NSString* newLangID = [BIP39Mnemonic languageIDForlocaleIdentifier: newLocale.localeIdentifier];
				if(newLangID && ![newLangID isEqualToString:currentLanguageId])
				{
					[self updateTagsToLanguageID:newLangID];
				}
			}
		}
	}
	
	for(NSString* tag in _tagView.tags)
	{
		NSString* newTag = nil;
		
		NSArray* comps = [tag componentsSeparatedByString:@"\n"];
		NSString* normalizedTag = [[comps[0] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if(normalizedTag.length == 0) continue;
		
		if([bip39Words containsObject: normalizedTag ])
		{
			newTag = normalizedTag;
		}
		
		NSString* mnemonic = [BIP39Mnemonic matchingMnemonicForString:normalizedTag
																			languageID:currentLanguageId
																				  error:nil];
		if(mnemonic.length > 0)
		{
			newTag = mnemonic;
		}
		
		if(newTag == nil)
		{
			newTag = [NSString stringWithFormat:@"%@%@",normalizedTag, kRKTagsColorSuffix_Red];
		}
		else
		{
			bip39WordCount = bip39WordCount+1;
		}
		[newTagArray addObject:newTag];
		
	}
	[_tagView removeAllTags];
	
	for(NSString* tag in newTagArray)
		[_tagView addTag:tag];
	
	[self refreshCloneWordForCount:newTagArray.count
							  validWords:bip39WordCount];
}

- (BOOL)tagsView:(RKTagsView *)tagsView shouldAddTagWithText:(NSString *)text
{
	BOOL shouldAddTag = YES;
	return shouldAddTag;
}

- (void)tagsViewDidGetNewline:(RKTagsView *)tagsView
{
	if(_btnCloneWordsVerify.enabled)
	{
		[self cloneWordsVerifyButtonTapped:self];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Keyboard Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
	CGPoint containerPoint = [_vwCloneContainer convertPoint:locationPoint fromView:self.view];
	
	if (![_vwCloneContainer pointInside:containerPoint withEvent:event])
	{
		[super touchesBegan:touches withEvent:event];
	}
	else
	{
		if (currentCloneView == _vwCloneWordsInput)
		{
			if(!CGRectContainsPoint(_tagView.frame, containerPoint))
			{
				[_tagView  endEditing:YES];
				
			}
		}
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

		 strongSelf->_containerViewBottomConstraint.constant =  (keyboardHeight + 8);
		 [self.view layoutIfNeeded]; // animate constraint change
		 strongSelf->currentCloneView.frame = strongSelf->_vwCloneContainer.bounds;
		 
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

	_containerViewBottomConstraint.constant = originalContainerViewBottomConstraint;
	[self.view layoutIfNeeded]; // animate constraint change
	
	[UIView animateWithDuration:animationDuration
								 delay:0.1
							  options:AnimationOptionsFromCurve(animationCurve)
						  animations:
	 ^{
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

		 strongSelf->currentCloneView.frame = strongSelf->_vwCloneContainer.bounds;
		 
	 } completion:^(BOOL finished) {
		 
		 // Nothing to do
	 }];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - LanguageListViewController_Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
					  didSelectLanguage:(NSString* __nullable) languageID
{
	if ([languageID isEqualToString:kLanguageListAutoDetect])
	{
		autoPickLanguage = YES;
		[self tagsViewDidChange:_tagView];
	}
	else
	{
		autoPickLanguage = NO;
		currentLanguageId = languageID;
		[self updateTagsToLanguageID:currentLanguageId];
		[self tagsViewDidChange:_tagView];
	}
}

@end
