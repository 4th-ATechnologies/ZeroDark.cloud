/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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
  static const int zdcLogLevel = ZDCLogLevelVerbose | ZDCLogFlagTrace;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

typedef NS_ENUM(NSInteger, ActivityType) {
	ActivityType_Uploads    = 0,
	ActivityType_Downloads,
	ActivityType_UploadsDownloads,
	ActivityType_Raw,
};

static NSString *const kSyncStatus     = @"sync";
static NSString *const kAdvisoryStatus = @"advisory";
static NSString *const kActionStatus   = @"action";


@implementation ActivityMonitor_IOS
{
	ZDCIconTitleButton *							_btnTitle;
	IBOutlet __weak UISegmentedControl*   	_segActivity;
	IBOutlet __weak UITableView*   			_tblActivity;

	IBOutlet __weak UILabel*   				_lblStatus;
	IBOutlet __weak UIButton*  				_btnPause;
	UISwipeGestureRecognizer*    				swipeRight;

	ZeroDarkCloud *zdc;
	YapDatabaseConnection *uiDatabaseConnection;
	
	NSArray<NSString*> *localUserIDs;
	NSString *selectedLocalUserID;
	
	ActivityType selectedActivityType;
	
	NSMutableDictionary<id, NSMutableDictionary*> *statusStates;

	NSArray<ZDCCloudOperation*> *rawOperations;
	NSDictionary<NSUUID*, ZDCCloudOperation*> *rawOperationsDict;
	
	NSArray<NSString *> *uploadNodeIDs;
	NSDictionary<NSString*, NSArray<ZDCCloudOperation *> *> *uploadTasks; // key=nodeID, value=[operations]
	NSDictionary<NSString*, NSNumber*> *minSnapshotDict;                  // key=nodeID, value=snapshot (uint64_t)
	
	NSArray<NSString *> *downloadNodeIDs;
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
                  localUserID:(NSString *)inLocalUserID
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"ActivityMonitor_IOS" bundle:bundle];
	
	self = [storyboard instantiateViewControllerWithIdentifier:@"ActivityMonitor"];
	if (self)
	{
		zdc = inOwner;
		selectedLocalUserID = [inLocalUserID copy];
		
		uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;
		selectedActivityType = zdc.internalPreferences.activityMonitor_lastActivityType;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
	[super viewDidLoad];
	
	statusStates = [[NSMutableDictionary alloc] init];
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	self.navigationItem.title = @"Activity";
	
	UIImage *image = [[UIImage imageNamed: @"backarrow"
	                             inBundle: [ZeroDarkCloud frameworkBundle]
	        compatibleWithTraitCollection: nil]
	               imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem *backItem =
	  [[UIBarButtonItem alloc] initWithImage: image
	                                   style: UIBarButtonItemStylePlain
	                                  target: self
	                                  action: @selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
	
	swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];
	
	[self refreshLocalUsersList];
	[self refreshNavigationTitle];
	
	[self refreshUploadList];
	[self refreshDownloadList];
	[_tblActivity reloadData];

	[self refreshActivityType];
	[self refreshGeneralStatus];
}

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillDisappear:animated];
	
	[self.view removeGestureRecognizer:swipeRight];
	swipeRight = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Refresh Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)refreshLocalUsersList
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Method must be run on main thread");
	
	// Update `localUserIDs`
	
	NSMutableArray<NSString *> *_localUserIDs = [NSMutableArray array];
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[zdc.localUserManager enumerateLocalUsersWithTransaction: transaction
		                                              usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
		{
			if (localUser.hasCompletedSetup
			 && !localUser.accountDeleted
			 && !localUser.accountSuspended
			 && !localUser.accountNeedsA0Token)
			{
				[_localUserIDs addObject:localUser.uuid];
			}
		}];
		
	#pragma clang diagnostic pop
	}];
	
	localUserIDs = _localUserIDs.copy;
	
	if (!selectedLocalUserID && localUserIDs.count == 1) {
		selectedLocalUserID = localUserIDs.firstObject;
	}
}

