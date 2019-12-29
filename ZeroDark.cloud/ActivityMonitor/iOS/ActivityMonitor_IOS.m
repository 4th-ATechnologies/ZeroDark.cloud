/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ActivityMonitor_IOS.h"

#import "ActivityDescriptions.h"
#import "ActivityMonitorTableViewCell.h"
#import "ActivityMonitorTableViewCellRaw.h"
#import "LocalUserListViewController.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCIconTitleButton.h"
#import "ZDCLogging.h"
#import "ZeroDarkCloudPrivate.h"

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
	ActivityType_Uploads          = 0,
	ActivityType_Downloads        = 1,
	ActivityType_UploadsDownloads = 2,
	ActivityType_Raw              = 3,
};

static NSString *const kSyncStatus     = @"sync";
static NSString *const kAdvisoryStatus = @"advisory";
static NSString *const kActionStatus   = @"action";


@implementation ActivityMonitor_IOS
{
	IBOutlet __weak UISegmentedControl*   	_segActivity;
	IBOutlet __weak UITableView*   			_tblActivity;

	IBOutlet __weak UILabel*   				_lblStatus;
	IBOutlet __weak UIButton*  				_btnPause;
	
	ZDCIconTitleButton *							_btnTitle;
	UISwipeGestureRecognizer*    				swipeRight;
	
	ZeroDarkCloud *zdc;
	YapDatabaseConnection *uiDatabaseConnection;
	
	NSArray<NSString*> *localUserIDs;
	NSString *selectedLocalUserID;
	
	ActivityType selectedActivityType;
	
	NSMutableDictionary<NSUUID*, NSProgress*> *monitoredUploadProgress;
	NSMutableDictionary<NSString*, NSProgress*> *monitoredDownloadProgress;
	
	NSMutableDictionary<id, NSMutableDictionary*> *statusStates;

	NSArray<ZDCCloudOperation*> *rawOperations;
	NSDictionary<NSUUID*, ZDCCloudOperation*> *rawOperationsDict;
	
	NSArray<NSString *> *uploadNodeIDs;
	NSDictionary<NSString*, NSArray<ZDCCloudOperation *> *> *uploadTasks; // key=nodeID, value=[operations]
	NSDictionary<NSString*, NSNumber*> *minSnapshotDict;                  // key=nodeID, value=snapshot (uint64_t)
	
	NSArray<NSString *> *downloadNodeIDs;
	
	NSMutableOrderedSet<NSString *> *tableViewUpdate_oldIdentifiers;
	NSMutableOrderedSet<NSString *> *tableViewUpdate_oldSelectedIdentifiers;
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
		
		if (selectedActivityType != ActivityType_Uploads &&
		    selectedActivityType != ActivityType_Downloads &&
		    selectedActivityType != ActivityType_UploadsDownloads &&
		    selectedActivityType != ActivityType_Raw)
		{
			selectedActivityType = ActivityType_UploadsDownloads;
		}
	}
	return self;
}

- (void)dealloc
{
	ZDCLogAutoTrace();
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	if ((monitoredUploadProgress.count > 0) || (monitoredDownloadProgress.count > 0))
	{
		NSArray<NSString *> *observerKeyPaths = [self observerKeyPaths];
		
		for (NSProgress *progress in [monitoredUploadProgress objectEnumerator])
		{
			for (NSString *keyPath in observerKeyPaths)
			{
				[progress removeObserver:self forKeyPath:keyPath];
			}
		}
		for (NSProgress *progress in [monitoredDownloadProgress objectEnumerator])
		{
			for (NSString *keyPath in observerKeyPaths)
			{
				[progress removeObserver:self forKeyPath:keyPath];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
	[super viewDidLoad];
	
	monitoredUploadProgress = [[NSMutableDictionary alloc] init];
	monitoredDownloadProgress = [[NSMutableDictionary alloc] init];
	
	statusStates = [[NSMutableDictionary alloc] init];
	
	_tblActivity.separatorInset = UIEdgeInsetsMake(0, 0, 0, 0);
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(databaseConnectionDidUpdate:)
	                                             name: UIDatabaseConnectionDidUpdateNotification
	                                           object: nil];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(pipelineQueueChanged:)
	                                             name: YDBCloudCorePipelineQueueChangedNotification
	                                           object: nil];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(progressListChanged:)
	                                             name: ZDCProgressListChangedNotification
	                                           object: nil];
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
	
	_segActivity.selectedSegmentIndex = selectedActivityType;
	
	[self refreshUploadList];
	[self refreshDownloadList];
	[_tblActivity reloadData];
	
	[self refreshGeneralStatus];
	[self refreshSyncStatus];
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

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
	BOOL localUsersChanged = [[uiDatabaseConnection ext:Ext_View_LocalUsers] hasChangesForNotifications:notifications];
	
	if (localUsersChanged)
	{
		[self refreshLocalUsersList]; // <- might change: `allUsersSelected`, `selectedLocalUserID`
		
		[self refreshNavigationTitle];
		[self refreshGeneralStatus];
		[self refreshSyncStatus];
	}
	
	if (selectedActivityType == ActivityType_Uploads         ||
	    selectedActivityType == ActivityType_Downloads       ||
	    selectedActivityType == ActivityType_UploadsDownloads )
	{
		__block NSMutableArray<NSIndexPath*> *changedIndexPaths = nil;
	
		for (ActivityMonitorTableViewCell *cell in [_tblActivity visibleCells])
		{
			BOOL nodeChanged =
			  [uiDatabaseConnection hasObjectChangeForKey: cell.nodeID
			                                 inCollection: kZDCCollection_Nodes
			                              inNotifications: notifications];
			if (nodeChanged)
			{
				NSIndexPath *indexPath = [_tblActivity indexPathForCell:cell];
				if (indexPath)
				{
					if (changedIndexPaths == nil) {
						changedIndexPaths = [[NSMutableArray alloc] init];
					}
				}
				
				[changedIndexPaths addObject:indexPath];
			}
		}
		
		if (changedIndexPaths.count > 0)
		{
			[_tblActivity reloadRowsAtIndexPaths: changedIndexPaths
			                    withRowAnimation: UITableViewRowAnimationNone];
		}
	}
}

