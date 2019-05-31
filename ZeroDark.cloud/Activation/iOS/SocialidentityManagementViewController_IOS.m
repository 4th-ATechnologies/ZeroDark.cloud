/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "SocialidentityManagementViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCImageManagerPrivate.h"

#import "ZDCLogging.h"

#import "SocialIDUITableViewCell.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "IdentityProviderTableViewCell.h"
#import "SCLAlertView.h"
#import "SCLAlertViewStyleKit.h"

// Categories
#import "OSImage+ZeroDark.h"

// Libraries
#import <stdatomic.h>

// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int ddLogLevel = DDLogLevelVerbose;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)



@implementation SocialidentityManagementViewController_IOS
{
	IBOutlet __weak UITableView             *_tblProviders;
	IBOutlet __weak UIView                  *_vwAddMoreLoser;

    YapDatabaseConnection *         databaseConnection;
    Auth0ProviderManager*			providerManager;
    ZDCImageManager*                 imageManager;
    AFNetworkReachabilityManager*   reachability;

	NSString*                       localUserID;
	NSArray *                       providerTable;
    UIImage*                        defaultUserImage;
  
    dispatch_queue_t            internetQueue;
    void  *                     IsOnInternetQueueKey;
    
    BOOL                        hasInternet;

	SCLAlertView *                  warningAlert;
	BOOL registered;
}

@synthesize accountSetupVC = accountSetupVC;


- (void)viewDidLoad {
	[super viewDidLoad];

	registered = NO;

    internetQueue = dispatch_queue_create("SocialidentityManagementViewController.internetQueue", DISPATCH_QUEUE_SERIAL);
    IsOnInternetQueueKey = &IsOnInternetQueueKey;
    dispatch_queue_set_specific(internetQueue, IsOnInternetQueueKey, IsOnInternetQueueKey, NULL);

	defaultUserImage = [imageManager.defaultUserAvatar imageWithMaxSize:[SocialIDUITableViewCell avatarSize]];

	[SocialIDUITableViewCell registerViewsforTable:_tblProviders bundle:[ZeroDarkCloud frameworkBundle]];
	_vwAddMoreLoser.hidden = YES;

	// make the left inset line up with the cell text
	_tblProviders.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0); // top, left, bottom, right

	_tblProviders.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblProviders.frame.size.width, 1)];

	self.navigationItem.hidesBackButton = YES;

}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	accountSetupVC.btnBack.hidden = YES;

	databaseConnection = accountSetupVC.owner.databaseManager.uiDatabaseConnection;
	providerManager = accountSetupVC.owner.auth0ProviderManager;
    imageManager =  accountSetupVC.owner.imageManager;
    reachability = accountSetupVC.owner.reachability;

  
	self.navigationItem.title = @"Social Identities";

	UIImage* image = [[UIImage imageNamed:@"backarrow"
								 inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																 style:UIBarButtonItemStylePlain
																target:self
																action:@selector(handleNavigationBack:)];

	self.navigationItem.leftBarButtonItem = backItem;

	UIBarButtonItem* addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
																			 target:self
																			 action:@selector(btnAddSocialTapped:)];

	self.navigationItem.rightBarButtonItem = addItem;


}

-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if(!registered)
	{
        
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(reachabilityChanged:)
                                                     name: AFNetworkingReachabilityDidChangeNotification
                                                   object: nil /* notification doesn't assign object ! */];
        
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(databaseConnectionDidUpdate:)
													 name:UIDatabaseConnectionDidUpdateNotification
												   object:nil];

        hasInternet = reachability.isReachable;

		registered = YES;
	}

	[self refreshProviders];
	[self refreshView];
}


-(void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	//    DDLogAutoTrace();

	if( registered)
	{
//		[S4ThumbnailManager unCacheAvatarForSize:SocialIDUITableViewCell.avatarSize];

		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:UIDatabaseConnectionDidUpdateNotification
													  object:nil];

		registered = NO;
	}


}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}



- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return NO;

}


- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];

	if(!localUserID)
		return;

	BOOL hasUserChanges = NO;

	if(localUserID)
	{
		hasUserChanges =  [databaseConnection hasChangeForKey:localUserID
												 inCollection:kZDCCollection_Users
											  inNotifications:notifications];
	}

	if(hasUserChanges)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refreshView];
		});


}


/**
 * Invoked when the reachability changes.
 * That is, when the circumstances of our Internet access has changed.
 **/
- (void)reachabilityChanged:(NSNotification *)notification
{
    DDLogAutoTrace();
	__weak typeof(self) weakSelf = self;

    BOOL newHasInternet = reachability.isReachable;
    
    // Note: the 'hasInternet' variable is only safe to access/modify within the 'queue'.
    dispatch_block_t block = ^{ @autoreleasepool {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;

        BOOL updateUI = NO;
        
        if (!strongSelf->hasInternet && newHasInternet)
        {
            strongSelf->hasInternet = YES;
            updateUI = YES;
        }
        else if (strongSelf->hasInternet && !newHasInternet)
        {
            strongSelf->hasInternet = NO;
            updateUI = YES;
         }
        
        if(updateUI)
        {
            dispatch_async(dispatch_get_main_queue(), ^{ @autoreleasepool {
                
                if(newHasInternet)
                {
                    [self refreshView];
                }
                else
                {
                }
            }});
        }
    }};
    
    if (dispatch_get_specific(IsOnInternetQueueKey))
        block();
    else
        dispatch_async(internetQueue, block);
}

-(void) setUserID:(NSString *)localUserIDIn
{
	localUserID = localUserIDIn;
	if(registered)
	{
		[self refreshView];
	}

}


// MARK: actions

- (IBAction)btnAddSocialTapped:(id)sender
{
	DDLogAutoTrace();

	[self addProviderforUserID:localUserID];
}

// MARK: refresh

-( void)refreshView
{
	NSString* userID = localUserID?localUserID: accountSetupVC.user.uuid;
	localUserID = userID;

	if(!userID)return;

	__block ZDCLocalUser *user = NULL;

	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];

	}];

	if(!user)
		return;

	[self fillProviderView];

}

- (void)refreshProviders
{
	__weak typeof(self) weakSelf = self;

    if(!hasInternet)
        return;
    
	[accountSetupVC showWait: @"Please Wait…"
					 message: @"Checking our server"
			  viewController: self
			 completionBlock: nil];

	[accountSetupVC.owner.localUserManager refreshAuth0ProfilesForLocalUserID: localUserID
									  completionQueue: dispatch_get_main_queue()
									  completionBlock:^(NSError *error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;

		 [strongSelf->accountSetupVC cancelWait];
		 if (error)
		 {
			 [strongSelf.accountSetupVC showError: @"Could not get social identity"
									message: error.localizedDescription
							 viewController: self
							completionBlock: nil];
		 }
		 else
		 {
 			 [strongSelf refreshView];
		 }
	 }];
}


- (void)fillProviderView
{
	__weak typeof(self) weakSelf = self;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
 	__block ZDCLocalUser *user = nil;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
	}];
