/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import "ActivityMonitor_IOS.h"

#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

#import "ZDCIconTitleButton.h"
#import "LocalUserListViewController.h"

#import "ZDCLogging.h"

// Categories
#import "NSString+ZeroDark.h"
#import "OSImage+ZeroDark.h"


// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int ddLogLevel = DDLogLevelWarning;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif

typedef NS_ENUM(NSInteger, ActivityType) {
	ActivityType_Uploads    = 0,
	ActivityType_Downloads,
	ActivityType_UploadsDownloads,
	ActivityType_Raw,
};


@implementation ActivityMonitor_IOS
{
	IBOutlet __weak UISegmentedControl*   	_segActivity;
	IBOutlet __weak UITableView*   			_tblActivity;

	IBOutlet __weak UILabel*   				_lblStatus;
	IBOutlet __weak UIButton*  				_btnPause;

	ZeroDarkCloud*                     owner;
	NSString*                          _localUserID;

	UISwipeGestureRecognizer*          swipeRight;

	ZDCIconTitleButton            		*_btnTitle;

	ZDCImageManager*       				imageManager;
	YapDatabaseConnection*     		databaseConnection;
	ZDCLocalUserManager * 				localUserManager;
	ZDCSyncManager*						syncManager;
	ActivityType							selectedActivityType;
}


- (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description)
		userInfo = @{ NSLocalizedDescriptionKey: description };
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}


- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
						localUserID:(NSString* __nullable)inLocalUserID
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"ActivityMonitor_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"ActivityMonitor"];
	if (self)
	{
		owner = inOwner;
		_localUserID = inLocalUserID;
	}
	return self;
	
}

- (void)viewDidLoad {
    [super viewDidLoad];

	imageManager =  owner.imageManager;
	localUserManager = owner.localUserManager;
	syncManager = owner.syncManager;
	databaseConnection = owner.databaseManager.uiDatabaseConnection;
	
	selectedActivityType = owner.internalPreferences.activityMonitor_lastActivityType;
	[self refreshActivityType];
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	self.navigationItem.title = @"Activity";
	
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
	
	[self setNavigationTitleForUserID:_localUserID];

}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
}


-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[self handleNavigationBack:NULL];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}


-(void) setNavigationTitleForUserID:(NSString*)userID
{
	__weak typeof(self) weakSelf = self;
	
	BOOL shouldEnable = YES;
	
	// check if there are more than one users
	__block NSArray<NSString *> * userIDs = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		userIDs = [localUserManager allLocalUserIDs:transaction];
	}];
#pragma clang diagnostic pop
	
	if(userIDs.count == 1)
 	{
		if(!userID)
			userID = userIDs.firstObject;
		
		shouldEnable = NO;
	}

	if(!_btnTitle)
	{
		_btnTitle = [ZDCIconTitleButton buttonWithType:UIButtonTypeCustom];
		
		[_btnTitle setTitleColor:self.view.tintColor forState:UIControlStateNormal];
	}
	
	if(shouldEnable)
	{
			[_btnTitle addTarget:self action:@selector(navTitleButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
	}
	else
	{
		[_btnTitle removeTarget:self action:NULL
				 forControlEvents:UIControlEventTouchUpInside];
	}
	
	
	self.navigationItem.titleView = _btnTitle;
	
	if(userID)
	{
		__block ZDCUser* user = nil;
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		}];
#pragma clang diagnostic pop
		
		if(user)
		{
			[_btnTitle setTitle: user.displayName
						  forState:UIControlStateNormal ];
			
			void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
				
				__strong typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				
				UIImage* scaledImage = [image?image:strongSelf->imageManager.defaultUserAvatar
											scaledToHeight:30];
				
				[strongSelf->_btnTitle setImage:scaledImage
											  forState:UIControlStateNormal];
				
			};
			void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
				
				__strong typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				
				UIImage* scaledImage = [image?image:strongSelf->imageManager.defaultUserAvatar
											scaledToHeight:30];
				
				[strongSelf->_btnTitle setImage:scaledImage
											  forState:UIControlStateNormal];
			};
			
			[imageManager fetchUserAvatar: user
								 preFetchBlock: preFetchBlock
								postFetchBlock: postFetchBlock];
		}
	}
	else
	{
		[_btnTitle setTitle: NSLocalizedString(@"All Users", @"All Users")
					  forState:UIControlStateNormal ];
		
		UIImage* scaledImage = [imageManager.defaultMultiUserAvatar scaledToHeight:30];
		
		[_btnTitle setImage:scaledImage
					  forState:UIControlStateNormal];
	}
	
}