- (void)refreshUploadList
{
	ZDCLogAutoTrace();
	
	ZDCDatabaseManager *databaseManager = zdc.databaseManager;
	
	NSMutableArray *_rawOperations = [[NSMutableArray alloc] init];
	NSMutableDictionary *_rawOperationsDict = [[NSMutableDictionary alloc] init];
	
	NSMutableOrderedSet *_uploadNodes     = [[NSMutableOrderedSet alloc] init];
	NSMutableDictionary *_uploadTasks     = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *_minSnapshotDict = [[NSMutableDictionary alloc] init];
	
	for (NSString *localUserID in localUserIDs)
	{
		ZDCCloud *ext = [databaseManager cloudExtForUserID:localUserID];
		YapDatabaseCloudCorePipeline *pipeline = [ext  defaultPipeline];
		
		[pipeline enumerateOperationsUsingBlock:^(YapDatabaseCloudCoreOperation *op, NSUInteger graphIdx, BOOL *stop){
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			if (![op isKindOfClass:[ZDCCloudOperation class]]) {
				return; // from block (i.e. continue)
			}
			
			ZDCCloudOperation *operation = (ZDCCloudOperation *)op;
			
			//
			// Update "raw" variables
			//
			
			[_rawOperations addObject:operation];
			_rawOperationsDict[operation.uuid] = operation;
			
			//
			// Update "upload" variables
			//
			
			NSString *nodeID = operation.nodeID;
			if (nodeID == nil) {
				return; // from block (i.e. continue)
			}
			
			[_uploadNodes addObject:nodeID];
			
			NSMutableArray<ZDCCloudOperation *> *_nodeTasks = _uploadTasks[nodeID];
			if (_nodeTasks == nil) {
				_nodeTasks = _uploadTasks[nodeID] = [[NSMutableArray alloc] init];
			}
			
			[_nodeTasks addObject:operation];
			
			NSNumber *minSnapshot = _minSnapshotDict[nodeID];
			if (minSnapshot == nil) {
				minSnapshot = @(operation.snapshot);
			}
			else {
				minSnapshot = @(MIN(operation.snapshot, [minSnapshot unsignedLongLongValue]));
			}
			
			// IMPORTANT:
			// Consider how the tableView would change for this list of operations:
			//
			// - [snapshot 42] put[data]  - nodeID:abc123
			// - [snapshot 43] put[rcrd]  - nodeID:def456
			// - [snapshot 44] put[xattr] - nodeID:abc123
			//
			// So the UI starts by looking like this:
			//
			// - nodeID:abc123 put(data, xattr)
			// - nodeID:def456 put(rcrd)
			//
			// But then the data upload completes for nodeID:abc123.
			// So what do we do at this point ?
			// Does that row move in position ?
			//
			// The problem here is that if nodeID:abc123 jumps from index0 to index1,
			// it will be confusing to the user.
			//
			// So our solution is to maintain knowledge of the minSnapshot associated
			// with a nodeID until it's removed from the tableView.
			//
			NSNumber *prvMinSnapshot = minSnapshotDict[nodeID];
			if (prvMinSnapshot)
			{
				minSnapshot = @(MIN([minSnapshot unsignedLongLongValue], [prvMinSnapshot unsignedLongLongValue]));
			}
			
			_minSnapshotDict[nodeID] = minSnapshot;
			
		#pragma clang diagnostic pop
		}];
	}
	
	[_rawOperations sortWithOptions: NSSortStable
	                usingComparator:^NSComparisonResult(ZDCCloudOperation *opA, ZDCCloudOperation *opB)
	{
		uint64_t snapshotA = opA.snapshot;
		uint64_t snapshotB = opB.snapshot;
		 
		// - NSOrderedAscending  : The left operand is smaller than the right operand.
		// - NSOrderedDescending : The left operand is greater than the right operand.
		
		if (snapshotA < snapshotB) return NSOrderedAscending;
		if (snapshotA > snapshotB) return NSOrderedDescending;
		
		return NSOrderedSame;
	}];
	
	NSMutableArray *sortedUploadNodes = [_uploadNodes.array mutableCopy];
	
	[sortedUploadNodes sortUsingComparator:^NSComparisonResult(NSString *nodeID_A, NSString *nodeID_B) {
		
		NSNumber *minSnapshot_A = _minSnapshotDict[nodeID_A];
		NSNumber *minSnapshot_B = _minSnapshotDict[nodeID_B];
		
		NSComparisonResult result = [minSnapshot_A compare:minSnapshot_B];
		if (result == NSOrderedSame) {
			result = [nodeID_A compare:nodeID_B];
		}
		
		return result;
	}];
	
	rawOperations     = [_rawOperations copy];
	rawOperationsDict = [_rawOperationsDict copy];
	
	uploadNodeIDs     = [sortedUploadNodes copy];
	uploadTasks     = [_uploadTasks copy];
	minSnapshotDict = [_minSnapshotDict copy];
	
	[self refreshSyncStatus];
}

