/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
static const int ddLogLevel = DDLogLevelWarning;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

@implementation UserSearchSocialIDViewController_IOS
{
    IBOutlet __weak UITableView             *_tblSocialID;
    IBOutlet __weak UIBarButtonItem            *_bbVerifyPubKey;
    
    IBOutlet __weak UIView                     *_vwWait;
    IBOutlet __weak UIActivityIndicatorView *_actWait;
    IBOutlet __weak UILabel                     *_lblWait;
    NSTimer *       showWaitBoxTimer;
    SCLAlertView *  errorAlert;
 
    ZeroDarkCloud*                   owner;
    Auth0ProviderManager*            providerManager;
    ZDCImageManager*                 imageManager;
    
    NSString*                       localUserID;
    ZDCSearchUserResult*            searchResultInfo;
    NSArray*                        auth0IDs;
    
    UIImage*                        defaultUserImage;
    
    UISwipeGestureRecognizer*       swipeRight;
}

@synthesize delegate = delegate;


- (instancetype)initWithDelegate:(nullable id <UserSearchSocialIDViewControllerDelegate>)inDelegate
                           owner:(ZeroDarkCloud*)inOwner
                     localUserID:(NSString* __nonnull)inLocalUserID
                searchResultInfo:(ZDCSearchUserResult* __nonnull)inSearchResultInfo
{
  
    NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UserSearchSocialIDViewController_IOS" bundle:bundle];
    self = [storyboard instantiateViewControllerWithIdentifier:@"UserSearchSocialIDViewController"];
    if (self)
    {
        owner = inOwner;
        delegate = inDelegate;
        localUserID = inLocalUserID;
        searchResultInfo = inSearchResultInfo;
        auth0IDs = searchResultInfo.auth0_profiles.allKeys;
      }
    return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	//    // make the left inset line up with the cell text
	_tblSocialID.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0); // top, left, bottom, right
	_tblSocialID.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblSocialID.frame.size.width, 1)];
	
	defaultUserImage = [imageManager.defaultUserAvatar imageWithMaxSize:[SocialIDUITableViewCell avatarSize]];
		
	[SocialIDUITableViewCell registerViewsforTable:_tblSocialID bundle:[ZeroDarkCloud frameworkBundle]];
	
	providerManager = owner.auth0ProviderManager;
	imageManager =  owner.imageManager;
	
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
    SocialIDUITableViewCell *cell = (SocialIDUITableViewCell *)[tv dequeueReusableCellWithIdentifier:kSocialIDCellIdentifier];
    
    __weak typeof(self) weakSelf = self;
    
    NSString* auth0ID = [auth0IDs objectAtIndex:indexPath.row];
    NSDictionary* auth0Info = [searchResultInfo.auth0_profiles objectForKey:auth0ID];
    
    BOOL isPreferredProfile = [searchResultInfo.auth0_preferredID isEqualToString:auth0ID];
 
    NSString* displayName   = auth0Info[@"displayName"];
    
    NSURL * pictureURL = nil;
    NSString* picture  = [Auth0ProviderManager correctPictureForAuth0ID:auth0ID
                                                            profileData:auth0Info
                                                                 region:searchResultInfo.aws_region
                                                                 bucket:searchResultInfo.aws_bucket];
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
        
         [ imageManager fetchUserAvatar:localUserID
                                auth0ID: auth0ID
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
    
    if([self.delegate respondsToSelector:@selector(userSearchSocialIDViewController:
                                                   didSelectAuth0ID:forUserID:)])
    {
        
        [self.delegate userSearchSocialIDViewController:self
                                           didSelectAuth0ID:auth0ID
                                                  forUserID:searchResultInfo.uuid];
    }
    
    [[self navigationController] popViewControllerAnimated:YES];
}

#pragma - actions

-(void) createRemoteUserIfNeeded:(NSString*)remoteUserID
                 completionBlock:(void (^)(ZDCUser *remoteUser, NSError *error))completionBlock
{
 
     __block ZDCUser*    user    = nil;
    
    // SELECT A USERID for doing searches
    [owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        user = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
    }];
    
    if(!user)
    {
        dispatch_queue_t concurrentQueue
        = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
        
        [owner.remoteUserManager createRemoteUserWithID: remoteUserID
                                            requesterID: localUserID
                                        completionQueue: concurrentQueue
                                        completionBlock:^(ZDCUser *remoteUser, NSError *error)
         {
             
             dispatch_async(dispatch_get_main_queue(), ^{ @autoreleasepool {
                 
                 if(completionBlock)
                     completionBlock(remoteUser,error);
             }});
             
         }];
    }
    else
    {
        if(completionBlock)
            completionBlock(user,nil);
      }
}


-(IBAction)btnVerifyPubKeyHit:(id)sender
{
    __weak typeof(self) weakSelf = self;

    [self createRemoteUserIfNeeded:searchResultInfo.uuid
                   completionBlock:^(ZDCUser *remoteUser, NSError *error)
     {
         __strong typeof(self) strongSelf = weakSelf;
         if (strongSelf)
         {
             VerifyPublicKey_IOS* vc = [[VerifyPublicKey_IOS alloc]
                                        initWithOwner:strongSelf->owner
                                        remoteUserID:remoteUser.uuid
                                        localUserID:strongSelf->localUserID];
             
             strongSelf.navigationController.navigationBarHidden = NO;
             //    [self.tabBarController.tabBar setHidden:YES];
             [strongSelf.navigationController pushViewController:vc animated:YES];
         }
     }];  
}


@end
