#import "ZDCSessionManager.h"

#import "S3ResponseSerialization.h"
#import "ZDCConstants.h"
#import "ZDCDatabaseManagerPrivate.h"
#import "ZDCDirectoryManager.h"
#import "ZDCDownloadContext.h"
#import "ZDCDownloadManagerPrivate.h"
#import "ZDCLocalUser.h"
#import "ZDCLogging.h"
#import "ZDCPushManagerPrivate.h"
#import "ZDCSessionInfo.h"
#import "ZDCSessionUserInfo.h"
#import "ZDCTaskContext.h"
#import "ZeroDarkCloudPrivate.h"

#import <YapDatabase/YapDatabase.h>

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelWarning | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

static NSString *const kSessionDescriptionPrefix_Background = @"bg";
static NSString *const kSessionDescriptionPrefix_Foreground = @"fg";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IPHONE

@interface ZDCSessionPendingItem : NSObject

@property (nonatomic, strong, readwrite) NSURLSessionTask *task;

@property (nonatomic, strong, readwrite) NSURL *downloadedFileURL;

@property (nonatomic, assign, readwrite) BOOL isComplete;
@property (nonatomic, strong, readwrite) NSError *error;

@end

@implementation ZDCSessionPendingItem

@end

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCSessionStorageItem : NSObject

@property (nonatomic, strong, readwrite) ZDCObject *context;
@property (nonatomic, assign, readwrite) BOOL contextIsSaved;

@property (nonatomic, strong, readwrite) NSInputStream *stream;
@property (nonatomic, assign, readwrite) BOOL streamUsedOnce;

@property (nonatomic, strong, readwrite) NSURL *downloadedFileURL;
@property (nonatomic, strong, readwrite) NSMutableData *downloadedData;

@end

@implementation ZDCSessionStorageItem

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCSessionManager
{
	__weak ZeroDarkCloud *zdc;
	
	YapDatabaseConnection *internal_roConnection;
	
	dispatch_queue_t queue;
	void *IsOnQueueKey;
	
	NSMutableDictionary<NSString *, ZDCSessionInfo *> * sessionDict;
	NSMutableDictionary<NSString *, ZDCSessionInfo *> * staleSessionDict;
	
	NSMutableDictionary<NSString *, ZDCSessionStorageItem *> *storage;

#if TARGET_OS_IPHONE
	BOOL isReadyForStorage;
	NSMutableSet *localUserIDsPendingRestore;
	
	NSMutableDictionary<NSString *, NSMutableDictionary *> *pending;
#endif
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self" // Singleton class - never deallocated

- (instancetype)init
{
	return nil; // You need to use: [[Sync4 sharedInstance] sessionManager];
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		queue = dispatch_queue_create("SessionManager", DISPATCH_QUEUE_SERIAL);
		
		IsOnQueueKey = &IsOnQueueKey;
		dispatch_queue_set_specific(queue, IsOnQueueKey, IsOnQueueKey, NULL);
		
		sessionDict      = [[NSMutableDictionary alloc] initWithCapacity:2];
		staleSessionDict = [[NSMutableDictionary alloc] initWithCapacity:2];
		
		storage = [[NSMutableDictionary alloc] initWithCapacity:16];
	#if TARGET_OS_IPHONE
		pending = [[NSMutableDictionary alloc] initWithCapacity:4];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(applicationDidEnterBackground:)
		                                             name: UIApplicationDidEnterBackgroundNotification
		                                           object: nil];
	#endif
		
		internal_roConnection = [zdc.databaseManager internal_roConnection];
	
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(databaseConnectionDidUpdate:)
		                                             name: YapDatabaseModifiedNotification
		                                           object: zdc.databaseManager.database];
	
	#if TARGET_OS_IPHONE
		[self restoreTasksInBackgroundSessions];
	#endif
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This notification is posted to the main thread.
**/
- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = @[notification];
	
	YapDatabaseAutoViewConnection *ext = [internal_roConnection ext:Ext_View_LocalUsers];
	BOOL localUserChanged = [ext hasChangesForNotifications:notifications];
	if (!localUserChanged) {
		return;
	}
	
	dispatch_async(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		// Move all entries from the sessionCache to the staleSessionCache.
		// Then clear the sessionCache.
		//
		// When doing a lookup, if an item is missing from the sessionCache,
		// but is available in the staleSessionCache, this will force
		// us to refresh the userInfo for the cache entry.
		
		[staleSessionDict addEntriesFromDictionary:sessionDict];
		[sessionDict removeAllObjects];
		
	#pragma clang diagnostic pop
	}});
	
	__block NSMutableArray *missingUserIDs = nil;
	
	[internal_roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		// Delete any entries for users that no longer exist.
		//
		// I.E.: The user deleted the local account, so we should cleanup all associated resources.
		//       Doing so will automatically cancel all uploads too.
		
		NSMutableArray *userIDs = [NSMutableArray array];
		
		dispatch_sync(queue, ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"

			for (NSString *userID in sessionDict)
			{
				[userIDs addObject:userID];
			}
			
			for (NSString *userID in staleSessionDict)
			{
				[userIDs addObject:userID];
			}
			
		#pragma clang diagnostic pop
		}});
		
		if (userIDs.count == 0) return;
		
		missingUserIDs = [NSMutableArray arrayWithCapacity:[userIDs count]];
		
		for (NSString *userID in userIDs)
		{
			if (![transaction hasObjectForKey:userID inCollection:kZDCCollection_Users])
			{
				[missingUserIDs addObject:userID];
			}
		}
		
	#pragma clang diagnostic pop
	} completionQueue:queue completionBlock:^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (missingUserIDs.count == 0) return;
		
		for (NSString *userID in missingUserIDs)
		{
			ZDCSessionInfo *sessionInfo = sessionDict[userID];
			if (sessionInfo == nil)
				sessionInfo = staleSessionDict[userID];
			
			if (sessionInfo)
			{
			#if TARGET_OS_IPHONE
				[sessionInfo.foregroundSession invalidateSessionCancelingTasks:YES];
				[sessionInfo.backgroundSession invalidateSessionCancelingTasks:YES];
			#else
				[sessionInfo.session invalidateSessionCancelingTasks:YES];
			#endif
			}
		}
	
		[sessionDict removeObjectsForKeys:missingUserIDs];
		[staleSessionDict removeObjectsForKeys:missingUserIDs];
		
	#pragma clang diagnostic pop
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Provides a standard "User-Agent" value that's created by extracting information from the app's Info.plist.
 * The value is of the format:
 *
 *   "[Application Name] ([version])([build if present])"