- (void)refreshDownloadList
{
	ZDCLogAutoTrace();
	
	ZDCProgressManager *progressManager = zdc.progressManager;
	
	NSMutableArray<NSString *> *_downloadNodes = nil;
	BOOL allUsersSelected = selectedLocalUserID == nil;

	if (allUsersSelected)
	{
		_downloadNodes = [[[progressManager allDownloadingNodeIDs] allObjects] mutableCopy];
	}
	else if (selectedLocalUserID)
	{
		_downloadNodes = [[[progressManager allDownloadingNodeIDs:selectedLocalUserID] allObjects] mutableCopy];
	}
	else
	{
		_downloadNodes = [NSMutableArray array];
	}
	
	if (downloadNodeIDs)
	{
		// Maintain sort order compared to how the items were first sorted.
		
		NSMutableDictionary<NSString*, NSNumber*> *positions =
		[NSMutableDictionary dictionaryWithCapacity:downloadNodeIDs.count];
		
		NSUInteger i = 0;
		for (NSString *nodeID in downloadNodeIDs)
		{
			positions[nodeID] = @(i);
			i++;
		}
		
		[_downloadNodes sortWithOptions: NSSortStable
							 usingComparator:^NSComparisonResult(NSString *nodeIDA, NSString *nodeIDB)
		 {
			 NSNumber *posA = positions[nodeIDA];
			 NSNumber *posB = positions[nodeIDB];
			 
			 // NSOrderedAscending  - The left operand is smaller than the right operand.
			 // NSOrderedDescending - The left operand is greater than the right operand.
			 
			 if (posA)
			 {
				 if (posB)
					 return [posA compare:posB];
				 else
					 return NSOrderedAscending;
			 }
			 else
			 {
				 if (posB)
					 return NSOrderedDescending;
				 else
					 return NSOrderedSame;
			 }
		 }];
	}
	
	downloadNodeIDs = [_downloadNodes copy];
	
	[self refreshSyncStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Refresh UI
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)refreshNavigationTitle
{
	ZDCLogAutoTrace();
	
	ZDCImageManager *imageManager = zdc.imageManager;
	
	BOOL shouldEnable = YES;
	if (localUserIDs.count == 1)
 	{
		shouldEnable = NO;
	}

	if (!_btnTitle)
	{
		_btnTitle = [ZDCIconTitleButton buttonWithType:UIButtonTypeCustom];
		[_btnTitle setTitleColor:self.view.tintColor forState:UIControlStateNormal];
	}
	
	if (shouldEnable)
	{
		[_btnTitle addTarget: self
		              action: @selector(navTitleButtonClicked:)
		    forControlEvents: UIControlEventTouchUpInside];
	}
	else
	{
		[_btnTitle removeTarget: self
		                 action: nil
		       forControlEvents: UIControlEventTouchUpInside];
	}
	
	self.navigationItem.titleView = _btnTitle;
	
	CGSize avatarSize = CGSizeMake(30, 30);
	UIImage* (^defaultAvatar)(void) = ^{
		
		return [imageManager.defaultUserAvatar scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
	};
	
	if (selectedLocalUserID)
	{
	 	__block ZDCLocalUser *localUser = nil;
		[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
			localUser = [transaction objectForKey:selectedLocalUserID inCollection:kZDCCollection_Users];
			
		#pragma clang diagnostic pop
		}];

		[_btnTitle setTitle: localUser.displayName
		           forState: UIControlStateNormal];
		
		UIImage* (^processingBlock)(OSImage *) = ^UIImage* (UIImage *image){
			
			return [image scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
		};
		
		void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *userAvatar, BOOL willFetch){
			
			// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns
			
			UIImage *image = userAvatar ?: defaultAvatar();
			[self->_btnTitle setImage: image
			                 forState: UIControlStateNormal];
		};
		
		__weak typeof(self) weakSelf = self;
		void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *userAvatar, NSError *error){
			
			// The postFetchBlock is invoked LATER, possibly after downloading the avatar
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf && userAvatar)
			{
				[strongSelf->_btnTitle setImage: userAvatar
				                       forState: UIControlStateNormal];
			}
		};

		[imageManager fetchUserAvatar: localUser
		                  withOptions: nil
		                 processingID: NSStringFromClass([self class])
		              processingBlock: processingBlock
		                preFetchBlock: preFetchBlock
		               postFetchBlock: postFetchBlock];
	}
	else
	{
		[_btnTitle setTitle: NSLocalizedString(@"All Users", @"All Users")
		           forState: UIControlStateNormal ];
		
		UIImage *image = defaultAvatar();
		
		[_btnTitle setImage: image
		           forState: UIControlStateNormal];
	}
}