-(void) navTitleButtonClicked:(UIButton*) sender
{
	LocalUserListViewController_IOS* uVC = [[LocalUserListViewController_IOS alloc]
													initWithOwner:owner
													delegate:(id<LocalUserListViewController_Delegate>)self
													currentUserID:_localUserID];
	
	
	uVC.modalPresentationStyle = UIModalPresentationPopover;
	
	UIPopoverPresentationController *popover =  uVC.popoverPresentationController;
	popover.delegate = uVC;
	
	popover.sourceView	 = _btnTitle;
	popover.sourceRect 	= _btnTitle.frame;
	
	popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
	
	[self presentViewController:uVC animated:YES completion:^{
		}];
}


-(void)refreshActivityType
{
	
	if (selectedActivityType != ActivityType_Uploads &&
		 selectedActivityType != ActivityType_Downloads &&
		 selectedActivityType != ActivityType_UploadsDownloads &&
		 selectedActivityType != ActivityType_Raw)
	{
		selectedActivityType = ActivityType_UploadsDownloads;
	}
	
	if( owner.internalPreferences.activityMonitor_lastActivityType != selectedActivityType)
	{
		owner.internalPreferences.activityMonitor_lastActivityType = selectedActivityType;
	}
	
	_segActivity.selectedSegmentIndex = selectedActivityType;
	
	// do what is needed to update the table.
}


// MARK: actions

- (IBAction)btnPauseHit:(id)sender
{
	NSString *__unused L10nComment = @"Activity Monitor - actions menu item";
	
	BOOL allUsersSelected = _localUserID == nil;
	
	// Step 1 of 2:
	//
	// Determine state of user/users
	
	__block BOOL syncingPaused = NO;
	__block BOOL uploadsPaused = NO;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		
		if (allUsersSelected)
		{
			// Rules:
			//
			// - If EVERY user is disabled (syncing paused), then we'll display the "Resume Syncing" option.
			// - If EVERY non-disabled user is paused, then we'll display the "Resume Uploads" option.
			
			__block NSUInteger numSyncingPaused = 0;
			__block NSUInteger numSyncingActive = 0;
			__block NSUInteger numPushingPaused = 0;
			
			[self->localUserManager enumerateLocalUsersWithTransaction:transaction
																					usingBlock:^(ZDCLocalUser * _Nonnull localUser, BOOL * _Nonnull stop)
			 {
				 if (localUser.syncingPaused)
				 {
					 numSyncingPaused++;
				 }
				 else
				 {
					 numSyncingActive++;
					 if([owner.syncManager isPullingOrPushingChangesForLocalUserID:localUser.uuid])
						 numPushingPaused++;
					 
				 }
			 }];
			
			syncingPaused = ((numSyncingActive == 0) || (numSyncingPaused > 0));
			uploadsPaused = ((numSyncingActive > 0) && (numSyncingActive == numPushingPaused));
		}
		else if (_localUserID)
		{
			ZDCLocalUser *localUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
			syncingPaused = localUser.syncingPaused;
			uploadsPaused = [owner.syncManager isPullingOrPushingChangesForLocalUserID:_localUserID];
		}
		
	}];