**/
- (NSString *)userAgent
{
	NSBundle *main = [NSBundle mainBundle];
	
	NSString *appName = [main objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (appName == nil) {
		appName = [main objectForInfoDictionaryKey:@"CFBundleName"];
	}
	if (appName == nil) {
		appName = [main objectForInfoDictionaryKey:@"CFBundleIdentifier"];
	}
	if (appName == nil) {
		appName = NSStringFromClass([self class]);
	}
	
    NSString *version = [main objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build   = [main objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
	
	if (build)
		return [NSString stringWithFormat: @"%@ %@ (%@)", appName, version, build];
	else if (version)
		return [NSString stringWithFormat: @"%@ %@", appName, version];
	else
		return appName;
}

- (NSString *)sessionIdentifierForLocalUserID:(NSString *)localUserID isBackground:(BOOL)isBackgroundSession
{
	// The sessionIdentifier must include:
	//
	// - zdc prefix, so we can distinguish between our sessions, and those created externally.
	// - bg/fg information
	// - the localUserID
	//
	// The sessionIdentifier is also used in 'storageKeyForTask:inSession:'.
	// and we need it to properly differentiate between any other session.
	
	return [NSString stringWithFormat:@"zdc:%@|%@",
	  (isBackgroundSession ? kSessionDescriptionPrefix_Background : kSessionDescriptionPrefix_Foreground), localUserID];
}

- (BOOL)parseSessionIdentifier:(NSString *)sessionIdentifier
                   localUserID:(NSString **)outLocalUserID
                  isBackground:(BOOL *)outIsBackgroundSession
{
	BOOL result = NO;
	NSString *localUserID = nil;
	BOOL isBackgroundSession = NO;
	
	NSArray<NSString*> *components = nil;
	
	if (![sessionIdentifier hasPrefix:@"zdc:"]) {
		goto done;
	}
	sessionIdentifier = [sessionIdentifier substringFromIndex:4];
	
	components = [sessionIdentifier componentsSeparatedByString:@"|"];
	if (components.count == 2)
	{
		isBackgroundSession = [components[0] isEqualToString:kSessionDescriptionPrefix_Background];
		localUserID = components[1];
		
		result = YES;
	}
	
done:
	
	if (outLocalUserID) *outLocalUserID = localUserID;
	if (outIsBackgroundSession) *outIsBackgroundSession = isBackgroundSession;
	
	return result;
}

- (NSString *)storageKeyForTask:(NSURLSessionTask *)task inSession:(NSURLSession *)session
{
	NSParameterAssert([session isKindOfClass:[NSURLSession class]]);
	
	return [NSString stringWithFormat:@"%llu|%@", (unsigned long long)task.taskIdentifier, session.sessionDescription];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Session Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (ZDCSessionInfo *)sessionInfoForUserID:(NSString *)userID
{
	__block ZDCSessionInfo *sessionInfo = nil;
	__block BOOL needsUserInfoRefresh = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		sessionInfo = sessionDict[userID];
		
		if (sessionInfo == nil)
		{
			sessionInfo = staleSessionDict[userID];
			if (sessionInfo)
			{
				sessionDict[userID] = sessionInfo;
				staleSessionDict[userID] = nil;
				
				needsUserInfoRefresh = YES;
			}
		}
		
		if (sessionInfo == nil)
		{
			dispatch_queue_t sessionQueue = dispatch_queue_create([userID UTF8String], DISPATCH_QUEUE_SERIAL);
			
		#if TARGET_OS_IPHONE
			
			AFURLSessionManager *fgSession = [self createSessionForLocalUserID:userID isBackground:NO];
			AFURLSessionManager *bgSession = [self createSessionForLocalUserID:userID isBackground:YES];
			
			fgSession.completionQueue = sessionQueue;
			bgSession.completionQueue = sessionQueue;
			
			sessionInfo = [[ZDCSessionInfo alloc] initWithForegroundSession: fgSession
			                                              backgroundSession: bgSession
			                                                          queue: sessionQueue];
		#else
			
			AFURLSessionManager *session = [self createSessionForLocalUserID:userID isBackground:NO];
			session.completionQueue = sessionQueue;
			
			sessionInfo = [[ZDCSessionInfo alloc] initWithSession:session queue:sessionQueue];
			
		#endif
			
			sessionDict[userID] = sessionInfo;
			needsUserInfoRefresh = YES;
		}
		else if (sessionInfo.userInfo == nil)
		{
			needsUserInfoRefresh = YES;
		}
		
		// Always make a copy of the info !
		// It's not safe to read or modify the original instance stored in 'sessionCache' outside the 'queue'.
		
		sessionInfo = [sessionInfo copy];
		
	#pragma clang diagnostic pop
	}});
	
	if (needsUserInfoRefresh)
	{
		// Deadlock warning:
		//
		// The 'databaseConnectionDidUpdate:' method (above) does the following:
		//
		//   [database asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){
		//       dispatch_sync(queue, ^{ ... })
		//   }];
		//
		// So if we were to do the opposite in this method:
		//
		//   dispatch_sync(queue, ^{
		//       [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){ ... }];
		//   });
		//
		// Then we would eventually end up in a deadlock situation.
		// For this reason we explicitly perform the database read outside the queue in this method.
		
		__block ZDCLocalUser *user = nil;
		[internal_roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		}];
		
		if (user)
		{
			// Create userInfo object from S4LocalUser
			
			ZDCSessionUserInfo *userInfo = [[ZDCSessionUserInfo alloc] init];
			
			userInfo.region = user.aws_region;
			userInfo.bucket = user.aws_bucket;
			userInfo.stage  = user.aws_stage;
			
			// Update both the 'info' object we're going to return,
			// as well as the one stored in sessionCache.
			
			sessionInfo.userInfo = userInfo;
			
			dispatch_sync(queue, ^{ @autoreleasepool {
			#pragma clang diagnostic push
			#pragma clang diagnostic ignored "-Wimplicit-retain-self"

				ZDCSessionInfo *originalInfo = sessionDict[userID];
				if (originalInfo)
				{
					if (originalInfo.userInfo == nil)
					{
					#if TARGET_OS_IPHONE
						[self configureSession:originalInfo.foregroundSession isBackground:NO  withUserInfo:userInfo];
						[self configureSession:originalInfo.backgroundSession isBackground:YES withUserInfo:userInfo];
					#else
						[self configureSession:originalInfo.session isBackground:NO withUserInfo:userInfo];
					#endif
					}
					
					originalInfo.userInfo = userInfo;
				}
				
			#pragma clang diagnostic pop
			}});
		}
	}
	
	return sessionInfo;
}

