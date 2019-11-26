/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/


#import "UserSearchSocialIDViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "SCLAlertView.h"
#import "SocialIDUITableViewCell.h"
#import "Auth0ProviderManager.h"
#import "VerifyPublicKey_IOS.h"

#import "ZDCLogging.h"

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
	NSArray *auth0IDs;
    
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
     //   auth0IDs = searchResultInfo.auth0_profiles.allKeys;
      }
    return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	//    // make the left inset line up with the cell text
	_tblSocialID.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0); // top, left, bottom, right
	_tblSocialID.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblSocialID.frame.size.width, 1)];
	
	defaultUserImage = [zdc.imageManager.defaultUserAvatar imageWithMaxSize:[SocialIDUITableViewCell avatarSize]];
		
	[SocialIDUITableViewCell registerViewsforTable:_tblSocialID bundle:[ZeroDarkCloud frameworkBundle]];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    
    self.navigationItem.title = @"Social Identities";
    
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
    
    [_vwWait.layer setCornerRadius:8.0f];
    [_vwWait.layer setMasksToBounds:YES];
    
    [self cancelWait];


}


-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
    
 //   [[NSNotificationCenter defaultCenter]  removeObserver:self];
  
}


-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
    [self handleNavigationBack:NULL];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
    [[self navigationController] popViewControllerAnimated:YES];
}




#pragma mark - Progress

-(void) showError:(NSString*)title
          message:(NSString*)message
  completionBlock:(dispatch_block_t __nullable)completionBlock

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


-(void) showWait:(NSString*)title
{
    [self cancelWait];
    
    NSMutableDictionary * userInfo =    @{  @"title":   title?:@""  }.mutableCopy;
    
    showWaitBoxTimer =  [NSTimer scheduledTimerWithTimeInterval:.7
                                                         target:self
                                                       selector:@selector(showWaitBox:)
                                                       userInfo:userInfo
                                                        repeats:NO];
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


-(void) cancelWait
{
    if(errorAlert)
    {
        [errorAlert hideView];
        errorAlert = nil;
    }
    
    if(showWaitBoxTimer) {
        [showWaitBoxTimer invalidate];
    }
    
    [_actWait stopAnimating];
    _vwWait.hidden = YES;
    
}

#pragma mark - tableview

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return auth0IDs.count;
}



- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [SocialIDUITableViewCell heightForCell];
}


- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSAssert(NO, @"Not implemented"); // finish refactoring
	return nil;
/*
    SocialIDUITableViewCell *cell = (SocialIDUITableViewCell *)[tv dequeueReusableCellWithIdentifier:kSocialIDCellIdentifier];
    
    __weak typeof(self) weakSelf = self;
    
    NSString* auth0ID = [auth0IDs objectAtIndex:indexPath.row];
    NSDictionary* auth0Info = [searchResult.auth0_profiles objectForKey:auth0ID];
    
    BOOL isPreferredProfile = [searchResult.auth0_preferredID isEqualToString:auth0ID];
 
    NSString* displayName   = auth0Info[@"displayName"];
    
    NSURL *pictureURL = nil;
    NSString *picture =
	  [Auth0Utilities correctPictureForAuth0ID: auth0ID
	                               profileData: auth0Info
	                                    region: searchResultInfo.aws_region
	                                    bucket: searchResultInfo.aws_bucket];
    if(picture)
        pictureURL = [NSURL URLWithString:picture];
   
    cell.Auth0ID = auth0ID;
    cell.lbLeftTag.textColor = self.view.tintColor;

    NSArray* comps = [auth0ID componentsSeparatedByString:@"|"];
    NSString* provider = comps.firstObject;

    if(isPreferredProfile)
    {
        cell.lbLeftTag.text = @"✓";
    }
    else
    {
        cell.lbLeftTag.text = @"";
    }

    OSImage* providerImage = [[providerManager
                                   providerIcon:Auth0ProviderIconType_Signin
                                    forProvider:provider]
                                  scaledToHeight:[SocialIDUITableViewCell imgProviderHeight]];

    if(providerImage)
    {
        cell.imgProvider.image =  providerImage;
        cell.imgProvider.hidden = NO;
        cell.lbProvider.hidden = YES;
    }
    else
    {
        NSString* providerName =  [providerManager displayNameforProvider:provider];
        if(!providerName)
            providerName = provider;
        cell.lbProvider.text = providerName;
        cell.lbProvider.hidden = NO;
        cell.imgProvider.hidden = YES;
    }
    
    cell.lblUserName.text = displayName;
    cell.imgAvatar.layer.cornerRadius =  SocialIDUITableViewCell.avatarSize.height / 2;
    cell.imgAvatar.clipsToBounds = YES;
    cell.imgAvatar.image = defaultUserImage;

    if(pictureURL)
    {
        CGSize avatarSize = [SocialIDUITableViewCell avatarSize];
        
         [imageManager fetchUserAvatar:localUserID
                            identityID: auth0ID
                                fromURL: pictureURL
			                       options: nil
                           processingID: pictureURL.absoluteString
                        processingBlock:^UIImage * _Nonnull(UIImage * _Nonnull image)
         {
             return [image imageWithMaxSize:avatarSize];
         }
                         preFetchBlock:^(UIImage * _Nullable image)
         {
             if(image)
             {
                 cell.imgAvatar.image = image;
             }
         }
                        postFetchBlock:^(UIImage * _Nullable image, NSError * _Nullable error)
         {
             
             __strong typeof(self) strongSelf = weakSelf;
             if(strongSelf == nil) return;
             
             // check that the cell is still being used for this user
             
             if( [cell.Auth0ID isEqualToString: auth0ID])
             {
                 if(image)
                 {
                     cell.imgAvatar.image =  image;
                 }
                 else
                 {
                     cell.imgAvatar.image = strongSelf->defaultUserImage;
                 }
             }
         }];
    }
    else
    {
        cell.imgAvatar.image = defaultUserImage;
    }

    return cell;
*/
}


// prevent deselection - in effect we have radio buttons
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray<NSIndexPath *>* indexPaths = tableView.indexPathsForSelectedRows;
    
    [indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * iPath, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if(![iPath isEqual:indexPath])
        {
            [tableView deselectRowAtIndexPath:iPath animated:NO];
            *stop = YES;
        }
    }];
    
    NSString* auth0ID = [auth0IDs objectAtIndex:indexPath.row];
    
	SEL selector = @selector(userSearchSocialIDViewController:didSelectIdentityID:forUserID:);
	if ([self.delegate respondsToSelector:selector])
	{
		[self.delegate userSearchSocialIDViewController: self
		                            didSelectIdentityID: auth0ID
		                                      forUserID: searchResult.userID];
	}
	
	[[self navigationController] popViewControllerAnimated:YES];
}

#pragma - actions

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
