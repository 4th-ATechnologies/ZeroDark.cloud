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
	IBOutlet __weak UILabel  * titleLabel;
	IBOutlet __weak UIButton * btnSignIn;
	IBOutlet __weak UIButton * btnCreateAccount;
}

@synthesize accountSetupVC = accountSetupVC;

- (void)viewDidLoad
{
	[super viewDidLoad];

	[btnSignIn zdc_colorize];
	[btnCreateAccount zdc_colorize];
	
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
	titleLabel.text = appName ?: @"";
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	accountSetupVC.btnBack.hidden = YES;
	[accountSetupVC setHelpButtonHidden:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)signInButtonAction:(id)sender
{
	ZDCLogAutoTrace();

 	self.accountSetupVC.setupMode = AccountSetupMode_ExistingAccount;
 	[self.accountSetupVC pushIdentity];
}


- (IBAction)createAccountButtonAction:(id)sender
{
	ZDCLogAutoTrace();

	self.accountSetupVC.setupMode = AccountSetupMode_Trial;
	[self.accountSetupVC pushIdentity];
}

@end