/**
 * Creates the session object, and sets up universal configuration.
 * CloudService specific configuration occurs in '
 */
- (AFURLSessionManager *)createSessionForLocalUserID:(NSString *)localUserID
                                        isBackground:(BOOL)isBackgroundSession
{
	ZDCLogAutoTrace();
	
	// Note: The session identifier (for background sessions) MUST be the localUserID.
	// We depend on this being true in 'handleEventsForBackgroundURLSession:'.
	
	NSString *const sessionIdentifier =
	  [self sessionIdentifierForLocalUserID: localUserID
	                           isBackground: isBackgroundSession];
	
	NSURLSessionConfiguration *sessionConfig;
	if (isBackgroundSession)
		sessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionIdentifier];
	else
		sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
	
	sessionConfig.HTTPShouldUsePipelining = YES;
	
	NSMutableDictionary *customHeaders = [NSMutableDictionary dictionaryWithCapacity:1];
	
	NSString *userAgent = [self userAgent];
	if (userAgent) {
		customHeaders[@"User-Agent"] = userAgent;
	}
	
	sessionConfig.HTTPAdditionalHeaders = customHeaders;
	
	sessionConfig.HTTPCookieStorage = nil;
	sessionConfig.URLCache = nil;
	sessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	
	AFURLSessionManager *session = [[AFURLSessionManager alloc] initWithSessionConfiguration:sessionConfig];
	
	session.session.sessionDescription = sessionIdentifier;
	
	[session setTaskNeedNewBodyStreamBlock:^NSInputStream *(NSURLSession *session, NSURLSessionTask *task){
		
		return [self streamForTask:task inSession:session];
	}];
	
	[session setDataTaskDidBecomeDownloadTaskBlock:
	    ^(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask)
	{
		[self migrateDataTask:dataTask toDownloadTask:downloadTask inSession:session];
	}];
	
	[session setDownloadTaskDidFinishDownloadingBlock:
	  ^NSURL *(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *fileURL)
	{
		return [self downloadTaskDidFinishDownloading: downloadTask
		                                    inSession: session
		                                 withLocation: fileURL
		                                  localUserID: localUserID];
	}];
	
	[session setTaskDidCompleteBlock:^(NSURLSession *session, NSURLSessionTask *task, NSError *error){
		
		[self taskDidComplete:task inSession:session withError:error localUserID:localUserID];
	}];
	
