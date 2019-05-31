/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "IntroViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "UIButton+Activation.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int ddLogLevel = DDLogLevelVerbose;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)


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
	DDLogAutoTrace();
}



- (IBAction)SignInButtonClicked:(id)sender
{
	DDLogAutoTrace();

 	self.accountSetupVC.setupMode = AccountSetupMode_ExistingAccount;

 	[self.accountSetupVC pushIdentity];
}


- (IBAction)StartTrialButtonClicked:(id)sender
{
	DDLogAutoTrace();

	self.accountSetupVC.setupMode = AccountSetupMode_Trial;

	[self.accountSetupVC pushIdentity];
}


@end
