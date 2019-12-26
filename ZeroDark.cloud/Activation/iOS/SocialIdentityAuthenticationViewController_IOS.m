/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "SocialIdentityAuthenticationViewController_IOS.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"

#import "ZDCUserProfile.h"
#import "ZDCLogging.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"

// Apple Libraries
#import <AudioToolbox/AudioToolbox.h>
#import <WebKit/WebKit.h>

// 3rd Party Libraries
#import <SCLAlertView_Objective_C/SCLAlertView.h>
#import <SCLAlertView_Objective_C/SCLAlertViewStyleKit.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@implementation SocialIdentityAuthenticationViewController_IOS
{
	IBOutlet __weak UIActivityIndicatorView *actProgress;
	IBOutlet __weak UILabel            *lblTitle;
	IBOutlet __weak UIWebView          *webAuth0View;

	IBOutlet __weak UIButton           *_btnUseWebBrowser;

	NSString    *connectionName;
	NSString*   csrfState; // a nonce to prevent CSRF attack
	NSString*   pkceCode;
	NSString* 	callbackURLscheme;

	NSString*   eventQueryString;

	NSURL*      loadingProgressURL;
	BOOL        didFirstLoad;
	NSURL*      socialURL;

	NSTimer *       showWaitBoxTimer;

	BOOL                isInAddSocialView;
	BOOL isRunning;
 
	SCLAlertView *reauthAlert;

}

@synthesize accountSetupVC = accountSetupVC;
@synthesize URLEventQueryString = URLEventQueryString;
@synthesize providerName = providerName;

#pragma mark  - view

- (void)viewDidLoad {
    [super viewDidLoad];

	webAuth0View.delegate = (id <UIWebViewDelegate> ) self;

	reauthAlert = nil;

	isInAddSocialView = [self.restorationIdentifier isEqualToString:@"SocialIdentityAuthenticationViewControllerADD_IOS"];
	if (isInAddSocialView)
	{
		_btnUseWebBrowser.layer.cornerRadius    = 8.0f;
		_btnUseWebBrowser.layer.masksToBounds    = YES;
		_btnUseWebBrowser.layer.borderWidth      = 1.0f;
		_btnUseWebBrowser.layer.borderColor      = self.view.tintColor.CGColor;
	}
	else
	{
	//	webAuth0View.layer.cornerRadius   = 16;
	//	webAuth0View.layer.masksToBounds  = YES;
	//	webAuth0View.layer.borderColor    = [UIColor whiteColor].CGColor;
	//	webAuth0View.layer.borderWidth    = 1.0f;

		_btnUseWebBrowser.layer.cornerRadius    = 8.0f;
		_btnUseWebBrowser.layer.masksToBounds    = YES;
		_btnUseWebBrowser.layer.borderWidth      = 1.0f;
		_btnUseWebBrowser.layer.borderColor      = [UIColor whiteColor].CGColor;

		[_btnUseWebBrowser setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[_btnUseWebBrowser setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
	}

	_btnUseWebBrowser.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	_btnUseWebBrowser.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);


	webAuth0View.hidden = YES;
	socialURL = nil;

	loadingProgressURL = [[ZeroDarkCloud frameworkBundle] URLForResource:@"SocialIdentityAuthenticationLoading" withExtension:@"html"];
	isRunning = NO;

	[self clearSessions];
	[self removeWebProgress];
}

- (void)viewWillDisappear
{
	lblTitle.text = @"";
	[accountSetupVC cancelWait];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	isRunning = NO;
	didFirstLoad = NO;

	[webAuth0View loadRequest:[NSURLRequest requestWithURL:loadingProgressURL]];

	[self clearSessions];

	if (reauthAlert)
	{
		[reauthAlert hideView];
		reauthAlert = nil;
	}
}

- (BOOL)schemeAvailable:(NSString *)scheme
{
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:scheme];
	return [application canOpenURL:URL];
}

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
	if(isInAddSocialView)
	{
		actProgress.hidden = YES;
	}
	else
	{
		actProgress.hidden = NO;
		[actProgress startAnimating];
	}
}



