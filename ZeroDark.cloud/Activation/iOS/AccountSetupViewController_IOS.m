/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "AccountSetupViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "Auth0ProviderManager.h"

#import "IntroViewController_IOS.h"
#import "IdentityProviderViewController_IOS.h"
#import "DatabaseIdentityAuthenticationViewController_IOS.h"
#import "AccountCloneScanController_IOS.h"
#import "AccountCloneUnlockController_IOS.h"
#import "SocialIdentityAuthenticationViewController_IOS.h"
#import "DatabaseIdentityCreateViewController_IOS.h"
#import "AccountRegionSelectViewController_IOS.h"
#import "AccountSetupHelpViewController_IOS.h"
#import "SocialidentityManagementViewController_IOS.h"
#import "AddIdentitityProviderViewController_IOS.h"
#import "UserAvatarViewController_IOS.h"

#import "ZDCPanTransition.h"
#import "SCLAlertView.h"
#import "UIColor+Crayola.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int ddLogLevel = DDLogLevelWarning;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif

@implementation AccountSetupSubViewController_Base

@synthesize accountSetupVC = accountSetupVC;

@end

@implementation AccountSetupViewController_IOS {
	IBOutlet __weak UIView *containerView;
	
	UIPanGestureRecognizer *panRecognizer;
	UIPercentDrivenInteractiveTransition *interactionController;
	
	UIViewController*												 vc_Initial;
	
	IntroViewController_IOS*                            vc_Intro;
	IdentityProviderViewController_IOS*                 vc_Identity;
	DatabaseIdentityAuthenticationViewController_IOS*   vc_DBAuth;
	DatabaseIdentityCreateViewController_IOS*           vc_DBCreate;
	SocialIdentityAuthenticationViewController_IOS*     vc_SocialAuth;
	AccountCloneScanController_IOS*                     vc_ScanCloneCode;
	AccountCloneUnlockController_IOS*                   vc_UnlockCloneCode;
	AccountSetupHelpViewController_IOS*                 vc_Help;
	AccountRegionSelectViewController_IOS*              vc_Region;
	SocialidentityManagementViewController_IOS*         vc_SocialidMgmt;
	AddIdentitityProviderViewController_IOS*            vc_AddIdent;
	SocialIdentityAuthenticationViewController_IOS*     vc_SocialAuthAdd;
	DatabaseIdentityCreateViewController_IOS*           vc_DBCreateAdd;
	DatabaseIdentityAuthenticationViewController_IOS*   vc_DBReAuth;
	UserAvatarViewController_IOS*                       vc_UserAvatar;
	
	UIViewController* vcToPushTo;
	
	NSTimer *       showWaitBoxTimer;
	SCLAlertView *  errorAlert;
	SCLAlertView *  waitingAlert;
	
	BOOL isSetup;
	
	accountSetupViewCompletionHandler  		completionHandler;
}

@synthesize canDismissWithoutNewAccount = canDismissWithoutNewAccount;
@synthesize containedNavigationController = containedNavigationController;

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AccountSetup_IOS" bundle:bundle];
	
	self = [storyboard instantiateViewControllerWithIdentifier:@"AccountSetupViewController"];
	if (self)
	{
		self.owner = inOwner;
	}
	return self;
}

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
  canDismissWithoutNewAccount:(BOOL)inCanDismissWithoutNewAccount
				completionHandler:(accountSetupViewCompletionHandler __nullable )inCompletionHandler
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AccountSetup_IOS" bundle:bundle];
	
	self = [storyboard instantiateViewControllerWithIdentifier:@"AccountSetupViewController"];
	if (self)
	{
		self.owner = inOwner;
		completionHandler = inCompletionHandler;
		canDismissWithoutNewAccount = inCanDismissWithoutNewAccount;
	}
	return self;
}


- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	for (UIViewController *childVC in [self childViewControllers])
	{
		if ([childVC isKindOfClass:[UINavigationController class]])
		{
			containedNavigationController = (UINavigationController *)childVC;
			break;
		}
	}
	
	containedNavigationController.navigationBarHidden = YES;
	containedNavigationController.delegate = self;
	
	void (^TintButtonImage)(UIButton *) = ^(UIButton *button){
		
		UIImage *image = [button imageForState:UIControlStateNormal];
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		
		[button setImage:image forState:UIControlStateNormal];
		button.tintColor = [UIColor whiteColor];
	};
	
	TintButtonImage(_btnCancel);
	TintButtonImage(_btnBack);
	TintButtonImage(_btnNext);
	TintButtonImage(_btnHelp);
	
	_btnNext.hidden = YES;
}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	if(self.navigationController)
	{
		// be presented in a nav controller
		
		[containedNavigationController setViewControllers:@[vcToPushTo]];
		vcToPushTo = NULL;
		
	}
	else
	{
		if(!isSetup)
		{
			// first run
			isSetup = YES;
			_btnBack.hidden = YES;
			
			if(vcToPushTo)
			{
				[containedNavigationController setViewControllers:@[vcToPushTo]];
				vcToPushTo = NULL;
			}
		}
		
		_btnCancel.hidden = !canDismissWithoutNewAccount;
		
	}
	
}


-(void) viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	
	if(errorAlert)
	{
		[errorAlert hideView];
		errorAlert = nil;
	}
	if(waitingAlert)
	{
		[waitingAlert hideView];
		waitingAlert = nil;
	}
	
}


-(void)pushInitialViewController:(UIViewController* __nonnull)initialViewController
{
	NSParameterAssert(initialViewController != nil);
	
	vc_Initial = initialViewController;
	
	self.identityMode = IdenititySelectionMode_NewAccount;
	[self viewControllerForViewID:AccountSetupViewID_Intro];
	
	if(isSetup)
	{
		[containedNavigationController setViewControllers:@[vc_Initial]];
	}
	else
	{
		vcToPushTo = vc_Initial;
	}
}


-(AccountSetupSubViewController_Base*)viewControllerForViewID:(AccountSetupViewID)viewID
{
	AccountSetupSubViewController_Base* vc = NULL;
	
	switch(viewID)
	{
		case AccountSetupViewID_Intro:
			if(!vc_Intro)
			{
				vc_Intro        = (IntroViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"IntroViewController_IOS"];
			}
			vc = vc_Intro;
			break;
			
		case AccountSetupViewID_Identity:
			if(!vc_Identity)
			{
				vc_Identity        = (IdentityProviderViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"IdentityProviderViewController_IOS"];
			}
			vc = vc_Identity;
			break;
			
		case AccountSetupViewID_DBAuth:
			if(!vc_DBAuth)
			{
				vc_DBAuth        = (DatabaseIdentityAuthenticationViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"DatabaseIdentityAuthenticationViewController_IOS"];
			}
			vc = vc_DBAuth;
			break;
			
		case AccountSetupViewID_ReAuthDatabase:
			if(!vc_DBReAuth)
			{
				vc_DBReAuth        = (DatabaseIdentityAuthenticationViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"DatabaseIdentityAuthenticationViewController_LOGIN_IOS"];
			}
			vc = vc_DBReAuth;
			break;
			
		case AccountSetupViewID_DBCreate:
			if(!vc_DBCreate)
			{
				vc_DBCreate        = (DatabaseIdentityCreateViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"DatabaseIdentityCreateViewController_IOS"];
			}
			vc = vc_DBCreate;
			break;
			
		case AccountSetupViewID_AddDatabase:
			if(!vc_DBCreateAdd)
			{
				vc_DBCreateAdd        = (DatabaseIdentityCreateViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"DatabaseIdentityCreateViewController_ADDIOS"];
			}
			vc = vc_DBCreateAdd;
			break;
			
		case AccountSetupViewID_SocialAuth:
			if(!vc_SocialAuth)
			{
				vc_SocialAuth        = (SocialIdentityAuthenticationViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"SocialIdentityAuthenticationViewController_IOS"];
			}
			vc = vc_SocialAuth;
			break;
			
		case AccountSetupViewID_AddSocial:
			if(!vc_SocialAuthAdd)
			{
				vc_SocialAuthAdd        = (SocialIdentityAuthenticationViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"SocialIdentityAuthenticationViewControllerADD_IOS"];
			}
			vc = vc_SocialAuthAdd;
			break;
			
		case AccountSetupViewID_ScanCloneCode:
			if(!vc_ScanCloneCode)
			{
				vc_ScanCloneCode   = (AccountCloneScanController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"AccountCloneScanController_IOS"];
			}
			vc = vc_ScanCloneCode;
			break;
			
		case AccountSetupViewID_UnlockCloneCode:
			if(!vc_UnlockCloneCode)
			{
				vc_UnlockCloneCode  = (AccountCloneUnlockController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"AccountCloneUnlockController_IOS"];
			}
			vc = vc_UnlockCloneCode;
			break;
			
		case AccountSetupViewID_Region:
			if(!vc_Region)
			{
				vc_Region = (AccountRegionSelectViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"AccountRegionSelectViewController_IOS"];
			}
			vc = vc_Region;
			break;
			
		case AccountSetupViewID_SocialidMgmt:
			if(!vc_SocialidMgmt)
			{
				vc_SocialidMgmt = (SocialidentityManagementViewController_IOS  *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"SocialidentityManagementViewController_IOS"];
			}
			vc = vc_SocialidMgmt;
			break;
			
		case AccountSetupViewID_Help:
			if(!vc_Help)
			{
				vc_Help = (AccountSetupHelpViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"AccountSetupHelpViewController_IOS"];
			}
			vc = vc_Help;
			break;
			
		case AccountSetupViewID_AddIdentitityProvider:
			if(!vc_AddIdent)
			{
				vc_AddIdent = (AddIdentitityProviderViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"AddIdentitityProviderViewController_IOS"];
			}
			vc = vc_AddIdent;
			break;
			
		case AccountSetupViewID_UserAvatar:
			if(!vc_UserAvatar)
			{
				vc_UserAvatar = (UserAvatarViewController_IOS *)
				[self.storyboard instantiateViewControllerWithIdentifier:@"UserAvatarViewController_IOS"];
				
			}
			vc = vc_UserAvatar;
			break;
			
		default:;
			
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
													 reason:[NSString stringWithFormat:@"internal error viewControllerForViewID (%ld)", (long)viewID ]  userInfo:nil];
	}
	
	vc.accountSetupVC = self;
	
	return vc;
}