#pragma clang diagnostic pop

	if (!user) return;

	NSMutableArray* providers = [NSMutableArray array];
	NSDictionary* profiles = user.auth0_profiles;

	[profiles enumerateKeysAndObjectsUsingBlock:^(NSString* auth0_userID, NSDictionary* profile, BOOL* stop) {

		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;

		NSArray* comps = [auth0_userID componentsSeparatedByString:@"|"];
		NSString* provider = comps.firstObject;

		BOOL isRecoveryId =  [Auth0Utilities isRecoveryProfile:profile];

		NSDictionary* providerInfo = strongSelf->providerManager.providersInfo[provider];
		if ( !isRecoveryId  // skip the recovery ident
			&& providerInfo)
		{
			NSString* providerName = providerInfo[kAuth0ProviderInfo_Key_DisplayName];
			NSString* connection = profile[@"connection"];

			// this is a hack for now, we would really use the entire auth0 ID

			OSImage* 	providerImage = [[strongSelf->providerManager providerIcon:Auth0ProviderIconType_Signin
																	 forProvider:provider]
										 scaledToHeight:[SocialIDUITableViewCell imgProviderHeight]];

			NSURL * pictureURL = nil;
			NSString* picture  = [Auth0ProviderManager correctPictureForAuth0ID:auth0_userID
																	profileData:profile
																		 region:user.aws_region
																		 bucket:user.aws_bucket];
			if(picture)
				pictureURL = [NSURL URLWithString:picture];

			NSString* displayName = [user displayNameForAuth0ID:auth0_userID];
            
            BOOL isUserAuthProfile = [Auth0Utilities isUserAuthProfile:profile];
            
			NSMutableDictionary* profileDict = [NSMutableDictionary dictionaryWithDictionary
												:@{
												   @"isRealCell"            :@(YES),
                                                   @"isUserAuthProfile"     :@(isUserAuthProfile),
												   @"displayName"           : displayName,
												   @"connection"            : connection?connection:@"",
												   @"auth0_userID"          : auth0_userID,
												   kAuth0ProviderInfo_Key_ID : provider,
												   @"providerName"          : providerName,
												   @"isPrimaryProfile"      : @([profile[@"isPrimaryProfile"] boolValue]),
												   @"isPreferredProfile"    : @([auth0_userID isEqualToString:user.auth0_preferredID])
												   }];

			if(pictureURL)
				[profileDict setObject:pictureURL forKey:@"pictureURL"];

			if(providerImage)
				[profileDict setObject:providerImage forKey:@"providerImage"];

			[providers addObject:profileDict];
		}
	}];

	// sort alpha
	[providers sortUsingComparator:^NSComparisonResult(NSDictionary *item1, NSDictionary *item2) {

		NSString* id1 = item1[@"providerName"];
		NSString* id2 = item2[@"providerName"];

		return [id1 localizedCaseInsensitiveCompare:id2];
	}];

	_vwAddMoreLoser.hidden = providers.count > 1;

	// show 5 entries even if they are blank
	for( NSUInteger i = providers.count; i < 5 ; i++)
	{
		[providers addObject:@{@"isRealCell":@(NO) }];
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;

		strongSelf->providerTable = providers;
		[ strongSelf reloadTable];
	});

}

-(void) scrollToPreferedProvider
{
	for(int row = 0; row < providerTable.count; row++)
	{
		NSDictionary* dict  =  providerTable[row];
		BOOL isPreferredProfile = [dict[@"isPreferredProfile"] boolValue];

		if(isPreferredProfile )
		{
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
			NSArray* visablePaths = _tblProviders.indexPathsForVisibleRows;

			if(![visablePaths containsObject:indexPath])
			{
				[_tblProviders scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];

			}
			return;
		}
	}
}

-(void) reloadTable
{

	[_tblProviders reloadData];
	[self scrollToPreferedProvider];


}


// MARK: tableview

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return providerTable.count;
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [SocialIDUITableViewCell heightForCell];
}


- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	SocialIDUITableViewCell *cell = (SocialIDUITableViewCell *)[tv dequeueReusableCellWithIdentifier:kSocialIDCellIdentifier];
	
	__weak typeof(self) weakSelf = self;
	
	NSDictionary* dict  =  providerTable[indexPath.row];
	
	BOOL isRealCell =   [dict[@"isRealCell"] boolValue];
	
	if(isRealCell)
	{
		NSString* auth0ID 		= dict[@"auth0_userID"];
		NSString* provider 		= dict[kAuth0ProviderInfo_Key_ID];
		NSURL*	 pictureURL		= dict[@"pictureURL"];
		NSString* displayName	= dict[@"displayName"];
		BOOL isPrimaryProfile 	= [dict[@"isPrimaryProfile"] boolValue];
		BOOL isPreferredProfile = [dict[@"isPreferredProfile"] boolValue];
		BOOL isUserAuthProfile  = [dict[@"isUserAuthProfile"] boolValue];
		
		cell.uuid = localUserID;
		cell.Auth0ID = auth0ID;
		cell.lbLeftTag.textColor = self.view.tintColor;
		cell.delegate = (id<SocialIDUITableViewCellDelegate>) self;
		if(isPreferredProfile)
		{
			cell.lbLeftTag.text = @"✓";
		}
		else if(isPrimaryProfile)
		{
			cell.lbLeftTag.text = @"⚬";
		}
		else
		{
			cell.lbLeftTag.text = @"";
		}
		
		
		if(isUserAuthProfile)
		{
			[cell showRightButton:YES];
		}
		else
		{
			[cell showRightButton:NO];
		}
		
		OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:provider] scaledToHeight:[SocialIDUITableViewCell imgProviderHeight]];
		
		if(providerImage)
		{
			cell.imgProvider.image =  providerImage;
			cell.imgProvider.hidden = NO;
			cell.lbProvider.hidden = YES;
		}
		else
		{
			cell.lbProvider.text = provider;
			cell.lbProvider.hidden = NO;
			cell.imgProvider.hidden = YES;
		}
		
		cell.lblUserName.text = displayName;
		cell.imgAvatar.hidden = NO;
		
		cell.imgAvatar.layer.cornerRadius =  SocialIDUITableViewCell.avatarSize.height / 2;
		cell.imgAvatar.clipsToBounds = YES;
		
		if(pictureURL)
		{
			CGSize avatarSize = [SocialIDUITableViewCell avatarSize];
			
			[ imageManager fetchUserAvatar: localUserID
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
				 if( cell.Auth0ID == auth0ID)
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
		
		cell.lblUserName.textColor = [UIColor blackColor];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.lblUserName.hidden = NO;
	}
	else
	{
		
		cell.imgAvatar.hidden = YES;
		cell.imgProvider.hidden = YES;
		cell.lbProvider.hidden = YES;
		cell.lblUserName.hidden = YES;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.lbLeftTag.text = @"";
	}
	
	return cell;
}


- (NSArray *)tableView:(UITableView *)tv editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
	__weak typeof(self) weakSelf = self;

	NSUInteger realAccounts = 0;
	for(NSDictionary* dict in providerTable)
	{
		BOOL isRealCell =   [dict[@"isRealCell"] boolValue];
		if(isRealCell) realAccounts++;
	}

	NSDictionary* dict  =  providerTable[indexPath.row];
	BOOL isRealCell =   [dict[@"isRealCell"] boolValue];

	if(!isRealCell)
	{
		return @[];
	}

	if(realAccounts > 1)
	{
		UITableViewRowAction *deleteAction =
		[UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
										   title:@"Remove"
										 handler:^(UITableViewRowAction *action, NSIndexPath *indexPath)
		 {
			 __strong typeof(self) strongSelf = weakSelf;
			 if (strongSelf == nil) return;

			 CGRect aFrame = [tv rectForRowAtIndexPath:indexPath];
			 aFrame.origin.y += aFrame.size.height/2;
			 aFrame.size.height = 1;
			 aFrame.size.width =  aFrame.size.width/3;

			 NSDictionary* dict  =  strongSelf->providerTable[indexPath.row];
			 [strongSelf verifyDeleteProvider:dict
							  forUserID:strongSelf->localUserID
							 sourceView:strongSelf->_tblProviders
							 sourceRect:aFrame];

		 }];

		deleteAction.backgroundColor = [UIColor redColor];
		return @[deleteAction];
	}
	else
	{
		UITableViewRowAction *deleteAction =
		[UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
										   title:@"Cannot Remove"
										 handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {


										 }];

		deleteAction.backgroundColor = [UIColor lightGrayColor];

		return @[deleteAction];

	}

	return @[];
}