-(void) removeWebProgress
{
	if(showWaitBoxTimer) {
		[showWaitBoxTimer invalidate];
	}

	if(isInAddSocialView)
	{
		actProgress.hidden = YES;
	}
	else
	{
		actProgress.hidden = YES;
		[actProgress stopAnimating];
	}

 }

-(void) setURLEventQueryString:(NSString *)queryString
{
	eventQueryString = queryString;

}

-(void) setProviderName:(NSString *)providerName
{
	connectionName = providerName;
}


- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	[accountSetupVC setHelpButtonHidden:NO];
	accountSetupVC.btnBack.hidden = NO;

	if(isRunning)
		return;

	webAuth0View.hidden = YES;

	// check for callback url coming from web browser.
	if(eventQueryString.length)
	{

		// recover the csrfState nonce
//		NSDictionary* socialCallBackInfo = S4AppDelegate.auth0SocialCallBackInfo;
//		if(socialCallBackInfo)
//		{
//			CSRFStateString = socialCallBackInfo[kAuth0SocialCallBackInfo_CSRFStateString];
//		}

		[self removeWebProgress];

		[self processQueryString:eventQueryString provider:connectionName];

		eventQueryString = nil;
		connectionName = nil;
		return;
	}

	NSDictionary *identDict = accountSetupVC.selectedProvider;
	if (identDict)
	{
		Auth0ProviderType strategyType = [identDict[kAuth0ProviderInfo_Key_Type] integerValue];
		NSString* strategyName      =  identDict[kAuth0ProviderInfo_Key_ID];
		NSString* displayName       = identDict[kAuth0ProviderInfo_Key_DisplayName];

		if (strategyType == Auth0ProviderType_Social)
		{
			if (isInAddSocialView)
			{
				self.navigationItem.title = [NSString stringWithFormat:@"Sign in to %@", displayName];

				lblTitle.hidden = YES;
			}
			else
			{
				lblTitle.text = [NSString stringWithFormat:@"Sign in to %@", displayName];

				lblTitle.hidden = NO;
			}

			//
			// workaround to get Auth0 to work with new Google policy
			//
			// https://developers.googleblog.com/2016/08/modernizing-oauth-interactions-in-native-apps.html
			//
			if([strategyName isEqualToString:@"google-oauth2"])
			{
				NSDictionary *defDict = @{@"UserAgent":  @"Safari/537.36"};

				// Registered defaults are never stored between runs of an application, and are visible
				// only to the application that registers them.

				[[NSUserDefaults standardUserDefaults] registerDefaults:defDict];
			}

			[self startLoginProcessWithStrategyName:strategyName];
		}
		else
		{
			// error should never get here
		}
	}
}