-(void)setHelpButtonHidden:(BOOL)hidden
{
	__weak typeof(self) weakSelf = self;
	
	[UIView animateWithDuration:.2 animations:^{
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		strongSelf->_btnHelp.alpha = hidden?0:1;
	} completion:^(BOOL finished) {
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		strongSelf->_btnHelp.hidden = hidden;
	}];
	
	
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Progress
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void) showError:(NSString* __nonnull)title
			 message:(NSString* __nullable)message
	viewController:(UIViewController* __nullable)viewController
  completionBlock:(dispatch_block_t __nullable)completionBlock
{
	[self cancelWait];
	
	errorAlert = [[SCLAlertView alloc] initWithNewWindowWidth: self.view.frame.size.width -40];
	errorAlert.showAnimationType = SCLAlertViewShowAnimationFadeIn;
	
	__weak typeof(self) weakSelf = self;
	
	[errorAlert addButton:@"OK" actionBlock:^(void) {
		
		if(completionBlock) {
			completionBlock();
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf) {
			strongSelf->errorAlert = nil;
		}
	}];
	
	[errorAlert showError:viewController?viewController:self
						 title:title
					 subTitle:message
		  closeButtonTitle:nil
					 duration:0.f];
	
	
}

-(void) showError:(NSString*)title
			 message:(NSString*)message
  completionBlock:(dispatch_block_t __nullable)completionBlock

{
	[self showError:title message:message viewController:nil completionBlock:completionBlock];
}

-(void) showWait:(NSString* __nonnull)title
			message:(NSString* __nullable)message
  viewController:(UIViewController* __nullable)viewController
 completionBlock:(dispatch_block_t __nullable)completionBlock
{
	[self cancelWait];
	
	NSMutableDictionary * userInfo =    @{  @"title":   title?:@"",
														 @"message": message?:@""
														 }.mutableCopy;
	
	if(viewController)
		[userInfo setObject:viewController forKey:@"viewController"];
	
	if(completionBlock)
		[userInfo setObject:completionBlock forKey:@"completionBlock"];
	
	showWaitBoxTimer =  [NSTimer scheduledTimerWithTimeInterval:.7
																		  target:self
																		selector:@selector(showWaitBox:)
																		userInfo:userInfo
																		 repeats:NO];
	
}

-(void) showWait:(NSString*)title
			message:(NSString*)message
 completionBlock:(dispatch_block_t __nullable) completionBlock
{
	[self showWait:title message:message viewController:nil completionBlock:completionBlock];
}