- (void)refreshActivityType
{
	ZDCLogAutoTrace();
	
	if (selectedActivityType != ActivityType_Uploads &&
		 selectedActivityType != ActivityType_Downloads &&
		 selectedActivityType != ActivityType_UploadsDownloads &&
		 selectedActivityType != ActivityType_Raw)
	{
		selectedActivityType = ActivityType_UploadsDownloads;
	}
	
	if (zdc.internalPreferences.activityMonitor_lastActivityType != selectedActivityType)
	{
		zdc.internalPreferences.activityMonitor_lastActivityType = selectedActivityType;
	}
	
	_segActivity.selectedSegmentIndex = selectedActivityType;
	
	// do what is needed to update the table.
}

/**
 * Invoke this method when:
 * - the `allUsersSelected` or `selectedLocalUser` variable is changed
 * - the window is displayed for the first time
 *
 * During these events, IF syncing is paused,
 * then we want to display an "action" status that reminds the user of such.
 *
 * Remember:
 * > An "action" status is a temporary status that gets displayed.
 * >
 * > Typically, this is in response to an action that the user has just taken.
 * > For example, the user changes a setting, and we set a temporary action status as feedback.
 * > E.g. user clicks "activate foobar", and we display "foobar activated" message for a few seconds.
 **/
- (void)refreshGeneralStatus
{
	ZDCLogAutoTrace();
	
	BOOL allUsersSelected = selectedLocalUserID == nil;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		if (allUsersSelected)
		{
			// If some users's are paused, we're going to display it.
			
			NSUInteger numActive = 0;
			NSUInteger numPaused = 0;
			
	 		for(NSString* localUserID in localUserIDs)
			{
				ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];

				if (localUser.syncingPaused) {
					numPaused++;
				}
				else {
					numActive++;
				}
			}
	 
			if ((numActive == 0) && (numPaused > 0))
			{
				NSString *msg = NSLocalizedString(@"Syncing paused", @"Activity Monitor status");
				
				[self setAdvisoryStatus:msg forLocalUserID:nil];
			}
			else if ((numActive > 0) && (numPaused > 0))
			{
				// Mixed state - display action status
				
				NSString *frmt = NSLocalizedString(@"Accounts paused: %llu,  active: %llu", @"Activity Monitor status");
				NSString *msg = [NSString stringWithFormat:frmt,
									  (unsigned long long)numPaused,
									  (unsigned long long)numActive];
				
				[self setAdvisoryStatus:nil forLocalUserID:nil];
				[self setActionStatus:msg forLocalUserID:nil];
			}
			else
			{
				[self setAdvisoryStatus:nil forLocalUserID:nil];
			}
		}
		else if (selectedLocalUserID)
		{
			ZDCLocalUser *localUser = [transaction objectForKey:selectedLocalUserID inCollection:kZDCCollection_Users];
			
			if (localUser.syncingPaused)
			{
				NSString *msg = NSLocalizedString(@"Syncing paused", @"Activity Monitor status");
				
				[self setAdvisoryStatus:msg forLocalUserID:selectedLocalUserID];
			}
			else
			{
				[self setAdvisoryStatus:nil forLocalUserID:selectedLocalUserID];
			}
		}
		
	#pragma clang diagnostic push
	}];
}