- (void)pipelineQueueChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Notification posted to non-main thread !");
	
	if (selectedActivityType == ActivityType_Downloads)
	{
		// Upload operations aren't currently being displayed in the tableView.
		// So we can just update the underlying data source.
		//
		[self refreshUploadList];
		[self refreshSyncStatus];
	}
	else
	{
		[self tableViewDataSourceWillChange];
		{
			[self refreshUploadList];
			[self refreshSyncStatus];
		}
		[self tableViewDataSourceDidChange:/*animateChanges:*/YES];
	}
	
	// The above calls will refresh the source data,
	// and will animate changes to the tableView.
	//
	// -- However --
	//
	// They will NOT properly reload cells that changed.
	// So we have to do that manually here.
	
	NSDictionary *userInfo = notification.userInfo;
	NSSet<NSUUID*> *modifiedOpUUIDs = userInfo[YDBCloudCorePipelineQueueChangedKey_modifiedOperationUUIDs];
	
	if (modifiedOpUUIDs.count > 0)
	{
		NSMutableArray<NSIndexPath*> *modifiedIndexPaths = [NSMutableArray array];
		
		switch (selectedActivityType)
		{
			case ActivityType_Raw:
			{
				for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
				{
					ZDCCloudOperation *op = rawOperations[indexPath.row];
					if ([modifiedOpUUIDs containsObject:op.uuid])
					{
						[modifiedIndexPaths addObject:indexPath];
					}
				}
				break;
			}
			case ActivityType_Uploads:
			case ActivityType_UploadsDownloads:
			{
				for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
				{
					if ((selectedActivityType == ActivityType_UploadsDownloads) && (indexPath.row >= uploadNodeIDs.count)) {
						continue;
					}
					
					NSString *nodeID = uploadNodeIDs[indexPath.row];
					NSArray<ZDCCloudOperation*> *ops = uploadTasks[nodeID];
					
					for (ZDCCloudOperation *op in ops)
					{
						if ([modifiedOpUUIDs containsObject:op.uuid])
						{
							[modifiedIndexPaths addObject:indexPath];
							break;
						}
					}
				}
				break;
			}
			default: { break; }
		}
		
		if (modifiedIndexPaths.count > 0)
		{
			[_tblActivity reloadRowsAtIndexPaths:modifiedIndexPaths withRowAnimation:UITableViewRowAnimationNone];
		}
	}
}

- (void)progressListChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Notification posted to non-main thread !");
	
	ZDCProgressManagerChanges *changes = notification.userInfo[kZDCProgressManagerChanges];
	ZDCProgressType progressType = changes.progressType;
	
	if (progressType == ZDCProgressType_Upload)
	{
		NSUUID *operationUUID = changes.operationUUID;
		
		NSIndexPath *visibleIndexPath = [self visibleIndexPathForOperationUUID:operationUUID];
		if (visibleIndexPath)
		{
			[_tblActivity reloadRowsAtIndexPaths:@[visibleIndexPath] withRowAnimation:UITableViewRowAnimationNone];
		}
	}
	else if (progressType == ZDCProgressType_MetaDownload || progressType == ZDCProgressType_DataDownload)
	{
		if (selectedActivityType == ActivityType_Downloads ||
		    selectedActivityType == ActivityType_UploadsDownloads)
		{
			[self tableViewDataSourceWillChange];
			{
				[self refreshDownloadList];
				[self refreshSyncStatus];
			}
			[self tableViewDataSourceDidChange:/*animateChanges:*/YES];
		}
		else
		{
			// Download operations aren't currently being displayed in the tableView.
			// So we can just update the underlying data source.
			//
			[self refreshDownloadList];
			[self refreshSyncStatus];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Progress Monitoring
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<NSString *> *)observerKeyPaths
{
	return @[
		NSStringFromSelector(@selector(fractionCompleted)),
		
		// This doesn't work.
		// We have to be more precise.
		//
	//	NSStringFromSelector(@selector(userInfo)),
		
		// This works fine, but we actually don't need it.
		//
	//	[NSString stringWithFormat:@"%@.%@",
	//	  NSStringFromSelector(@selector(userInfo)), NSProgressThroughputKey],
		//
		// ZDCProgressManager always sets both NSProgressThroughputKey & NSProgressEstimatedTimeRemainingKey together.
		// And it always sets NSProgressEstimatedTimeRemainingKey last.
		// So we can just observe that instead.
		
		[NSString stringWithFormat:@"%@.%@",
		  NSStringFromSelector(@selector(userInfo)), NSProgressEstimatedTimeRemainingKey],
		
		// We use this for multipart descriptions.
		[NSString stringWithFormat:@"%@.%@",
		  NSStringFromSelector(@selector(userInfo)), ZDCLocalizedDescriptionKey],
	];
}

- (NSProgress *)monitoredUploadProgressForOperationUUID:(NSUUID *)operationUUID
{
	if (operationUUID == nil) return nil;
	
	NSProgress *progress = monitoredUploadProgress[operationUUID];
	if (progress) {
		return progress;
	}
	
	__weak typeof(self) weakSelf = self;
	progress = [zdc.progressManager uploadProgressForOperationUUID: operationUUID
	                                               completionQueue: dispatch_get_main_queue()
	                                               completionBlock:^(BOOL success)
	{
		[weakSelf stopMonitoringUploadProgressForOperationUUID:operationUUID];
	}];
	
	if (progress)
	{
		for (NSString *keyPath in [self observerKeyPaths])
		{
			[progress addObserver: self
			           forKeyPath: keyPath
			              options: 0
			              context: NULL];
		}
		
		monitoredUploadProgress[operationUUID] = progress;
	}
	
	return progress;
}

- (void)stopMonitoringUploadProgressForOperationUUID:(NSUUID *)operationUUID
{
	if (operationUUID == nil) return;
	
	NSProgress *progress = monitoredUploadProgress[operationUUID];
	if (progress)
	{
		for (NSString *keyPath in [self observerKeyPaths])
		{
			[progress removeObserver:self forKeyPath:keyPath];
		}
	
		monitoredUploadProgress[operationUUID] = nil;
	
		NSIndexPath *visibleIndexPath = [self visibleIndexPathForOperationUUID:operationUUID];
		if (visibleIndexPath)
		{
			id <ActivityMonitorTableCellProtocol> cell = (id <ActivityMonitorTableCellProtocol>)
			  [_tblActivity cellForRowAtIndexPath:visibleIndexPath];
	
			if (cell)
			{
				[self updateCell:cell withProgress:nil];
				[self updateCell:cell withProgressUserInfo:nil];
			}
		}
	}
}

- (NSProgress *)monitoredDownloadProgressForNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return nil;
	
	NSProgress *progress = monitoredDownloadProgress[nodeID];
	if (progress) {
		return progress;
	}
	
	progress = [zdc.progressManager downloadProgressForNodeID:nodeID];
	
	if (progress)
	{
		ZDCProgressType type = (ZDCProgressType)[progress.userInfo[ZDCProgressTypeKey] integerValue];
		
		if (type == ZDCProgressType_MetaDownload)
		{
			NSNumber *components = progress.userInfo[ZDCNodeMetaComponentsKey];
			
			__weak typeof(self) weakSelf = self;
			[zdc.progressManager addMetaDownloadListenerForNodeID:nodeID
																	 components:components
															  completionQueue:dispatch_get_main_queue()
															  completionBlock:
			^(ZDCCloudDataInfo *header, NSData *metadata, NSData *thumbnail, NSError *error) {
				
				[weakSelf stopMonitoringDownloadProgressForNodeID:nodeID];
			}];
		}
		else if (type == ZDCProgressType_DataDownload)
		{
			__weak typeof(self) weakSelf = self;
			[zdc.progressManager addDataDownloadListenerForNodeID:nodeID
															  completionQueue:dispatch_get_main_queue()
															  completionBlock:
			^(ZDCCloudDataInfo *header, ZDCCryptoFile *cryptoFile, NSError *error) {
				
				[weakSelf stopMonitoringDownloadProgressForNodeID:nodeID];
			}];
			
		}
		
		for (NSString *keyPath in [self observerKeyPaths])
		{
			[progress addObserver: self
			           forKeyPath: keyPath
			              options: 0
			              context: NULL];
		}
		
		monitoredDownloadProgress[nodeID] = progress;
	}
	
	return progress;
}

- (void)stopMonitoringDownloadProgressForNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return;
	
	NSProgress *progress = monitoredDownloadProgress[nodeID];
	if (progress)
	{
		for (NSString *keyPath in [self observerKeyPaths])
		{
			[progress removeObserver:self forKeyPath:keyPath];
		}
	
		monitoredDownloadProgress[nodeID] = nil;
	
		NSIndexPath *visibleIndexPath = [self visibleIndexPathForDownloadingNodeID:nodeID];
		if (visibleIndexPath)
		{
			id <ActivityMonitorTableCellProtocol> cell = (id <ActivityMonitorTableCellProtocol>)
			  [_tblActivity cellForRowAtIndexPath:visibleIndexPath];
		
			if (cell)
			{
				[self updateCell:cell withProgress:nil];
				[self updateCell:cell withProgressUserInfo:nil];
			}
		}
	}
}


- (void)progressPercentChanged:(NSProgress *)progress
{
//	ZDCLogAutoTrace(); // noisy
	
	NSIndexPath *visibleIndexPath = [self visibleIndexPathForProgress:progress];
	if (visibleIndexPath)
	{
		id <ActivityMonitorTableCellProtocol> cell = (id <ActivityMonitorTableCellProtocol>)
		  [_tblActivity cellForRowAtIndexPath:visibleIndexPath];

		if (cell)
		{
			[self updateCell:cell withProgress:progress];
		}
	}
}

- (void)progressDescriptionChanged:(NSProgress *)progress
{
//	ZDCLogAutoTrace(); // noisy
	
	NSIndexPath *visibleIndexPath = [self visibleIndexPathForProgress:progress];
	if (visibleIndexPath)
	{
		id <ActivityMonitorTableCellProtocol> cell = (id <ActivityMonitorTableCellProtocol>)
		  [_tblActivity cellForRowAtIndexPath:visibleIndexPath];

		if ([cell isKindOfClass:[ActivityMonitorTableViewCell class]])
		{
			NSString *multipartDescription = progress.userInfo[ZDCLocalizedDescriptionKey];
			if (multipartDescription)
			{
				((ActivityMonitorTableViewCell *)cell).opsInfo.text = multipartDescription;
			}
		}
	}
}

/**
 * Progress "calculations" includes networkThroughput & timeRemaining.
 */
- (void)progressCalculationsChanged:(NSProgress *)progress
{
//	ZDCLogAutoTrace(); // too noisy
	
	NSIndexPath *visibleIndexPath = [self visibleIndexPathForProgress:progress];
	if (visibleIndexPath)
	{
		id <ActivityMonitorTableCellProtocol> cell = (id <ActivityMonitorTableCellProtocol>)
		  [_tblActivity cellForRowAtIndexPath:visibleIndexPath];

		if (cell)
		{
			[self updateCell:cell withProgressUserInfo:progress.userInfo];
		}
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
	NSAssert([object isKindOfClass:[NSProgress class]], @"Observing unexpected object ?");
	
	NSProgress *progress = (NSProgress *)object;
	
	__weak typeof(self) weakSelf = self;
	
	dispatch_block_t block = ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			if ([keyPath isEqualToString:NSStringFromSelector(@selector(fractionCompleted))])
				[strongSelf progressPercentChanged:progress];
			else if ([keyPath hasSuffix:ZDCLocalizedDescriptionKey])
				[strongSelf progressDescriptionChanged:progress];
			else
				[strongSelf progressCalculationsChanged:progress];
		}
		
	#pragma clang diagnostic pop
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable NSIndexPath *)visibleIndexPathForProgress:(NSProgress *)progress
{
	BOOL maybeUpload = YES;
	if (@available(macOS 10.13, iOS 11, *))
	{
		NSProgressFileOperationKind kind = progress.fileOperationKind;
		if (kind)
		{
			if (kind == NSProgressFileOperationKindDownloading) {
				maybeUpload = NO;
			}
		}
	}
	
	__block NSUUID *operationUUID = nil;
	if (maybeUpload)
	{
		[monitoredUploadProgress enumerateKeysAndObjectsUsingBlock:
			^(NSUUID *opUUID, NSProgress *opProgress, BOOL *stop)
		{
			if (progress == opProgress)
			{
				operationUUID = opUUID;
				*stop = YES;
			}
		}];
	}
	
	__block NSString *downloadNodeID = nil;
	if (operationUUID == nil)
	{
		[monitoredDownloadProgress enumerateKeysAndObjectsUsingBlock:
			^(NSString *nodeID, NSProgress *downloadProgress, BOOL *stop)
		{
			if (progress == downloadProgress)
			{
				downloadNodeID = nodeID;
				*stop = YES;
			}
		}];
	}
	
	NSIndexPath *visibleIndexPath = [self visibleIndexPathForOperationUUID:operationUUID];
	if (!visibleIndexPath) {
		visibleIndexPath = [self visibleIndexPathForDownloadingNodeID:downloadNodeID];
	}
	
	return visibleIndexPath;
}

