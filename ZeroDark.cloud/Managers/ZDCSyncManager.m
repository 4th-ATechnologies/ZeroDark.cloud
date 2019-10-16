/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCSyncManagerPrivate.h"

#import "ZDCLogging.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSDate+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelInfo;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

/* extern */ NSString *const ZDCPullStartedNotification = @"ZDCPullStartedNotification";
/* extern */ NSString *const ZDCPullStoppedNotification = @"ZDCPullStoppedNotification";

/* extern */ NSString *const ZDCPushStartedNotification = @"ZDCPushStartedNotification";
/* extern */ NSString *const ZDCPushStoppedNotification = @"ZDCPushStoppedNotification";

/* extern */ NSString *const ZDCSyncingNodeIDsChangedNotification = @"ZDCSyncingNodeIDsChangedNotification";

/* extern */ NSString *const kLocalUserIDKey = @"localUserID";
/* extern */ NSString *const kAppIDKey       = @"appID";
/* extern */ NSString *const kPullResultKey  = @"result";

static NSTimeInterval const ZDCDefaultPullInterval = 60 * 15; // 15 minutes (in the absence of push notifications)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCLocalUserSyncState : NSObject

- (instancetype)initWithLocalUserID:(NSString *)localUserID;

@property (nonatomic, copy, readonly) NSString *localUserID;

@property (nonatomic, strong, readwrite) ZDCCloud *cloudExt;

@property (nonatomic, assign, readwrite) BOOL isEnabled;
@property (nonatomic, assign, readwrite) BOOL isPushingPaused;

@property (nonatomic, assign, readwrite) BOOL isPulling;            // S4PullManager activated for user
@property (nonatomic, assign, readwrite) BOOL isPullingWithChanges; // S4PullManager actually found changes to pull

@property (nonatomic, assign, readwrite) BOOL isPushing;
@property (nonatomic, assign, readwrite) BOOL isPushingSuspended; // the suspend/resume we're responsible for

@property (nonatomic, assign, readwrite) BOOL lastPullFailed;
@property (nonatomic, strong, readwrite) NSDate *lastPullSuccess;
@property (nonatomic, assign, readwrite) NSUInteger pullInterruptedFailCount;

@property (nonatomic, strong, readwrite) dispatch_source_t timer;
@property (nonatomic, assign, readwrite) BOOL timerSuspended;

@property (nonatomic, strong, readwrite) NSSet<NSString *> *syncingNodeIDs;

@end

@implementation ZDCLocalUserSyncState

@synthesize localUserID = localUserID;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
{
	if ((self = [super init]))
	{
		localUserID = [inLocalUserID copy];
		
		self.isPushingSuspended = YES; // to match initial suspend in DatabaseManager
	}
	return self;
}

- (void)dealloc
{
	// Deallocating a suspended timer will cause a crash
	if (self.timer && self.timerSuspended)
	{
		dispatch_resume(self.timer);
		self.timerSuspended = NO;
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCSyncManager
{
	__weak ZeroDarkCloud *zdc;
	
	dispatch_queue_t queue;
	void *IsOnQueueKey;
	
	BOOL hasInternet;
	NSMutableDictionary<NSString *, ZDCLocalUserSyncState *> *syncStates;
	
	ZDCAsyncCompletionDispatch *pendingPulls;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.localUserManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		queue = dispatch_queue_create("ZDCSyncManager", DISPATCH_QUEUE_SERIAL);
		
		IsOnQueueKey = &IsOnQueueKey;
		dispatch_queue_set_specific(queue, IsOnQueueKey, IsOnQueueKey, NULL);
		
		hasInternet = zdc.reachability.isReachable;
		syncStates = [[NSMutableDictionary alloc] init];
		
		pendingPulls = [[ZDCAsyncCompletionDispatch alloc] init];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(reachabilityChanged:)
		                                             name: AFNetworkingReachabilityDidChangeNotification
		                                           object: nil /* notification doesn't assign object ! */];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(databaseConnectionDidUpdate:)
		                                             name: YapDatabaseModifiedNotification
		                                           object: nil];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(pipelineActiveStatusChanged:)
																	name: YDBCloudCorePipelineActiveStatusChangedNotification
		                                           object: nil];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(pipelineQueueChanged:)
																	name: YDBCloudCorePipelineQueueChangedNotification
		                                           object: nil];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(progressListChanged:)
		                                             name: ZDCProgressListChangedNotification
		                                           object: nil];
		
	#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(applicationDidBecomeActive:)
		                                             name: UIApplicationDidBecomeActiveNotification
		                                           object: nil];
	#endif
		
		[self refreshLocalUsers];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSTimeInterval)exponentialBackoffForFailCount:(NSUInteger)failCount
{
	// Note: NSTimeInterval is in seconds
	
	switch (failCount)
	{
		case 0 : return  0.0;
		case 1 : return  1.0;
		case 2 : return  2.0;
		case 3 : return  4.0;
		case 4 : return  8.0;
		case 5 : return 16.0;
		case 6 : return 32.0;
		default: return 60.0;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications - Incoming
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoked (directly) by PullManager.
 */
- (void)notifyPullStartedForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(treeID != nil);
	
	// Update ZDCLocalUserSyncState accordingly
	//
	// Note:
	//   We need this in case the PullManager gets started by a process other than ourselves.
	//   For example, the PushManager forces it to run.
	
	if ([treeID isEqualToString:zdc.primaryTreeID])
	{
		dispatch_block_t block = ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
			ZDCLocalUserSyncState *syncState = syncStates[localUserID];
			if (syncState)
			{
				syncState.isPulling = YES;
			}
			
		#pragma clang diagnostic pop
		}};
	
		if (dispatch_get_specific(IsOnQueueKey))
			block();
		else
			dispatch_sync(queue, block);
	}
	
	// We do NOT post the public ZDCPullStartedNotification here.
	// That notification isn't posted unless we DISCOVER CHANGES that need to be pulled from the cloud.
}