#if TARGET_OS_IPHONE
	if (isBackgroundSession)
	{
		session.attemptsToRecreateUploadTasksForBackgroundSessions = YES;
		
		[session setDidFinishEventsForBackgroundURLSessionBlock:^(NSURLSession *session){
			
			[self didFinishEventsForBackgroundURLSession:session localUserID:localUserID];
		}];
	}
#endif
	return session;
}

/**
 * This method is called exactly once.
 * It is called when the session is matched to userInfo for the first time.
 *
 * We may use this in the future as a hook to allow the ZeroDarkCloudDelegate
 * to customize the session on a per-user basis.
 */
- (void)configureSession:(AFURLSessionManager *)session
            isBackground:(BOOL)isBackgroundSession
            withUserInfo:(ZDCSessionUserInfo *)userInfo
{
	ZDCLogAutoTrace();
	
	session.responseSerializer = [S3ResponseSerialization serializer];
}

/**
 * Invoked by the AppDelegate in response to a
 * 'application:handleEventsForBackgroundURLSession:completionHandler:' message from the system.
 * 
 * It is the responsibility of the SessionManager to create the corresponding background session (if needed),
 * so that it can receive and process the events from the session.
 */
- (void)handleEventsForBackgroundURLSession:(NSString *)sessionIdentifier
{
	ZDCLogAutoTrace();
	
	NSString *localUserID = nil;
	BOOL isBackgroundSession = NO;
	
	if ([self parseSessionIdentifier: sessionIdentifier
	                     localUserID: &localUserID
	                    isBackground: &isBackgroundSession])
	{
		// All we have to do here is create the session, if it doesn't already exist.
		
		(void)[self sessionInfoForUserID:localUserID];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Session Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSURL *)downloadTaskDidFinishDownloading:(NSURLSessionDownloadTask *)downloadTask
                                  inSession:(NSURLSession *)session
                               withLocation:(NSURL *)fileURL
                                localUserID:(NSString *)localUserID
{
	__block NSURL *result = nil;
	__block ZDCSessionStorageItem *storageItem = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

	#if TARGET_OS_IPHONE
		
		if (isReadyForStorage && ![localUserIDsPendingRestore containsObject:localUserID])
		{
			storageItem = [self storageItemForTask:downloadTask inSession:session];
		}
		else
		{
			// We haven't finished restoring tasks from previous app launch.
			
			ZDCSessionPendingItem *pendingItem =
			  [self pendingItemForTask: downloadTask
			                 inSession: session
			           createIfMissing: YES];
			
			result = pendingItem.downloadedFileURL = [zdc.directoryManager generateDownloadURL];
		}
		
	#else // OSX
		
		storageItem = [self storageItemForTask:downloadTask inSession:session];
		
	#endif
	#pragma clang diagnostic pop
	}});
	
	if (storageItem && storageItem.context)
	{
		result = storageItem.downloadedFileURL = [zdc.directoryManager generateDownloadURL];
	}
	
	return result;
}

