
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "BackupAsTextViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

#import "LanguageListViewController_IOS.h"
#import "RKTagsView.h"

// Categories
#import "OSImage+ZeroDark.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)



@implementation BackupAsTextViewController_IOS
{
	UIBarButtonItem* 				globeBbn;

	IBOutlet __weak RKTagsView  *       _tagView;
	IBOutlet __weak NSLayoutConstraint *_tagViewHeightConstraint;

	IBOutlet __weak UIBarButtonItem  	*_bbnNext;
	IBOutlet __weak UIBarButtonItem  	*_bbnAction;

	UISwipeGestureRecognizer 				*swipeLeft;
	UISwipeGestureRecognizer 				*swipeRight;

	YapDatabaseConnection *         databaseConnection;
}

@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

	_tagView.lineSpacing = 4;
	_tagView.interitemSpacing = 4;
	_tagView.allowCopy = NO;

	_tagView.layer.cornerRadius   = 8;
	_tagView.layer.masksToBounds  = YES;
	_tagView.layer.borderColor    = [UIColor lightGrayColor].CGColor;
	_tagView.layer.borderWidth    = 1.0f;
//	_tagView.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//


	_tagView.tagsEdgeInsets  = UIEdgeInsetsMake(8, 8, 8, 8);
//	_tagView.userInteractionEnabled = NO;
	_tagView.allowCopy = YES;
	_tagView.editable = NO;
	_tagView.selectable = NO;
	_tagView.tintAdjustmentMode =  UIViewTintAdjustmentModeNormal;
	_tagView.tintColor = UIColor.darkGrayColor;

//	_tagView.textField.placeholder = @"Enter recovery phrase…";
//	_tagView.delegate = (id <RKTagsViewDelegate>) self;
//	_tagView.textField.autocorrectionType = UITextAutocorrectionTypeNo;


}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;

	self.navigationItem.title = @"Backup as Text";

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

 	swipeLeft = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeLeft:)];
	swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft  ;
	[self.view addGestureRecognizer:swipeLeft];

	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	swipeRight.direction = UISwipeGestureRecognizerDirectionRight  ;
	[self.view addGestureRecognizer:swipeRight];

	[self refreshView];
}


-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
	[self.view removeGestureRecognizer:swipeLeft]; swipeLeft = nil;

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}
 
- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_tagViewHeightConstraint.constant = _tagView.contentSize.height;
}

-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[self handleNavigationBack:NULL];
 }

-(void)swipeLeft:(UISwipeGestureRecognizer *)gesture
{
 	[keyBackupVC pushVerifyText];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
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




- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;

}

-(IBAction)nextButtonTapped:(id)sender
{
	[keyBackupVC pushVerifyText];

}

- (IBAction)actionButtonTapped:(id)sender
{
    
    NSString* accessString = [_tagView.tags componentsJoinedByString:@" "];
    accessString =  [accessString stringByAppendingString:@" "];        // add a space at end to help with insert
    
    
      UIActivityViewController *avc = [[UIActivityViewController alloc]
                                     initWithActivityItems:@[accessString]
                                     applicationActivities:  nil  ];
    
    
    avc.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError)  {
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

-(void) refreshView
{
	NSError* error = NULL;

	NSArray<NSString*> * wordList = [BIP39Mnemonic mnemonicFromKey:keyBackupVC.accessKeyData
														passphrase:keyBackupVC.user.syncedSalt
														languageID:keyBackupVC.currentLanguageId
														 algorithm:Mnemonic_Storm4
															 error:&error];
	if(error)
	{
	// return
	}

	[_tagView removeAllTags];

	for(NSString* tag in wordList)
		[_tagView addTag:tag];

}


#pragma mark - LanguageListViewController_Delegate

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
				 didSelectLanguage:(NSString* __nullable) languageID
{
	keyBackupVC.currentLanguageId = languageID;
	[self refreshView];

}

@end