- (void)clearSessions
{
	if (NSClassFromString(@"WKWebsiteDataStore")) {
		NSSet *types = [NSSet setWithArray:@[
											 WKWebsiteDataTypeLocalStorage,
											 WKWebsiteDataTypeCookies,
											 WKWebsiteDataTypeSessionStorage,
											 WKWebsiteDataTypeIndexedDBDatabases,
											 WKWebsiteDataTypeWebSQLDatabases
											 ]];
		NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
		[[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types modifiedSince:dateFrom completionHandler:^{
		}];
	}

	NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	for (NSHTTPCookie *cookie in [storage cookies]) {
		[storage deleteCookie:cookie];
	}
}


-(void) startLoginProcessWithStrategyName:(NSString*)strategyName
{

	NSParameterAssert(strategyName != nil);

	isRunning = YES;

	callbackURLscheme = [[Auth0APIManager sharedInstance]callbackURLscheme];
	connectionName = strategyName;

	// generate a random string to prevent cross site reference attack.
	csrfState = [[NSUUID UUID] UUIDString];
	pkceCode = @"morecheeseplease";

//	S4AppDelegate.auth0SocialCallBackInfo = nil;
	webAuth0View.hidden = NO;

	// First we display our loading HTML.
	// And once that's up, we query the social URL.
	
	socialURL = [[Auth0APIManager sharedInstance] socialQueryURLforStrategyName: strategyName
	                                                          callBackURLScheme: callbackURLscheme
	                                                                  csrfState: csrfState
	                                                                   pkceCode: pkceCode];
	
	didFirstLoad = NO;
	[webAuth0View loadRequest:[NSURLRequest requestWithURL:loadingProgressURL]];
}


#pragma mark - actions

- (IBAction)btnUseWebBrowserClicked:(id)sender
{
	ZDCLogAutoTrace();

	[self authenticateWithWebBrowser: socialURL
	                    strategyName: connectionName];
}


- (BOOL)authenticateWithWebBrowser:(NSURL *)url
                      strategyName:(NSString *)strategyName
{
	[accountSetupVC showError: @"Not yet!"
	                  message: @"This code isnt ready yet."
	           viewController: self
	          completionBlock:
	^{
	//	[accountSetupVC popFromCurrentView];
	}];

	/*

	 NOTE: for this to work on IOS we must set the CFBundleURLTypes to point to the clientID
	 note that the clientID has a prefix OF 'a0'

	 <key>CFBundleURLTypes</key>
	 <array>
	 <dict>
	 <key>CFBundleTypeRole</key>
	 <string>Editor</string>
	 <key>CFBundleURLName</key>
	 <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	 <key>CFBundleURLSchemes</key>
	 <array>
	 <string>a0iLjaFx3CHIyzaXYjrundOOzmYIvS1nbu</string>
	 <string>storm4</string>
	 </array>
	 </dict>
	 </array>

	 */
	
//
//	NSMutableDictionary* socialCallBackInfo = NSMutableDictionary.dictionary;
//	socialCallBackInfo[kAuth0SocialCallBackInfo_SchemeKey] = callbackURLscheme;
//	socialCallBackInfo[kAuth0SocialCallBackInfo_ProviderKey] = connectionName;
//	socialCallBackInfo[kAuth0SocialCallBackInfo_CSRFStateString] = CSRFStateString;
//
//	if(isInAddSocialView)
//	{
//		socialCallBackInfo[kAuth0SocialCallBackInfo_AddingToUserIDKey] =  accountSetupVC.user.uuid;
//		socialCallBackInfo[kAuth0SocialCallBackInfo_LastController]    =  self;
//	}
//	S4AppDelegate.auth0SocialCallBackInfo = socialCallBackInfo;
//
//	[[UIApplication sharedApplication] openURL: socialURL ];

	return YES;
}

#pragma mark - webview delagate


- (void)webViewDidStartLoad:(UIWebView *)webView
{
	[self startWebProgress];

}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	ZDCLogAutoTrace();

	if (!didFirstLoad)
	{
		didFirstLoad = YES;

		if (socialURL)
		{
			[webAuth0View loadRequest:[NSURLRequest requestWithURL:socialURL]];
		}
	}
	
	[self removeWebProgress];
}


- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
	[self removeWebProgress];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
                                                 navigationType:(UIWebViewNavigationType)navigationType
{

	if(!isRunning)
		return NO;

	// check if this is the ODIC login returning to us
	if(! [ request.URL.scheme.lowercaseString isEqualToString: callbackURLscheme])
	{
		[self startWebProgress];

		return YES;
	}

	NSString *queryString = request.URL.query ?: request.URL.fragment;

	[self removeWebProgress];
	[self processQueryString:queryString provider:connectionName];

	return NO;
}