- (void)taskDidComplete:(NSURLSessionTask *)task
              inSession:(NSURLSession *)session
              withError:(NSError *)error
            localUserID:(NSString *)localUserID
{
	__block ZDCSessionStorageItem *storageItem = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

	#if TARGET_OS_IPHONE
		
		if (isReadyForStorage && ![localUserIDsPendingRestore containsObject:localUserID])
		{
			storageItem = [self storageItemForTask:task inSession:session];
		}
		else
		{
			// We haven't finished restoring tasks from previous app launch.
			
			ZDCSessionPendingItem *pendingItem =
			  [self pendingItemForTask: task
			                 inSession: session
			           createIfMissing: YES];
			
			pendingItem.isComplete = YES;
			pendingItem.error = error;
		}
		
	#else // OSX
		
		storageItem = [self storageItemForTask:task inSession:session];
		
	#endif
	#pragma clang diagnostic pop
	}});
	
	if (storageItem && storageItem.context)
	{
		ZDCSessionInfo *sessionInfo = [self sessionInfoForUserID:localUserID];
		
		[self notifyTaskDidComplete: task
		                  inSession: session
		                  withError: error
		                    context: storageItem.context
		          downloadedFileURL: storageItem.downloadedFileURL
		                sessionInfo: sessionInfo];
	}
	
	if (storageItem) {
		[self removeStorageItem:storageItem forTask:task inSession:session];
	}
}

#if TARGET_OS_IPHONE

- (void)didFinishEventsForBackgroundURLSession:(NSURLSession *)session localUserID:(NSString *)localUserID
{
	ZDCSessionInfo *sessionInfo = [self sessionInfoForUserID:localUserID];
	
	[self notifyDidFinishEventsForBackgroundSession:session sessionInfo:sessionInfo];
}

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Session Restore
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IPHONE

/**
 * Invoked after the database is setup, and we're being asked to:
 *
 * - restore the list of active uploads/downloads
 * - process any completed uploads/downloads
 * - decrement the suspendCount for the YDBCloudCore extension
**/
- (void)restoreTasksInBackgroundSessions
{
	ZDCLogAutoTrace();
	
	NSSet<NSString *> *localUserIDs = zdc.databaseManager.previouslyRegisteredLocalUserIDs;
	
	if (localUserIDs.count == 0)
	{
		dispatch_sync(queue, ^{
			
			isReadyForStorage = YES;
		});
	}
	else
	{
		dispatch_sync(queue, ^{
			
			isReadyForStorage = YES;
			localUserIDsPendingRestore = [localUserIDs mutableCopy];
		});
		
		dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		dispatch_async(bgQueue, ^{ @autoreleasepool {
		
			for (NSString *localUserID in localUserIDs)
			{
				ZDCSessionInfo *sessionInfo = [self sessionInfoForUserID:localUserID];
				NSURLSession *backgroundSession = sessionInfo.backgroundSession.session;
				
				[backgroundSession getTasksWithCompletionHandler:
				  ^(NSArray<NSURLSessionDataTask *> *dataTasks,
				    NSArray<NSURLSessionUploadTask *> *uploadTasks,
				    NSArray<NSURLSessionDownloadTask *> *downloadTasks)
				{
					[self restoreUploadTasks: uploadTasks
					           downloadTasks: downloadTasks
					               inSession: backgroundSession
					          forLocalUserID: localUserID];
				}];
			}
		}});
	}
}