/**
 * Invoked (directly) by PullManager.
 */
- (void)notifyPullFoundChangesForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(treeID != nil);
	
	// Update ZDCLocalUserSyncState accordingly
	//
	// Note:
	//   We need this in case the PullManager gets started by a process other than ourselves.
	//   For example, the PushManager forces it to run.
	
	if ([treeID isEqualToString:zdc.primaryTreeID])
	{
		dispatch_block_t block = ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
			ZDCLocalUserSyncState *syncState = syncStates[localUserID];
			if (syncState)
			{
				syncState.isPullingWithChanges = YES;
			}
			
		#pragma clang diagnostic pop
		}};
		
		if (dispatch_get_specific(IsOnQueueKey))
			block();
		else
			dispatch_sync(queue, block);
	}
	
	// Now that we've updated our internal state,
	// we're safe to rebroadcast the notification to the UI.
	//
	[self postPullStartedNotificationForLocalUserID:localUserID treeID:treeID];
}

/**
 * Invoked (directly) by PullManager.
 */
- (void)notifyPullStoppedForLocalUserID:(NSString *)localUserID
                                 treeID:(NSString *)treeID
                             withResult:(ZDCPullResult)result
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(treeID != nil);
	
	BOOL isRegisteredTreeID = [treeID isEqualToString:zdc.primaryTreeID];
	
	// Update ZDCLocalUserSyncState accordingly
	
	__block BOOL wasPullingWithChanges = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState)
		{
			wasPullingWithChanges = syncState.isPullingWithChanges;
			
			syncState.isPulling = NO;
			syncState.isPullingWithChanges = NO;
			
			if (result == ZDCPullResult_Success)
			{
				syncState.lastPullFailed = NO;
				syncState.lastPullSuccess = [NSDate date];
				syncState.pullInterruptedFailCount = 0;
				
				NSTimeInterval delay = ZDCDefaultPullInterval;
				NSDate *nextPull = [syncState.lastPullSuccess dateByAddingTimeInterval:delay];
				
				[self updateTimerForSyncState:syncState withNextPull:nextPull];
				
				if (syncState.isPushingSuspended && syncState.isEnabled && hasInternet)
				{
					[syncState.cloudExt resume];
					syncState.isPushingSuspended = NO;
				}
			}
			else if (hasInternet)
			{
				if (result == ZDCPullResult_Fail_CloudChanged)
				{
					// Pull was interrupted by another client modifying the cloud.
					// Retry again after a short delay.
					
					syncState.lastPullFailed = YES;
					syncState.pullInterruptedFailCount++;
					
					NSTimeInterval delay = [self exponentialBackoffForFailCount:syncState.pullInterruptedFailCount];
					NSDate *nextRetry = [[NSDate date] dateByAddingTimeInterval:delay];
					
					[self updateTimerForSyncState:syncState withNextPull:nextRetry];
				}
				else if (result == ZDCPullResult_Fail_Other)
				{
					// Pull failed for some other reason.
					// Retry again after a longer delay.
					
					syncState.lastPullFailed = YES;
					syncState.pullInterruptedFailCount = 0;
					
					NSTimeInterval delay = 60; // seconds
					NSDate *nextRetry = [[NSDate date] dateByAddingTimeInterval:delay];
					
					[self updateTimerForSyncState:syncState withNextPull:nextRetry];
				}
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (isRegisteredTreeID)
	{
		if (dispatch_get_specific(IsOnQueueKey))
			block();
		else
			dispatch_sync(queue, block);
	}
	
	// Handle pending completionBlocks (from processPushNotification:::)
	
	if (isRegisteredTreeID)
	{
		NSArray *completionQueues = nil;
		NSArray *completionBlocks = nil;
		
		[pendingPulls popCompletionQueues: &completionQueues
		                 completionBlocks: &completionBlocks
		                           forKey: localUserID];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCPullResult) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock(result);
			}});
		}
	}
	
	// Now that we've updated our internal state,
	// we're safe to rebroadcast the notification to the UI.
	//
	BOOL shouldPostNotification = YES;
	if (isRegisteredTreeID) {
		shouldPostNotification = wasPullingWithChanges;
	}
	if (shouldPostNotification) {
		[self postPullStoppedNotificationForLocalUserID:localUserID treeID:treeID result:result];
	}
}

