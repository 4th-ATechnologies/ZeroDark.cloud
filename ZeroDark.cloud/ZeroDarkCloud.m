/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZeroDarkCloudPrivate.h"

#import "ZDCAuditPrivate.h"
#import "ZDCBlockchainManager.h"
#import "ZDCDatabaseKeyManagerPrivate.h"
#import "ZDCDatabaseManagerPrivate.h"
#import "ZDCDirectoryManagerPrivate.h"
#import "ZDCDiskManagerPrivate.h"
#import "ZDCDownloadManagerPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCProgressManagerPrivate.h"
#import "ZDCPullManagerPrivate.h"
#import "ZDCPushInfo.h"
#import "ZDCPushManagerPrivate.h"
#import "ZDCSyncManagerPrivate.h"
#import "ZDCUserManagerPrivate.h"
#import "ZDCUserSearchManagerPrivate.h"
#import "ZDCTask_UnregisterPushToken.h"
#import "ZDCUIToolsPrivate.h"
#import "ZDCRestManagerPrivate.h"

// Categories
#import "NSData+AWSUtilities.h"
#import "NSDate+ZeroDark.h"
#import "NSError+S4.h"
#import "NSError+ZeroDark.h"

// Libraries
#import <os/log.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAtomic.h>

@import CoreText;

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

typedef void (^ZDCLogHandler)(ZDCLogMessage *);

@interface ZeroDarkCloud () <YapDatabaseCloudCorePipelineDelegate>

@property (nonatomic, readwrite, strong) NSURL *databasePath;
@property (nonatomic, readwrite, copy) NSString *primaryTreeID;

@property (nonatomic, readwrite, strong) AFNetworkReachabilityManager *reachability;

@property (nonatomic, readwrite) Auth0APIManager       * auth0APIManager;
@property (nonatomic, readwrite) ZDCDatabaseKeyManager * databaseKeyManager;
@property (nonatomic, readwrite) ZDCDirectoryManager   * directoryManager;
@property (nonatomic, readwrite) ZDCProgressManager    * progressManager;

@property (nonatomic, readwrite, nullable) Auth0ProviderManager	 * auth0ProviderManager;
@property (nonatomic, readwrite, nullable) AWSCredentialsManager   * awsCredentialsManager;
@property (nonatomic, readwrite, nullable) ZDCBlockchainManager    * blockchainManager;
@property (nonatomic, readwrite, nullable) ZDCCryptoTools          * cryptoTools;
@property (nonatomic, readwrite, nullable) ZDCDatabaseManager      * databaseManager;
@property (nonatomic, readwrite, nullable) ZDCDiskManager          * diskManager;
@property (nonatomic, readwrite, nullable) ZDCDownloadManager      * downloadManager;
@property (nonatomic, readwrite, nullable) ZDCImageManager         * imageManager;
@property (nonatomic, readwrite, nullable) ZDCInternalPreferences  * internalPreferences;
@property (nonatomic, readwrite, nullable) ZDCLocalUserManager     * localUserManager;
@property (nonatomic, readwrite, nullable) ZDCNetworkTools         * networkTools;
@property (nonatomic, readwrite, nullable) ZDCPullManager          * pullManager;
@property (nonatomic, readwrite, nullable) ZDCPushManager          * pushManager;
@property (nonatomic, readwrite, nullable) ZDCUserSearchManager    * searchManager;
@property (nonatomic, readwrite, nullable) ZDCSessionManager       * sessionManager;
@property (nonatomic, readwrite, nullable) ZDCSharesManager  		 * sharesManager;
@property (nonatomic, readwrite, nullable) ZDCSyncManager          * syncManager;
@property (nonatomic, readwrite, nullable) ZDCRestManager          * restManager;
@property (nonatomic, readwrite, nullable) ZDCUserManager          * userManager;
@property (nonatomic, readwrite, nullable) ZDCUserAccessKeyManager * userAccessKeyManager;
@property (nonatomic, readwrite, nullable) ZDCUITools        	    * uiTools;