- (nullable NSIndexPath *)visibleIndexPathForOperationUUID:(nullable NSUUID *)operationUUID
{
	if (operationUUID == nil) return nil;
	
	NSIndexPath *result = nil;
	
	if (selectedActivityType == ActivityType_Uploads)
	{
		for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
		{
			NSString *nodeID = uploadNodeIDs[indexPath.row];
			for (ZDCCloudOperation *op in uploadTasks[nodeID])
			{
				if ([op.uuid isEqual:operationUUID])
				{
					result = indexPath;
					break;
				}
			}
		}
	}
	else if (selectedActivityType == ActivityType_UploadsDownloads)
	{
		for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
		{
			if (indexPath.row < uploadNodeIDs.count) // "both" has uploads & downloads
			{
				NSString *nodeID = uploadNodeIDs[indexPath.row];
				for (ZDCCloudOperation *op in uploadTasks[nodeID])
				{
					if ([op.uuid isEqual:operationUUID])
					{
						result = indexPath;
						break;
					}
				}
			}
		}
	}
	else if (selectedActivityType == ActivityType_Raw)
	{
		for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
		{
			ZDCCloudOperation *op = rawOperations[indexPath.row];
			if ([op.uuid isEqual:operationUUID])
			{
				result = indexPath;
				break;
			}
		}
	}
	
	return result;
}

- (nullable NSIndexPath *)visibleIndexPathForDownloadingNodeID:(nullable NSString *)inNodeID
{
	if (inNodeID == nil) return nil;
	
	NSIndexPath *result = nil;
	
	if (selectedActivityType == ActivityType_Downloads)
	{
		for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
		{
			NSString *nodeID = downloadNodeIDs[indexPath.row];
			if ([nodeID isEqualToString:inNodeID])
			{
				result = indexPath;
				break;
			}
		}
	}
	else if (selectedActivityType == ActivityType_UploadsDownloads)
	{
		for (NSIndexPath *indexPath in [_tblActivity indexPathsForVisibleRows])
		{
			if (indexPath.row >= uploadNodeIDs.count) // "both" has uploads & downloads
			{
				NSString *nodeID = downloadNodeIDs[indexPath.row - uploadNodeIDs.count];
				if ([nodeID isEqualToString:inNodeID])
				{
					result = indexPath;
					break;
				}
			}
		}
	}
	
	return result;
}

- (int32_t)priorityForOperation:(ZDCCloudOperation *)op
{
	NSAssert([NSThread isMainThread], @"Attempting to access non-safe ivars on on main-thread !");
	
//	NSArray<NSNumber*> *overrideInfo = priorityOverrides[op.uuid];
//	if (overrideInfo)
//	{
//		NSNumber *override = overrideInfo[0];
//		return override.intValue;
//	}
//	else
//	{
		return op.priority;
//	}
}

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
	
	ZDCSyncManager *syncManager = zdc.syncManager;
	
	BOOL usePlayIcon = NO;
	BOOL useGearIcon = NO;
	
	BOOL allUsersSelected = (selectedLocalUserID == nil);
	if (allUsersSelected)
	{
		__block NSUInteger numSyncingPaused = 0;
		__block NSUInteger numPushingPaused = 0;
		__block NSUInteger numActive = 0;
		
		[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			for (NSString *localUserID in localUserIDs)
			{
				ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];

				if (localUser.syncingPaused) {
					numSyncingPaused++;
				}
				else if ([syncManager isPushingPausedForLocalUserID:localUserID]) {
					numPushingPaused++;
				}
				else {
					numActive++;
				}
			}
			
		#pragma clang diagnostic push
		}];
		
		if ((numActive == 0) && (numSyncingPaused > 0 && numPushingPaused == 0))
		{
			NSString *msg = NSLocalizedString(@"Syncing paused", @"Activity Monitor status");
			
			[self setAdvisoryStatus:msg forLocalUserID:nil];
			
			usePlayIcon = YES;
		}
		else if ((numActive > 0) && (numSyncingPaused > 0 || numPushingPaused > 0))
		{
			// Mixed state - display action status
			
			NSString *frmt = NSLocalizedString(@"Accounts paused: %llu,  active: %llu", @"Activity Monitor status");
			NSString *msg = [NSString stringWithFormat:frmt,
				(unsigned long long)(numSyncingPaused | numPushingPaused),
				(unsigned long long)numActive];
			
			[self setAdvisoryStatus:msg forLocalUserID:nil];
			[self setActionStatus:msg forLocalUserID:nil];
			
			useGearIcon = YES;
		}
		else
		{
			[self setAdvisoryStatus:nil forLocalUserID:nil];
		}
	}
	else // if (selectedLocalUserID != nil)
	{
		__block ZDCLocalUser *localUser = nil;
		
		[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			localUser = [transaction objectForKey:selectedLocalUserID inCollection:kZDCCollection_Users];
			
		#pragma clang diagnostic push
		}];
		
		if (localUser.syncingPaused)
		{
			NSString *msg = NSLocalizedString(@"Syncing paused", @"Activity Monitor status");
			
			[self setAdvisoryStatus:msg forLocalUserID:selectedLocalUserID];
			usePlayIcon = YES;
		}
		else if ([syncManager isPushingPausedForLocalUserID:selectedLocalUserID])
		{
			NSString *msg = NSLocalizedString(@"Pushing paused", @"Activity Monitor status");
			
			[self setAdvisoryStatus:msg forLocalUserID:selectedLocalUserID];
			useGearIcon = YES;
		}
		else
		{
			[self setAdvisoryStatus:nil forLocalUserID:selectedLocalUserID];
		}
	}
	
	UIImage *image = nil;
	
	if (usePlayIcon)
	{
		if (@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)) {
			image = [UIImage systemImageNamed:@"play.circle"];
		}
		if (image == nil) {
			image = [ZeroDarkCloud imageNamed:@"play-round-24"];
		}
	}
	else if (useGearIcon)
	{
		if (@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)) {
			image = [UIImage systemImageNamed:@"gear"];
		}
		if (image == nil) {
			image = [ZeroDarkCloud imageNamed:@"gear"];
		}
	}
	else // usePauseIcon
	{
		if (@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)) {
			image = [UIImage systemImageNamed:@"pause.circle"];
		}
		if (image == nil) {
			image = [ZeroDarkCloud imageNamed:@"pause-round-24"];
		}
	}
	
	[_btnPause setImage:image forState:UIControlStateNormal];
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
//	ZDCLogAutoTrace(); // noisy
	
	BOOL allUsersSelected = (selectedLocalUserID == nil);

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
					if ([zdc.syncManager isPushingPausedForLocalUserID:localUser.uuid]) {
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
			uploadsPaused = [zdc.syncManager isPushingPausedForLocalUserID:selectedLocalUserID];
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
			{ // Scoping
				
				UIAlertAction *pauseUploadsAction =
				  [UIAlertAction actionWithTitle: NSLocalizedString(@"Pause Uploads", L10nComment)
				                           style: UIAlertActionStyleDefault
				                         handler:^(UIAlertAction *action)
				{
					[weakSelf pauseUploadsPlusAbort:YES];
				}];
			
				[alertController addAction:pauseUploadsAction];
			}
			{ // Scoping
	
				UIAlertAction *pauseFutureUploadsAction =
				  [UIAlertAction actionWithTitle: NSLocalizedString(@"Pause Uploads (continue in-progress)", L10nComment)
				                           style: UIAlertActionStyleDefault
				                         handler:^(UIAlertAction *action)
				{
					[weakSelf pauseUploadsPlusAbort:NO];
				}];
		
				[alertController addAction:pauseFutureUploadsAction];
			}
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
	
	selectedActivityType = _segActivity.selectedSegmentIndex;
	
	if (zdc.internalPreferences.activityMonitor_lastActivityType != selectedActivityType)
	{
		zdc.internalPreferences.activityMonitor_lastActivityType = selectedActivityType;
	}
	
	[_tblActivity reloadData];
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
	}];
}