- (void)showWaitBox:(NSTimer*)sender
{
	NSDictionary* userInfo = sender.userInfo;
	
	NSString* title = userInfo[@"title"];
	NSString* message = userInfo[@"message"];
	dispatch_block_t completionBlock =  userInfo[@"completionBlock"];
	UIViewController* vc = userInfo[@"viewController"];
	
	if(waitingAlert)
	{
		[waitingAlert hideView];
		waitingAlert = nil;
	}
	
	waitingAlert = [[SCLAlertView alloc] init];
	waitingAlert.customViewColor = [UIColor crayolaBlueJeansColor];
	waitingAlert.showAnimationType = SCLAlertViewShowAnimationFadeIn;
	
	__weak typeof(self) weakSelf = self;
	
	if(completionBlock)
	{
		[waitingAlert addButton:@"Cancel"
						actionBlock:^(void)
		 {
			 if(completionBlock) {
				 completionBlock();
			 }
			 
			 __strong typeof(self) strongSelf = weakSelf;
			 if (strongSelf) {
				 [strongSelf cancelWait];
			 }
		 }];
	}
	
	[waitingAlert showWaiting:vc?vc:self
							  title:title
						  subTitle:message
				closeButtonTitle:nil
						  duration:0.f];
	
	
}


-(void) cancelWait
{
	if(showWaitBoxTimer) {
		[showWaitBoxTimer invalidate];
	}
	
	if(waitingAlert)
	{
		[waitingAlert hideView];
		waitingAlert = nil;
	}
	
}