/**
 * Invoked when the reachability changes.
 * That is, when the circumstances of our Internet access has changed.
 */
- (void)reachabilityChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusUnknown;
	
	NSNumber *statusNum = notification.userInfo[AFNetworkingReachabilityNotificationStatusItem];
	if (statusNum) {
		status = (AFNetworkReachabilityStatus)[statusNum integerValue];
	}
	
	BOOL newHasInternet = (status > AFNetworkReachabilityStatusNotReachable);
	
	__weak typeof(self) weakSelf = self;
	
	// Note: the 'hasInternet' variable is only safe to access/modify within the 'queue'.
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		if (!strongSelf->hasInternet && newHasInternet)
		{
			strongSelf->hasInternet = YES;
			[strongSelf pullChangesForAllEnabledUsersIfNeeded];
		}
		else if (strongSelf->hasInternet && !newHasInternet)
		{
			strongSelf->hasInternet = NO;
			[strongSelf abortPullAndSuspendPushForAllUsers];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block);
}

/**
 * Invoked for every commit made to the database.
 * This method is invoked on the main thread.
 */
- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	NSArray *notifications = @[notification];
	
	// We're on the main thread.
	YapDatabaseConnection *uiDatabaseConnection = [zdc.databaseManager uiDatabaseConnection];
	
	BOOL localUserChanged = [[uiDatabaseConnection ext:Ext_View_LocalUsers] hasChangesForNotifications:notifications];
	if (localUserChanged)
	{
		[self refreshLocalUsers];
	}
}

- (void)pipelineActiveStatusChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	YapDatabaseCloudCorePipeline *sender_pipeline = (YapDatabaseCloudCorePipeline *)notification.object;
	YapDatabaseCloudCore *sender_cloudCore = sender_pipeline.owner;
	
	if (![sender_cloudCore isKindOfClass:[ZDCCloud class]])
	{
		return;
	}
	
	ZDCCloud *sender_cloudExt = (ZDCCloud *)sender_cloudCore;
	
	if (![sender_cloudExt.treeID isEqualToString:zdc.primaryTreeID])
	{
		return;
	}
	
	NSString *localUserID = sender_cloudExt.localUserID;
	
	BOOL newIsPushing = [notification.userInfo[@"isActive"] boolValue];
	
	__block BOOL found = NO;
	__block BOOL oldIsPushing = newIsPushing;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		__block ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState && (syncState.cloudExt == sender_cloudExt))
		{
			found = YES;
			
			oldIsPushing = syncState.isPushing;
			syncState.isPushing = newIsPushing;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	if (found && (oldIsPushing != newIsPushing))
	{
		if (newIsPushing)
			[self postPushStartedNotification:localUserID];
		else
			[self postPushStoppedNotification:localUserID];
	}
}

- (void)pipelineQueueChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	YapDatabaseCloudCorePipeline *sender_pipeline = (YapDatabaseCloudCorePipeline *)notification.object;
	YapDatabaseCloudCore *sender_cloudCore = sender_pipeline.owner;
	
	if (![sender_cloudCore isKindOfClass:[ZDCCloud class]])
	{
		return;
	}
	
	ZDCCloud *sender_cloudExt = (ZDCCloud *)sender_cloudCore;
	
	if (![sender_cloudExt.treeID isEqualToString:zdc.primaryTreeID])
	{
		return;
	}
	
	NSString *localUserID = sender_cloudExt.localUserID;
	[self refreshSyncingNodeIDsForLocalUserID:localUserID];
}

- (void)progressListChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	ZDCProgressManagerChanges *changes = notification.userInfo[kZDCProgressManagerChanges];
	
	[self refreshSyncingNodeIDsForLocalUserID:changes.localUserID];
}

