
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "CloneDeviceViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

#import "ZDCAccessCode.h"
#import "LanguageListViewController_IOS.h"

// Categories
#import "ZDCLogging.h"
#import "OSImage+QRCode.h"
#import "RKTagsView.h"
#import "OSImage+ZeroDark.h"
#import "NSString+ZeroDark.h"
#import "UIImageViewPasteable.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)



@implementation CloneDeviceViewController_IOS
{
	UIBarButtonItem* 				globeBbn;
	
	IBOutlet __weak UIView*						_vwQRCodeBorder;
	IBOutlet __weak UIImageViewPasteable*	_imgQRCode;

	IBOutlet __weak RKTagsView  *       	_tagView;
	IBOutlet __weak NSLayoutConstraint *	_tagViewHeightConstraint;

	UISwipeGestureRecognizer 				*swipeRight;
	
	UIImage*					   				defaultQRcodeImage;
	NSString*              		   		qrCodeString;

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
	
	_vwQRCodeBorder.layer.cornerRadius   = 8;
	_vwQRCodeBorder.layer.masksToBounds  = YES;
	_vwQRCodeBorder.layer.borderColor    = self.view.tintColor.CGColor;
	_vwQRCodeBorder.layer.borderWidth    = 1.0f;
	
	_imgQRCode.canCopy = YES;
	_imgQRCode.canPaste = NO;
	
	defaultQRcodeImage  = [UIImage imageNamed:@"qrcode-default"
												inBundle:[ZeroDarkCloud frameworkBundle]
					compatibleWithTraitCollection:nil];

}




-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	self.navigationItem.title = @"Setup on another device";

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

	[self refreshView];

}
-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
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



-(void) refreshView
{
	__weak typeof(self) weakSelf = self;
	NSError* error = nil;

	P2K_Algorithm p2kAlgorithm = kP2K_Algorithm_Argon2i;
	NSString* qrCodeString = [self.keyBackupVC accessKeyStringWithPasscode:keyBackupVC.user.syncedSalt
																 p2kAlgorithm:p2kAlgorithm
																		  error:&error];

	NSArray<NSString*> * wordList = [BIP39Mnemonic mnemonicFromKey:keyBackupVC.accessKeyData
																		 passphrase:keyBackupVC.user.syncedSalt
																		 languageID:keyBackupVC.currentLanguageId
																				error:&error];

	
	[_tagView removeAllTags];
	
	for(NSString* tag in wordList)
		[_tagView addTag:tag];
	
	
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


#pragma mark - LanguageListViewController_Delegate

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
					  didSelectLanguage:(NSString* __nullable) languageID
{
	keyBackupVC.currentLanguageId = languageID;
	[self refreshView];
	
}


@end
