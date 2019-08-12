/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "AccountCloneScanController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCUserAccessKeyManager.h"
#import "ZDCAccessCode.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCSound.h"

#import "LanguageListViewController_IOS.h"

#import "SCShapeView.h"
#import "QRcodeView.h"
#import "RKTagsView.h"

#import "ZDCLogging.h"

// Categories
#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"
#import "UIButton+Activation.h"
#import "NSError+S4.h"

// Libraries
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

@import CoreImage;
@import ImageIO;


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
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
	BOOL                hasCamera;
	
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
	YapDatabaseConnection 	*databaseConnection;
	Auth0ProviderManager	*providerManager;
	ZDCUserAccessKeyManager *accessKeyManager;
	ZDCImageManager         *imageManager;
	
	BOOL                    isUsingCarmera;
	
}

@synthesize accountSetupVC = accountSetupVC;

- (void)viewDidLoad {
	[super viewDidLoad];
	
	
	void (^PrepContainer)(UIView *) = ^(UIView *container){
		container.layer.cornerRadius   = 16;
		container.layer.masksToBounds  = YES;
		container.layer.borderColor    = [UIColor whiteColor].CGColor;
		container.layer.borderWidth    = 1.0f;
		container.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];
	};
	PrepContainer(_vwCloneContainer);
	
	void (^TintButtonImage)(UIButton *) = ^(UIButton *button){
		
		UIImage *image = [button imageForState:UIControlStateNormal];
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		
		[button setImage:image forState: UIControlStateNormal];
		button.tintColor = [UIColor whiteColor];
	};
	
	TintButtonImage(_btnPaste);
	TintButtonImage(_btnPhoto);
	
	[_btnCloneWordsVerify setup];
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
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(databaseConnectionDidUpdate:)
																name:UIDatabaseConnectionDidUpdateNotification
															 object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(applicationDidResignActiveNotification)
																name:UIApplicationWillResignActiveNotification
															 object:NULL];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(applicationDidBecomeActiveNotification)
																name:UIApplicationDidBecomeActiveNotification
															 object:NULL];
	
	originalContainerViewBottomConstraint  = CGFLOAT_MAX;
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	databaseConnection = accountSetupVC.owner.databaseManager.uiDatabaseConnection;
	providerManager = accountSetupVC.owner.auth0ProviderManager;
	accessKeyManager = accountSetupVC.owner.userAccessKeyManager;
	imageManager = accountSetupVC.owner.imageManager;
	
	defaultUserImage = imageManager.defaultUserAvatar;
	_imgCloneCodeAvatar.image = defaultUserImage;
	_imgCloneWordsAvatar.image = defaultUserImage;

	[[UITabBar appearance] setTintColor:[UIColor whiteColor ]];
	[[UITabBar appearance] setBarTintColor:[UIColor clearColor]];
	
	
	if(originalContainerViewBottomConstraint == CGFLOAT_MAX)
		originalContainerViewBottomConstraint = _containerViewBottomConstraint.constant;
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillShow:)
																name:UIKeyboardWillShowNotification
															 object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillHide:)
																name:UIKeyboardWillHideNotification
															 object:nil];
	
	
	accountSetupVC.btnBack.hidden = self.navigationController.viewControllers.count == 1;
	
	[_tagView removeAllTags];
	[self refreshCloneWordForCount:0 validWords:0];
	_btnCloneWordsVerify.enabled  = NO;
	
	
	_btnStatus.hidden = YES;
	
	[self setCameraStatusString:NSLocalizedString(@"Checking camera access…",
																 @"Checking camera access…")
							 isButton:NO
								 color:UIColor.whiteColor];
	
	[self refreshView];
	
	_imgNoCamera.hidden = YES;
	[self switchViewsToTag: kCloneCodeViewTab_QRCode];
	
}

-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	
	BOOL canPaste = [[UIPasteboard generalPasteboard] image] != nil;
	_btnPaste.enabled = canPaste;
	
	[accountSetupVC setHelpButtonHidden:NO];
	accountSetupVC.btnBack.hidden = YES;  // cant go back from here
	
}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	isUsingCarmera = NO;
	[self stopReading];
	
	[[UITabBar appearance] setTintColor:nil];
	[[UITabBar appearance] setBarTintColor:nil];
	
}


- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return (self.navigationController.viewControllers.count > 1);
	
}


- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}



- (void)applicationDidResignActiveNotification
{
	[self stopReading];
	
}