#if TARGET_OS_IPHONE
/**
 * Invoked on iOS when the app returns from the background.
 */
- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	// Note: the 'hasInternet' variable is only safe to access/modify within the 'queue'.
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		if (strongSelf->hasInternet)
		{
			[strongSelf pullChangesForAllEnabledUsersIfNeeded];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block);
}
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications - Outgoing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)postPullStartedNotificationForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(treeID != nil);
	
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kLocalUserIDKey : localUserID,
			kAppIDKey       : treeID
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCPullStartedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

- (void)postPullStoppedNotificationForLocalUserID:(NSString *)localUserID
                                           treeID:(NSString *)treeID
                                           result:(ZDCPullResult)pullResult
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(treeID != nil);
	
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kLocalUserIDKey : localUserID,
			kAppIDKey       : treeID,
			kPullResultKey  : @(pullResult)
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCPullStoppedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

- (void)postPushStartedNotification:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUserID != nil);
	
	NSString *const treeID = zdc.primaryTreeID;
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kLocalUserIDKey : localUserID,
			kAppIDKey       : treeID
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCPushStartedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

- (void)postPushStoppedNotification:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUserID != nil);
	
	NSString *const treeID = zdc.primaryTreeID;
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kLocalUserIDKey : localUserID,
			kAppIDKey       : treeID
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCPushStoppedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

- (void)postSyncingNodeIDsChangedNotification:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUserID != nil);
	
	NSString *const treeID = zdc.primaryTreeID;
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kLocalUserIDKey : localUserID,
			kAppIDKey       : treeID
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCSyncingNodeIDsChangedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called:
 * - when the database is unlocked (framework starts)
 * - when a ZDCLocalUser object is inserted, modified or removed from the database
 *
 * It enumerates the local users, and then invokes manageLocalUsers,
 * which handles performing the correct action for each local user.
 */
- (void)refreshLocalUsers
{
	ZDCLogAutoTrace();
	
	NSMutableDictionary<NSString *, ZDCLocalUser *> *localUsers = [NSMutableDictionary dictionaryWithCapacity:1];
	
	__weak typeof(self) weakSelf = self;
	
	YapDatabaseConnection *roConnection = zdc.databaseManager.roDatabaseConnection;
	[roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCLocalUserManager *localUserManager = strongSelf->zdc.localUserManager;
		
		[localUserManager enumerateLocalUsersWithTransaction: transaction
		                                          usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
		{
			// A localUser isn't really setup until it has a private key.
			// And we can't do any syncing stuff until we have the private key.
			//
			if (localUser.hasCompletedSetup)
			{
				localUsers[localUser.uuid] = localUser;
			}
		}];
		
	} completionQueue:queue completionBlock:^{
		
		[weakSelf manageLocalUsers:localUsers];
	}];
}

/**
 * Invoke this method with the complete list of localUser's.
 *
 * It will then:
 * - setup any users that weren't setup before
 * - teardown any users that have been removed from the set
 */