@property (atomic, readwrite, strong, nullable) NSString *pushToken;

@end

@implementation ZeroDarkCloud {
	dispatch_queue_t serialQueue;
	BOOL isUnlocked;
	
	NSMutableDictionary *backgroundSessionCompletionHandlers;
	S4KeyContextRef databaseKeyCtx;
}

@synthesize delegate;
@synthesize databasePath;
@synthesize primaryTreeID;

@dynamic isDatabaseUnlocked;

@dynamic auth0APIManager;
@dynamic cloudPathManager;
@synthesize databaseKeyManager;
@synthesize directoryManager;
@dynamic nodeManager;
@synthesize progressManager;

@synthesize awsCredentialsManager;
@synthesize cryptoTools;
@synthesize uiTools;
@synthesize databaseManager;
@synthesize diskManager;
@synthesize downloadManager;
@synthesize imageManager;
@synthesize networkTools;
@synthesize pullManager;
@synthesize pushManager;
@synthesize sessionManager;
@synthesize userManager;
@synthesize auth0ProviderManager;
@synthesize searchManager;
@synthesize sharesManager;

@synthesize pushToken = _mustUseAtomicProperty_pushToken;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ZDCLogHandler logHandler = nil;
static NSMutableSet<NSString*> *registeredDatabaseNames = nil;
static YAPUnfairLock registrationLock = YAP_UNFAIR_LOCK_INIT;

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		logHandler = [self defaultLogHandler];
		registeredDatabaseNames = [[NSMutableSet alloc] initWithCapacity:1];
		[self loadFontWithName:@"Exo2-Regular"];
	}
}

+ (NSBundle *)frameworkBundle
{
	static NSBundle *frameworkBundle = nil;
	
	static dispatch_once_t predicate;
	dispatch_once(&predicate, ^{
		frameworkBundle = [NSBundle bundleForClass:[ZeroDarkCloud class]];
	});
	
	return frameworkBundle;
}

+ (void)loadFontWithName:(NSString *)fontName
{
	NSString *fontPath = [[self frameworkBundle] pathForResource:fontName ofType:@"ttf"];
	NSData *fontData = [NSData dataWithContentsOfFile:fontPath];

	CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)fontData);
	if (provider)
	{
		CGFontRef font = CGFontCreateWithDataProvider(provider);
		if (font)
		{
			CFErrorRef error = NULL;
			if (CTFontManagerRegisterGraphicsFont(font, &error) == NO)
			{
				CFStringRef errorDescription = CFErrorCopyDescription(error);
				ZDCLogError(@"Failed to load font: %@", errorDescription);
				CFRelease(errorDescription);
			}

			CFRelease(font);
		}

		CFRelease(provider);
	}
}

