
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "BackupSuccessViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

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



@implementation BackupSuccessViewController_IOS
{
    IBOutlet  __weak UIButton   *            _btnDone;
    
	UISwipeGestureRecognizer 				*swipeRight;
}


@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

    
    _btnDone.layer.cornerRadius    = 8.0f;
    _btnDone.layer.masksToBounds    = YES;
    _btnDone.layer.borderWidth      = 1.0f;
    _btnDone.layer.borderColor      = self.view.tintColor.CGColor;

}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	self.navigationItem.title = @"Access Key Backup Successful";

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
 
	[self refreshView];

}
-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
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

#pragma mark - Actions
- (IBAction)DoneButtonTapped:(id)sender
{
    [keyBackupVC handleDone];
}

@end