#pragma clang diagnostic pop
	
	// Step 2 of 2:
	//
	// Configure the menu accordingly
	
	
	UIAlertController *alertController
	= [UIAlertController alertControllerWithTitle: NULL
													  message: NULL
											 preferredStyle: UIAlertControllerStyleActionSheet];

	if (syncingPaused)
	{
		if (allUsersSelected)
		{
			UIAlertAction *resumeSyncingAction =
			[UIAlertAction actionWithTitle:NSLocalizedString(@"Resume Syncing (for all users)", L10nComment)
											 style:UIAlertActionStyleDefault
										  handler:^(UIAlertAction * _Nonnull action) {
											  [self pauseSyncing:FALSE];
	 										  }];
			
			[alertController addAction:resumeSyncingAction];

		}
		else
		{
			UIAlertAction *resumeSyncingAction =
			[UIAlertAction actionWithTitle:NSLocalizedString(@"Resume Syncing", L10nComment)
											 style:UIAlertActionStyleDefault
										  handler:^(UIAlertAction * _Nonnull action) {
											  [self pauseSyncing:FALSE];
											  }];
			
			[alertController addAction:resumeSyncingAction];
		}
	}
	else
	{
		if (uploadsPaused)
		{
			UIAlertAction *resumeUploadsAction =
			[UIAlertAction actionWithTitle:NSLocalizedString(@"Resume Uploads", L10nComment)
											 style:UIAlertActionStyleDefault
										  handler:^(UIAlertAction * _Nonnull action) {
											  [self pauseUploads:NO andAbortUploads:NO];
										  }];

			[alertController addAction:resumeUploadsAction];
		}
		else
		{
			UIAlertAction *pauseUploadsAction =
			[UIAlertAction actionWithTitle:NSLocalizedString(@"Pause Uploads", L10nComment)
											 style:UIAlertActionStyleDefault
										  handler:^(UIAlertAction * _Nonnull action) {
											  [self pauseUploads:NO andAbortUploads:YES];
								  }];
			
			[alertController addAction:pauseUploadsAction];
		}
		
		UIAlertAction *pauseSyncingAction =
		[UIAlertAction actionWithTitle:NSLocalizedString(@"Pause Syncing", L10nComment)
										 style:UIAlertActionStyleDefault
									  handler:^(UIAlertAction * _Nonnull action) {
										  [self pauseSyncing:TRUE];
									  }];
		
		[alertController addAction:pauseSyncingAction];

		UIAlertAction *pauseFutureUploadsAction =
		[UIAlertAction actionWithTitle:NSLocalizedString(@"Pause Uploads (continue in-progress)", L10nComment)
										 style:UIAlertActionStyleDefault
									  handler:^(UIAlertAction * _Nonnull action) {
										  [self pauseUploads:YES andAbortUploads:NO];
										  }];
		
		[alertController addAction:pauseFutureUploadsAction];
	}
	
	
	UIAlertAction *cancelAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
									 style:UIAlertActionStyleCancel
								  handler:^(UIAlertAction * _Nonnull action) {
								 
									  
								  }];
	
 	[alertController addAction:cancelAction];

	if([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.sourceView = _btnPause;
		alertController.popoverPresentationController.sourceRect = _btnPause.frame;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController:alertController animated:YES
						  completion:^{
						  }];
}


- (IBAction)segmentedControlChanged:(id)sender
{
	DDLogAutoTrace();
	
	if(sender == _segActivity)
	{
		selectedActivityType = _segActivity.selectedSegmentIndex;
  		[self refreshActivityType];
	}
 }



-(void)pauseSyncing:(BOOL)pause
{
	BOOL allUsersSelected = _localUserID == nil;
	NSString *_selectedLocalUserID = _localUserID;

	DDLogAutoTrace();
	
	[owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		if (allUsersSelected)
		{
			NSArray<NSString *> *localUserIDs = [self->localUserManager allLocalUserIDs:transaction];
			for (NSString *localUserID in localUserIDs)
			{
				ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
				if (localUser && localUser.isLocal)
				{
					if (localUser.syncingPaused != pause)
					{
						localUser = [localUser copy];
						localUser.syncingPaused = pause;
						
						[transaction setObject:localUser forKey:localUser.uuid inCollection:kZDCCollection_Users];
					}
				}
			}
		}
		else
		{
			ZDCLocalUser *localUser = [transaction objectForKey:_selectedLocalUserID inCollection:kZDCCollection_Users];
			if (localUser && localUser.isLocal)
			{
				if (localUser.syncingPaused != pause)
				{
					localUser = [localUser copy];
					localUser.syncingPaused = pause;
					
					[transaction setObject:localUser forKey:localUser.uuid inCollection:kZDCCollection_Users];
				}
			}
		}
	}];
}

-(void)pauseUploads:(BOOL)pause andAbortUploads:(BOOL)shouldAbortUploads;
{
	BOOL allUsersSelected = _localUserID == nil;
	
	if (allUsersSelected)
	{
		if(pause)
		{
			[syncManager pausePushForAllLocalUsersAndAbortUploads:shouldAbortUploads];
		}
		else
		{
			[syncManager resumePushForAllLocalUsers];
		}
	}
	else
	{
		if(pause)
		{
			[syncManager pausePushForLocalUserID:_localUserID andAbortUploads: shouldAbortUploads];
		}
		else
		{
			[syncManager resumePushForLocalUserID:_localUserID];
		}
		
	}
	
}


// MARK: LocalUserListViewController_Delegate

- (void)localUserListViewController:(LocalUserListViewController_IOS *)sender
						  didSelectUserID:(NSString* __nullable) userID
{
	_localUserID = userID.length?userID:NULL;
	
	[self setNavigationTitleForUserID:_localUserID];

}



@end
