/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "UserSearchSocialIDViewController_IOS.h"

#import "Auth0ProviderManager.h"
#import "SCLAlertView.h"
#import "SocialIDUITableViewCell.h"
#import "VerifyPublicKey_IOS.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZDCImageManagerPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "OSImage+ZeroDark.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@implementation UserSearchSocialIDViewController_IOS
{
    IBOutlet __weak UITableView             *_tblSocialID;
    IBOutlet __weak UIBarButtonItem            *_bbVerifyPubKey;
    
    IBOutlet __weak UIView                     *_vwWait;
    IBOutlet __weak UIActivityIndicatorView *_actWait;
    IBOutlet __weak UILabel                     *_lblWait;
    NSTimer *       showWaitBoxTimer;
    SCLAlertView *  errorAlert;
 
	ZeroDarkCloud *zdc;
	
	NSString *localUserID;
	ZDCSearchResult *searchResult;
    
	UIImage *defaultUserImage;
    
	UISwipeGestureRecognizer *swipeRight;
}

@synthesize delegate = delegate;

- (instancetype)initWithDelegate:(id<UserSearchSocialIDViewControllerDelegate>)inDelegate
                           owner:(ZeroDarkCloud *)inOwner
                     localUserID:(NSString *)inLocalUserID
                    searchResult:(ZDCSearchResult *)inSearchResult
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UserSearchSocialIDViewController_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"UserSearchSocialIDViewController"];
	if (self)
	{
		zdc = inOwner;
		delegate = inDelegate;
		localUserID = [inLocalUserID copy];
		searchResult = inSearchResult;
	}
	return self;
}

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
	[super viewDidLoad];
	
	// make the left inset line up with the cell text
	_tblSocialID.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0); // top, left, bottom, right
	_tblSocialID.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblSocialID.frame.size.width, 1)];
	
	defaultUserImage = [zdc.imageManager.defaultUserAvatar imageWithMaxSize:[SocialIDUITableViewCell avatarSize]];
		
	[SocialIDUITableViewCell registerViewsforTable:_tblSocialID bundle:[ZeroDarkCloud frameworkBundle]];
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	self.navigationItem.title = @"Social Identities";
    
	UIImage *image =
	           [[UIImage imageNamed: @"backarrow"
	                       inBundle: [ZeroDarkCloud frameworkBundle]
	  compatibleWithTraitCollection: nil]
	         imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate];
    
	UIBarButtonItem *backItem =
	  [[UIBarButtonItem alloc] initWithImage: image
	                                   style: UIBarButtonItemStylePlain
	                                  target: self
	                                  action: @selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
  
	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];
	
	[_vwWait.layer setCornerRadius:8.0f];
	[_vwWait.layer setMasksToBounds:YES];
	
	[self cancelWait]; // why ?
}

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
	
//	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}

- (void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	ZDCLogAutoTrace();
	
	[self handleNavigationBack:NULL];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	ZDCLogAutoTrace();
	
	[[self navigationController] popViewControllerAnimated:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Progress
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)showError:(NSString *)title
          message:(NSString *)message
  completionBlock:(dispatch_block_t)completionBlock
{
    [self cancelWait];
    
    errorAlert = [[SCLAlertView alloc] initWithNewWindowWidth: self.view.frame.size.width -40];
    errorAlert.showAnimationType = SCLAlertViewShowAnimationFadeIn;
    
    __weak typeof(self) weakSelf = self;
    
    [errorAlert addButton:@"OK" actionBlock:^(void) {
        if(completionBlock) completionBlock();
        
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->errorAlert = nil;
        }
    }];
    
    [errorAlert showError:self
                    title:title
                 subTitle:message
         closeButtonTitle:nil
                 duration:0.f];
    
}

- (void)showWait:(NSString *)title
{
	ZDCLogAutoTrace();
	
	[self cancelWait];
    
	NSDictionary *userInfo = @{
		@"title" : title ?: @""
	};
	
	showWaitBoxTimer =
	  [NSTimer scheduledTimerWithTimeInterval: 0.7
	                                   target: self
	                                 selector: @selector(showWaitBox:)
	                                 userInfo: userInfo
	                                  repeats: NO];
}

- (void)showWaitBox:(NSTimer*)sender
{
    NSDictionary* userInfo = sender.userInfo;
    
    NSString* title = userInfo[@"title"];
    
    __weak typeof(self) weakSelf = self;
    
    _lblWait.text = title;
    [_actWait startAnimating];
    
    _vwWait.hidden = NO;
    _vwWait.alpha = 0.0;
    
    [UIView animateWithDuration:0.25 animations:^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_vwWait.alpha = 1.0;
        }
        
    } completion:^(BOOL finished) {
        
    }];
}