- (void)restoreUploadTasks:(NSArray<NSURLSessionUploadTask *> *)uploadTasks
             downloadTasks:(NSArray<NSURLSessionDownloadTask *> *)downloadTasks
                 inSession:(NSURLSession *)session
            forLocalUserID:(NSString *)localUserID
{
	ZDCLogTrace(@"%@ %@", THIS_METHOD, localUserID);
	
	ZDCSessionInfo *sessionInfo = [self sessionInfoForUserID:localUserID];
	
	NSUInteger capacity = uploadTasks.count + downloadTasks.count;
	
	NSMutableArray<NSURLSessionTask *> *matchedTasks = [NSMutableArray arrayWithCapacity:capacity];
	NSMutableArray<ZDCObject *> *contexts         = [NSMutableArray arrayWithCapacity:capacity];
	
	[internal_roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (NSURLSessionUploadTask *task in uploadTasks)
		{
			NSString *key = [self storageKeyForTask:task inSession:session];
			
			ZDCObject *context = [transaction objectForKey:key inCollection:kZDCCollection_SessionStorage];
			if (context)
			{
				[matchedTasks addObject:task];
				[contexts addObject:context];
			}
		}
		
		for (NSURLSessionDownloadTask *task in downloadTasks)
		{
			NSString *key = [self storageKeyForTask:task inSession:session];
			
			ZDCObject *context = [transaction objectForKey:key inCollection:kZDCCollection_SessionStorage];
			if (context)
			{
				[matchedTasks addObject:task];
				[contexts addObject:context];
			}
		}
		
	} completionQueue:queue completionBlock:^{
		
		NSMutableArray *storageKeysToRemove = nil;
		
		const NSUInteger count = matchedTasks.count;
		for (NSUInteger i = 0; i < count; i++)
		{
			NSURLSessionTask *task = matchedTasks[i];
			ZDCObject *context = contexts[i];
			
			NSString *storageKey = [self storageKeyForTask:task inSession:session];
			ZDCSessionPendingItem *pendingItem = [self pendingItemForTask:task inSession:session createIfMissing:NO];
			
			if (pendingItem && pendingItem.isComplete)
			{
				[self notifyTaskDidComplete: task
				                  inSession: session
				                  withError: pendingItem.error
				                    context: context
				          downloadedFileURL: pendingItem.downloadedFileURL
				                sessionInfo: sessionInfo];
				
				if (storageKeysToRemove == nil)
					storageKeysToRemove = [NSMutableArray arrayWithCapacity:matchedTasks.count];
				
				[storageKeysToRemove addObject:storageKey];
			}
			else
			{
				ZDCSessionStorageItem *storageItem = [[ZDCSessionStorageItem alloc] init];
				
				storageItem.context = context;
				storageItem.contextIsSaved = YES;
				
				storageItem.downloadedFileURL = pendingItem.downloadedFileURL;
				
				storage[storageKey] = storageItem;
				
				[self notifyDidRestoreTask: task
				                 inSession: session
				               withContext: context
				               sessionInfo: sessionInfo];
			}
		}
		
		// All of the [self notify...] calls go through sessionInfo.queue.
		// So once we've processed all these,
		// we can decrement the suspendCloud of the ZDCCloud extension instance.
		
		dispatch_async(sessionInfo.queue, ^{ @autoreleasepool {
			
			NSArray<NSString *> *appIDs = [zdc.databaseManager previouslyRegisteredAppIDsForUser:localUserID];
			for (NSString *appID in appIDs)
			{
				[[zdc.databaseManager cloudExtForUser:localUserID app:appID] resume];
			}
		}});
		
		// Delete storage items from the database for the completed items.
		
		if (storageKeysToRemove)
		{
			YapDatabaseConnection *rwDatabaseConnection = zdc.databaseManager.rwDatabaseConnection;
			[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction removeObjectsForKeys:storageKeysToRemove inCollection:kZDCCollection_SessionStorage];
			}];
		}
		
		// And finally, remove the "hold" on the localUserID so we transition from 'pending' to 'storage'.
		
		[localUserIDsPendingRestore removeObject:localUserID];
		
		if (localUserIDsPendingRestore.count == 0)
		{
			[pending removeAllObjects];
		}
	}];
}

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notify
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if TARGET_OS_IPHONE
- (void)notifyDidRestoreTask:(NSURLSessionTask *)task
                   inSession:(NSURLSession *)session
                 withContext:(ZDCObject *)inContext
                 sessionInfo:(ZDCSessionInfo *)sessionInfo
{
	NSAssert(NO, @"Not implemented");
	
	dispatch_async(sessionInfo.queue, ^{ @autoreleasepool {
		
		if ([inContext isKindOfClass:[ZDCDownloadContext class]])
		{
			ZDCDownloadContext *context = (ZDCDownloadContext *)inContext;
	
			ZDCSessionInfo *sessionInfo = [self sessionInfoForUserID:context.localUserID];
			AFURLSessionManager *sessionManager = sessionInfo.backgroundSession;
	
			NSProgress *progress = [sessionManager downloadProgressForTask:task];
			if (progress)
			{
				if (context.isMeta)
				{
					[zdc.progressManager setMetaDownloadProgress: progress
					                                   forNodeID: context.nodeID
					                                  components: context.components
					                                 localUserID: context.localUserID];
				}
				else
				{
					[zdc.progressManager setDataDownloadProgress: progress
					                                   forNodeID: context.nodeID
					                                 localUserID: context.localUserID];
				}
			}
		}
		else
		{
			NSAssert(NO, @"Not implemented");
		}
		
	}});
}
#endif