- (void)processQueryString:(NSString *)queryString
                  provider:(NSString *)provider
{
	[accountSetupVC showWait: @"Please Wait…"
	                 message: @"Downloading user info"
	         completionBlock: nil];
	
	__weak typeof(self) weakSelf = self;
	
	void (^Fail)(NSString*, NSString*) = ^(NSString *title, NSString *msg){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		[strongSelf.accountSetupVC cancelWait];
		[strongSelf.accountSetupVC showError: title
											  message: msg
									completionBlock:
		^{
			[strongSelf.accountSetupVC popFromCurrentView];
		}];
	};
	
	Auth0APIManager *auth0APIManager = [Auth0APIManager sharedInstance];
	AWSCredentialsManager *awsCredentialsManager = accountSetupVC.zdc.awsCredentialsManager;
	
	NSDictionary *queryResult = [auth0APIManager parseQueryString:queryString];
	
	A0Token *a0Token = nil;
	NSString *csrfResult = nil;
	NSError *error = nil;
	
	BOOL decodeSuccess =
	  [auth0APIManager decodeSocialQueryResult: queryResult
	                                   a0Token: &a0Token
	                                 csrfState: &csrfResult
	                                     error: &error];
	
	if (!decodeSuccess)
	{
		NSString *err_title = @"Social Login Failed";
		NSString *err_msg = error.localizedDescription;
		
		Fail(err_title, err_msg);
		return;
	}
	
	if (![csrfResult isEqualToString:csrfState])
	{
		NSString *err_title = @"Social Login Failed";
		NSString *err_msg = error ? error.localizedDescription : @"Possible cross-site request forgery attack";
		
		Fail(err_title, err_msg);
		return;
	}
	
	NSString *userID = accountSetupVC.user.uuid;
	IdenititySelectionMode identityMode = accountSetupVC.identityMode;
	
	[auth0APIManager getUserProfileWithAccessToken: a0Token.accessToken
	                               completionQueue: nil
	                               completionBlock:
	^(ZDCUserProfile *profile, NSError *error)
	{
		if (error)
		{
			NSString *err_title = @"Could not Authenticate";
			NSString *err_msg = error.localizedDescription;
			
			Fail(err_title, err_msg);
			return;
		}
		
		if (identityMode == IdenititySelectionMode_ExistingAccount)
		{
			[weakSelf linkUserWithProfile:profile];
			return;
		}
		
		if (identityMode == IdenititySelectionMode_ReauthorizeAccount)
		{
			// update user a0Token.refreshToken
			
			// Check if this is a linked account first
			if (![userID isEqualToString:profile.appMetadata[@"aws_id"]])
			{
				NSString *err_title = @"This identity is not linked to your account.";
				NSString *err_msg = @"To reauthorize your account, please login with the proper identity";
				
				Fail(err_title, err_msg);
				return;
			}
			
			[awsCredentialsManager resetAWSCredentialsForUser: userID
			                                 withRefreshToken: a0Token.refreshToken
			                                  completionQueue: nil
			                                  completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
			{
				if (error)
				{
					NSString *err_title = @"Could not Authenticate";
					NSString *err_msg = error.localizedDescription;
					
					Fail(err_title, err_msg);
					return;
				}
				
				__strong typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				
				[strongSelf.accountSetupVC cancelWait];
				
				strongSelf->reauthAlert = [[SCLAlertView alloc] init];
				
				[strongSelf->reauthAlert addButton:@"OK" actionBlock:^(void) {
					
					__strong typeof(self) strongSelf = weakSelf;
					if (!strongSelf) return;
					
					[strongSelf.accountSetupVC popToNonAccountSetupView:strongSelf.navigationController];
					strongSelf->reauthAlert = nil;
				}];
						  
				[strongSelf->reauthAlert showSuccess: strongSelf
				                               title: @"Account reauthorized "
				                            subTitle: @"Your account has been reauthorized."
				                    closeButtonTitle: nil
				                            duration: 0.0f];
			}];
		}
		else // if (identityMode == IdenititySelectionMode_NewAccount)
		{
			[auth0APIManager getIDTokenWithRefreshToken: a0Token.refreshToken
			                            completionQueue: nil
			                            completionBlock:^(NSString *auth0_idToken, NSError *error)
			{
				if (error)
				{
					NSString *err_title = @"Could not Authenticate";
					NSString *err_msg = error.localizedDescription;
					
					Fail(err_title, err_msg);
					return;
				}
				
				[awsCredentialsManager fetchAWSCredentialsWithIDToken: auth0_idToken
				                                                stage: @"prod"
				                                      completionQueue: nil
				                                      completionBlock:^(NSDictionary *delegation, NSError *error)
				{
					if (error)
					{
						NSString *err_title = @"Could not Authenticate";
						NSString *err_msg = error.localizedDescription;
			
						Fail(err_title, err_msg);
						return;
					}
			
					ZDCLocalUserAuth *auth = nil;
			
					BOOL parseSuccess =
					  [awsCredentialsManager parseLocalUserAuth: &auth
					                             fromDelegation: delegation
					                               refreshToken: a0Token.refreshToken
					                                    idToken: auth0_idToken];
					if (!parseSuccess)
					{
						NSString *err_title = @"Could not Authenticate";
						NSString *err_msg = error.localizedDescription;
				
						Fail(err_title, err_msg);
						return;
					}
				
					[weakSelf authenticateUserWithAuth: auth
					                           profile: profile
					                          provider: provider];
				}];
			}];
		}
	}];
}