- (void)cancelWait
{
	ZDCLogAutoTrace();
	
	if (errorAlert)
	{
		[errorAlert hideView];
		errorAlert = nil;
	}
	
	if (showWaitBoxTimer) {
		[showWaitBoxTimer invalidate];
	}
    
	[_actWait stopAnimating];
	_vwWait.hidden = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return searchResult.identities.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [SocialIDUITableViewCell heightForCell];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	SocialIDUITableViewCell *cell = (SocialIDUITableViewCell *)
	  [tv dequeueReusableCellWithIdentifier:kSocialIDCellIdentifier];
	
	ZDCUserIdentity *identity = searchResult.identities[indexPath.row];
	NSString *identityID = identity.identityID;
	
	BOOL isPreferredIdentity = [searchResult.preferredIdentityID isEqual:identityID];
 	NSString *displayName = identity.displayName;
	
	cell.identityID = identityID;
	cell.lbLeftTag.textColor = self.view.tintColor;

	if (isPreferredIdentity) {
		cell.lbLeftTag.text = @"✓";
	}
	else {
		cell.lbLeftTag.text = @"";
	}
	
	UIImage *providerImage =
	 [[zdc.auth0ProviderManager iconForProvider: identity.provider
														type: Auth0ProviderIconType_Signin]
	                             scaledToHeight: [SocialIDUITableViewCell imgProviderHeight]];

	if (providerImage)
	{
		cell.imgProvider.image =  providerImage;
		cell.imgProvider.hidden = NO;
		cell.lbProvider.hidden = YES;
	}
	else
	{
		NSString *providerName = [zdc.auth0ProviderManager displayNameForProvider:identity.provider];
		
		cell.lbProvider.text = providerName;
		cell.lbProvider.hidden = NO;
		cell.imgProvider.hidden = YES;
	}
	
	cell.lblUserName.text = displayName;
	cell.imgAvatar.layer.cornerRadius =  SocialIDUITableViewCell.avatarSize.height / 2;
	cell.imgAvatar.clipsToBounds = YES;
	cell.imgAvatar.image = defaultUserImage;
	
	CGSize avatarSize = [SocialIDUITableViewCell avatarSize];
	
	UIImage* (^processingBlock)(UIImage*) = ^UIImage* (UIImage *image) {
		
		return [image scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
	};
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns
		
		cell.imgAvatar.image = image ?: self->defaultUserImage;
	};
	
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetchBlock is invoked LATER, possibly after downloading the avatar
		
		if (image) {
			// Ensure cell hasn't been recycled
			if ([cell.identityID isEqualToString:identityID]) {
				cell.imgAvatar.image = image;
			}
		}
	};
	
	[zdc.imageManager fetchUserAvatar: searchResult
	                       identityID: identityID
	                     processingID: NSStringFromClass([self class])
	                  processingBlock: processingBlock
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];

	return cell;
}


// prevent deselection - in effect we have radio buttons
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	NSArray<NSIndexPath *>* indexPaths = tableView.indexPathsForSelectedRows;
	[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath *iPath, NSUInteger idx, BOOL *stop) {
        
		if (![iPath isEqual:indexPath])
		{
			[tableView deselectRowAtIndexPath:iPath animated:NO];
			*stop = YES;
		}
	}];
	
	ZDCUserIdentity *identity = searchResult.identities[indexPath.row];
	NSString *identityID = identity.identityID;
    
	SEL selector = @selector(userSearchSocialIDViewController:didSelectIdentityID:forUserID:);
	if ([self.delegate respondsToSelector:selector])
	{
		[self.delegate userSearchSocialIDViewController: self
		                            didSelectIdentityID: identityID
		                                      forUserID: searchResult.userID];
	}
	
	[[self navigationController] popViewControllerAnimated:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)btnVerifyPubKeyHit:(id)sender
{
	__weak typeof(self) weakSelf = self;
	
	[zdc.userManager fetchUserWithID: searchResult.userID
	                     requesterID: localUserID
	                 completionQueue: dispatch_get_main_queue()
	                 completionBlock:^(ZDCUser *remoteUser, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		VerifyPublicKey_IOS *vc =
		  [[VerifyPublicKey_IOS alloc] initWithOwner: strongSelf->zdc
		                                remoteUserID: remoteUser.uuid
		                                 localUserID: strongSelf->localUserID];
		
		strongSelf.navigationController.navigationBarHidden = NO;
	//	[self.tabBarController.tabBar setHidden:YES];
		[strongSelf.navigationController pushViewController:vc animated:YES];
	}];  
}

@end