-(void) handleFail
{
	[self invokeCompletionBlockWithLocalUserID:self.user.uuid
								  completedActivation:NO
								shouldBackupAccessKey:NO];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// code to allow passthrough of buttons


-(NSString*) tagForViewContoller:(UIViewController*)vc
{
	NSString* tag = vc.restorationIdentifier;
	
	if(vc == vc_SocialAuth ||  vc == vc_Identity)
	{
		NSDictionary* identDict =  self.selectedProvider;
		
		if(identDict)
		{
			NSString*   providerKey = identDict[kAuth0ProviderInfo_Key_ID];
			tag = [NSString stringWithFormat:@"%@_%@", tag, providerKey];
		}
	}
	
	return tag;
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
	
	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
	
	CGPoint viewPoint;
	
	if(_btnCancel.enabled && !_btnCancel.hidden)
	{
		viewPoint = [_btnCancel convertPoint:locationPoint fromView:self.view];
		if ( [_btnCancel pointInside:viewPoint withEvent:event])
		{
			[self CloseButtonClicked:self ];
			return;
		}
	}
	
	if(_btnHelp.enabled && !_btnHelp.hidden)
	{
		viewPoint = [_btnHelp convertPoint:locationPoint fromView:self.view];
		if ( [_btnHelp pointInside:viewPoint withEvent:event])
		{
			[self HelpButtonClicked:self ];
			return;
		}
	}
	
	if(_btnBack.enabled && !_btnBack.hidden)
	{
		viewPoint = [_btnBack convertPoint:locationPoint fromView:self.view];
		if ( [_btnBack pointInside:viewPoint withEvent:event])
		{
			[self LeftButtonClicked:self ];
			return;
		}
	}
	if(_btnNext.enabled && !_btnNext.hidden)
	{
		viewPoint = [_btnNext convertPoint:locationPoint fromView:self.view];
		if ( [_btnNext pointInside:viewPoint withEvent:event])
		{
			[self RightButtonClicked:self ];
			return;
		}
	}
	
}

- (IBAction)RightButtonClicked:(id)sender
{
	
}



- (IBAction)LeftButtonClicked:(id)sender
{
	_btnBack.hidden = YES;
	[containedNavigationController popViewControllerAnimated:YES];
}

- (IBAction)HelpButtonClicked:(id)sender
{
	[self pushHelpWithTag:[self tagForViewContoller:containedNavigationController.topViewController]];
}



- (IBAction)CloseButtonClicked:(id)sender
{
	UIViewController *topViewController = containedNavigationController.topViewController;
	
	if( topViewController == vc_ScanCloneCode
		|| topViewController == vc_UnlockCloneCode )
	{
		[self cancelWait];
		
		errorAlert = [[SCLAlertView alloc] init];
		
		__weak typeof(self) weakSelf = self;
		
		[errorAlert addButton:@"Later" actionBlock:^(void) {
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			strongSelf->errorAlert = nil;
			
			[strongSelf invokeCompletionBlockWithLocalUserID:strongSelf.user.uuid
												  completedActivation:NO
												shouldBackupAccessKey:NO];
			
		}];
		
		[errorAlert showQuestion:self
								 title:@"Cancel Activation"
							 subTitle:@"Are you sure you want to stop the account setup now? You can continue this later."
				  closeButtonTitle:@"Continue"
							 duration:0.f];
		
	}
	else
		[self invokeCompletionBlockWithLocalUserID:self.user.uuid
									  completedActivation:NO
									shouldBackupAccessKey:NO];
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  - UIPanGestureRecognizer
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
	return YES;
}


- (void)pan:(UIPanGestureRecognizer *)recognizer
{
	UIView *view = self.view;
	
	if (recognizer.state == UIGestureRecognizerStateBegan)
	{
		//	NSLog(@"pan: UIGestureRecognizerStateBegan");
		
		CGPoint location = [recognizer locationInView:view];
		
		BOOL isLeftHalf = (location.x < CGRectGetMidX(view.bounds));
		if (!isLeftHalf) {
			return;
		}
		
		if (containedNavigationController.viewControllers.count == 1) {
			return;
		}
		
		UIViewController *topViewController = containedNavigationController.topViewController;
		if ([topViewController respondsToSelector:@selector(canPopViewControllerViaPanGesture:)])
		{
			if (![(id<AccountSetupViewController_IOS_Child_Delegate>)topViewController canPopViewControllerViaPanGesture:self]) {
				return;
			}
		}
		
		interactionController = [UIPercentDrivenInteractiveTransition new];
		
		interactionController.completionCurve = UIViewAnimationCurveLinear;
		interactionController.completionSpeed = 0.75; // slow down the post-drag animation
		
		[containedNavigationController popViewControllerAnimated:YES];
		
		_btnBack.hidden = YES;
	}
	else if (recognizer.state == UIGestureRecognizerStateChanged)
	{
		//	NSLog(@"pan: UIGestureRecognizerStateChanged");
		
		if (interactionController)
		{
			CGPoint translation = [recognizer translationInView:view];
			CGFloat d = fabs(translation.x / CGRectGetWidth(view.bounds));
			
			d = d * 0.5; // 50% of the animation is the bounce
			
			[interactionController updateInteractiveTransition:d];
		}
	}
	else if (recognizer.state == UIGestureRecognizerStateEnded)
	{
		//	NSLog(@"pan: UIGestureRecognizerStateEnded");
		
		if (interactionController)
		{
			if ([recognizer velocityInView:view].x > 0) {
				[interactionController finishInteractiveTransition];
			} else {
				[interactionController cancelInteractiveTransition];
			}
			
			interactionController = nil;
		}
	}
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UINavigationControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
											 animationControllerForOperation:(UINavigationControllerOperation)operation
															  fromViewController:(UIViewController *)fromVC
																 toViewController:(UIViewController *)toVC
{
	//	NSLog(@"navigationController:animationControllerForOperation:fromViewController:toViewController:");
	
	ZDCPanTransition *transition = [[ZDCPanTransition alloc] init];
	transition.reverse = (operation == UINavigationControllerOperationPop);
	
	return transition;
}

- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)navigationController
								 interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animationController
{
	//	NSLog(@"navigationController:interactionControllerForAnimationController:");
	
	return interactionController;
}

- (void)navigationController:(UINavigationController *)navigationController
		 didShowViewController:(UIViewController *)viewController
						  animated:(BOOL)animated
{
	DDLogAutoTrace();
}


// MARK: view control


-(void)invokeCompletionBlockWithLocalUserID:(NSString *__nullable) localUserID
								completedActivation:(BOOL)completedActivation
							 shouldBackupAccessKey:(BOOL)shouldBackupAccessKey
{
	__weak typeof(self) weakSelf = self;

	if(completionHandler == nil)
		return;
	
	if ([NSThread isMainThread])
	{
		completionHandler(localUserID,completedActivation,shouldBackupAccessKey);
	}
	else
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
	
			strongSelf->completionHandler(localUserID,completedActivation, shouldBackupAccessKey);
			
		});
	}
}