+ (ZDCLogHandler)defaultLogHandler
{
	NSString *subsystem = @"ZeroDark";
	NSString *category = @"ZeroDark";
	
	os_log_t logger = os_log_create([subsystem UTF8String], [category UTF8String]);
	
	ZDCLogHandler handler = ^void (ZDCLogMessage *log){ @autoreleasepool {
		
		if (log.flag & ZDCLogFlagError) {
			os_log_error(logger, "%{public}@ %{public}@", log.function, log.message);
		}
		else if (log.flag & ZDCLogFlagWarning) {
			os_log_info(logger, "%{public}@ %{public}@", log.function, log.message);
		}
	}};
	return handler;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
+ (void)setLogHandler:(void (^)(ZDCLogMessage *))inLogHandler
{
	logHandler = inLogHandler ?: [self defaultLogHandler];
}

/**
 * Used by the macros defined in ZDCLogging.h
 */
+ (void)log:(ZDCLogLevel)level
       flag:(ZDCLogFlag)flag
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
     format:(NSString *)format, ...
{
	va_list args;
	if (format)
	{
		va_start(args, format);
		NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
      va_end(args);
		
		ZDCLogMessage *logMessage =
		  [[ZDCLogMessage alloc] initWithMessage: message
		                                   level: level
		                                    flag: flag
		                                    file: [NSString stringWithFormat:@"%s", file]
		                                function: [NSString stringWithFormat:@"%s", function]
		                                    line: line];
		
		logHandler(logMessage);
	}
}

/**
 * Every ZDC instance must have a unique database.
 * That is, multiple ZDC instances are not allowed to share the same database.
 *
 * Further, there are other ZDC classes that need their own unique values or directories.
 * For example, the ZDCDiskManager needs container directories that won't overlap with
 * other possible ZeroDarkCloud instances.
 *
 * To achieve this result, we derive unique values from the database filename.
 * Another possible option would have been to hash the database filepath.
 * However, iOS makes this idea difficult for us because it keeps changing the location of the app containers.
 * For example, you get a different filepath each time you build-and-go on the simulator.
 *
 * So our simple solution is to require database filenames to be unique.
 */
+ (BOOL)registerDatabaseName:(NSString *)inDatabaseName
{
	NSString *databaseName = [inDatabaseName lowercaseString];
	if (databaseName == nil) return NO;
	
	BOOL result = NO;
	YAPUnfairLockLock(&registrationLock);
	{
		if (![registeredDatabaseNames containsObject:databaseName])
		{
			[registeredDatabaseNames addObject:databaseName];
			result = YES;
		}
	}
	YAPUnfairLockUnlock(&registrationLock);
	
	return result;
}

+ (void)deregisterDatabaseName:(NSString *)inDatabaseName
{
	NSString *databaseName = [inDatabaseName lowercaseString];
	if (databaseName == nil) return;
	
	YAPUnfairLockLock(&registrationLock);
	{
		[registeredDatabaseNames removeObject:databaseName];
	}
	YAPUnfairLockUnlock(&registrationLock);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	return nil; // This is not the init method you're looking for.
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (instancetype)initWithDelegate:(id<ZeroDarkCloudDelegate>)inDelegate
                          config:(ZDCConfig *)config
{
	if (inDelegate == nil) return nil;
	if (config == nil) return nil;
	if (config.databaseName.length == 0) return nil;
	
	NSURL *dbPath = [ZDCDirectoryManager fileURLsForDatabaseName:config.databaseName][0];
	
	if (![ZeroDarkCloud registerDatabaseName:[dbPath lastPathComponent]])
	{
		NSString *reason =
		  @"You cannot create multiple ZeroDarkCloud instances with the same database filename."
		  @" Every ZeroDarkCloud instance must have a unique database (not shared with other ZDC instance)."
		  @" Further, the database filename itself needs to be unique across instances because it's used"
		  @" as a key (by various classes) to segregate data between multiple instances.";
		
		@throw [NSException exceptionWithName: @"ZerDarkCloud:DatabaseNameConflict"
		                               reason: reason
		                             userInfo: nil];
	}
	
	if ((self = [super init]))
	{
		serialQueue = dispatch_queue_create("ZeroDarkCloud", DISPATCH_QUEUE_SERIAL);
		
		self.delegate = inDelegate;
		self.databasePath = dbPath;
		self.primaryTreeID = config.primaryTreeID;
		
		self->databaseKeyCtx = kInvalidS4KeyContextRef;
		
		self.reachability = [AFNetworkReachabilityManager sharedManager];
		[self.reachability startMonitoring];
		
		self.databaseKeyManager = [[ZDCDatabaseKeyManager alloc] initWithOwner:self];
		self.directoryManager = [[ZDCDirectoryManager alloc] initWithOwner:self];
		self.progressManager = [[ZDCProgressManager alloc] initWithOwner:self];
	}
	return self;
}

- (void)dealloc
{
	NSString *databaseName = [self.databasePath lastPathComponent];
	if (databaseName) {
		[[self class] deregisterDatabaseName:databaseName];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Framework Unlock
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (BOOL)unlockOrCreateDatabase:(ZDCDatabaseConfig *)config error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	__block NSError *error = nil;

	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (self->isUnlocked)
		{
			return; // from block
		}

		S4Err	err = kS4Err_NoErr;
		ZDCDatabaseManager *db = nil;

		// Create the storage key.
		//
		// Be careful here.
		// If you change the algorithm you will break any imported private keys.
		
		NSData *databaseKey = config.encryptionKey;
		
		Cipher_Algorithm encryptionAlgorithm = kCipher_Algorithm_2FISH256;
		size_t keySizeInBits = 0;
		err = Cipher_GetKeySize(encryptionAlgorithm, &keySizeInBits);CKERR;
		ASSERTERR(databaseKey.length == (keySizeInBits / 8), kS4Err_CorruptData);

		// Create a S4 Symmetric key to unlock the pub/priv key with
		err = S4Key_NewSymmetric(encryptionAlgorithm, databaseKey.bytes, &databaseKeyCtx); CKERR;

		db = [[ZDCDatabaseManager alloc] initWithOwner:self];
		if (![db setupDatabase:config])
		{
			NSDictionary *userInfo = @{
				NSLocalizedDescriptionKey: @"Unable to open database"
			};
			
			error = [NSError errorWithDomain:@"ZeroDarkCloud" code:100 userInfo:userInfo];
			return;
		}
		
		self->isUnlocked = YES;
		
		self.databaseManager = db;
		
		self.cryptoTools = [[ZDCCryptoTools alloc] initWithOwner:self];
		self.networkTools = [[ZDCNetworkTools alloc] initWithOwner:self];

		// several others depend on internalPreferences
		self.internalPreferences = [[ZDCInternalPreferences alloc] initWithOwner:self];

		self.awsCredentialsManager = [[AWSCredentialsManager alloc] initWithOwner:self];
		self.diskManager = [[ZDCDiskManager alloc] initWithOwner:self];
		self.downloadManager = [[ZDCDownloadManager alloc] initWithOwner:self];
		self.imageManager = [[ZDCImageManager alloc] initWithOwner:self];
		self.localUserManager = [[ZDCLocalUserManager alloc] initWithOwner:self];
		self.sessionManager = [[ZDCSessionManager alloc] initWithOwner:self];
		self.userManager = [[ZDCUserManager alloc] initWithOwner:self];
		self.restManager  = [[ZDCRestManager alloc] initWithOwner:self];
		
		self.syncManager = [[ZDCSyncManager alloc] initWithOwner:self];
		self.pullManager = [[ZDCPullManager alloc] initWithOwner:self]; // must come after networkTools
		self.pushManager = [[ZDCPushManager alloc] initWithOwner:self]; // must come after networkTools
		self.auth0ProviderManager = [[Auth0ProviderManager alloc] initWithOwner:self];
		self.uiTools = [[ZDCUITools alloc] initWithOwner:self];
		self.userAccessKeyManager = [[ZDCUserAccessKeyManager alloc] initWithOwner:self];
		self.searchManager = [[ZDCUserSearchManager alloc] initWithOwner:self];
		self.blockchainManager = [[ZDCBlockchainManager alloc] initWithOwner:self];
 		self.sharesManager = [[ZDCSharesManager alloc] initWithOwner:self];

	done:

		if (IsS4Err(err)) {
			error = [NSError errorWithS4Error:err];
		}

	#pragma clang diagnostic pop
	}});
	
	BOOL success = (error == nil);
	if (success)
	{
		// Resume all re-registered ZDCCloud extensions.
		
		NSArray<YapCollectionKey*> *tuples = self.databaseManager.previouslyRegisteredTuples;
		for (YapCollectionKey *tuple in tuples)
		{
			NSString *localUserID = tuple.collection;
			NSString *treeID = tuple.key;
			
			[[self.databaseManager cloudExtForUserID:localUserID treeID:treeID] resume];
		}
		
		[auth0ProviderManager updateProviderCache:NO];  // update provider cache if needed
	}
	
	if (outError) *outError = error;
	return success;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (BOOL)isDatabaseUnlocked
{
	__block BOOL result = NO;
	dispatch_sync(serialQueue, ^{
		
		result = self->isUnlocked;
	});
	
	return result;
}

- (S4KeyContextRef)storageKey
{
	__block S4KeyContextRef keyCtx = kInvalidS4KeyContextRef;
	dispatch_sync(serialQueue, ^{

		keyCtx = self->databaseKeyCtx;
	});

	return keyCtx;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Managers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (Auth0APIManager *)auth0APIManager
{
	return [Auth0APIManager sharedInstance];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (ZDCCloudPathManager *)cloudPathManager
{
	return [ZDCCloudPathManager sharedInstance];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (ZDCNodeManager *)nodeManager
{
	return [ZDCNodeManager sharedInstance];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (nullable ZDCCloudTransaction *)cloudTransaction:(YapDatabaseReadTransaction *)transaction
                                    forLocalUserID:(NSString *)localUserID
{
	return [self cloudTransaction:transaction forLocalUserID:localUserID treeID:self.primaryTreeID];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (nullable ZDCCloudTransaction *)cloudTransaction:(YapDatabaseReadTransaction *)transaction
                                    forLocalUserID:(NSString *)localUserID
                                            treeID:(nullable NSString *)treeID
{
	ZDCDatabaseManager *databaseManager = self.databaseManager;
	if (databaseManager == nil) return nil;
	
	NSString *extName = [databaseManager cloudExtNameForUserID:localUserID treeID:treeID];
	return [transaction ext:extName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
	NSString *pushToken = [deviceToken lowercaseHexString];
	
	self.pushToken = pushToken;
	[self registerPushTokenForLocalUsersIfNeeded];
}

- (void)registerPushTokenForLocalUsersIfNeeded
{
	// We need 2 things before we can perform this action:
	// - pushToken
	// - unlocked database
	//
	NSString *pushToken = self.pushToken;
	
	if (!pushToken || !self.isDatabaseUnlocked)
	{
		return;
	}
	
	// When do we need to register the push token with the server ?
	// We certainly don't need to do this everytime.
	// We only need to do it if:
	// - we've never registered a push token for the user before
	// - the push token we got during this app launch is different than last time
	// - and just to be safe, we re-register it every 30 days
	
	NSDate *refreshEverySoOften = [NSDate dateWithTimeIntervalSinceNow:(-1 * 60 * 60 * 24 * 30)]; // 30 days
	
	// Debugging stub.
	// Use this to test push notification registrations.
	//
	NSDate *forceReregisterPushAfterDate = nil;
//	forceReregisterPushAfterDate = [NSDate dateFromRfc3339String:@"2018-07-20T00:00:00Z"];
	
	// Update our local users with push token (if changed)
	
	[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSMutableArray *localUsersToChange = [NSMutableArray array];
		
		[self.localUserManager enumerateLocalUsersWithTransaction: transaction
		                                               usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
		{
			if (localUser.canPerformSync)
			{
				BOOL needsRegisterPushToken = NO;
				
				if (!localUser.lastPushTokenRegistration ||
				    !localUser.pushToken ||
				   ![localUser.pushToken isEqualToString:pushToken])
				{
					needsRegisterPushToken = YES;
				}
				
				if (!needsRegisterPushToken && refreshEverySoOften &&
				    [refreshEverySoOften isAfter:localUser.lastPushTokenRegistration])
				{
					ZDCLogInfo(@"Forcing push notification refresh for: %@", localUser.displayName);
					needsRegisterPushToken = YES;
				}
				
				if (!needsRegisterPushToken && forceReregisterPushAfterDate &&
				    [forceReregisterPushAfterDate isAfter:localUser.lastPushTokenRegistration])
				{
					ZDCLogInfo(@"Forcing push notification (re)registration for: %@", localUser.displayName);
					needsRegisterPushToken = YES;
				}
				
				if (needsRegisterPushToken) {
					[localUsersToChange addObject:localUser];
				}
			}
		}];
		
		for (ZDCLocalUser *localUser in localUsersToChange)
		{
			// The process of registering the push token with the server is an async task.
			// And it requires internet connectivity.
			// So all we have to do is set the `needsRegisterPushToken` flag on the user,
			// and the YapDatabaseActionManager handles the rest for us.
			//
			// Here's how that works:
			// 1. The DatabaseManager registers a YapDatabaseActionManager extension with the database.
			//    This is done in `-[ZDCDatabaseManager setupActionManager]`.
			//
			//    The extension uses its own custom "scheduler" so that it won't interfere with your app,
			//    should you choose to register your own YapDatabaseActionManager extension for yourself.
			//
			// 2. The custom "scheduler" is run everytime an object is added / modified within the database.
			//    The scheduler code is in `-[ZDCDatabaseManager actionManagerScheduler]`.
			//
			//    The scheduler sets up a task to be performed if ZDCLocalUser.needsRegisterPushToken is true.
			//    The task has the `requiresInternet` flag set to true,
			//    so the ActionManager knows not to fire the task if there's no internet connectivity.
			//
			// 3. When the ActionManager fires the task,
			//    the `-[ZDCDatabaseManager action_localUser_registerPushToken]` method gets run.
			//
			//    This method attempts to register the token with the server.
			//    If successful, it unsets the `needsRegisterPushToken` flag on the ZDCLocalUser.
			//    Which causes the actionManager task to get deleted.
			//
			// Long story short:
			//    The ActionManager is a way in which we can persist (to disk) actions that need to get completed.
			//    Since these actions are asynchronous, and require Internet connectivity etc,
			//    we can't depend on them getting completed during this app launch.
			//    So persisting them to disk, and using a system that will automatically trigger
			//    the actions (even on temporary failures, or subsequent app launches) is useful and more reliable.
			
			ZDCLocalUser *updatedLocalUser = [localUser copy];
			updatedLocalUser.pushToken              = pushToken;
			updatedLocalUser.needsRegisterPushToken = YES;
			
			[transaction setObject: updatedLocalUser
			                forKey: updatedLocalUser.uuid
			          inCollection: kZDCCollection_Users];
		}
	}];
}

#if TARGET_OS_IOS
/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (BOOL)didReceiveRemoteNotification:(NSDictionary *)apnsDict
              fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
	ZDCPushInfo *pushInfo = [ZDCPushInfo parsePushInfo:apnsDict];
	if (!pushInfo)
	{
		// Push notification doesn't apply to us
		return NO;
	}
	
	[self processPushNotification: pushInfo
	              completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	              completionBlock:^(BOOL newData, BOOL failed)
	{
		UIBackgroundFetchResult result =
		  newData ? UIBackgroundFetchResultNewData
		    : (failed ? UIBackgroundFetchResultFailed : UIBackgroundFetchResultNoData);
		
		completionHandler(result);
	}];
	
	return YES;
}
#else
/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (BOOL)didReceiveRemoteNotification:(NSDictionary *)apnsDict
{
	ZDCPushInfo *pushInfo = [ZDCPushInfo parsePushInfo:apnsDict];
	if (!pushInfo)
	{
		// Push notification doesn't apply to us
		return NO;
	}
	
	[self processPushNotification: pushInfo
	              completionQueue: nil
	              completionBlock: nil];
	
	return YES;
}
#endif

- (void)processPushNotification:(ZDCPushInfo *)pushInfo
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable void (^)(BOOL newData, BOOL failed))completionBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(pushInfo != nil);
	
	void (^InvokeCompletionBlock)(BOOL, BOOL) = ^(BOOL newData, BOOL failed){
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(newData, failed);
			}});
		}
	};
	
	if (!self.isDatabaseUnlocked)
	{
		// Can't access the database yet, so there's nothing we can currently do about the notification.
		// Not to fear though - this change is sitting on the server in our queue.
		// So the next pull will deliver this same notification to us, and we'll process it then.
		
		InvokeCompletionBlock(/* newData:*/NO, /* failed:*/NO);
		return;
	}
	
	NSString *localUserID = pushInfo.localUserID;
	if (localUserID == nil)
	{
		// Push notification is invalid !
		
		InvokeCompletionBlock(/* newData:*/NO, /* failed:*/NO);
		return;
	}
	
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	
	__block ZDCLocalUser *localUser = nil;
	[self.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		if (user.isLocal) {
			localUser = (ZDCLocalUser *)user;
		}
		
	} completionQueue:backgroundQueue completionBlock:^{
		
		if (!localUser)
		{
			// We received a push notification for a user that's no longer logged-in on this device.
			// We need to unregister for pushes for this unknown user.
		
			YapDatabaseConnection *rwConnection = self.databaseManager.rwDatabaseConnection;
			[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				__block BOOL taskAlreadyExists = NO;
				[transaction enumerateKeysAndObjectsInCollection: kZDCCollection_Tasks
				                                      usingBlock:^(NSString *key, id object, BOOL *stop)
				{
					if ([object isKindOfClass:[ZDCTask_UnregisterPushToken class]])
					{
						__unsafe_unretained ZDCTask_UnregisterPushToken *task = object;
						if ([task.userID isEqualToString:localUserID])
						{
							taskAlreadyExists = YES;
							*stop = YES;
						}
					}
				}];
				
				if (!taskAlreadyExists)
				{
					ZDCTask_UnregisterPushToken *task =
					  [[ZDCTask_UnregisterPushToken alloc] initWithUserID: localUserID
					                                               region: AWSRegion_Invalid];
					
					[transaction setObject: task
					                forKey: task.uuid
					          inCollection: kZDCCollection_Tasks];
				}
				
			} completionQueue:backgroundQueue completionBlock:^{
				
				InvokeCompletionBlock(NO, NO);
			}];
		}
		else if (localUser.syncingPaused)
		{
			// We're ignoring the push notification because syncing is paused.
			// Thus, we're not allowed to perform any network IO for the user at this time.
			
			InvokeCompletionBlock(/* newData:*/NO, /* failed:*/NO);
		}
		else if (pushInfo.isActivation)
		{
		//	[self.localUserManager checkActivationForLocalUser: localUser
		//	                                   completionQueue: dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)
		//	                                   completionBlock:^(BOOL activationComplete, NSError *error)
		//	{
		//		BOOL newData = activationComplete;
		//		BOOL failed = (error != nil);
		//
		//		InvokeCompletionBlock(newData, failed);
		//	}];
		}
		else
		{
			[self.pushManager processPushNotification:pushInfo];
			
			[self.pullManager processPushNotification: pushInfo
			                          completionQueue: backgroundQueue
			                          completionBlock:^(BOOL needsPull)
			{
				if (needsPull)
				{
					void (^pullCompletionBlock)(ZDCPullResult) = ^(ZDCPullResult result){
						
						BOOL failed = (result != ZDCPullResult_Success);
						
						InvokeCompletionBlock(/* newData:*/YES, failed);
					};
					
					[self.syncManager enqueuePullCompletionQueue: backgroundQueue
					                             completionBlock: pullCompletionBlock
					                              forLocalUserID: localUserID];
					
					[self.syncManager pullChangesForLocalUserID:localUserID];
				}
				else
				{
					InvokeCompletionBlock(/* newData:*/NO, /* failed:*/NO);
				}
			}];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud Audit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if DEBUG

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZeroDarkCloud.html
 */
- (void)fetchAuditCredentials:(NSString *)localUserID
            completionHandler:(void (^)(ZDCAudit *_Nullable audit, NSError *_Nullable error))completionHandler
{
	if (completionHandler == nil) return;
	
	AWSCredentialsManager *aws = self.awsCredentialsManager;
	
	if (aws == nil)
	{
		NSString *msg = @"You must unlock the database first";
		NSError *error = [NSError errorWithClass:[self class] code:500 description:msg];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			completionHandler(nil, error);
		});
		return;
	}
	
	// We always want to give the caller fresh credentials.
	// Otherwise, we might end up giving them credentials that expire in 5 minutes.
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	[aws flushAWSCredentialsForUser: localUserID
	             deleteRefreshToken: NO
	                completionQueue: bgQueue
	                completionBlock:^
	{
		[aws getAWSCredentialsForUser: localUserID
		              completionQueue: bgQueue
		              completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					completionHandler(nil, error);
				});
				return;
			}
			
			__block ZDCLocalUser *localUser = nil;
			
			YapDatabaseConnection *roConnection = self.databaseManager.roDatabaseConnection;
			[roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
				
				localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
				
			} completionQueue:dispatch_get_main_queue() completionBlock:^{
				
				if (!localUser || ![localUser isKindOfClass:[ZDCLocalUser class]])
				{
					NSString *msg = @"You must first login to the given user's account.";
					NSError *error = [NSError errorWithClass:[self class] code:500 description:msg];
					
					completionHandler(nil, error);
					return;
				}
				
				NSString *regionStr = [AWSRegions shortNameForRegion:localUser.aws_region];
				
				ZDCAudit *audit =
				  [[ZDCAudit alloc] initWithLocalUserID: localUserID
				                                 region: regionStr
				                                 bucket: localUser.aws_bucket
				                            accessKeyID: auth.aws_accessKeyID
				                                 secret: auth.aws_secret
				                                session: auth.aws_session
				                             expiration: auth.aws_expiration];
				
				completionHandler(audit, nil);
			}];
		}];
	}];
}

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Background Networking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IOS