- (void)applicationDidBecomeActiveNotification
{
	if(isUsingCarmera)
		[self startReading];
}



- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	[self refreshView];
	
}



-(void)refreshView
{
	__weak typeof(self) weakSelf = self;
	
	__block ZDCLocalUser *user = NULL;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:accountSetupVC.user.uuid inCollection:kZDCCollection_Users];
	}];
#pragma clang diagnostic pop
	

	if(!user)return;
	
	NSString* displayName = user.displayName;
	
	_lblCloneCodeDisplayName.text = displayName;
	_lblCloneCodeDisplayName.hidden = NO;
	
	_lblCloneWordsDisplayName.text = displayName;
	_lblCloneWordsDisplayName.hidden = NO;
	
	NSString* auth0ID = user.auth0_preferredID;
	NSArray* comps = [auth0ID componentsSeparatedByString:@"|"];
	NSString* provider = comps.firstObject;
	
	NSURL *pictureURL = nil;
	NSString* picture  = [Auth0ProviderManager correctPictureForAuth0ID:auth0ID
																			  profileData:user.auth0_profiles[auth0ID]
																					 region:user.aws_region
																					 bucket:user.aws_bucket];
	if(picture)
		pictureURL = [NSURL URLWithString:picture];
	
	OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:provider] scaledToHeight:_imgCloneWordsProvider.frame.size.height];
	
	if(providerImage)
	{
		_imgCloneCodeProvider.hidden = NO;
		_imgCloneCodeProvider.image = providerImage;
		_lblCloneWordsProvider.hidden = YES;
		
		_imgCloneWordsProvider.hidden = NO;
		_imgCloneWordsProvider.image = providerImage;
		_lblCloneCodeProvider.hidden = YES;
		
	}
	else
	{
		_imgCloneCodeProvider.hidden = YES;
		_lblCloneWordsProvider.text = provider;
		_lblCloneWordsProvider.hidden = NO;
		
		_imgCloneCodeProvider.hidden = YES;
		_lblCloneCodeProvider.text = provider;
		_lblCloneCodeProvider.hidden = NO;
	}
	
	if(pictureURL)
	{
		CGSize avatarSize = _imgCloneWordsAvatar.frame.size;
		[imageManager fetchUserAvatar: user.uuid
									 auth0ID: auth0ID
									 fromURL: pictureURL
									 options: nil
							  processingID: pictureURL.absoluteString
						  processingBlock:^UIImage * _Nonnull(UIImage * _Nonnull image)
		 {
			 return [image imageWithMaxSize: avatarSize];
		 }
							 preFetchBlock:^(UIImage * _Nullable image)
		 {
			 __strong typeof(self) strongSelf = weakSelf;
			 if(strongSelf == nil) return;
			 
			 if(image)
			 {
				 strongSelf->_imgCloneCodeAvatar.hidden = NO;
				 strongSelf->_imgCloneWordsAvatar.hidden = NO;
				 strongSelf->_imgCloneCodeAvatar.image = image;
				 strongSelf->_imgCloneWordsAvatar.image = image;
			 }
			 
		 }            postFetchBlock:^(UIImage * _Nullable image, NSError * _Nullable error)
		 {
			 
			 __strong typeof(self) strongSelf = weakSelf;
			 if(strongSelf == nil) return;
			 
			 strongSelf->_imgCloneCodeAvatar.hidden = NO;
			 strongSelf->_imgCloneWordsAvatar.hidden = NO;
			 
			 if(!image)
			 {
				 image = strongSelf->defaultUserImage;
			 }
			 strongSelf->_imgCloneCodeAvatar.image = image;
			 strongSelf->_imgCloneWordsAvatar.image = image;
		 }];
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


-(void)hideNoCamera:(BOOL)shouldHide
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


-(void) refreshCloneCodeView
{
	__weak typeof(self) weakSelf = self;
	lastQRCode = NULL;
	
	if(ZDCConstants.appHasCameraPermission)
	{
		hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];
		
		if(hasCamera)
		{
			// check camera authorization status
			AVAuthorizationStatus cameraAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
			
			switch (cameraAuthStatus) {
					
				case AVAuthorizationStatusAuthorized: { // camera authorized
					
					[self hideNoCamera:YES completion:^{
						[self startReading];
					}];
				}
					break;
					
				case AVAuthorizationStatusNotDetermined: { // request authorization
					
					[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
						dispatch_async(dispatch_get_main_queue(), ^{
							
							__strong typeof(self) strongSelf = weakSelf;
							if(!strongSelf) return;

							if(granted) {
								[strongSelf hideNoCamera:YES completion:^{
									[strongSelf startReading];
								}];
								
							} else {
								
								strongSelf->_imgNoCamera.hidden = NO;
								
								[strongSelf setCameraStatusString:NSLocalizedString(@"Camera access is denied.",
																							 @"camera access is denied")
														 isButton:YES
															 color:strongSelf.view.tintColor];
							}
						});
					}];
				}
					break;
					
				default:
				{
					
					_imgNoCamera.hidden = NO;
					[self setCameraStatusString:NSLocalizedString(@"Camera access is denied.",
																				 @"camera access is denied")
											 isButton:YES
												 color:UIColor.whiteColor];
					
				}
			}
		}
		else
		{
			_imgNoCamera.hidden = NO;
			
			NSString* message =   NSLocalizedString(@"Camera is not available on this device.",
																 @"Camera is not available on this device");
			if(ZDCConstants.isSimulator)
				message = NSLocalizedString(@"Camera is not available on the simulator.",
													 @"Camera is not available on the simulator");
			
			[self setCameraStatusString: message
									 isButton:NO
										 color:UIColor.whiteColor];
			
			
		}
	}
	else
	{
		_imgNoCamera.hidden = NO;
		[self setCameraStatusString:NSLocalizedString(@"Camera access is not enabled by this application.",
																	 @"camera access is not enabled by this application")
								 isButton:NO
									 color:UIColor.whiteColor];
	}
}


