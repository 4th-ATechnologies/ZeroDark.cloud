/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "IntroViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "UIButton+Activation.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation IntroViewController_IOS
{
	IBOutlet __weak UIButton       *btnStartTrial;
	IBOutlet __weak UIButton       *btnSignIn;
	IBOutlet __weak UIView        *containerView;
}

@synthesize accountSetupVC = accountSetupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

	[btnStartTrial setup];
	[btnSignIn setup];
}
-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	accountSetupVC.btnBack.hidden = YES;
	[accountSetupVC setHelpButtonHidden:YES];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)TESTButtonClicked:(id)sender
{
	ZDCLogAutoTrace();
}



- (IBAction)SignInButtonClicked:(id)sender
{
	ZDCLogAutoTrace();

 	self.accountSetupVC.setupMode = AccountSetupMode_ExistingAccount;

 	[self.accountSetupVC pushIdentity];
}


- (IBAction)StartTrialButtonClicked:(id)sender
{
	ZDCLogAutoTrace();

	self.accountSetupVC.setupMode = AccountSetupMode_Trial;

	[self.accountSetupVC pushIdentity];
}


@end