#if __IPHONE_11_0
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0)
{
	__weak typeof(self) weakSelf = self;

	UISwipeActionsConfiguration* config = nil;

	NSUInteger realAccounts = 0;
	for(NSDictionary* dict in providerTable)
	{
		BOOL isRealCell =   [dict[@"isRealCell"] boolValue];
		if(isRealCell) realAccounts++;
	}

	NSDictionary* dict  =  providerTable[indexPath.row];
	BOOL isRealCell =   [dict[@"isRealCell"] boolValue];

	if (@available(iOS 11.0, *)) {

		if(!isRealCell)
		{
			config = [UISwipeActionsConfiguration configurationWithActions:@[]];
		}
		else
		{
			NSMutableArray* actions =  NSMutableArray.array;

			if(realAccounts > 1)
			{
				UIContextualAction* deleteAction =
				[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
														title:@"Remove"
													  handler:
				 ^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL))
				 {
					 __strong typeof(self) strongSelf = weakSelf;
					 if (strongSelf == nil) return;

					 CGRect aFrame = [tv rectForRowAtIndexPath:indexPath];
					 aFrame.origin.y += aFrame.size.height/2;
					 aFrame.size.height = 1;
					 aFrame.size.width =  aFrame.size.width/3;

					 NSDictionary* dict  =  strongSelf->providerTable[indexPath.row];
					 [self verifyDeleteProvider:dict
									  forUserID:strongSelf->localUserID
									 sourceView:strongSelf->_tblProviders
									 sourceRect:aFrame];

					 completionHandler(YES);
				 }];
				deleteAction.backgroundColor = UIColor.redColor;
				[actions addObject:deleteAction];


			}
			else
			{
				UIContextualAction* deleteAction =
				[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
														title:@"Cannot Remove"
													  handler:
				 ^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL))
				 {
					 completionHandler(YES);
				 }];
				deleteAction.backgroundColor = UIColor.lightGrayColor;
				[actions addObject:deleteAction];

			}
			config = [UISwipeActionsConfiguration configurationWithActions:actions];
			config.performsFirstActionWithFullSwipe = NO;

		}

	};

	return config;
}

#endif


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	__weak typeof(self) weakSelf = self;

	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary* info  		=  providerTable[indexPath.row];
	NSString* selectedAuth0ID	= info[@"auth0_userID"];
	BOOL isRealCell 			= [info[@"isRealCell"] boolValue];

	if(!isRealCell)
		return;

	// dont allow selection of recovery
	BOOL isRecoveryId =  [Auth0Utilities isRecoveryProfile:info];
	if(isRecoveryId)
		return;

	[accountSetupVC. owner.databaseManager.rwDatabaseConnection
	 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		 __strong typeof(self) strongSelf = weakSelf;
		 if (strongSelf == nil) return;

		ZDCLocalUser *updatedUser = [transaction objectForKey:strongSelf->localUserID inCollection:kZDCCollection_Users];

		if(updatedUser)
		{
			updatedUser 				= updatedUser.copy;
			updatedUser.auth0_preferredID = selectedAuth0ID;
			[transaction setObject:updatedUser forKey:updatedUser.uuid inCollection:kZDCCollection_Users];
		}

	}completionBlock:^{
	}];

}

// MARK: SocialIDUITableViewCellDelegate
- (void)tableView:(UITableView * _Nonnull)tableView rightButtonTappedAtCell:(SocialIDUITableViewCell* _Nonnull)cell
{

    [self.accountSetupVC pushUserAvatarWithUserID:cell.uuid
                                          auth0ID:cell.Auth0ID
                         withNavigationController:self.navigationController];
 
}


// MARK: provider actions