#pragma  mark - check QRcode


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
	CloneCodeViewTab newTag = (CloneCodeViewTab)item.tag;
	
	if(selectedTab != newTag)
	{
		[self switchViewsToTag: newTag];
	}
}


-(void) switchViewsToTag:(CloneCodeViewTab)newTag
{
	__weak typeof(self) weakSelf = self;

	for(UITabBarItem *item in  _tabBar.items)
	{
		if(item.tag == newTag)
		{
			[_tabBar setSelectedItem:item];
			break;
		}
	}
	
	switch (newTag)
	{
		case kCloneCodeViewTab_Words:
			[_tagView removeAllTags];
			[self refreshCloneWordForCount:0 validWords:0];
			_btnCloneWordsVerify.enabled  = NO;
			failCount = 0;
			isUsingCarmera = NO;
			[self stopReading];
			break;
			
		case kCloneCodeViewTab_QRCode:
			
			// delay this till view is up
			//		[self refreshCloneCodeView];
			
			break;
			
		default:
			currentCloneView = NULL;
			break;
	}
	
	
	[UIView transitionWithView:_vwCloneContainer
							duration:.2
							 options:UIViewAnimationOptionCurveEaseInOut
						 animations:^
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

		 // clear any old subviews
		 for (UIView *subview in strongSelf->_vwCloneContainer.subviews)
			 [subview removeFromSuperview];
		 
		 switch (newTag)
		 {
			 case kCloneCodeViewTab_Words:
				 strongSelf->_vwCloneWordsInput.frame = strongSelf->_vwCloneContainer.bounds;
				 [strongSelf->_vwCloneContainer  addSubview:strongSelf->_vwCloneWordsInput];
				 strongSelf->currentCloneView = strongSelf->_vwCloneWordsInput;
				 break;
				 
			 case kCloneCodeViewTab_QRCode:
				 strongSelf->_vwCloneCodeScan.frame = strongSelf->_vwCloneContainer.bounds;
				 [strongSelf->_vwCloneContainer  addSubview:strongSelf->_vwCloneCodeScan];
				 strongSelf->currentCloneView = strongSelf->_vwCloneCodeScan;
				 
				 break;
				 
			 default:
				 strongSelf->currentCloneView = NULL;
				 break;
		 }
		 
		 
	 }completion:^(BOOL finished) {
		 
		 if(newTag == kCloneCodeViewTab_QRCode)
		 {
			 [self refreshCloneCodeView];
		 }
		 
		 
		 //		 [self.view layoutIfNeeded]; // animate constraint change
	 }];
	
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
			 [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
			 
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
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
		
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


#pragma mark - Keyboard show/Hide Notifications


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
		if(currentCloneView == _vwCloneWordsInput)
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

#pragma mark - LanguageListViewController_Delegate

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
					  didSelectLanguage:(NSString* __nullable) languageID
{
	if([languageID isEqualToString:kLanguageListAutoDetect])
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