/**
 * Invoke this method when:
 * - the `uploadNodes` variable changes
 * - the `downloadNodes` variable changes
 **/
- (void)refreshSyncStatus
{
	ZDCLogAutoTrace();
	
	if ((uploadNodeIDs.count == 0) && (downloadNodeIDs.count == 0))
	{
		NSString *msg = NSLocalizedString(@"Up-to-date", @"Activity Monitor status");
		
		[self setSyncStatus:msg forLocalUserID:selectedLocalUserID];
	}
	else
	{
		NSUInteger numUsersPaused = 0;
		
		for (NSString *localUserID in localUserIDs)
		{
			if ([zdc.syncManager isPushingPausedForLocalUserID:localUserID]) {
				numUsersPaused++;
			}
		}
		
		NSString *format;
		if (numUsersPaused == localUserIDs.count) {
			format = NSLocalizedString(@"Uploads (paused): %llu,  Downloads: %llu", @"Activity Monitor status");
		} else {
			format = NSLocalizedString(@"Uploads: %llu,  Downloads: %llu", @"Activity Monitor status");
		}
		
		NSString *msg = [NSString stringWithFormat:format,
							  (unsigned long long)uploadNodeIDs.count,
							  (unsigned long long)downloadNodeIDs.count];
		
		[self setSyncStatus:msg forLocalUserID:selectedLocalUserID];
	}
}