-(void) continueWithURLEventQueryString:(NSString *)queryString
							   provider:(NSString*)provider
{
	[self removeWebProgress];

	[self processQueryString:queryString
					provider:provider];

}

- (void)authenticateUserWithAuth:(ZDCLocalUserAuth *)auth
                         profile:(ZDCUserProfile *)profile
                        provider:(NSString *)provider
{
	__weak typeof(self) weakSelf = self;

	[accountSetupVC socialAccountLoginWithAuth: auth
	                                   profile: profile
	                           completionBlock:^(AccountState accountState, NSError * _Nonnull error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		if (error)
		{
			 NSString* errorString = error.localizedDescription;

			 [strongSelf.accountSetupVC showError:@"Could not Authenticate"
										  message:errorString
								  completionBlock:^{

									  __strong typeof(self) strongSelf = weakSelf;
									  if (!strongSelf) return;

									  [strongSelf->accountSetupVC popFromCurrentView];
								  }];
		 }
		 else
		 {
			 [strongSelf.accountSetupVC cancelWait];

			 switch (accountState) {

				 case AccountState_Ready:
					 [strongSelf.accountSetupVC pushAccountReady ];
					 break;

				 case AccountState_NeedsCloneClode:
					 [strongSelf.accountSetupVC pushScanClodeCode  ];
					 break;

				 case AccountState_NeedsRegionSelection:
					 [strongSelf.accountSetupVC pushRegionSelection  ];
					 break;

				 default:
					 [strongSelf.accountSetupVC showError:@"Could not Authenticate"
												  message:@"internal error"
										  completionBlock:^{

											  __strong typeof(self) strongSelf = weakSelf;
											  if (!strongSelf) return;

											  [strongSelf->accountSetupVC popFromCurrentView];
										  }];
					 break;
			 }
		 }
	 }];

}

- (void)linkUserWithProfile:(ZDCUserProfile *)profile
{
	__weak typeof(self) weakSelf = self;

	[accountSetupVC linkProfile:profile
				  toLocalUserID:accountSetupVC.user.uuid
				completionQueue:dispatch_get_main_queue()
				completionBlock:^(NSError * _Nullable error)
	 {

		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;

		 [strongSelf->accountSetupVC cancelWait];

		 if(error)
		 {
			 NSString* errorDetail = error.localizedDescription;
			 if([strongSelf->accountSetupVC isAlreadyLinkedError:error])
			 {
				 errorDetail = @"This identity is already linked to a different account. To link it to this account, you must first unlink it from the other account.";
			 }

			 [strongSelf->accountSetupVC showError:@"Could not add identity to user."
							   message:errorDetail
					   completionBlock:^{

							__strong typeof(self) strongSelf = weakSelf;
							if (!strongSelf) return;

						   [strongSelf->accountSetupVC popToViewControllerForViewID: AccountSetupViewID_SocialidMgmt
											   withNavigationController: self.navigationController];
						   //							  [accountSetupVC pushSocialIdMgmtWithUserID:accountSetupVC.user.uuid];

					   }];
		 }
		 else
		 {
			 [strongSelf->accountSetupVC popToViewControllerForViewID: AccountSetupViewID_SocialidMgmt
								 withNavigationController: self.navigationController];

			 //						[accountSetupVC pushSocialIdMgmtWithUserID:accountSetupVC.user.uuid];
		 }
	 }];
}



@end