- (void)notifyTaskDidComplete:(NSURLSessionTask *)task
                    inSession:(NSURLSession *)session
                    withError:(NSError *)error
                      context:(ZDCObject *)inContext
            downloadedFileURL:(NSURL *)downloadedFileURL
                  sessionInfo:(ZDCSessionInfo *)sessionInfo
{
	dispatch_async(sessionInfo.queue, ^{ @autoreleasepool {
		
		if ([task isKindOfClass:[NSURLSessionDownloadTask class]])
		{
			if ([inContext isKindOfClass:[ZDCDownloadContext class]])
			{
				ZDCDownloadContext *context = (ZDCDownloadContext *)inContext;
		
				[zdc.downloadManager downloadTaskDidComplete: (NSURLSessionDownloadTask *)task
				                                   inSession: session
				                                 withContext: context
				                                       error: error
				                           downloadedFileURL: downloadedFileURL];
			}
			else
			{
				[zdc.pushManager downloadTaskDidComplete: (NSURLSessionDownloadTask *)task
				                               inSession: session
				                               withError: error
				                                 context: inContext
				                       downloadedFileURL: downloadedFileURL];
			}
		}
		else
		{
			[zdc.pushManager taskDidComplete: task
			                       inSession: session
			                       withError: error
			                         context: inContext];
		}
	}});
}

#if TARGET_OS_IPHONE

- (void)notifyDidFinishEventsForBackgroundSession:(NSURLSession *)session
                                      sessionInfo:(ZDCSessionInfo *)sessionInfo
{
	// We need to tell the OS that we're done processing events from a background session.
	// However, we may have outstanding database operations (due to processing the results).
	//
	// So let's flush the rwDatabaseConnection being used by the PushManager & PullManager first.
	// And then we'll notify the OS that we're done.
	
	YapDatabaseConnection *rwConnection = [zdc.databaseManager internal_rwConnection];
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	[rwConnection flushTransactionsWithCompletionQueue:concurrentQueue completionBlock:^{
		
		[zdc invokeCompletionHandlerForBackgroundURLSession:session.configuration.identifier];
	}];
}

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark PendingItem Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IPHONE

- (ZDCSessionPendingItem *)pendingItemForTask:(NSURLSessionTask *)task
                                    inSession:(NSURLSession *)session
                              createIfMissing:(BOOL)createIfMissing
{
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"SessionPendingItem's can only be accessed/modified within queue");
	
	ZDCSessionPendingItem *item = nil;
	NSString *dictKey = session.sessionDescription; // <- contains fg/bg & localUserID
	
	NSMutableDictionary<NSNumber *, ZDCSessionPendingItem *> *dict = pending[dictKey];
	if (!dict && createIfMissing)
	{
		dict = [[NSMutableDictionary alloc] initWithCapacity:1];
		pending[dictKey] = dict;
	}
	
	if (dict)
	{
		NSNumber *itemKey = @(task.taskIdentifier);
		
		item = dict[itemKey];
		if (!item && createIfMissing)
		{
			item = [[ZDCSessionPendingItem alloc] init];
			item.task = task;
			
			dict[itemKey] = item;
		}
	}
	
	return item;
}

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark StorageItem Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For background tasks that require the use of delegate callbacks (vs blocks),
 * this method allows you to associate a context object with a task.
 * 
 * The context object can be whatever you want, so long as it can be serialized & deserialized.
 * The context object may be stored to the database if the task is still in-flight while the app is backgrounded.
**/
- (void)associateContext:(ZDCObject *)context
                withTask:(NSURLSessionTask *)task
               inSession:(NSURLSession *)session
{
	if (task == nil) return;
	if (session == nil) return;
	
	[context makeImmutable];
	NSString *key = [self storageKeyForTask:task inSession:session];
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCSessionStorageItem *item = storage[key];
		if (item == nil)
		{
			item = [[ZDCSessionStorageItem alloc] init];
			storage[key] = item;
		}
		
		item.context = context;
		item.contextIsSaved = NO;
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
}