/**
 * Your AppDelegate should invoke this method in response to a
 * 'application:handleEventsForBackgroundURLSession:completionHandler:' message from the system.
 */
- (BOOL)handleEventsForBackgroundURLSession:(NSString *)sessionIdentifier
                          completionHandler:(void (^)(void))completionHandler
{
	ZDCLogAutoTrace();
	
	if (![sessionIdentifier hasPrefix:@"zdc:"]) {
		return NO;
	}
	
	dispatch_block_t block = ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (backgroundSessionCompletionHandlers == nil)
			backgroundSessionCompletionHandlers = [[NSMutableDictionary alloc] init];
	
		NSMutableArray *completionHandlers = backgroundSessionCompletionHandlers[sessionIdentifier];
		if (completionHandlers == nil)
		{
			completionHandlers = [[NSMutableArray alloc] init];
			backgroundSessionCompletionHandlers[sessionIdentifier] = completionHandlers;
		}
	
		[completionHandlers addObject:completionHandler];
		
		[self.sessionManager handleEventsForBackgroundURLSession:sessionIdentifier];
		
	#pragma clang diagnostic pop
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
	
	return YES;
}

- (void)invokeCompletionHandlerForBackgroundURLSession:(NSString *)sessionIdentifier
{
	ZDCLogAutoTrace();
	
	dispatch_block_t block = ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray *completionHandlers = backgroundSessionCompletionHandlers[sessionIdentifier];
		if (completionHandlers.count > 0)
		{
			dispatch_block_t completionHandler = [completionHandlers firstObject];
			completionHandler();
			
			[completionHandlers removeObjectAtIndex:0];
			if (completionHandlers.count == 0)
			{
				backgroundSessionCompletionHandlers[sessionIdentifier] = nil;
			}
		}
		
	#pragma clang diagnostic pop
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseCloudCorePipelineDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startOperation:(YapDatabaseCloudCoreOperation *)op
           forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	[self.pushManager startOperation:op forPipeline:pipeline];
}

@end