- (void)manageLocalUsers:(NSDictionary<NSString *, ZDCLocalUser *> *)inLocalUsers
{
	ZDCLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	NSString *treeID = zdc.primaryTreeID;
	
	for (ZDCLocalUser *localUser in [inLocalUsers objectEnumerator])
	{
		NSString *localUserID = localUser.uuid;
		BOOL isNewSyncState = NO;
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState == nil)
		{
			syncState = [[ZDCLocalUserSyncState alloc] initWithLocalUserID:localUserID];
			
			syncState.cloudExt = [zdc.databaseManager cloudExtForUserID:localUserID treeID:treeID];
			if (syncState.cloudExt == nil)
			{
				syncState.cloudExt = [zdc.databaseManager registerCloudExtensionForUserID:localUserID treeID:treeID];
			}
			
		//	YapDatabaseCloudCorePipeline *pipeline = [syncState.cloudExt defaultPipeline];
		//	pipeline.maxConcurrentOperationCount = [S4Preferences_si uploadConcurrencyForLocalUserID:localUserID];
			
			__weak typeof(self) weakSelf = self;
			syncState.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
			dispatch_source_set_event_handler(syncState.timer, ^{
				
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf) {
					[strongSelf pullChangesForLocalUserID:localUserID];
				}
			});
			
			syncState.timerSuspended = YES;
			
			[self refreshSyncingNodeIDsForLocalUserID:localUserID];
			
			syncStates[localUserID] = syncState;
			isNewSyncState = YES;
		}
		
		BOOL wasDisabled = syncState.isEnabled == NO;
		syncState.isEnabled = localUser.canPerformSync;
		
		if (isNewSyncState || (wasDisabled && syncState.isEnabled))
		{
			// Possibility #1:
			//
			//   A localUser was just added to the database.
			//   And so we need to register for push notifications right away.
			//
			// Possibility #2:
			//
			//   A localUser.canPerformSync flag just got changed from NO to YES
			//
			//   The method `registerPushTokenForLocalUsersIfNeeded` ignores users where
			//   `localUser.canPerformSync == NO`. So when that changes, we need to perform
			//   another check.
			//
			//   Here's an actual bug report from the field:
			//   - user A was disabled
			//   - macOS updated to a new version
			//   - user A was re-enabled
			//   - user A wasn't getting push notifications
			//
			//   Diagnosis:
			//   - push token changed with OS update
			//   - app launch ignored user A
			//   - re-enabling user A did not cause new push token to be registered with server
			//
			[zdc registerPushTokenForLocalUsersIfNeeded];
		}
		
		if (syncState.isEnabled)
		{
			if ((wasDisabled || isNewSyncState) && hasInternet)
			{
				if (!syncState.isPulling)
				{
					[zdc.pullManager pullRemoteChangesForLocalUserID:localUserID treeID:treeID];
					[self updateTimerForSyncState:syncState withNextPull:nil];
					syncState.isPulling = YES;
				}
			}
		}
		else // disabled
		{
			if (syncState.isPulling)
			{
				syncState.isPulling = NO;
				syncState.isPullingWithChanges = NO;
				
				[zdc.pullManager abortPullForLocalUserID:syncState.localUserID treeID:treeID];
			}
			
			if (!syncState.isPushingSuspended)
			{
				[syncState.cloudExt suspend];
				syncState.isPushingSuspended = YES;
				
				[zdc.pushManager abortOperationsForLocalUserID:localUserID treeID:treeID];
			}
		}
	}
	
	__block NSMutableArray<NSString *> *localUserIDsToDelete = nil;
	
	[syncStates enumerateKeysAndObjectsUsingBlock:
	^(NSString *localUserID, ZDCLocalUserSyncState *syncState, BOOL *stop) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (inLocalUsers[localUserID] == nil)
		{
			// This user has been deleted.
			// So we have to abort everything, and clean the database.
			
			if (syncState.isPulling)
			{
				syncState.isPulling = NO;
				syncState.isPullingWithChanges = NO;
				
				[zdc.pullManager abortPullForLocalUserID:localUserID treeID:zdc.primaryTreeID];
			}

			if (!syncState.isPushingSuspended)
			{
				[syncState.cloudExt suspend];
				syncState.isPushingSuspended = YES;
				
				[zdc.pushManager abortOperationsForLocalUserID:localUserID treeID:treeID];
			}
			
			[zdc.databaseManager unregisterCloudExtensionForUserID:localUserID treeID:treeID];
			
			if (localUserIDsToDelete == nil)
				localUserIDsToDelete = [NSMutableArray arrayWithCapacity:1];
			
			[localUserIDsToDelete addObject:localUserID];
		}
		
	#pragma clang diagnostic pop
	}];
	
	if (localUserIDsToDelete)
	{
		[syncStates removeObjectsForKeys:localUserIDsToDelete];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Starts a pull for every enabled user.
 * Use this when a network re-connection is detected (or iOS app returns from background).
 */
- (void)pullChangesForAllEnabledUsersIfNeeded
{
	ZDCLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	NSDate *now = [NSDate date];
	
	[syncStates enumerateKeysAndObjectsUsingBlock:
	^(NSString *localUserID, ZDCLocalUserSyncState *syncState, BOOL *stop) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (!syncState.isPulling && syncState.isEnabled)
		{
			BOOL needsPull = NO;
			if (syncState.lastPullSuccess == nil)
			{
				needsPull = YES;
			}
			else
			{
				NSTimeInterval pullInterval = ZDCDefaultPullInterval;
				NSDate *nextPull = [syncState.lastPullSuccess dateByAddingTimeInterval:pullInterval];
				
				needsPull = [nextPull isBeforeOrEqual:now];
			}
			
			if (needsPull)
			{
				[zdc.pullManager pullRemoteChangesForLocalUserID:localUserID treeID:zdc.primaryTreeID];
				[self updateTimerForSyncState:syncState withNextPull:nil];
				syncState.isPulling = YES;
			}
			else
			{
				if (syncState.isPushingSuspended && hasInternet)
				{
					[syncState.cloudExt resume];
					syncState.isPushingSuspended = NO;
				}
			}
		}
		
	#pragma clang diagnostic pop
	}];
}