- (void)pauseUploadsPlusAbort:(BOOL)shouldAbortUploads
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
	
	selectedLocalUserID = userID.length ? userID : nil;
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

#pragma mark UITableView Logic

- (UITableViewCell *)uploadTableViewCell:(NSString *)nodeID forRow:(NSInteger)rowIndex
{
	ActivityMonitorTableViewCell *cell =
	  [_tblActivity dequeueReusableCellWithIdentifier:@"ActivityMonitorTableViewCell"];

	cell.opTypeImageView.image =
	  [UIImage imageNamed: @"cloud-upload-template-18"
	             inBundle: [ZeroDarkCloud frameworkBundle] compatibleWithTraitCollection:nil];
	
	__block ZDCTreesystemPath *path = nil;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCNode *node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		//
		// node might be nil (i.e. node has been deleted)
		
		path = [zdc.nodeManager pathForNode:node transaction:transaction];
		
	#pragma clang diagnostic pop
	}];
	
	NSArray<ZDCCloudOperation *> *nodeOps = uploadTasks[nodeID];
	
	if (path)
	{
		if (path.trunk == ZDCTreesystemTrunk_Home) {
			cell.nodeInfo.text = path.relativePath;
		}
		else {
			cell.nodeInfo.text = path.fullPath;
		}
	}
	else // if (path == nil) // node might be nil (i.e. node has been deleted & trash emptied)
	{
		// Backup plan:
		// Try to get the cloudPath from an operation.
		
		ZDCCloudOperation *op = [nodeOps firstObject];
		
		ZDCCloudPath *cloudPath = op.cloudLocator.cloudPath;
		
		ZDCCloudPathComponents comps = ZDCCloudPathComponents_DirPrefix | ZDCCloudPathComponents_FileName_WithoutExt;
		NSString *cloudPathStr = [cloudPath pathWithComponents:comps];
		
		cell.nodeInfo.text = cloudPathStr ?: @"/?";
	}
	
	{ // Priority
	
		int32_t priority = [self priorityForOperation:[nodeOps firstObject]];
		
		BOOL mixedPriorities = NO;
		BOOL hasPositivePriority = (priority > 0);
		BOOL hasNegativePriority = (priority < 0);
		
		for (NSUInteger i = 1; i < nodeOps.count; i++)
		{
			int32_t altPriority = [self priorityForOperation:nodeOps[i]];
			if (priority != altPriority)
			{
				mixedPriorities = YES;
				hasPositivePriority = hasPositivePriority || (altPriority > 0);
				hasNegativePriority = hasNegativePriority || (altPriority < 0);
			}
		}
		
		if (mixedPriorities)
		{
			cell.priority.hidden = NO;
			
			if (hasPositivePriority && !hasNegativePriority) {
				cell.priority.text = @"+X";
			}
			else if (!hasPositivePriority && hasNegativePriority) {
				cell.priority.text = @"-X";
			}
			else {
				cell.priority.text = @"+-";
			}
		}
		else if (priority == 0)
		{
			cell.priority.hidden = YES;
			cell.priority.text = @"";
		}
		else
		{
			cell.priority.hidden = NO;
			cell.priority.text = [NSString stringWithFormat:@"%@%d", (priority > 0 ? @"+" : @""), priority];
		}
	}
	
	ZDCCloudOperation *dataUpload = nil;
	BOOL hasActiveOp = NO;
	BOOL hasPutOp = NO;
	BOOL hasMoveOp = NO;
	BOOL hasDeleteOp = NO;
	BOOL hasCopyOp = NO;
	BOOL hasPutRcrdOp = NO;
	BOOL hasPutDataOp = NO;
	
	ZDCCloud *cloudExt = [zdc.databaseManager cloudExtForUserID:selectedLocalUserID];
	
	for (ZDCCloudOperation *op in nodeOps)
	{
		if ([op isPutNodeDataOperation])
		{
			// There might be multiple file uploads in the queue.
			// Always use the first one.
			//
			if (dataUpload == nil) {
				dataUpload = op;
			}
		}
		
		YDBCloudCoreOperationStatus opStatus =
		  [[cloudExt pipelineWithName:op.pipeline] statusForOperationWithUUID:op.uuid];
		
		if (opStatus == YDBCloudOperationStatus_Active)
		{
			hasActiveOp = YES;
		}
		
		if ((opStatus != YDBCloudOperationStatus_Skipped) && (opStatus != YDBCloudOperationStatus_Completed))
		{
			switch (op.type)
			{
				case ZDCCloudOperationType_Put:
				{
					hasPutOp = YES;
					switch (op.putType)
					{
						case ZDCCloudOperationPutType_Node_Rcrd:
							hasPutRcrdOp = YES;
							break;
						case ZDCCloudOperationPutType_Node_Data:
							hasPutDataOp = YES;
							break;
						default: break;
					}
					break;
				}
				case ZDCCloudOperationType_Move:
				{
					hasMoveOp = YES;
					break;
				}
				case ZDCCloudOperationType_DeleteLeaf:
				case ZDCCloudOperationType_DeleteNode:
				{
					hasDeleteOp = YES;
					break;
				}
				case ZDCCloudOperationType_CopyLeaf:
				{
					hasCopyOp = YES;
					break;
				}
				default: break;
			}
		}
	}
	
	NSProgress *progress = [self monitoredUploadProgressForOperationUUID:dataUpload.uuid];
	
	NSString *detailedInfo = nil;
	
	if (dataUpload && progress && [progress isKindOfClass:[ZDCProgress class]])
	{
		detailedInfo = progress.userInfo[ZDCLocalizedDescriptionKey];
	}
	
	if (detailedInfo == nil)
	{
		NSMutableArray *opStrs = [NSMutableArray arrayWithCapacity:4];
		
		if (hasPutOp)
		{
			NSMutableArray *components = [NSMutableArray arrayWithCapacity:3];
			if (hasPutRcrdOp)  [components addObject:@"rcrd"];
			if (hasPutDataOp)  [components addObject:@"data"];
			
			NSString *str = [NSString stringWithFormat:@"put (%@)", [components componentsJoinedByString:@", "]];
			[opStrs addObject:str];
		}
		
		if (hasMoveOp)
		{
			[opStrs addObject:@"move/rename"];
		}
		
		if (hasDeleteOp)
		{
			[opStrs addObject:@"delete"];
		}
		
		if (hasCopyOp)
		{
			[opStrs addObject:@"copy"];
		}
		
		detailedInfo = [opStrs componentsJoinedByString:@", "];
	}
	
	cell.opsInfo.text = detailedInfo;
	
	if (hasActiveOp)
		[cell.circularProgress startAnimating];
	else
		[cell.circularProgress stopAnimating];
	
	[self updateCell:cell withProgress:progress];
	[self updateCell:cell withProgressUserInfo:progress.userInfo];
	
	return cell;
}

