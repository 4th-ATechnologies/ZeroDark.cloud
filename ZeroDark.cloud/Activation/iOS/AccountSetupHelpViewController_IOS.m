/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "AccountSetupHelpViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"

#import "ZDCLogging.h"

// Libraries
#import <MessageUI/MessageUI.h>

// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@implementation AccountSetupHelpViewController_IOS
{
	IBOutlet __weak UIActivityIndicatorView *actProgress;
	IBOutlet __weak UILabel            *lblTitle;
	IBOutlet __weak UIWebView          *webSupportView;

	IBOutlet __weak UIBarButtonItem   *bbtnBack;
	IBOutlet __weak UIBarButtonItem   *bbtnFwd;

	NSURL           *supportURL;
	NSURL*          loadingProgressURL;
	BOOL        didFirstLoad;

	NSTimer *       showWaitBoxTimer;

}

@synthesize accountSetupVC = accountSetupVC;
@synthesize helpTag = helpTag;

- (void)viewDidLoad {
	[super viewDidLoad];


	void (^PrepContainer)(UIView *) = ^(UIView *container){
		//        container.layer.cornerRadius   = 16;
		//        container.layer.masksToBounds  = YES;
		container.layer.borderColor    = [UIColor whiteColor].CGColor;
		container.layer.borderWidth    = 1.0f;
	};
	PrepContainer(webSupportView);

	[self removeWebProgress];

	loadingProgressURL = [[NSBundle mainBundle] URLForResource:@"SupportHelpViewLoading" withExtension:@"html"];

	webSupportView.delegate = ( id <UIWebViewDelegate> ) self;
}


-(void)viewDidAppear:(BOOL)animated

{
	[super viewDidAppear:animated];
	accountSetupVC.btnBack.hidden = NO;
	[accountSetupVC setHelpButtonHidden:YES];

	//   didFirstLoad = NO;

	NSURL *url = [self supportURLForTag:helpTag];

	bbtnBack.enabled = NO;
	bbtnFwd.enabled = NO;

	[webSupportView loadRequest:[NSURLRequest requestWithURL:url]];

}

-(void)viewWillDisappear:(BOOL)animated

{
	[super viewWillDisappear:animated];
	[accountSetupVC setHelpButtonHidden:NO];

}

/////// redo this

/*

 -(NSData*) makeAppSupportData
 {
 NSData* data = nil;

 NSBundle *main = NSBundle.mainBundle;
 NSString* versionStr = [main objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
 NSString *build   = [main objectForInfoDictionaryKey: (NSString *)kCFBundleVersionKey];
 NSString* gitCommitVersion = [NSString stringWithFormat: @"%s", GIT_COMMIT_HASH];

 BOOL isDebug = [AppConstants isApsEnvironmentDevelopment];
 if(isDebug) versionStr = [versionStr stringByAppendingString:@" dev"];

 // this one incorporates the build number
 NSString* appVersion = [NSString stringWithFormat: @"%@ (%@) %@", versionStr, build, gitCommitVersion];

 NSString* dateString = [NSString stringWithFormat: @"%s", BUILD_DATE];
 NSString* xcodeVersion = [main objectForInfoDictionaryKey: @"DTXcode"];
 NSString* xcodeBuild = [main objectForInfoDictionaryKey: @"DTXcodeBuild"];
 NSString* xcodeString = [NSString stringWithFormat: @"%@ (%@)", xcodeVersion, xcodeBuild];

 char s4_version_string[256];
 S4_GetVersionString(s4_version_string);
 NSString* s4VersionString = [NSString stringWithFormat: @"%s", s4_version_string];

 #if TARGET_OS_IPHONE
 NSInteger iosSDK = __IPHONE_OS_VERSION_MAX_ALLOWED;
 NSInteger iosSDKMajor = iosSDK / 10000;
 NSInteger iOSSDKMinor = (iosSDK / 100) % 100;
 NSInteger iosSDKRevision = iosSDK % 100;
 NSString *iOSSDKBuild = [main objectForInfoDictionaryKey: @"DTSDKBuild"];

 NSString *iosSDKVersion = iosSDKRevision ?
 [NSString stringWithFormat: @"%ld.%ld.%ld", (long)iosSDKMajor, (long)iOSSDKMinor, (long)iosSDKRevision]
 : [NSString stringWithFormat: @"%ld.%ld", (long)iosSDKMajor, (long)iOSSDKMinor];

 NSString* IOSSDKString = [NSString stringWithFormat: @"%@ (%@)", iosSDKVersion, iOSSDKBuild];


 NSString* baseString = [NSString  stringWithFormat:
 @"Storm4 Version: %@\n"
 @"Build Date: %@\n"
 "SC Crypto Library Version: %@\n"
 "Xcode Version: %@\n"
 "IOS SDK Version:%@\n",
 appVersion,dateString, s4VersionString, xcodeString, IOSSDKString];

 #else
 //   NSString* MACOSSDKString = [NSString stringWithFormat: @"%@ (%@)", iosSDKVersion, iOSSDKBuild];
 NSString* MACOSSDKString = @"insert MacOS Info" ;


 NSString* baseString = [NSString  stringWithFormat:
 @"Storm4 Version: %@\n"
 @"Build Date: %@\n"
 "SC Crypto Library Version: %@\n"
 "Xcode Version: %@\n"
 "MacOS SDK Version:%@\n",
 appVersion,dateString, s4VersionString, xcodeString, MACOSSDKString];

 #endif


 data =  [baseString dataUsingEncoding:NSUTF8StringEncoding];
 return data;

 }
 */