/**
 * Cancels all network activity for the localUsers.
 * Use this when a network disconnection is detected.
**/
- (void)abortPullAndSuspendPushForAllUsers
{
	ZDCLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	NSString *const treeID = zdc.primaryTreeID;
	
	[syncStates enumerateKeysAndObjectsUsingBlock:
	^(NSString *localUserID, ZDCLocalUserSyncState *syncState, BOOL *stop) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (syncState.isPulling)
		{
			syncState.isPulling = NO;
			syncState.isPullingWithChanges = NO;
			
			[zdc.pullManager abortPullForLocalUserID:localUserID treeID:treeID];
		}
		
		if (!syncState.isPushingSuspended)
		{
			[syncState.cloudExt suspend];
			syncState.isPushingSuspended = YES;
		}
		
	#pragma clang diagnostic pop
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Timer Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateTimerForAllUsers
{
	ZDCLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	[syncStates enumerateKeysAndObjectsUsingBlock:
		^(NSString *localUserID, ZDCLocalUserSyncState *syncState, BOOL *stop)
	{
		if (!syncState.lastPullFailed && syncState.isEnabled)
		{
			NSTimeInterval delay = ZDCDefaultPullInterval;
			NSDate *nextPull = [syncState.lastPullSuccess dateByAddingTimeInterval:delay];
			
			[self updateTimerForSyncState:syncState withNextPull:nextPull];
		}
	}];
}

- (void)updateTimerForLocalUserID:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	ZDCLocalUserSyncState *syncState = syncStates[localUserID];
	if (syncState)
	{
		if (!syncState.lastPullFailed && syncState.isEnabled)
		{
			NSTimeInterval delay = ZDCDefaultPullInterval;
			NSDate *nextPull = [syncState.lastPullSuccess dateByAddingTimeInterval:delay];
			
			[self updateTimerForSyncState:syncState withNextPull:nextPull];
		}
	}
}

- (void)updateTimerForSyncState:(ZDCLocalUserSyncState *)syncState withNextPull:(NSDate *)nextPull
{
	ZDCLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	if (nextPull)
	{
		NSTimeInterval startOffset = [nextPull timeIntervalSinceNow];
		if (startOffset < 0.0)
			startOffset = 0.0;
		
		dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (startOffset * NSEC_PER_SEC));
		
		uint64_t interval = DISPATCH_TIME_FOREVER;
		uint64_t leeway = (0.1 * NSEC_PER_SEC);
		
		dispatch_source_set_timer(syncState.timer, start, interval, leeway);
		
		if (syncState.timerSuspended) {
			dispatch_resume(syncState.timer);
			syncState.timerSuspended = NO;
		}
	}
	else
	{
		if (!syncState.timerSuspended) {
			dispatch_suspend(syncState.timer);
			syncState.timerSuspended = YES;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Manual Pull
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)pullChangesForLocalUserID:(NSString *)localUserID
{
	if (localUserID == nil) return;
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCLocalUserSyncState *syncState = strongSelf->syncStates[localUserID];
		if (syncState)
		{
			[strongSelf _pullChanges:syncState];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);// <-- ASYNC
}

/**
 * See header file for description.
 */
- (void)pullChangesForAllLocalUsers
{
	ZDCLogAutoTrace();
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		for (ZDCLocalUserSyncState *syncState in [strongSelf->syncStates objectEnumerator])
		{
			[strongSelf _pullChanges:syncState];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // <-- ASYNC
}

- (void)_pullChanges:(ZDCLocalUserSyncState *)syncState
{
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	if (syncState.isEnabled && hasInternet)
	{
		if (!syncState.isPulling)
		{
			[zdc.pullManager pullRemoteChangesForLocalUserID:syncState.localUserID treeID:zdc.primaryTreeID];
			[self updateTimerForSyncState:syncState withNextPull:nil];
			syncState.isPulling = YES;
		}
	}
}

- (void)enqueuePullCompletionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(ZDCPullResult))completionBlock
                    forLocalUserID:(NSString *)localUserID
{
	[pendingPulls pushCompletionQueue: completionQueue
	                  completionBlock: completionBlock
	                           forKey: localUserID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pause & Resume Push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)pausePushForLocalUserID:(NSString *)localUserID andAbortUploads:(BOOL)shouldAbortUploads
{
	ZDCLogAutoTrace();
	
	if (localUserID == nil) return;
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCLocalUserSyncState *syncState = strongSelf->syncStates[localUserID];
		if (syncState)
		{
			[strongSelf _pausePush:syncState andAbortUploads:shouldAbortUploads];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // <-- ASYNC
}

/**
 * See header file for description.
 */
- (void)pausePushForAllLocalUsersAndAbortUploads:(BOOL)shouldAbortUploads
{
	ZDCLogAutoTrace();
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		for (ZDCLocalUserSyncState *syncState in strongSelf->syncStates)
		{
			[strongSelf _pausePush:syncState andAbortUploads:shouldAbortUploads];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // <-- ASYNC
}

- (void)_pausePush:(ZDCLocalUserSyncState *)syncState andAbortUploads:(BOOL)shouldAbortUploads
{
	if (!syncState.isPushingPaused)
	{
		syncState.isPushingPaused = YES;
		[syncState.cloudExt suspend];
		//	syncState.isPushingSuspended = YES; // <-- NO ! We must NOT do this here
		// ^^ No, that's wrong ^^
		//
		//	Here's the deal:
		// There are 2 SEPARATE ways that pushing can be suspended:
		// 1.) It's done manually by the end user (e.g. they clicked "pause uploads" in activity monitor)
		// 2.) It's done automatically by this class due to things like Internet availability
		//
		// Now recall that YDBCloudCorePipeline uses a suspend/resume count (think: retainCount).
		// This allows us to keep these 2 things completely separate.
		//
		// Therefore:
		//
		// - toggling `isPushingPaused` is connected with incrementing/decrementing the suspendCount,
		//   AND is controlled by the end user (e.g. via the activity monitor)
		//
		// - toggling `isPushingSuspended` is connected with incrementing/decremented the suspendCount,
		//   AND is conrolled by this class (e.g. due to Internet reachability change)
		//
		// By keeping these separate it becomes easier to ensure we only push
		// when ALL the conditions are properly met to allow it.
	}
	
	if (shouldAbortUploads)
	{
		[zdc.pushManager abortOperationsForLocalUserID: syncState.localUserID
		                                        treeID: zdc.primaryTreeID];
	}
}

/**
 * See header file for description.
 */
- (void)resumePushForLocalUserID:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	if (localUserID == nil) return;
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCLocalUserSyncState *syncState = strongSelf->syncStates[localUserID];
		if (syncState)
		{
			[strongSelf _resumePush:syncState];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // <-- ASYNC
}

/**
 * See header file for description.
 */
- (void)resumePushForAllLocalUsers
{
	ZDCLogAutoTrace();
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		for (ZDCLocalUserSyncState *syncState in [strongSelf->syncStates objectEnumerator])
		{
			[strongSelf _resumePush:syncState];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // <-- ASYNC
}

- (void)_resumePush:(ZDCLocalUserSyncState *)syncState
{
	if (syncState.isPushingPaused)
	{
		syncState.isPushingPaused = NO;
		[syncState.cloudExt resume];
		//	syncState.isPushingSuspended = NO; // <-- NO ! We must NOT do this here
		//	^^ No, that's wrong ^^
		//
		//	Here's the deal:
		// There are 2 SEPARATE ways that pushing can be suspended:
		// 1.) It's done manually by the end user (e.g. they clicked "pause uploads" in activity monitor)
		// 2.) It's done automatically by this class due to things like Internet availability
		//
		// Now recall that YDBCloudCorePipeline uses a suspend/resume count (think: retainCount).
		// This allows us to keep these 2 things completely separate.
		//
		// Therefore:
		//
		// - toggling `isPushingPaused` is connected with incrementing/decrementing the suspendCount,
		//   AND is controlled by the end user (e.g. via the activity monitor)
		//
		// - toggling `isPushingSuspended` is connected with incrementing/decremented the suspendCount,
		//   AND is conrolled by this class (e.g. due to Internet reachability change)
		//
		// By keeping these separate it becomes easier to ensure we only push
		// when ALL the conditions are properly met to allow it.
	}
}

/**
 * See header file for description.
 */
- (BOOL)isPushingPausedForLocalUserID:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	if (localUserID == nil) return NO;
	
	__block BOOL result = NO;
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState)
		{
			result = syncState.isPushingPaused;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)isPushingPausedForAllUsers
{
	ZDCLogAutoTrace();
	
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (syncStates.count > 0)
		{
			BOOL foundNonPausedUser = NO;
			
			for (ZDCLocalUserSyncState *syncState in [syncStates objectEnumerator])
			{
				if (!syncState.isPushingPaused)
				{
					foundNonPausedUser = YES;
					break;
				}
			}
		
			result = (foundNonPausedUser == NO);
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)isPushingPausedForAnyUser
{
	ZDCLogAutoTrace();
	
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (ZDCLocalUserSyncState *syncState in [syncStates objectEnumerator])
		{
			if (syncState.isPushingPaused)
			{
				result = YES;
				break;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Activity State
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (BOOL)isPullingChangesForLocalUserID:(NSString *)localUserID
{
	if (localUserID == nil) return NO;
	
	__block BOOL isPulling = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState)
		{
			isPulling = (syncState.isPulling && syncState.isPullingWithChanges);
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return isPulling;
}

/**
 * See header file for description.
 */
- (BOOL)isPushingChangesForLocalUserID:(NSString *)localUserID
{
	if (localUserID == nil) return NO;
	
	__block BOOL isPushing = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState)
		{
			isPushing = syncState.isPushing;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return isPushing;
}

/**
 * See header file for description.
 */
- (BOOL)isPullingOrPushingChangesForLocalUserID:(NSString *)localUserID
{
	if (localUserID == nil) return NO;
	
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState)
		{
			result = (syncState.isPulling && syncState.isPullingWithChanges) || syncState.isPushing;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)isPullingOrPushingChangesForAnyLocalUser
{
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (ZDCLocalUserSyncState *syncState in [syncStates objectEnumerator])
		{
			if ((syncState.isPulling && syncState.isPullingWithChanges) || syncState.isPushing)
			{
				result = YES;
				break;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node State
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (NSSet<NSString *> *)syncingNodeIDsForLocalUserID:(NSString *)localUserID
{
	__block NSSet<NSString *> *result = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCLocalUserSyncState *syncState = syncStates[localUserID];
		if (syncState)
		{
			result = syncState.syncingNodeIDs;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

/**
 * Internal method that actually performs the calculation.
 * External classes should use the method above, which uses a recent cached calculation.
 */
- (NSSet<NSString *> *)syncingNodeIDsForLocalUserID:(NSString *)localUserID
                                        transaction:(YapDatabaseReadTransaction *)transaction
{
	NSMutableSet<NSString *> *active_nodeIDs = [NSMutableSet set];
	
	// Grab all nodeIDs being pushed (or scheduled to be pushed)
	
	YapDatabaseCloudCore *ext = [zdc.databaseManager cloudExtForUserID:localUserID];
	YapDatabaseCloudCorePipeline *pipeline = [ext defaultPipeline];
	
	[pipeline enumerateOperationsUsingBlock:
		^(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
		
		NSString *nodeID = op.nodeID;
		if (nodeID)
		{
			// Ignore any operations that have been marked as completed or skipped.
			// This happens due to various optimizations.
			
			YDBCloudCoreOperationStatus status = [pipeline statusForOperationWithUUID:operation.uuid];
			
			if (status != YDBCloudOperationStatus_Completed && status != YDBCloudOperationStatus_Skipped)
			{
				[active_nodeIDs addObject:nodeID];
			}
		}
	}];
	
	// Grab all nodeIDs being pulled.
	//
	// ...
	// Todo: we need a way to track this information !
	// ...
	
	// Grab all nodeIDs being downloaded.
	
	NSSet<NSString *> *download_nodeIDs = [zdc.progressManager allDownloadingNodeIDs:localUserID];
	
	[active_nodeIDs unionSet:download_nodeIDs];
	
	// Add all parent nodes
	
	NSMutableSet<NSString *> *all_nodeIDs = [NSMutableSet set];
	
	for (NSString *nodeID in active_nodeIDs)
	{
		NSString *currentNodeID = nodeID;
		do {
			
			if ([all_nodeIDs containsObject:currentNodeID])
				break;
			else
				[all_nodeIDs addObject:currentNodeID];
			
			ZDCNode *currentNode = [transaction objectForKey:currentNodeID inCollection:kZDCCollection_Nodes];
			currentNodeID = currentNode.parentID;
			
		} while (currentNodeID != nil);
	}
	
	return all_nodeIDs;
}

- (void)refreshSyncingNodeIDsForLocalUserID:(NSString *)localUserID
{
	ZDCLogAutoTrace();
	
	if (localUserID == nil) return;
	
	__block NSSet<NSString *> *newSyncingNodeIDs = nil;
	
	__weak typeof(self) weakSelf = self;
	[zdc.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		newSyncingNodeIDs = [self syncingNodeIDsForLocalUserID:localUserID transaction:transaction];
		
	} completionQueue:queue completionBlock:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCLocalUserSyncState *syncState = strongSelf->syncStates[localUserID];
		if (syncState)
		{
			NSSet<NSString *> *oldSyncingNodeIDs = syncState.syncingNodeIDs;
			
			if (!oldSyncingNodeIDs || ![oldSyncingNodeIDs isEqualToSet:newSyncingNodeIDs])
			{
				syncState.syncingNodeIDs = newSyncingNodeIDs;
				
				[strongSelf postSyncingNodeIDsChangedNotification:localUserID];
			}
		}
	}];
}

@end