- (UITableViewCell *)downloadTableViewCell:(NSString *)nodeID forRow:(NSInteger)rowIndex
{
	ActivityMonitorTableViewCell *cell =
	  [_tblActivity dequeueReusableCellWithIdentifier:@"ActivityMonitorTableViewCell"];
	
	cell.opTypeImageView.image =
	  [UIImage imageNamed: @"cloud-download-template-18"
	             inBundle: [ZeroDarkCloud frameworkBundle] compatibleWithTraitCollection:nil];
	
	__block ZDCNode *node = nil;
	__block ZDCTreesystemPath *path = nil;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		//
		// node might be nil (i.e. node has been deleted)
		
		path = [zdc.nodeManager pathForNode:node transaction:transaction];
		
	#pragma clang diagnostic pop
	}];
	
	if (path)
	{
		if (path.trunk == ZDCTreesystemTrunk_Home) {
			cell.nodeInfo.text = path.relativePath;
		}
		else {
			cell.nodeInfo.text = path.fullPath;
		}
	}
	else
	{
		cell.nodeInfo.text = @"/?";
	}
	
	cell.priority.hidden = YES;
	cell.priority.text = @"";
	
	{ // scoping
		
		NSDate *lastModified = node.lastModified;
		if (lastModified)
		{
			NSString *when = [lastModified descriptionWithLocale:nil];
			
			NSString *frmt = NSLocalizedString(@"Modified %@", nil);
			NSString *str = [NSString stringWithFormat:frmt, when];
			
			cell.opsInfo.text = str ?: @"";
		}
		else
		{
			NSString *str = NSLocalizedString(@"Modified recently", nil);
			
			cell.opsInfo.text = str ?: @"";
		}
	}
	
	NSProgress *progress = [self monitoredDownloadProgressForNodeID:nodeID];
	
	BOOL isActive = progress.fractionCompleted > 0.0;
	if (isActive)
		[cell.circularProgress startAnimating];
	else
		[cell.circularProgress stopAnimating];
	
	[self updateCell:cell withProgress:progress];
	[self updateCell:cell withProgressUserInfo:progress.userInfo];
	
	return cell;
}

- (UITableViewCell *)rawTableViewCell:(ZDCCloudOperation *)op forRow:(NSInteger)rowIndex
{
	ActivityMonitorTableViewCellRaw *cell =
	  [_tblActivity dequeueReusableCellWithIdentifier:@"ActivityMonitorTableViewCellRaw"];
	
	NSString *opType = nil;
	switch (op.type)
	{
		case ZDCCloudOperationType_Put:
		{
			switch (op.putType)
			{
				case ZDCCloudOperationPutType_Node_Rcrd : opType = @"put:rcrd"; break;
				case ZDCCloudOperationPutType_Node_Data : opType = @"put:data"; break;
				default                                 : opType = @"put:?";    break;
			}
			
			break;
		}
		case ZDCCloudOperationType_Move:
		{
			opType = @"move";
			break;
		}
		case ZDCCloudOperationType_DeleteLeaf:
		{
			if (op.ifOrphan) {
				opType = @"delete-leaf (if-orphan)";
			} else {
				opType = @"delete-leaf";
			}
			
			break;
		}
		case ZDCCloudOperationType_DeleteNode:
		{
			if (op.ifOrphan) {
				opType = @"delete-node (if-orphan)";
			} else {
				opType = @"delete-node";
			}
			
			break;
		}
		case ZDCCloudOperationType_CopyLeaf:
		{
			opType = @"copy-leaf";
			break;
		}
		default:
		{
			opType = @"unknown";
			break;
		}
	}
	
	cell.opType.text = opType;
	cell.opUUID.text = [op.uuid UUIDString];
	cell.snapshot.text = [NSString stringWithFormat:@"%llu", (unsigned long long)op.snapshot];

	NSUInteger dependenciesRemaining = 0;
	for (NSUUID *depUUID in op.dependencies)
	{
		if (rawOperationsDict[depUUID] != nil) {
			dependenciesRemaining++;
		}
	}
	
	cell.dependenciesRemaining.text =
		[NSString stringWithFormat:@"%llu", (unsigned long long)dependenciesRemaining];
	
	ZDCCloudLocator *cloudLocator = op.dstCloudLocator;
	if (cloudLocator == nil) {
		cloudLocator = op.cloudLocator;
	}
	
	cell.dirPrefix.text = cloudLocator.cloudPath.dirPrefix ?: @"";
	cell.filename.text = cloudLocator.cloudPath.fileName ?: @"";
	
	int32_t priority = [self priorityForOperation:op];
	if (priority == 0) {
		cell.priority.hidden = YES;
		cell.priority.text = @"";
	}
	else {
		cell.priority.hidden = NO;
		cell.priority.text = [NSString stringWithFormat:@"%@%d", (priority > 0 ? @"+" : @""), priority];
	}
	
	ZDCCloud *cloudExt = [zdc.databaseManager cloudExtForUserID:op.localUserID];
	YapDatabaseCloudCorePipeline *pipeline = [cloudExt pipelineWithName:op.pipeline];
	
	YDBCloudCoreOperationStatus opStatus = [pipeline statusForOperationWithUUID:op.uuid];
	
	if (opStatus == YDBCloudOperationStatus_Active) {
		[cell.circularProgress startAnimating];
	}
	else {
		[cell.circularProgress stopAnimating];
	}
	
	NSProgress *progress = [self monitoredUploadProgressForOperationUUID:op.uuid];
	
	[self updateCell:cell withProgress:progress];
	[self updateCell:cell withProgressUserInfo:progress.userInfo];
	
	return cell;
}