-(void) verifyDeleteProvider:(NSDictionary*)auth0Info
				   forUserID:(NSString*)userID
				  sourceView:(UIView*)sourceView
				  sourceRect:(CGRect)sourceRect

{
	__weak typeof(self) weakSelf = self;

	NSString* auth0Provider = auth0Info[@"providerName"];
	NSString* displayName     = auth0Info[@"displayName"];
	BOOL isPrimaryProfile = [auth0Info[@"isPrimaryProfile"] boolValue];

	NSString* warningText = [NSString stringWithFormat:@"Are you sure you wish to remove the social identity with %@ for the user %@?",
							 auth0Provider,  displayName ];

	if(isPrimaryProfile)
	{
		warningText = [warningText stringByAppendingString:@"\nSince this is your primary profile, you might be required to sign in again."];
	}
	UIAlertController *alertController =
	[UIAlertController alertControllerWithTitle:@"Remove Social Identity"
										message:warningText
								 preferredStyle:UIAlertControllerStyleActionSheet];

	UIAlertAction *deleteAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Remove", @"Remove action")
							 style:UIAlertActionStyleDestructive
						   handler:^(UIAlertAction *action)
	 {

		 __strong typeof(self) strongSelf = weakSelf;

		 [strongSelf deleteProvider:auth0Info
						  forUserID:userID
				   isPrimaryProfile:isPrimaryProfile];
	 }];

	UIAlertAction *cancelAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action")
							 style:UIAlertActionStyleCancel
						   handler:^(UIAlertAction * _Nonnull action) {

							   __strong typeof(self) strongSelf = weakSelf;
							   if (strongSelf == nil) return;

							   [strongSelf->_tblProviders setEditing:NO];
						   }];

	[alertController addAction:deleteAction];
	[alertController addAction:cancelAction];

	if([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.sourceRect = sourceRect;
		alertController.popoverPresentationController.sourceView = sourceView;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}

	[self presentViewController:alertController animated:YES
					 completion:^{
					 }];



}

- (void)deleteProvider:(NSDictionary *)auth0Info
			 forUserID:(NSString *)userID
	  isPrimaryProfile:(BOOL)isPrimaryProfile
{
	__weak typeof(self) weakSelf = self;
	NSString* auth0ID = auth0Info[@"auth0_userID"];

	NSPredicate *authIDNotMatchpredicate = [NSPredicate predicateWithBlock:
											^BOOL(id obj, NSDictionary *bind)
											{
												NSDictionary* thisDict = (NSDictionary*)obj;
												NSString* thisID = thisDict[@"auth0_userID"];

												BOOL notIt = ![thisID isEqualToString:auth0ID];
												return notIt;
											}];

	// give user feedback right away
	providerTable = [providerTable filteredArrayUsingPredicate:authIDNotMatchpredicate];
	[_tblProviders reloadData];

	[self.accountSetupVC showWait: @"Please Wait…"
						  message: @"Updating user profile"
				   viewController: self
				  completionBlock: nil];

	[self.accountSetupVC unlinkAuth0ID: auth0ID
					   fromLocalUserID: userID
					   completionQueue: dispatch_get_main_queue()
					   completionBlock:^(NSError *error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;

		 [strongSelf->_tblProviders setEditing:NO];

		 [strongSelf.accountSetupVC cancelWait];

		 if(error)
		 {
			 [strongSelf.accountSetupVC showError:@"Could not remove social identity"
									message:error.localizedDescription completionBlock:^{


										[self refreshView];
									}];
		 }
		 else
		 {
			 if(isPrimaryProfile)
			 {
				 [strongSelf.navigationController popToRootViewControllerAnimated:YES];
			 }
			 else
			 {
				 [strongSelf refreshProviders];
			 }
		 }
	 }];


}

-(void) addProviderforUserID:(NSString*)userID
{
	[self.accountSetupVC pushAddIdentityWithUserID:userID
						  withNavigationController:self.navigationController];
}


@end
