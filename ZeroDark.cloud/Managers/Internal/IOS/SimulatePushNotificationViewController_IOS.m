/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "SimulatePushNotificationViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"

#import "ZDCLogging.h"

// Categories

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

@implementation SimulatePushNotificationViewController_IOS {
	
	IBOutlet __weak UIButton                *_btnSimPush;
	IBOutlet __weak UIActivityIndicatorView *_activityIndicator;
	
	ZeroDarkCloud *zdc;
}

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
{
	self = [super initWithNibName: @"SimulatePushNotificationViewController_IOS"
	                       bundle: [ZeroDarkCloud frameworkBundle]];
 	if (self)
	{
		zdc = inOwner;
 	}
	return self;
}

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
	[super viewDidLoad];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(syncStatusChanged:)
	                                             name: ZDCSyncStatusChangedNotification
	                                           object: nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Pull/Push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)syncStatusChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();

	BOOL isSyncing = [zdc.syncManager isPullingOrPushingChangesForAnyLocalUser];
	if (isSyncing) {
		[_activityIndicator startAnimating];
		_btnSimPush.enabled = NO;
	} else {
		[_activityIndicator stopAnimating];
		_btnSimPush.enabled = YES;
	}
}

- (IBAction)didHitSimulatePush:(id)sender
{
	[zdc.syncManager pullChangesForAllLocalUsers];
}
 
 
@end