-(void)popFromCurrentView
{
	[self cancelWait];
	
	if( containedNavigationController.viewControllers.count == 1)
	{
		[self invokeCompletionBlockWithLocalUserID:self.user.uuid
									  completedActivation:NO
									shouldBackupAccessKey:NO];
	}
	else
	{
		[containedNavigationController popViewControllerAnimated:YES];
	}
	
}

-(void)pushCreateAccount
{
	self.setupMode = AccountSetupMode_Trial;
	[self pushIdentity];
}

-(void)pushSignInToAccount
{
	self.setupMode = AccountSetupMode_ExistingAccount;
	[self pushIdentity];
}

-(void) pushIntro
{
	self.identityMode = IdenititySelectionMode_NewAccount;
	[self viewControllerForViewID:AccountSetupViewID_Intro];
	
	if(isSetup)
	{
		[containedNavigationController setViewControllers:@[vc_Intro]];
	}
	else
	{
		vcToPushTo = vc_Intro;
	}
	
}


- (void)pushHelpWithTag:(NSString*)tag
{
	[self viewControllerForViewID:AccountSetupViewID_Help];
	vc_Help.helpTag = tag;
	[containedNavigationController pushViewController:vc_Help animated:YES];
	
}

- (void)pushIdentity
{
	[self viewControllerForViewID:AccountSetupViewID_Identity];
	[containedNavigationController pushViewController:vc_Identity animated:YES];
}

- (void)pushResumeActivationForUserID:(NSString*)userID
{
	static BOOL  cancelOperationFlag = NO;
	__weak typeof(self) weakSelf = self;
	
	[self showWait: @"Please Wait…"
			 message: @"Checking user info"
  completionBlock: nil];
	
	[self resumeActivationForUserID:userID
					cancelOperationFlag:&cancelOperationFlag
						 completionBlock:^(NSError * _Nonnull error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;
		 
		 [strongSelf cancelWait];
		 
		 if(error)
		 {
			 [strongSelf showError: NSLocalizedString(@"Activation Failed", @"Activation Failed")
								message:error.localizedDescription
					 completionBlock:^{
						 [strongSelf handleFail];
					 }];
		 }
	 }];
}

- (void)pushDataBaseAuthenticate
{
	[self viewControllerForViewID:AccountSetupViewID_DBAuth];
	[containedNavigationController pushViewController:vc_DBAuth animated:YES];
}

- (void)pushSocialAuthenticate
{
	[self viewControllerForViewID:AccountSetupViewID_SocialAuth];
	[containedNavigationController pushViewController:vc_SocialAuth animated:YES];
}

- (void)pushDataBaseAccountCreate
{
	[self viewControllerForViewID:AccountSetupViewID_DBCreate];
	[containedNavigationController pushViewController:vc_DBCreate animated:YES];
}

- (void)pushAccountReady
{
	[self invokeCompletionBlockWithLocalUserID:self.user.uuid
								  completedActivation:YES
								shouldBackupAccessKey:!self.user.hasBackedUpAccessCode];
}

- (void)pushScanClodeCode
{
	[self viewControllerForViewID:AccountSetupViewID_ScanCloneCode];
	
	if(isSetup)
	{
		[containedNavigationController pushViewController:vc_ScanCloneCode animated:YES];
	}
	else
	{
		vcToPushTo = vc_ScanCloneCode;
	}
	
}

- (void)pushUnlockCloneCode:(NSString*)cloneString
{
	[self viewControllerForViewID:AccountSetupViewID_UnlockCloneCode];
	vc_UnlockCloneCode.cloneString = cloneString;
	
	if(isSetup)
	{
		[containedNavigationController pushViewController:vc_UnlockCloneCode animated:YES];
	}
	else
	{
		vcToPushTo = vc_UnlockCloneCode;
	}
}

- (void)pushRegionSelection
{
	
	[self viewControllerForViewID:AccountSetupViewID_Region];
	vc_Region.standAlone = NO;
	
	if(isSetup)
	{
		[containedNavigationController pushViewController:vc_Region animated:YES];
	}
	else
	{
		vcToPushTo = vc_Region;
	}
}