- (void)refreshStatusLabel
{
	ZDCLogAutoTrace(); // too noisy
	
	BOOL allUsersSelected = selectedLocalUserID == nil;

	id key = allUsersSelected ? [NSNull null] : (selectedLocalUserID ?: @"");
	NSMutableDictionary *info = statusStates[key];
	
	NSString *status = info[kActionStatus];
	if (status == nil) {
		status = info[kAdvisoryStatus];
	}
	if (status == nil) {
		status = info[kSyncStatus];
	}
	if (status == nil) {
		status = @"";
	}
	
	_lblStatus.text = status;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Status Label
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The "sync" status is the generic sync information for a user.
 *
 * For example: "Uploads: 2,  Downloads: 0"
 */
- (void)setSyncStatus:(NSString *)inStatus forLocalUserID:(nullable NSString *)localUserID
{
	//	ZDCLogAutoTrace(); // too noisy
	NSAssert([NSThread isMainThread], @"Called from wrong thread");
	
	NSString *status = [inStatus copy];
	id key = localUserID ?: [NSNull null];
	
	NSMutableDictionary *info = statusStates[key];
	if (info == nil) {
		info = statusStates[key] = [NSMutableDictionary dictionaryWithCapacity:3];
	}
	
	info[kSyncStatus] = status;
	[self refreshStatusLabel];
}

/**
 * If an "advisory" status is set, it will get displayed instead of the "sync" status.
 *
 * For example, if a user's account has been deleted, the status will convey this information as priority.
 */
- (void)setAdvisoryStatus:(NSString *)inStatus forLocalUserID:(nullable NSString *)localUserID
{
	//	ZDCLogAutoTrace(); // too noisy
	NSAssert([NSThread isMainThread], @"Called from wrong thread");
	
	NSString *status = [inStatus copy];
	id key = localUserID ?: [NSNull null];
	
	NSMutableDictionary *info = statusStates[key];
	if (info == nil) {
		info = statusStates[key] = [NSMutableDictionary dictionaryWithCapacity:3];
	}
	
	info[kAdvisoryStatus] = status;
	[self refreshStatusLabel];
}

/**
 * An "action" status is a temporary status that gets displayed.
 *
 * For example, when the "pause syncing" option is selected, a message is displayed for a few seconds telling
 * the user that syncing has been paused for the selected user.
 **/
- (void)setActionStatus:(NSString *)inStatus forLocalUserID:(nullable NSString *)localUserID
{
	//	ZDCLogAutoTrace(); // too noisy
	NSAssert([NSThread isMainThread], @"Called from wrong thread");
	
	NSString *status = [inStatus copy];
	id key = localUserID ?: [NSNull null];
	
	NSMutableDictionary *info = statusStates[key];
	if (info == nil) {
		info = statusStates[key] = [NSMutableDictionary dictionaryWithCapacity:3];
	}
	
	info[kActionStatus] = status;
	[self refreshStatusLabel];
	
	__weak typeof(self) weakSelf = self;
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		NSMutableDictionary *info = strongSelf->statusStates[key];
		NSString *existing = info[kActionStatus];
		
		if (existing && [existing isEqual:status])
		{
			info[kActionStatus] = nil;
			[strongSelf refreshStatusLabel];
		}
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

- (void)navTitleButtonClicked:(UIButton *)sender
{
	ZDCLogAutoTrace();
	
	LocalUserListViewController_IOS* uVC =
	  [[LocalUserListViewController_IOS alloc] initWithOwner: zdc
	                                                delegate: (id<LocalUserListViewController_Delegate>)self
	                                          selectedUserID: selectedLocalUserID];
	
	uVC.modalPresentationStyle = UIModalPresentationPopover;
	
	UIPopoverPresentationController *popover =  uVC.popoverPresentationController;
	popover.delegate = uVC;
	
	popover.sourceView = _btnTitle;
	popover.sourceRect = _btnTitle.frame;
	
	popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
	
	[self presentViewController:uVC animated:YES completion:^{
		// nothing to do here
	}];
}

- (IBAction)btnPauseHit:(id)sender
{
	ZDCLogAutoTrace();
	
	NSString *__unused L10nComment = @"Activity Monitor - actions menu item";
	
	BOOL allUsersSelected = (selectedLocalUserID == nil);
	
	// Step 1 of 2:
	//
	// Determine state of user/users
	
	__block BOOL syncingPaused = NO;
	__block BOOL uploadsPaused = NO;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (allUsersSelected)
		{
			// Rules:
			//
			// - If EVERY user is disabled (syncing paused), then we'll display the "Resume Syncing" option.
			// - If EVERY non-disabled user is paused, then we'll display the "Resume Uploads" option.
			
			__block NSUInteger numSyncingPaused = 0;
			__block NSUInteger numSyncingActive = 0;
			__block NSUInteger numPushingPaused = 0;
			
			[zdc.localUserManager enumerateLocalUsersWithTransaction: transaction
			                                              usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
			{
				if (localUser.syncingPaused)
				{
					numSyncingPaused++;
				}
				else
				{
					numSyncingActive++;
					if ([zdc.syncManager isPullingOrPushingChangesForLocalUserID:localUser.uuid]) {
						numPushingPaused++;
					}
				}
			}];
			
			syncingPaused = ((numSyncingActive == 0) || (numSyncingPaused > 0));
			uploadsPaused = ((numSyncingActive > 0) && (numSyncingActive == numPushingPaused));
		}
		else if (selectedLocalUserID)
		{
			ZDCLocalUser *localUser = [transaction objectForKey:selectedLocalUserID inCollection:kZDCCollection_Users];
			syncingPaused = localUser.syncingPaused;
			uploadsPaused = [zdc.syncManager isPullingOrPushingChangesForLocalUserID:selectedLocalUserID];
		}
		
	#pragma clang diagnostic pop
	}];
	
	// Step 2 of 2:
	//
	// Configure the menu accordingly
	
	__weak typeof(self) weakSelf = self;
	
	UIAlertController *alertController =
	  [UIAlertController alertControllerWithTitle: nil
	                                      message: nil
	                               preferredStyle: UIAlertControllerStyleActionSheet];
	
	if (syncingPaused)
	{
		if (allUsersSelected)
		{
			UIAlertAction *resumeSyncingAction =
			  [UIAlertAction actionWithTitle: NSLocalizedString(@"Resume Syncing (for all users)", L10nComment)
			                           style: UIAlertActionStyleDefault
			                         handler:^(UIAlertAction *action)
			{
				BOOL shouldPause = NO;
				[weakSelf pauseResumeSyncing:shouldPause];
			}];
			
			[alertController addAction:resumeSyncingAction];
		}
		else
		{
			UIAlertAction *resumeSyncingAction =
			  [UIAlertAction actionWithTitle: NSLocalizedString(@"Resume Syncing", L10nComment)
			                           style: UIAlertActionStyleDefault
			                         handler:^(UIAlertAction *action)
			{
				BOOL shouldPause = NO;
				[weakSelf pauseResumeSyncing:shouldPause];
			}];
			
			[alertController addAction:resumeSyncingAction];
		}
	}
	else
	{
		if (uploadsPaused)
		{
			UIAlertAction *resumeUploadsAction =
			  [UIAlertAction actionWithTitle: NSLocalizedString(@"Resume Uploads", L10nComment)
			                           style: UIAlertActionStyleDefault
			                         handler:^(UIAlertAction *action)
			{
				[weakSelf resumeUploads];
			}];

			[alertController addAction:resumeUploadsAction];
		}
		else
		{
			UIAlertAction *pauseUploadsAction =
			  [UIAlertAction actionWithTitle: NSLocalizedString(@"Pause Uploads", L10nComment)
			                           style: UIAlertActionStyleDefault
			                         handler:^(UIAlertAction *action)
			{
				[weakSelf pauseUploadsAndAbortUploads:YES];
			}];
			
			[alertController addAction:pauseUploadsAction];
		}
		
		{ // Scoping
			
			UIAlertAction *pauseSyncingAction =
			  [UIAlertAction actionWithTitle: NSLocalizedString(@"Pause Syncing", L10nComment)
			                           style: UIAlertActionStyleDefault
			                         handler:^(UIAlertAction *action)
			{
				BOOL shouldPause = YES;
				[weakSelf pauseResumeSyncing:shouldPause];
			}];
			
			[alertController addAction:pauseSyncingAction];
		}

		{ // Scoping
			
			UIAlertAction *pauseFutureUploadsAction =
			  [UIAlertAction actionWithTitle: NSLocalizedString(@"Pause Uploads (continue in-progress)", L10nComment)
			                           style: UIAlertActionStyleDefault
			                         handler:^(UIAlertAction *action)
			{
				[weakSelf pauseUploadsAndAbortUploads:NO];
			}];
			
			[alertController addAction:pauseFutureUploadsAction];
		}
	}
	
	UIAlertAction *cancelAction =
	  [UIAlertAction actionWithTitle: NSLocalizedString(@"Cancel", @"Cancel")
	                           style: UIAlertActionStyleCancel
	                         handler:^(UIAlertAction *action)
	{
		// Nothing to do here
	}];
	
 	[alertController addAction:cancelAction];

	if ([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.sourceView = _btnPause;
		alertController.popoverPresentationController.sourceRect = _btnPause.frame;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController: alertController
	                   animated: YES
	                 completion:
	^{
		// nothing to do here
	}];
}

- (IBAction)segmentedControlChanged:(id)sender
{
	ZDCLogAutoTrace();
	
	if(sender == _segActivity)
	{
		selectedActivityType = _segActivity.selectedSegmentIndex;
  		[self refreshActivityType];
	}
	
	[self refreshUploadList];
	[self refreshDownloadList];
	[_tblActivity reloadData];

	[self refreshGeneralStatus];
	[self refreshSyncStatus];
}

- (void)pauseResumeSyncing:(BOOL)pause
{
	ZDCLogAutoTrace();
	
	BOOL allUsersSelected = (selectedLocalUserID == nil);
	
	NSArray<NSString*> *_localUserIDs = [localUserIDs copy];
	NSString *_selectedLocalUserID = selectedLocalUserID;
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		if (allUsersSelected)
		{
			for (NSString *localUserID in _localUserIDs)
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
	} completionBlock:^{
	
		// remove this when we get notifications
		[self refreshGeneralStatus];
	}];
}