/**
 * If using [NSURLSession uploadTaskWithStreamedRequest:],
 * then you should use this method so we can automatically return the stream via
 * [NSURLSessionTaskDelegate URLSession:task:needNewBodyStream:].
 *
 * Note: You should make your stream copyable (NSCopying) in case the
 * URLSession:task:needNewBodyStream: method is invoked more than once.
**/
- (void)associateStream:(NSInputStream *)stream
               withTask:(NSURLSessionTask *)task
              inSession:(NSURLSession *)session
{
	if (task == nil) return;
	if (session == nil) return;
	
	NSString *key = [self storageKeyForTask:task inSession:session];
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCSessionStorageItem *item = storage[key];
		if (item == nil)
		{
			item = [[ZDCSessionStorageItem alloc] init];
			storage[key] = item;
		}
		
		item.stream = stream;
		item.streamUsedOnce = NO;
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
}

- (NSInputStream *)streamForTask:(NSURLSessionTask *)task inSession:(NSURLSession *)session
{
	if (task == nil) return nil;
	
	NSString *key = [self storageKeyForTask:task inSession:session];
	
	__block NSInputStream *stream = nil;
	__block BOOL needsCopy = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCSessionStorageItem *item = storage[key];
		if (item)
		{
			stream = item.stream;
			
			if (item.streamUsedOnce) {
				needsCopy = YES;
			}
			else {
				item.streamUsedOnce = YES;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	if (needsCopy)
	{
		if ([stream conformsToProtocol:@protocol(NSCopying)])
		{
			stream = [stream copy];
		}
		else
		{
			ZDCLogWarn(
			  @"The NSInputStream you have provided for an upload task is not copyable."
			  @" So we are being forced to return nil via URLSession:task:needNewBodyStream:."
			  @" This may result in an infinite loop if the task always uses an auth challenge.");
			
			stream = nil;
		}
	}
	
	return stream;
}

- (void)migrateDataTask:(NSURLSessionDataTask *)dataTask
         toDownloadTask:(NSURLSessionDownloadTask *)downloadTask
              inSession:(NSURLSession *)session
{
	if (dataTask == nil) return;
	if (downloadTask == nil) return;
	if (session == nil) return;
	
	NSString *oldKey = [self storageKeyForTask:dataTask inSession:session];
	NSString *newKey = [self storageKeyForTask:downloadTask inSession:session];
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCSessionStorageItem *item = storage[oldKey];
		if (item)
		{
			storage[oldKey] = nil;
			storage[newKey] = item;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
}

- (ZDCSessionStorageItem *)storageItemForTask:(NSURLSessionTask *)task inSession:(NSURLSession *)session
{
	if (task == nil) return nil;
	if (session == nil) return nil;
	
	NSString *key = [self storageKeyForTask:task inSession:session];
	__block ZDCSessionStorageItem *item = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		item = storage[key];
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return item;
}

- (void)removeStorageItem:(ZDCSessionStorageItem *)storageItem
                  forTask:(NSURLSessionTask *)task
                inSession:(NSURLSession *)session
{
	if (task == nil) return;
	if (session == nil) return;
	
	NSString *key = [self storageKeyForTask:task inSession:session];
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
		storage[key] = nil;
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	if (storageItem.contextIsSaved)
	{
		YapDatabaseConnection *rwDatabaseConnection = zdc.databaseManager.rwDatabaseConnection;
		[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			[transaction removeObjectForKey:key inCollection:kZDCCollection_SessionStorage];
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark StorageItem Persistence
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if TARGET_OS_IPHONE

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
	__block NSMutableDictionary<NSString *, ZDCObject *> *items = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		[storage enumerateKeysAndObjectsUsingBlock:^(NSString *key, ZDCSessionStorageItem *item, BOOL *stop) {
			
			if (item.context && !item.contextIsSaved)
			{
				if (items == nil)
					items = [[NSMutableDictionary alloc] initWithCapacity:16];
				
				items[key] = item.context;
				item.contextIsSaved = YES;
			}
		}];
	}});
	
	if (items)
	{
		__block UIBackgroundTaskIdentifier taskIdentifier =
			[[UIApplication sharedApplication] beginBackgroundTaskWithName:@"SessionManager" expirationHandler:^{
			
				[[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
			}];
		
		YapDatabaseConnection *rwDatabaseConnection = zdc.databaseManager.rwDatabaseConnection;
		[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			[items enumerateKeysAndObjectsUsingBlock:^(NSString *key, ZDCObject *context, BOOL *stop) {
				
				[transaction setObject:context forKey:key inCollection:kZDCCollection_SessionStorage];
			}];
			
		} completionBlock:^{
			
			if (taskIdentifier != UIBackgroundTaskInvalid)
			{
				[[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
			}
		}];
	}
}

#endif

#pragma clang diagnostic pop
@end