- (void)pushReauthenticateWithUserID:(NSString* __nonnull)userID
{
	
	DDLogAutoTrace();
	
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	self.identityMode = IdenititySelectionMode_ReauthorizeAccount;
	
	[self viewControllerForViewID:AccountSetupViewID_Identity];
	
	if(isSetup)
	{
		[containedNavigationController pushViewController:vc_Identity animated:YES];
	}
	else
	{
		vcToPushTo = vc_Identity;
	}
	
}

-(void)popToViewControllerForViewID:(AccountSetupViewID)viewID
			  withNavigationController:(UINavigationController*)navigationController
{
	AccountSetupSubViewController_Base* vc =  [self viewControllerForViewID:viewID];
	
	for (UIViewController *controller in navigationController.viewControllers)
	{
		if ([controller isKindOfClass:[vc class]])
		{
			[navigationController popToViewController:controller
														animated:YES];
			break;
		}
	}
}

-(void)popToNonAccountSetupView:(UINavigationController*)navigationController
{
	UIViewController *lastController = nil;
	
	for (UIViewController *controller in navigationController.viewControllers)
	{
		if (! [controller isKindOfClass:[AccountSetupSubViewController_Base class]])
		{
			lastController = controller;
		}
		else
		{
			break;
		}
	}
	
	if(lastController)
	{
		[navigationController popToViewController:lastController
													animated:YES];
	}
	else
	{
		
		if(completionHandler)
		{
			[self invokeCompletionBlockWithLocalUserID:self.user.uuid
										  completedActivation:NO
										shouldBackupAccessKey:NO];
		}
		else
		{
			[self pushIntro];
			
		}
		
		
	}
}


// MARK: IOS versions of social ID mgmt

-(void)pushSocialIdMgmtWithUserID:(NSString* __nonnull)userID
			withNavigationController:(UINavigationController*)navigationController
{
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	self.identityMode = IdenititySelectionMode_ExistingAccount;
	[self viewControllerForViewID:AccountSetupViewID_SocialidMgmt];
	
	[navigationController pushViewController:vc_SocialidMgmt animated:YES];
	vc_SocialidMgmt.userID =  userID;
}


-(void)pushUserAvatarWithUserID:(NSString* __nonnull)userID
								auth0ID:(NSString * __nullable )auth0ID
		 withNavigationController:(UINavigationController*)navigationController
{
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	self.identityMode = IdenititySelectionMode_ExistingAccount;
	[self viewControllerForViewID:AccountSetupViewID_UserAvatar];
	vc_UserAvatar.userID =  userID;
	vc_UserAvatar.auth0ID = auth0ID;
	
	[navigationController pushViewController:vc_UserAvatar animated:YES];
}


- (void)pushAddIdentityWithUserID:(NSString* __nonnull)userID
			withNavigationController:(UINavigationController*)navigationController

{
	DDLogAutoTrace();
	
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	self.identityMode = IdenititySelectionMode_ExistingAccount;
	[self viewControllerForViewID:AccountSetupViewID_AddIdentitityProvider];
	
	[navigationController pushViewController:vc_AddIdent animated:YES];
}

- (void)pushDataBaseAccountLogin:(NSString* __nonnull)userID
		  withNavigationController:(UINavigationController*)navigationController
{
	DDLogAutoTrace();
	
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	[self viewControllerForViewID:AccountSetupViewID_ReAuthDatabase];
	[navigationController pushViewController:vc_DBReAuth animated:YES];
	
	
}

- (void)pushDataBaseAccountCreate:(NSString* __nonnull)userID
			withNavigationController:(UINavigationController*)navigationController
{
	DDLogAutoTrace();
	
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	[self viewControllerForViewID:AccountSetupViewID_AddDatabase];
	[navigationController pushViewController:vc_DBCreateAdd animated:YES];
}

- (void)pushSocialAuthenticate:(NSString* __nonnull)userID
							 provider:(NSDictionary* __nonnull)provider
		withNavigationController:(UINavigationController*)navigationController
{
	DDLogAutoTrace();
	
	NSError* error = NULL;
	if(! [self commonInitWithUserID:userID error:&error])
	{
		[self handleInternalError:error];
		return;
	}
	
	[self viewControllerForViewID:AccountSetupViewID_AddSocial];
	self.selectedProvider = provider;
	[navigationController pushViewController:vc_SocialAuthAdd animated:YES];
}

@end