- (void)pauseUploadsAndAbortUploads:(BOOL)shouldAbortUploads
{
	ZDCLogAutoTrace();
	
	BOOL allUsersSelected = (selectedLocalUserID == nil);
	if (allUsersSelected)
	{
		[zdc.syncManager pausePushForAllLocalUsersAndAbortUploads:shouldAbortUploads];
	}
	else
	{
		[zdc.syncManager pausePushForLocalUserID:selectedLocalUserID andAbortUploads:shouldAbortUploads];
	}
	
	[self refreshGeneralStatus];
}

- (void)resumeUploads
{
	ZDCLogAutoTrace();
	
	BOOL allUsersSelected = (selectedLocalUserID == nil);
	if (allUsersSelected)
	{
		[zdc.syncManager resumePushForAllLocalUsers];
	}
	else
	{
		[zdc.syncManager resumePushForLocalUserID:selectedLocalUserID];
	}
	
	[self refreshGeneralStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark LocalUserListViewController_Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)localUserListViewController:(LocalUserListViewController_IOS *)sender
                    didSelectUserID:(NSString *)userID
{
	ZDCLogAutoTrace();
	
	selectedLocalUserID = userID.length?userID:NULL;
	[self refreshNavigationTitle];
	
	[self refreshUploadList];
	[self refreshDownloadList];
	[_tblActivity reloadData];
	
	[self refreshGeneralStatus];
	[self refreshSyncStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewDataSource
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	switch (selectedActivityType)
	{
		case ActivityType_Uploads          : return (NSInteger)(uploadNodeIDs.count); break;
		case ActivityType_Downloads        : return (NSInteger)(downloadNodeIDs.count);
		case ActivityType_UploadsDownloads : return (NSInteger)(uploadNodeIDs.count + downloadNodeIDs.count);
		case ActivityType_Raw              : return (NSInteger)(rawOperations.count);
		default                            : return (NSInteger)(0);
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSInteger rowIndex = indexPath.row;
	
	switch (selectedActivityType)
	{
		case ActivityType_Uploads: {
			NSString *nodeID = uploadNodeIDs[rowIndex];
			return [self uploadTableViewCell:nodeID forRow:rowIndex];
		}
		case ActivityType_Downloads: {
			NSString *nodeID = downloadNodeIDs[rowIndex];
			return [self downloadTableViewCell:nodeID forRow:rowIndex];
		}
		case ActivityType_UploadsDownloads: {
			if (rowIndex < uploadNodeIDs.count) {
				NSString *nodeID = uploadNodeIDs[rowIndex];
				return [self uploadTableViewCell:nodeID  forRow:rowIndex];
			}
			else {
				NSString *nodeID = downloadNodeIDs[rowIndex - uploadNodeIDs.count];
				return [self downloadTableViewCell:nodeID forRow:rowIndex];
			}
		}
		case ActivityType_Raw: {
			ZDCCloudOperation *op = rawOperations[rowIndex];
			return [self rawTableViewCell:op forRow:rowIndex];
		}
		default: {
			return nil;
		}
	}
 }


- (UITableViewCell *)uploadTableViewCell:(NSString *)nodeID forRow:(NSInteger)rowIndex
{

	UITableViewCell *cell = [_tblActivity dequeueReusableCellWithIdentifier:@"activityCell"];
	
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"activityCell"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}

	cell.textLabel.text =  [NSString stringWithFormat:@"Upload %ld ", (long)rowIndex];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)downloadTableViewCell:(NSString *)nodeID forRow:(NSInteger)rowIndex
{
	UITableViewCell *cell = [_tblActivity dequeueReusableCellWithIdentifier:@"activityCell"];
	
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"activityCell"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	
	cell.textLabel.text =  [NSString stringWithFormat:@"Dwonload %ld ", (long)rowIndex];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}


- (UITableViewCell *)rawTableViewCell:(ZDCCloudOperation *)op forRow:(NSInteger)rowIndex
{
	
	UITableViewCell *cell = [_tblActivity dequeueReusableCellWithIdentifier:@"activityCell"];
	
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"activityCell"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	
	cell.textLabel.text =  [NSString stringWithFormat:@"Raw %ld ", (long)rowIndex];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}

@end