- (NSURL *)storm4CustomerServiceURL
{
	return [NSURL URLWithString:@"https://support.storm4.cloud"];
}

-(NSURL*) supportURLForTag:(NSString*)helpTag
{
	NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithURL:[self storm4CustomerServiceURL] resolvingAgainstBaseURL:YES];

	NSString* os = @"";

#if TARGET_OS_IPHONE
	os = @"IOS";
#else
	os = @"MACOS";

#endif

	NSURLQueryItem *platform = [NSURLQueryItem queryItemWithName:@"platform" value:os];
	urlComponents.queryItems = @[ platform ];

	if(helpTag)
	{
		NSURLQueryItem *pageItem = [NSURLQueryItem queryItemWithName:@"page" value:helpTag];
		urlComponents.queryItems = [urlComponents.queryItems arrayByAddingObjectsFromArray:@[pageItem]];
	}

	NSURL* supportURL = [urlComponents URL];

	return supportURL;
}

//////

#pragma mark - Webview

-(void)startWebProgress
{
	[self removeWebProgress];

	showWaitBoxTimer =  [NSTimer scheduledTimerWithTimeInterval:.2
														 target:self
													   selector:@selector(showWebProgressBox:)
													   userInfo:nil
														repeats:NO];

}

- (void)showWebProgressBox:(NSTimer*)sender
{
	actProgress.hidden = NO;
	[actProgress startAnimating];

}



-(void) removeWebProgress
{
	if(showWaitBoxTimer) {
		[showWaitBoxTimer invalidate];
	}

	actProgress.hidden = YES;
	[actProgress stopAnimating];

}

#pragma  mark - AccountSetupViewController_IOS_Child_Delegate

- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return NO;
}




#pragma mark - UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)webView
{
	[self startWebProgress];

}


- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	NSString *theTitle=[webView stringByEvaluatingJavaScriptFromString:@"document.title"];

	lblTitle.text = theTitle;

	bbtnBack.enabled = [webView canGoBack];
	bbtnFwd.enabled = [webView canGoForward ];


	//    if(!didFirstLoad)
	//    {
	//        didFirstLoad = YES;
	//
	//        if(supportURL)
	//            [webView loadRequest:[NSURLRequest requestWithURL:supportURL]];
	//    }
	//
	[self removeWebProgress];

}


- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
	[self removeWebProgress];

}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType
{
	if (navigationType == UIWebViewNavigationTypeLinkClicked)
	{

		// Prevent navigating to other sites.
		// But allow inline links.

		if ([request.URL.scheme isEqual:@"mailto"] )
		{
			[self sendSupportEmailTo:request.URL.resourceSpecifier];
			return NO;
		}

	}


	return YES;
}


- (IBAction)backButtonTapped:(id)sender {
	if ([webSupportView canGoBack] ) {
		[webSupportView goBack];
	}
}

- (IBAction)fwdButtonTapped:(id)sender {
	if ([webSupportView canGoForward] ) {
		[webSupportView goForward];
	}
}

-(void) sendSupportEmailTo:(NSString*)email
{
	// Email Subject
	NSString *emailTitle = @"Storm4 Support";
	// Email Content

	NSString *messageBody = @"Hi there, just needed help with something...\n  (tell us what you need help with here)";

	//NSData* appSupportData = [S4AppDelegate makeAppSupportData];
	NSData* appSupportData = NULL;

	MFMailComposeViewController *mc = [[MFMailComposeViewController alloc] init];
	mc.mailComposeDelegate = (id<MFMailComposeViewControllerDelegate>) self;
	[mc setSubject:emailTitle];
	[mc setMessageBody:messageBody isHTML:NO];
	[mc setToRecipients: @[email]];

	[mc addAttachmentData:appSupportData mimeType:@"text/plain" fileName:@"storm4Info.txt"];

	// Present mail view controller on screen
	[self presentViewController:mc animated:YES completion:NULL];

}

- (void) mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
	switch (result)
	{
		case MFMailComposeResultCancelled:
			NSLog(@"Mail cancelled");
			break;

		case MFMailComposeResultSaved:
			NSLog(@"Mail saved");
			break;

		case MFMailComposeResultSent:
			NSLog(@"Mail sent");
			break;

		case MFMailComposeResultFailed:
			NSLog(@"Mail sent failure: %@", [error localizedDescription]);
			break;
		default:
			break;
	}

	// Close the Mail Interface
	[self dismissViewControllerAnimated:YES completion:NULL];
}

@end