- (void)updateCell:(id <ActivityMonitorTableCellProtocol>)cell withProgress:(NSProgress *)progress
{
	if (progress)
	{
		double percent = progress.fractionCompleted;
		
		cell.horizontalProgress.hidden = NO;
		cell.horizontalProgress.progress = percent;
	//	cell.horizontalProgress.indeterminate = (percent >= 1.0);
	}
	else
	{
		cell.horizontalProgress.hidden = YES;
		cell.horizontalProgress.progress = 0.0;
	}
}

- (void)updateCell:(id <ActivityMonitorTableCellProtocol>)cell withProgressUserInfo:(NSDictionary *)progressUserInfo
{
	NSNumber *throughput = progressUserInfo[NSProgressThroughputKey];
	if (throughput)
	{
		cell.networkThroughput.hidden = NO;
		cell.networkThroughput.text = [ActivityDescriptions descriptionForNetworkThroughput:throughput];
	}
	else
	{
		cell.networkThroughput.hidden = YES;
		cell.networkThroughput.text = @"";
	}
	
	NSNumber *remaining = progressUserInfo[NSProgressEstimatedTimeRemainingKey];
	if (remaining)
	{
		cell.timeRemaining.hidden = NO;
		cell.timeRemaining.text = [ActivityDescriptions descriptionForTimeRemaining:remaining];
	}
	else
	{
		cell.timeRemaining.hidden = YES;
		cell.timeRemaining.text = @"";
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableView Update
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is assists the animation & selection logic
 * within the `tableViewDataSourceWillChange` & `tableViewDataSourceDidChange:` methods.
 *
 * It's job is simple:
 *
 * - For a given index, the method must return a UNIQUE string the refers only to this item.
 * - The string must be derived from the underlying data source (i.e. don't use rowIndex as part of the string).
 *
 * Remember, this method gets called while in the middle of updating the table.
 * So the given rowIndex is a reference to the underlying data store,
 * and not necessarily the current tableView state.
**/
- (NSString *)identifierForRow:(NSUInteger)row
{
	NSString *const prefix_upload   = @"u|";
	NSString *const prefix_download = @"d|";
	NSString *const prefix_raw      = @"r|";
	
	switch (selectedActivityType)
	{
		case ActivityType_Uploads: {
			NSString *nodeID = uploadNodeIDs[row];
			return [prefix_upload stringByAppendingString:nodeID];
		}
		case ActivityType_Downloads: {
			NSString *nodeID = downloadNodeIDs[row];
			return [prefix_download stringByAppendingString:nodeID];
		}
		case ActivityType_UploadsDownloads: {
			if (row < uploadNodeIDs.count) {
				NSString *nodeID = uploadNodeIDs[row];
				return [prefix_upload stringByAppendingString:nodeID];
			}
			else {
				NSString *nodeID = downloadNodeIDs[row - uploadNodeIDs.count];
				return [prefix_download stringByAppendingString:nodeID];
			}
		}
		case ActivityType_Raw: {
			NSUUID *opUUID = rawOperations[row].uuid;
			return [prefix_raw stringByAppendingString:opUUID.UUIDString];
		}
		default: {
			NSAssert(NO, @"Invalid row");
			return [[NSUUID UUID] UUIDString];
		}
	}
}

- (void)tableViewDataSourceWillChange
{
	ZDCLogAutoTrace();
	
	{ // tableViewUpdate_oldIdentifiers
		
		const NSUInteger count = [_tblActivity numberOfRowsInSection:0];
		tableViewUpdate_oldIdentifiers = [[NSMutableOrderedSet alloc] initWithCapacity:count];
		
		for (NSUInteger rowIdx = 0; rowIdx < count; rowIdx++)
		{
			NSString *identifier = [self identifierForRow:rowIdx];
			NSAssert(
				![tableViewUpdate_oldIdentifiers containsObject:identifier],
				@"Method `uniqueIdentifierForRow` MUST return a unique identifier. Not unique: %@", identifier);
			
			[tableViewUpdate_oldIdentifiers addObject:identifier];
		}
	}
	{ // tableViewUpdate_oldSelectedIdentifiers
		
		NSArray<NSIndexPath*> *selected = _tblActivity.indexPathsForSelectedRows;
		tableViewUpdate_oldSelectedIdentifiers = [[NSMutableOrderedSet alloc] initWithCapacity:selected.count];
		
		for (NSIndexPath *indexPath in selected)
		{
			NSString *identifier = [self identifierForRow:indexPath.row];
			[tableViewUpdate_oldSelectedIdentifiers addObject:identifier];
		}
	}
}

- (void)tableViewDataSourceDidChange:(BOOL)animateChanges
{
	ZDCLogAutoTrace();
	
	// Step 1 of 3:
	//
	// Create a new list of identifiers for the rows.
	//
	// Note: We have NOT updated the `tableView` instance yet.
	// So if we call [_tblActivity numberOfRowsInSection:0], we'll get a bad answer.
	
	const NSUInteger count = (NSUInteger)[self tableView:_tblActivity numberOfRowsInSection:0]; // <- see note above
	NSMutableOrderedSet *tableViewUpdate_newIdentifiers = [NSMutableOrderedSet orderedSetWithCapacity:count];
	
	for (NSUInteger rowIdx = 0; rowIdx < count; rowIdx++)
	{
		NSString *identifier = [self identifierForRow:rowIdx];
		NSAssert(
			![tableViewUpdate_newIdentifiers containsObject:identifier],
			@"Method `uniqueIdentifierForRow` MUST return a unique identifier. Not unique: %@", identifier);
		
		[tableViewUpdate_newIdentifiers addObject:identifier];
	}
	
	// Step 2 of 3:
	//
	// Update the tableView data.
	
	if (!animateChanges)
	{
		[_tblActivity reloadData];
	}
	else
	{
		// The key to understanding tableView animations is the word "INCREMENTALLY".
		//
		// From the Apple Docs:
		//
		// > Changes are processed incrementally as the `insertRowsAtIndexes:withAnimation:`,
		// > `removeRowsAtIndexes:withAnimation:`, and the `moveRowAtIndex:toIndex:` methods
		// > are called. It is acceptable to delete row 0 multiple times,
		// > as long as there is still a row available.
		//
		// This was explained well in this StackOverflow post:
		// https://stackoverflow.com/questions/8319332/animating-nstableview-with-beginning-and-ending-array-states
		//
		// The original poster asked something about moving the following items around in a tableView:
		//
		// > [A,B,C,D] --> [B,C,D,A]
		//
		// And the answer was:
		//
		// > The documentation for moveRowAtIndex:toIndex: says,
		// > "Changes happen incrementally as they are sent to the table".
		// >
		// > The significance of 'incrementally' can be best illustrated with the transformation from ABCDE to ECDAB.
		// >
		// > If you just consider the initial and final indexes, it looks like:
		// >
		// > E: 4->0
		// > C: 2->1
		// > D: 3->2
		// > A: 0->3
		// > B: 1->4
		// >
		// > However, when performing the changes incrementally the 'initial' indexes can jump
		// > around as you transform your array:
		// >
		// > E: 4->0 (array is now EABCD)
		// > C: 3->1 (array is now ECABD)
		// > D: 4->2 (array is now ECDAB)
		// > A: 3->3 (array unchanged)
		// > B: 4->4 (array unchanged)
		// >
		// > Basically, you need to tell the NSTableView, step-by-step,
		// > which rows need to be moved in order to arrive at an array identical to your sorted array.
		
		NSMutableOrderedSet *incremental = [tableViewUpdate_oldIdentifiers mutableCopy];
		NSUInteger incIdx = 0;
		
		NSUInteger newIdx = 0;
		const NSUInteger newCount = tableViewUpdate_newIdentifiers.count;
		
		[_tblActivity beginUpdates];
		
		while ((incIdx < incremental.count) || (newIdx < newCount))
		{
			NSString *incIdentifier = nil;
			NSString *newIdentifier = nil;
			
			if (incIdx < incremental.count) {
				incIdentifier = incremental[incIdx];
			}
			if (newIdx < newCount) {
				newIdentifier = tableViewUpdate_newIdentifiers[newIdx];
			}
			
			if (incIdentifier)
			{
				if (newIdentifier)
				{
					// Multiple things to check here:
					// - was incIdentifier deleted ?
					// - was newIdentifier added ?
					// - was some oldIdentifer moved FORWARD ?
					
					if ([incIdentifier isEqualToString:newIdentifier])
					{
						incIdx++;
						newIdx++;
					}
					else if (![tableViewUpdate_newIdentifiers containsObject:incIdentifier])
					{
						NSIndexPath *indexPath = [NSIndexPath indexPathForRow:incIdx inSection:0];
						UITableViewRowAnimation opts = UITableViewRowAnimationBottom;
						
						[_tblActivity deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:opts];
						[incremental removeObjectAtIndex:incIdx];
					}
					else if (![incremental containsObject:newIdentifier])
					{
						NSIndexPath *indexPath = [NSIndexPath indexPathForRow:incIdx inSection:0];
						UITableViewRowAnimation opts = UITableViewRowAnimationBottom;
						
						[_tblActivity insertRowsAtIndexPaths:@[indexPath] withRowAnimation:opts];
						[incremental insertObject:newIdentifier atIndex:incIdx];
						
						incIdx++;
						newIdx++;
					}
					else
					{
						// Item exists in both old & new states.
						// But it's position has been moved.
						
						NSUInteger prvIncIdx = [incremental indexOfObject:newIdentifier];
						NSUInteger newIncIdx = incIdx;
						
						NSAssert(prvIncIdx != newIncIdx, @"Logic error");
						
						NSIndexPath *prvIdxPath = [NSIndexPath indexPathForRow:prvIncIdx inSection:0];
						NSIndexPath *newIdxPath = [NSIndexPath indexPathForRow:newIncIdx inSection:0];
						
						[_tblActivity moveRowAtIndexPath:prvIdxPath toIndexPath:newIdxPath];
						[incremental moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:prvIncIdx] toIndex:newIncIdx];
						
						incIdx++;
						newIdx++;
					}
				}
				else
				{
					// Only thing we have to check here:
					// - was oldIdentifier deleted ?
					
					if (![tableViewUpdate_newIdentifiers containsObject:incIdentifier])
					{
						NSIndexPath *indexPath = [NSIndexPath indexPathForRow:incIdx inSection:0];
						UITableViewRowAnimation opts = UITableViewRowAnimationBottom;
						
						[_tblActivity deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:opts];
						[incremental removeObjectAtIndex:incIdx];
					}
				}
			}
			else if (newIdentifier)
			{
				// Only thing we have to check here:
				// - was newIdentifier added ?
				
				if (![incremental containsObject:newIdentifier])
				{
					NSIndexPath *indexPath = [NSIndexPath indexPathForRow:incIdx inSection:0];
					UITableViewRowAnimation opts = UITableViewRowAnimationBottom;
					
					[_tblActivity insertRowsAtIndexPaths:@[indexPath] withRowAnimation:opts];
					[incremental insertObject:newIdentifier atIndex:incIdx];
					
					incIdx++;
					newIdx++;
				}
			}
		}
		
		NSAssert([incremental isEqual:tableViewUpdate_newIdentifiers], @"Logic error");
		
		[_tblActivity endUpdates];
	}
	
	// Step 3 of 3:
	//
	// Re-select the row(s) that were previously selected (if they still exist)
	
	NSUInteger rowIdx = 0;
	for (NSString *identifier in tableViewUpdate_newIdentifiers)
	{
		if ([tableViewUpdate_oldSelectedIdentifiers containsObject:identifier])
		{
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:rowIdx inSection:0];
			
			[_tblActivity selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
		}
		rowIdx++;
	}
}

@end
