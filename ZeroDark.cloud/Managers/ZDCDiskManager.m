/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCDiskManagerPrivate.h"

#import "ZDCLogging.h"
#import "ZDCUserPrivate.h"

// Categories
#import "NSData+S4.h"
#import "NSData+ZeroDark.h"
#import "NSDate+ZeroDark.h"
#import "NSError+ZeroDark.h"

// Libraries
#import <sys/xattr.h>
#import <YapDatabase/YapCollectionKey.h>
#import <YapDatabase/YapDatabaseAtomic.h>
#import <YapDatabase/YapSet.h>

@class ZDCFileInfo;
@class ZDCFileRetainToken;

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int ddLogLevel = DDLogLevelInfo;
#elif DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif

/* extern */ NSString *const ZDCDiskManagerChangedNotification = @"ZDCDiskManagerChanged";
/* extern */ NSString *const kZDCDiskManagerChanges            = @"changes";

typedef NS_ENUM(NSInteger, ZDCStorageMode) {
	ZDCStorageMode_Persistent,
	ZDCStorageMode_Cache
};

typedef NS_ENUM(NSInteger, ZDCFileType) {
	ZDCFileType_NodeData,
	ZDCFileType_NodeThumbnail,
	ZDCFileType_UserAvatar
};

static NSString *const kSubDirectoryName_NodeData       = @"nodeData";
static NSString *const kSubDirectoryName_NodeThumbnails = @"nodeThumbnails";
static NSString *const kSubDirectoryName_UserAvatars    = @"userAvatars";

static NSString *const kSubDirectoryName_CacheFile = @"cachefile";
static NSString *const kSubDirectoryName_Cloudfile = @"cloudfile";

static NSString *const kXattrName_maxCacheSize       = @"ZeroDark.cloud:maxCacheSize";
static NSString *const kXattrName_migrateAfterUpload = @"ZeroDark.cloud:migrate";
static NSString *const kXattrName_deleteAfterUpload  = @"ZeroDark.cloud:delete";
static NSString *const kXattrName_expiration         = @"ZeroDark.cloud:expiration";
static NSString *const kXattrName_eTag               = @"ZeroDark.cloud:eTag"; // xattr value is encrypted

static NSUInteger const kDefaultConfiguration_maxNodeDataCacheSize       = (1024 * 1024 * 25); // 25 MiB
static NSUInteger const kDefaultConfiguration_maxNodeThumbnailsCacheSize = (1024 * 1024 * 5);  //  5 MiB
static NSUInteger const kDefaultConfiguration_maxUserAvatarsCacheSize    = (1024 * 1024 * 5);  //  5 MiB

static NSTimeInterval const kDefaultConfiguration_nodeDataExpiration      = 0;
static NSTimeInterval const kDefaultConfiguration_nodeThumbnailExpiration = 0;
static NSTimeInterval const kDefaultConfiguration_userAvatarExpiration    = (60 * 60 * 24 * 7);

@interface ZDCDiskManager () <NSFileManagerDelegate>

- (void)decrementRetainCountForInfo:(ZDCFileInfo *)info;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCDiskExport ()

- (instancetype)initWithCryptoFile:(nullable ZDCCryptoFile *)cryptoFile
                      isPersistent:(BOOL)isPersistent
                              eTag:(nullable NSString *)eTag
                        expiration:(NSTimeInterval)expiration;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCDiskManagerChanges ()

@property (nonatomic, readwrite, copy) NSSet<NSString*> *changedNodeIDs;
@property (nonatomic, readwrite, copy) NSSet<NSString*> *changedNodeData;
@property (nonatomic, readwrite, copy) NSSet<NSString*> *changedNodeThumbnails;
@property (nonatomic, readwrite, copy) NSSet<NSString*> *changedUsersIDs;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCFileInfo : NSObject

- (instancetype)initWithMode:(ZDCStorageMode)mode
                        type:(ZDCFileType)type
                      format:(ZDCCryptoFileFormat)format
                     fileURL:(NSURL *)fileURL;

@property (nonatomic, assign, readonly) ZDCStorageMode mode;
@property (nonatomic, assign, readonly) ZDCFileType type;
@property (nonatomic, assign, readonly) ZDCCryptoFileFormat format;
@property (nonatomic, strong, readonly) NSURL *fileURL;

@property (nonatomic, copy, readwrite) NSString *nodeID;
@property (nonatomic, copy, readwrite) NSString *userID;
@property (nonatomic, copy, readwrite) NSString *auth0ID;

@property (nonatomic, assign, readwrite) uint64_t fileSize;
@property (nonatomic, strong, readwrite) NSDate *lastModified;
@property (nonatomic, strong, readwrite) NSDate *lastAccessed;

@property (nonatomic, assign, readwrite) BOOL migrateAfterUpload;
@property (nonatomic, assign, readwrite) BOOL deleteAfterUpload;
@property (nonatomic, assign, readwrite) NSTimeInterval expiration;
@property (nonatomic, copy, readwrite) id eTag; // NSString | NSNull

@property (nonatomic, assign, readonly) NSUInteger fileRetainCount;
@property (nonatomic, assign, readwrite) BOOL pendingDelete;

@property (nonatomic, readonly) BOOL isStoredPersistently;

- (NSUInteger)decrementFileRetainCount;
- (NSUInteger)incrementFileRetainCount;

- (BOOL)matchesMode:(ZDCStorageMode)mode
               type:(ZDCFileType)type
             format:(ZDCCryptoFileFormat)format;

- (BOOL)matchesMode:(ZDCStorageMode)mode
               type:(ZDCFileType)type
             format:(ZDCCryptoFileFormat)format
            auth0ID:(NSString *)auth0ID;

/**
 * Similar to a copy, but does NOT include fileRetainCount or pendingDelete.
 */
- (instancetype)duplicateWithMode:(ZDCStorageMode)mode fileURL:(NSURL *)fileURL;

@end

@implementation ZDCFileInfo

@synthesize mode = mode;
@synthesize type = type;
@synthesize format = format;
@synthesize fileURL = fileURL;

@synthesize nodeID = nodeID;
@synthesize userID = userID;
@synthesize auth0ID = auth0ID;

@synthesize fileSize = fileSize;
@synthesize lastModified = lastModified;
@synthesize lastAccessed = lastAccessed;

@synthesize migrateAfterUpload = migrateAfterUpload;
@synthesize deleteAfterUpload = deleteAfterUpload;
@synthesize expiration = expiration;
@synthesize eTag = eTag;

@synthesize fileRetainCount = fileRetainCount;
@synthesize pendingDelete;

@dynamic isStoredPersistently;

- (instancetype)initWithMode:(ZDCStorageMode)inMode
                        type:(ZDCFileType)inType
                      format:(ZDCCryptoFileFormat)inFrmt
                     fileURL:(NSURL *)inURL
{
	if ((self = [super init]))
	{
		mode = inMode;
		type = inType;
		format = inFrmt;
		fileURL = inURL;
	}
	return self;
}

- (BOOL)isStoredPersistently
{
	if (pendingDelete) return NO;
	
	return (mode == ZDCStorageMode_Persistent);
}

- (NSUInteger)decrementFileRetainCount
{
	// We don't need locks here because ZDCFileInfo instances are
	// only accessed/modified from within ZDCDiskManager.cacheQueue (serial dispatch_queue_t).
	// So access is already serialized externally.
	
	if (fileRetainCount > 0) {
		fileRetainCount--;
	}
	return fileRetainCount;
}

- (NSUInteger)incrementFileRetainCount
{
	// We don't need locks here because ZDCFileInfo instances are
	// only accessed/modified from within ZDCDiskManager.cacheQueue (serial dispatch_queue_t).
	// So access is already serialized externally.
	
	if (fileRetainCount < NSUIntegerMax) {
		fileRetainCount++;
	}
	return fileRetainCount;
}

- (BOOL)matchesMode:(ZDCStorageMode)inMode
               type:(ZDCFileType)inType
             format:(ZDCCryptoFileFormat)inFormat
{
	if (mode != inMode) return NO;
	if (type != inType) return NO;
	if (format != inFormat) return NO;
	
	return YES;
}

- (BOOL)matchesMode:(ZDCStorageMode)inMode
               type:(ZDCFileType)inType
             format:(ZDCCryptoFileFormat)inFormat
            auth0ID:(NSString *)inAuth0ID
{
	if (mode != inMode) return NO;
	if (type != inType) return NO;
	if (format != inFormat) return NO;
	
	if (auth0ID)
	{
		if (inAuth0ID)
			return [auth0ID isEqualToString:inAuth0ID];
		else
			return NO;
	}
	else
	{
		if (inAuth0ID)
			return NO;
		else
			return YES;
	}
}

- (instancetype)duplicateWithMode:(ZDCStorageMode)inMode fileURL:(NSURL *)inFileURL
{
	ZDCFileInfo *dup = [[ZDCFileInfo alloc] initWithMode:inMode type:type format:format fileURL:inFileURL];
	
	dup->nodeID = self->nodeID;
	dup->userID = self->userID;
	dup->auth0ID = self->auth0ID;
	
	dup->fileSize = self->fileSize;
	dup->lastModified = self->lastModified;
	dup->lastAccessed = self->lastAccessed;
	
	dup->migrateAfterUpload = self->migrateAfterUpload;
	dup->deleteAfterUpload = self->deleteAfterUpload;
	dup->expiration = self->expiration;
	dup->eTag = self->eTag;
	
	return dup;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCFileRetainToken : NSObject

- (instancetype)initWithInfo:(ZDCFileInfo *)info owner:(ZDCDiskManager *)owner;

@end

@implementation ZDCFileRetainToken
{
	__strong ZDCFileInfo *info;
	__weak ZDCDiskManager *owner;
}

- (instancetype)initWithInfo:(ZDCFileInfo *)inInfo owner:(ZDCDiskManager *)inOwner
{
	if ((self = [super init]))
	{
		info = inInfo;
		owner = inOwner;
	}
	return self;
}

- (void)dealloc
{
	[owner decrementRetainCountForInfo:info];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDiskManager
{
	__weak ZeroDarkCloud *zdc;
	
	dispatch_queue_t cacheQueue;
	void *IsOnCacheQueueKey;
	
	dispatch_queue_t refreshQueue;
	void *IsOnRefreshQueueKey;
	
	NSFileManager *fileManager;
	
	NSURL *persistentContainerURL;
	NSURL *cacheContainerURL;
	
	NSMutableArray<ZDCFilesystemMonitor*> *monitors;
	
	// The following variables can only be read/modified within cacheQueue:
	
	NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict_nodeData;       // key: nodeID
	NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict_nodeThumbnails; // key: nodeID
	NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict_userAvatars;    // key: userID
	
	NSMutableSet<NSString*> *changes_nodeData;       // nodeID's
	NSMutableSet<NSString*> *changes_nodeThumbnails; // nodeID's
	NSMutableSet<NSString*> *changes_userAvatars;    // userID's
	
	NSSet<NSString*> *uploadQueue_nodeIDs;
	
	BOOL notificationPending;
	
	dispatch_source_t expirationTimer;
	BOOL expirationTimerSuspended;
	NSDate *nextExpirationDate;
	NSDate *nextExpirationDate_nodeData;
	NSDate *nextExpirationDate_nodeThumbnails;
	NSDate *nextExpirationDate_userAvatars;
	
	YAPUnfairLock spinlock;
	NSMutableSet<NSURL*> *pendingRefresh;
}

@dynamic maxNodeDataCacheSize;
@dynamic maxNodeThumbnailsCacheSize;
@dynamic maxUserAvatarsCacheSize;

@dynamic defaultNodeDataCacheExpiration;
@dynamic defaultNodeThumbnailCacheExpiration;
@dynamic defaultUserAvatarCacheExpiration;

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.diskManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		cacheQueue   = dispatch_queue_create("DiskManager_cache", DISPATCH_QUEUE_SERIAL);
		refreshQueue = dispatch_queue_create("DiskManager_refresh", DISPATCH_QUEUE_SERIAL);
		
		IsOnCacheQueueKey = &IsOnCacheQueueKey;
		dispatch_queue_set_specific(cacheQueue, IsOnCacheQueueKey, IsOnCacheQueueKey, NULL);
		
		IsOnRefreshQueueKey = &IsOnRefreshQueueKey;
		dispatch_queue_set_specific(refreshQueue, IsOnRefreshQueueKey, IsOnRefreshQueueKey, NULL);
		
		fileManager = [[NSFileManager alloc] init];
		fileManager.delegate = self;
		
		NSString *databaseName = [zdc.databasePath lastPathComponent];
		persistentContainerURL = [ZDCDirectoryManager zdcPersistentDirectoryForDatabaseName:databaseName];
		cacheContainerURL      = [ZDCDirectoryManager zdcCacheDirectoryForDatabaseName:databaseName];
		
		dict_nodeData       = [[NSMutableDictionary alloc] init];
		dict_nodeThumbnails = [[NSMutableDictionary alloc] init];
		dict_userAvatars    = [[NSMutableDictionary alloc] init];
		
		changes_nodeData       = [[NSMutableSet alloc] init];
		changes_nodeThumbnails = [[NSMutableSet alloc] init];
		changes_userAvatars    = [[NSMutableSet alloc] init];
		
		notificationPending = NO;
		
		spinlock = YAP_UNFAIR_LOCK_INIT;
		pendingRefresh = [[NSMutableSet alloc] init];
		
	#if TARGET_OS_IPHONE && !TARGET_EXTENSION
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(applicationWillEnterForeground:)
		                                             name: UIApplicationWillEnterForegroundNotification
		                                           object: [UIApplication sharedApplication]];
	#endif
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(databaseModified:)
		                                             name: YapDatabaseModifiedNotification
		                                           object: zdc.databaseManager.database];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(pipelineQueueChanged:)
		                                             name: YDBCloudCorePipelineQueueChangedNotification
		                                           object: nil];
		
		// Prepare directories,
		// and populate cache with whatever we find on the file system.
		
		dispatch_async(cacheQueue, ^{ @autoreleasepool {
			
			NSArray<NSArray*> *list = @[
				@[ @(ZDCStorageMode_Persistent), @(ZDCFileType_NodeData),      @(ZDCCryptoFileFormat_CacheFile) ],
				@[ @(ZDCStorageMode_Persistent), @(ZDCFileType_NodeData),      @(ZDCCryptoFileFormat_CloudFile) ],
				@[ @(ZDCStorageMode_Cache),      @(ZDCFileType_NodeData),      @(ZDCCryptoFileFormat_CacheFile) ],
				@[ @(ZDCStorageMode_Cache),      @(ZDCFileType_NodeData),      @(ZDCCryptoFileFormat_CloudFile) ],
				@[ @(ZDCStorageMode_Persistent), @(ZDCFileType_NodeThumbnail), @(ZDCCryptoFileFormat_CacheFile) ],
				@[ @(ZDCStorageMode_Cache),      @(ZDCFileType_NodeThumbnail), @(ZDCCryptoFileFormat_CacheFile) ],
				@[ @(ZDCStorageMode_Persistent), @(ZDCFileType_UserAvatar),    @(ZDCCryptoFileFormat_CacheFile) ],
				@[ @(ZDCStorageMode_Cache),      @(ZDCFileType_UserAvatar),    @(ZDCCryptoFileFormat_CacheFile) ],
			];
			
			[self createDirectories:list];
			[self setupFilesystemMonitors:list];
			
			[self scanCacheDirectories];
			[self scanOfflineDirectories];
			
			[self launchCleanup];
		}});
	}
	return self;
}

- (void)dealloc
{
	[monitors removeAllObjects];
	
	// Deallocating a suspended timer will cause a crash
	if (expirationTimer && expirationTimerSuspended)
	{
		expirationTimerSuspended = NO;
		dispatch_resume(expirationTimer);
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark URL Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSURL *)URLForMode:(ZDCStorageMode)mode type:(ZDCFileType)type format:(ZDCCryptoFileFormat)format
{
	if (format == ZDCCryptoFileFormat_Unknown) {
		return nil;
	}
	
	switch (type)
	{
		case ZDCFileType_NodeData:
		{
			NSURL *parent = (mode == ZDCStorageMode_Persistent) ? persistentContainerURL : cacheContainerURL;
			NSURL *anchor = [parent URLByAppendingPathComponent:kSubDirectoryName_NodeData isDirectory:YES];
			
			NSString *subDirName = nil;
			switch (format)
			{
				case ZDCCryptoFileFormat_CacheFile : subDirName = kSubDirectoryName_CacheFile; break;
				case ZDCCryptoFileFormat_CloudFile : subDirName = kSubDirectoryName_Cloudfile; break;
				default : break;
			}
			
			return [anchor URLByAppendingPathComponent:subDirName isDirectory:YES];
		}
		case ZDCFileType_NodeThumbnail:
		{
			NSURL *parent = (mode == ZDCStorageMode_Persistent) ? persistentContainerURL : cacheContainerURL;
			NSURL *anchor = [parent URLByAppendingPathComponent:kSubDirectoryName_NodeThumbnails isDirectory:YES];
			
			switch (format)
			{
				case ZDCCryptoFileFormat_CacheFile : return anchor;
				default                            : return nil;
			}
		}
		case ZDCFileType_UserAvatar:
		{
			NSURL *parent = (mode == ZDCStorageMode_Persistent) ? persistentContainerURL : cacheContainerURL;
			NSURL *anchor = [parent URLByAppendingPathComponent:kSubDirectoryName_UserAvatars isDirectory:YES];
			
			switch (format)
			{
				case ZDCCryptoFileFormat_CacheFile : return anchor;
				default                            : return nil;
			}
		}
	}
	
	return nil;
}

- (BOOL)getMode:(ZDCStorageMode *)modePtr
           type:(ZDCFileType *)typePtr
         format:(ZDCCryptoFileFormat *)formatPtr
     forFileURL:(NSURL *)fileURL
{
	NSURL *parentURL = [fileURL URLByDeletingLastPathComponent];
	NSString *parentName = [parentURL lastPathComponent];
	
	ZDCStorageMode mode = ZDCStorageMode_Cache;
	ZDCFileType type = ZDCFileType_NodeData;
	ZDCCryptoFileFormat format = ZDCCryptoFileFormat_Unknown;
	
	if (!parentURL || !parentName)
	{
		if (modePtr) *modePtr = mode;
		if (typePtr) *typePtr = type;
		if (formatPtr) *formatPtr = format;
		return NO;
	}
	
	NSURL *containerURL = nil;
	
	if ([parentName caseInsensitiveCompare:kSubDirectoryName_CacheFile] == NSOrderedSame)
	{
		NSURL *grandParentURL = [parentURL URLByDeletingLastPathComponent];
		NSString *grandParentName = [grandParentURL lastPathComponent];
		
		if (grandParentName && [grandParentName caseInsensitiveCompare:kSubDirectoryName_NodeData] == NSOrderedSame)
		{
			// Path is: /<?>/nodeData/cachefile/<filename>
			
			format = ZDCCryptoFileFormat_CacheFile;
			type = ZDCFileType_NodeData;
			
			// We still need to know if <?> is either:
			// - cacheContainerURL
			// - persistentContainerURL
			
			containerURL = [grandParentURL URLByDeletingLastPathComponent];
		}
	}
	else if ([parentName caseInsensitiveCompare:kSubDirectoryName_Cloudfile] == NSOrderedSame)
	{
		NSURL *grandParentURL = [parentURL URLByDeletingLastPathComponent];
		NSString *grandParentName = [grandParentURL lastPathComponent];
		
		if (grandParentName && [grandParentName caseInsensitiveCompare:kSubDirectoryName_NodeData] == NSOrderedSame)
		{
			// Path is: /<?>/nodeData/cloudfile/<filename>
			
			format = ZDCCryptoFileFormat_CloudFile;
			type = ZDCFileType_NodeData;
			
			// We still need to know if <?> is either:
			// - cacheContainerURL
			// - persistentContainerURL
			
			containerURL = [grandParentURL URLByDeletingLastPathComponent];
		}
	}
	else if ([parentName caseInsensitiveCompare:kSubDirectoryName_NodeThumbnails] == NSOrderedSame)
	{
		// Path is? /<?>/nodeThumbnails/<filename>
		
		format = ZDCCryptoFileFormat_CacheFile;
		type = ZDCFileType_NodeThumbnail;
		
		// We still need to know if <?> is either:
		// - cacheContainerURL
		// - persistentContainerURL
		
		containerURL = [parentURL URLByDeletingLastPathComponent];
	}
	else if ([parentName caseInsensitiveCompare:kSubDirectoryName_UserAvatars] == NSOrderedSame)
	{
		// Path is? /<?>/avatars/<filename>
		
		format = ZDCCryptoFileFormat_CacheFile;
		type = ZDCFileType_UserAvatar;
		
		// We still need to know if <?> is either:
		// - cacheContainerURL
		// - persistentContainerURL
		
		containerURL = [parentURL URLByDeletingLastPathComponent];
	}
	
	BOOL result = NO;
	
	if (containerURL)
	{
		if ([containerURL isEqual:cacheContainerURL])
		{
			mode = ZDCStorageMode_Cache;
			result = YES;
		}
		else if ([containerURL isEqual:persistentContainerURL])
		{
			mode = ZDCStorageMode_Persistent;
			result = YES;
		}
		else
		{
			// NSURL might be misbehaving.
			// When this happens we resort to comparing iNodes.
			
			id iNode = nil;
			[containerURL getResourceValue:&iNode forKey:NSURLFileResourceIdentifierKey error:nil];
			
			id c_iNode = nil;
			[cacheContainerURL removeCachedResourceValueForKey:NSURLFileResourceIdentifierKey];
			[cacheContainerURL getResourceValue:&c_iNode forKey:NSURLFileResourceIdentifierKey error:nil];
			
			if ([iNode isEqual:c_iNode])
			{
				mode = ZDCStorageMode_Cache;
				result = YES;
			}
			else
			{
				id p_iNode = nil;
				[persistentContainerURL removeCachedResourceValueForKey:NSURLFileResourceIdentifierKey];
				[persistentContainerURL getResourceValue:&p_iNode forKey:NSURLFileResourceIdentifierKey error:nil];
				
				if ([iNode isEqual:p_iNode])
				{
					mode = ZDCStorageMode_Persistent;
					result = YES;
				}
			}
		}
	}
	
	if (modePtr) *modePtr = mode;
	if (typePtr) *typePtr = type;
	if (formatPtr) *formatPtr = format;
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications - Incoming
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if TARGET_OS_IPHONE && !TARGET_EXTENSION
- (void)applicationWillEnterForeground:(NSNotification *)notification
{
	[self scanCacheDirectories];
}
#endif

- (void)databaseModified:(NSNotification *)notification
{
	YapSet *deletedItems = notification.userInfo[YapDatabaseRemovedKeysKey];
	YapSet *modifiedItems = notification.userInfo[YapDatabaseObjectChangesKey];
	
	if (deletedItems.count > 0)
	{
		__block NSMutableArray<NSString*> *deletedNodeIDs = nil;
		__block NSMutableArray<NSString*> *deletedUserIDs = nil;
	
		for (YapCollectionKey *ck in deletedItems)
		{
			__unsafe_unretained NSString *collection = ck.collection;
	
			if ([collection isEqualToString:kZDCCollection_Nodes])
			{
				if (deletedNodeIDs == nil) {
					deletedNodeIDs = [NSMutableArray array];
				}
				[deletedNodeIDs addObject:ck.key];
			}
			else if ([collection isEqualToString:kZDCCollection_Users])
			{
				if (deletedUserIDs == nil) {
					deletedUserIDs = [NSMutableArray array];
				}
				[deletedUserIDs addObject:ck.key];
			}
		}
	
		if (deletedNodeIDs.count > 0)
		{
			[self deleteNodeDataForNodeIDs:deletedNodeIDs];
		}
		if (deletedUserIDs.count > 0)
		{
			[self deleteUserAvatarsForUserIDs:deletedUserIDs];
		}
	}
	
	if (modifiedItems.count > 0)
	{
		__block NSMutableArray<NSString*> *modifiedUserIDs = nil;
		
		for (YapCollectionKey *ck in deletedItems)
		{
			__unsafe_unretained NSString *collection = ck.collection;
			
			if ([collection isEqualToString:kZDCCollection_Users])
			{
				if (modifiedUserIDs == nil) {
					modifiedUserIDs = [NSMutableArray array];
				}
				[modifiedUserIDs addObject:ck.key];
			}
		}
		
		if (modifiedUserIDs.count > 0)
		{
			NSMutableDictionary<NSString*, NSSet<NSString*> *> *auth0IDs =
			  [NSMutableDictionary dictionaryWithCapacity:modifiedUserIDs.count];
			
			__weak typeof(self) weakSelf = self;
			[zdc.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
				
				for (NSString *userID in modifiedUserIDs)
				{
					ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
					if (user)
					{
						NSDictionary *profiles = user.auth0_profiles;
						if (profiles)
						{
							auth0IDs[userID] = [NSSet setWithArray:[profiles allKeys]];
						}
					}
				}
				
			} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
				
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf == nil) return;
				
				for (NSString *userID in auth0IDs)
				{
					[strongSelf deleteUserAvatars:userID excluding:auth0IDs[userID]];
				}
			}];
		}
	}
}

- (void)pipelineQueueChanged:(NSNotification *)notification
{
	YapDatabaseCloudCorePipeline *pipeline = (YapDatabaseCloudCorePipeline *)notification.object;
	YapDatabaseCloudCore *cloudCore = pipeline.owner;
	
	if (![cloudCore isKindOfClass:[ZDCCloud class]]) {
		return;
	}
	
	NSMutableSet<NSString*> *nodeIDs = [NSMutableSet set];
	
	[pipeline enumerateOperationsUsingBlock:
	^(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
		
		if (op.nodeID &&
		   (op.type == ZDCCloudOperationType_Put) &&
		   (op.putType == ZDCCloudOperationPutType_Node_Data))
		{
			[nodeIDs addObject:op.nodeID];
		}
	}];
	
	__weak typeof(self) weakSelf = self;
	dispatch_async(cacheQueue, ^{ @autoreleasepool {
		
		[weakSelf migrateOrDeleteAfterUpload:nodeIDs];
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications - Outgoing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)postDiskManagerChangedNotification
{
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	if (notificationPending) {
		return; // already dispatched, still pending execution
	}
	notificationPending = YES;
	
	dispatch_async(dispatch_get_main_queue(), ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		__block ZDCDiskManagerChanges *changes = nil;
		
		dispatch_sync(cacheQueue, ^{ @autoreleasepool {

			if (changes_nodeData.count       > 0 ||
			    changes_nodeThumbnails.count > 0 ||
			    changes_userAvatars.count    > 0)
			{
				changes = [[ZDCDiskManagerChanges alloc] init];
				
				changes.changedNodeIDs = [changes_nodeData setByAddingObjectsFromSet:changes_nodeThumbnails];
				changes.changedNodeData = [changes_nodeData copy];
				changes.changedNodeThumbnails = [changes_nodeThumbnails copy];
				changes.changedUsersIDs = [changes_userAvatars copy];
				
				[changes_nodeData removeAllObjects];
				[changes_nodeThumbnails removeAllObjects];
				[changes_userAvatars removeAllObjects];
			}
			
			notificationPending = NO;
		}});
		
		if (changes)
		{
			NSDictionary *userInfo = @{ kZDCDiskManagerChanges : changes };
			
			[[NSNotificationCenter defaultCenter] postNotificationName: ZDCDiskManagerChangedNotification
			                                                    object: self
			                                                  userInfo: userInfo];
		}
		
	#pragma clang diagnostic pop
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSFileManagerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)fileManager:(NSFileManager *)fileManager shouldProceedAfterError:(NSError *)error
                                                         movingItemAtURL:(NSURL *)srcURL
                                                                   toURL:(NSURL *)dstURL
{
	// Error code for: The operation couldn’t be completed. File exists
	if ([error code] == NSFileWriteFileExistsError)
		return YES;
	else
		return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)createDirectories:(NSArray<NSArray *> *)list
{
	for (NSArray *tuple in list)
	{
		ZDCStorageMode mode        = [tuple[0] integerValue];
		ZDCFileType type           = [tuple[1] integerValue];
		ZDCCryptoFileFormat format = [tuple[2] integerValue];
		
		NSURL *url = [self URLForMode:mode type:type format:format];
		NSAssert(url != nil, @"Bad <mode, type, format> tuple");
	
		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtURL: url
		                         withIntermediateDirectories: YES
		                                          attributes: nil
		                                               error: &error];
	
		if (error) {
			DDLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
	}
}

- (void)setupFilesystemMonitors:(NSArray<NSArray *> *)list
{
	monitors = [NSMutableArray arrayWithCapacity:list.count];
	
	__weak typeof(self) weakSelf = self;
	for (NSArray *tuple in list)
	{
		ZDCStorageMode mode        = [tuple[0] integerValue];
		ZDCFileType type           = [tuple[1] integerValue];
		ZDCCryptoFileFormat format = [tuple[2] integerValue];
		
		NSURL *url = [self URLForMode:mode type:type format:format];
		
		ZDCFilesystemMonitor *monitor = [[ZDCFilesystemMonitor alloc] initWithDirectoryURL:url];
		
		[monitor monitorWithMask: [ZDCFilesystemMonitor vnode_flags_all]
		                   queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
		                   block:^(dispatch_source_vnode_flags_t mask)
		{
			[weakSelf scanDirectoryWithMode:mode type:type format:format];
		}];
		
		[monitors addObject:monitor];
	}
}

- (void)scanCacheDirectories
{
	// cache + nodeData      + cacheFile
	// cache + nodeData      + cloudFile
	// cache + nodeThumbnail + cacheFile
	// cache + userAvatar    + cacheFile
	
	[self scanDirectoryWithMode: ZDCStorageMode_Cache
	                       type: ZDCFileType_NodeData
	                     format: ZDCCryptoFileFormat_CacheFile];
	
	[self scanDirectoryWithMode: ZDCStorageMode_Cache
	                       type: ZDCFileType_NodeData
	                     format: ZDCCryptoFileFormat_CloudFile];
	
	[self scanDirectoryWithMode: ZDCStorageMode_Cache
	                       type: ZDCFileType_NodeThumbnail
	                     format: ZDCCryptoFileFormat_CacheFile];
	
	[self scanDirectoryWithMode: ZDCStorageMode_Cache
	                       type: ZDCFileType_UserAvatar
	                     format: ZDCCryptoFileFormat_CacheFile];
}

- (void)scanOfflineDirectories
{
	// persistent + nodeData      + cacheFile
	// persistent + nodeData      + cloudFile
	// persistent + nodeThumbnail + cacheFile
	// persistent + userAvatar    + cacheFile
	
	[self scanDirectoryWithMode: ZDCStorageMode_Persistent
	                       type: ZDCFileType_NodeData
	                     format: ZDCCryptoFileFormat_CacheFile];
	
	[self scanDirectoryWithMode: ZDCStorageMode_Persistent
	                       type: ZDCFileType_NodeData
	                     format: ZDCCryptoFileFormat_CloudFile];
	
	[self scanDirectoryWithMode: ZDCStorageMode_Persistent
	                       type: ZDCFileType_NodeThumbnail
	                     format: ZDCCryptoFileFormat_CacheFile];
	
	[self scanDirectoryWithMode: ZDCStorageMode_Persistent
	                       type: ZDCFileType_UserAvatar
	                     format: ZDCCryptoFileFormat_CacheFile];
}

/**
 * Scans the corresponding directory, and ensures a ZDCFileInfo is created for each corresponding cached file.
 * Also deletes files from disk that no longer correspond to an item in the database.
 * And deletes ZDCFileInfo entries that no longer have a corresponding item on the file system.
**/
- (void)scanDirectoryWithMode:(ZDCStorageMode)mode type:(ZDCFileType)type format:(ZDCCryptoFileFormat)format
{
	DDLogAutoTrace();
	
	NSURL *directoryURL = [self URLForMode:mode type:type format:format];
	
	// This method can get called alot thanks to the disk monitors we have setup.
	// So we limit the number of passes per directory to one-at-a-time.
	//
	BOOL hasPendingRefresh = NO;
	YAPUnfairLockLock(&spinlock);
	{
		if ([pendingRefresh containsObject:directoryURL]) {
			hasPendingRefresh = YES;
		} else {
			[pendingRefresh addObject:directoryURL];
		}
	}
	YAPUnfairLockUnlock(&spinlock);
	
	if (hasPendingRefresh) {
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	dispatch_async(refreshQueue, ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		YAPUnfairLockLock(&strongSelf->spinlock);
		{
			[strongSelf->pendingRefresh removeObject:directoryURL];
		}
		YAPUnfairLockUnlock(&strongSelf->spinlock);
		
		NSDirectoryEnumerationOptions options =
		  NSDirectoryEnumerationSkipsSubdirectoryDescendants |
 		  NSDirectoryEnumerationSkipsPackageDescendants      |
		  NSDirectoryEnumerationSkipsHiddenFiles;
		
		NSArray<NSString *> *keys = @[
			NSURLFileSizeKey,
			NSURLContentAccessDateKey,
			NSURLContentModificationDateKey
		];
		
		NSDirectoryEnumerator<NSURL *> *enumerator =
		  [[NSFileManager defaultManager] enumeratorAtURL: directoryURL
		                       includingPropertiesForKeys: keys
		                                          options: options
		                                     errorHandler: NULL];
		
		NSMutableArray<ZDCFileInfo *> *infos = [NSMutableArray array];
		NSDate *now = [NSDate date];
		
		for (NSURL *url in enumerator)
		{
			ZDCFileInfo *info = [[ZDCFileInfo alloc] initWithMode:mode type:type format:format fileURL:url];
			
			NSNumber *fileSize = nil;
			[url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
			
			info.fileSize = [fileSize unsignedLongLongValue];
			
			NSDate *lastModified = nil;
			[url getResourceValue:&lastModified forKey:NSURLContentModificationDateKey error:nil];
			
			NSDate *lastAccessed = nil;
			[url getResourceValue:&lastAccessed forKey:NSURLContentAccessDateKey error:nil];
			
			info.lastModified = lastModified ?: now;
			
			// I read on the Twitters that 'NSURLContentAccessDateKey' may be broken on iOS.
			// So I'm guarding against that possibility to be safe.
			//
			info.lastAccessed = ZDCLaterDate(lastAccessed, lastModified) ?: now;
			
			info.migrateAfterUpload = [self shouldMigrateAfterUploadForURL:url];
			info.deleteAfterUpload = [self shouldDeleteAfterUploadForURL:url];
			
			NSTimeInterval expiration = 0;
			if ([strongSelf getExpiration:&expiration forURL:url]) {
				info.expiration = expiration;
			}
			
			[infos addObject:info];
		}
		
		if (type == ZDCFileType_NodeData || type == ZDCFileType_NodeThumbnail)
		{
			[strongSelf _updateNodeDictWithInfos: infos
			                                mode: mode
			                                type: type
			                              format: format];
		}
		else if (type == ZDCFileType_UserAvatar)
		{
			[strongSelf _updateUserDictWithInfos: infos
			                                mode: mode
			                                type: type
			                              format: format];
		}
		else
		{
			NSAssert(NO, @"Unrecognized type!");
		}
	}});
}

/**
 * Updates the underlying 'cache' with the given ZDCFileInfo entries
 * which were created from inspecting the file system.
 */
- (void)_updateNodeDictWithInfos:(NSArray<ZDCFileInfo *> *)onDiskInfos
                            mode:(ZDCStorageMode)mode
                            type:(ZDCFileType)type
                          format:(ZDCCryptoFileFormat)format
{
	DDLogAutoTrace();
	
	dispatch_async(cacheQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self" // Singleton
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict;
		if (type == ZDCFileType_NodeData) {
			dict = dict_nodeData;
		}
		else {
			dict = dict_nodeThumbnails;
		}
		
		NSMutableSet<NSString*> *unprocessedNodeIDs = [NSMutableSet setWithArray:[dict allKeys]];
		NSMutableSet<NSString*> *changedNodeIDs = [NSMutableSet set];
		
		// The 'infos' array represents every item that actually exists on the file system.
		// However, this is NOT every single file,
		// it's ONLY the files matching the given <directory, format> tuple.
		//
		// We need to do 2 things:
		// - Ensure there is a ZDCFileInfo entry for every given item.
		// - Delete every ZDCFileInfo entry that isn't represented in
		//   the given list (WITH THE SAME DIRECTORY & FORMAT).
		
		for (ZDCFileInfo *onDiskInfo in onDiskInfos)
		{
			NSString *nodeID = [onDiskInfo.fileURL lastPathComponent];
			if (nodeID == nil) {
				continue;
			}
			
			onDiskInfo.nodeID = nodeID;
			[unprocessedNodeIDs removeObject:nodeID];
			
			NSMutableArray<ZDCFileInfo *> *cachedInfos = dict[nodeID];
			if (cachedInfos == nil)
			{
				cachedInfos = [[NSMutableArray alloc] initWithCapacity:1];
				dict[nodeID] = cachedInfos;
			}
			
			ZDCFileInfo *matchingInfo = nil;
			for (ZDCFileInfo *existingInfo in cachedInfos)
			{
				if ([existingInfo matchesMode:mode type:type format:format])
				{
					matchingInfo = existingInfo;
				}
			}
			
			// If matchingInfo exists, then leave it be.
			// We need to preserve the following:
			// - info.fileRetainCount
			//
			if (matchingInfo)
			{
				matchingInfo.fileSize = onDiskInfo.fileSize;
				
				// Merge dates to give us a more accurate picture.
				//
				matchingInfo.lastAccessed = ZDCLaterDate(matchingInfo.lastAccessed, onDiskInfo.lastAccessed);
				matchingInfo.lastModified = ZDCLaterDate(matchingInfo.lastModified, onDiskInfo.lastModified);
			}
			else // if (matchingInfo == nil)
			{
				[cachedInfos addObject:onDiskInfo];
				[changedNodeIDs addObject:nodeID];
			}
		}
		
		// Delete any ZDCFileInfo entry that wasn't represented by the given list (with same directory & format).
		// These are files that were previously on disk, but have since been deleted.
		// This could be due to several different things:
		//
		// - The OS doing some file system maintenance, usually to make room when disk space gets low.
		// - The developer manually deleting the file(s).
		// - On macOS this may also just be the user deleting items in the filesystem.
		
		for (NSString *unprocessedNodeID in unprocessedNodeIDs)
		{
			NSMutableArray<ZDCFileInfo *> *cachedInfos = dict[unprocessedNodeID];
			
			NSUInteger matchingIndex = NSNotFound;
			NSUInteger i = 0;
			
			for (ZDCFileInfo *cachedInfo in cachedInfos)
			{
				if ([cachedInfo matchesMode:mode type:type format:format])
				{
					matchingIndex = i;
					break;
				}
				
				i++;
			}
			
			if (matchingIndex != NSNotFound)
			{
				[cachedInfos removeObjectAtIndex:matchingIndex];
				[changedNodeIDs addObject:unprocessedNodeID];
				
				if (cachedInfos.count == 0) {
					[dict removeObjectForKey:unprocessedNodeID];
				}
			}
		}
		
		if (changedNodeIDs.count > 0)
		{
			if (dict == dict_nodeData) {
				[changes_nodeData unionSet:changedNodeIDs];
			}
			else {
				[changes_nodeThumbnails unionSet:changedNodeIDs];
			}
			
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}});
}

/**
 * Updates the underlying 'cache' with the given ZDCFileInfo entries
 * which were created from inspecting the file system.
 */
- (void)_updateUserDictWithInfos:(NSArray<ZDCFileInfo *> *)onDiskInfos
                            mode:(ZDCStorageMode)mode
                            type:(ZDCFileType)type
                          format:(ZDCCryptoFileFormat)format
{
	DDLogAutoTrace();
	
	// Dispatch queue considerations:
	//
	// We are currently executing within the refreshQueue.
	// To update `dict_userAvatars`, we need to be executing within the cacheQueue.
	//
	// But before we can update the dict, we have a bunch of work to do.
	// The question is:
	// - Which queue do we perform the work on ?
	// - Or should we perform the work in some other queue ?
	//
	// We need to perform this work synchronously within the refreshQueue.
	// This is for 2 reasons:
	//
	// 1. We don't want to slow down the cacheQueue,
	//    which is meant to be used here as a light-weight lock/serialization-primitive.
	//
	// 2. The garbageCollection method makes some assumptions about when its safe to perform its task.
	//    And it doesn't expect any async tasks between the refreshQueue, and updating the dicts.
	//
	
	
	// The filenames are of the form: <user.random_uuid>.<hashed_auth0ID>
	
	NSMutableDictionary<NSString*, NSMutableSet<NSString*> *> *lookup = [NSMutableDictionary dictionary];
	
	for (ZDCFileInfo *info in onDiskInfos)
	{
		NSString *filename = [info.fileURL lastPathComponent];
		NSArray<NSString*> *components = [filename componentsSeparatedByString:@"."];
		
		if (components.count == 2)
		{
			NSString *random_uuid = components[0];
			NSString *hashed_auth0ID = components[1];
			
			NSMutableSet *hashes = lookup[random_uuid];
			if (hashes == nil)
			{
				hashes = [NSMutableSet set];
				lookup[random_uuid] = hashes;
			}
			
			[hashes addObject:hashed_auth0ID];
		}
	}
	
	// Now we need to create some mappings like so:
	//
	// - map_userID  : key(user.random_uuid) => value(user.uuid)
	// - map_auth0ID : key(hashed_auth0ID)   => value(auth0ID)
	
	NSMutableDictionary<NSString*, NSString*> *map_userID = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString*, NSString*> *map_auth0ID = [NSMutableDictionary dictionary];
	
	[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (NSString *random_uuid in lookup)
		{
			ZDCUser *user = [self findUserWithRandom:random_uuid transaction:transaction];
			if (user)
			{
				map_userID[random_uuid] = user.uuid;
				
				NSMutableSet *hashes = lookup[random_uuid];
				[self findAuth0IDsMatchingHashes:hashes forUser:user withMap:map_auth0ID];
			}
		}
	}];
	
	// Now we're going to put everything together for quick processing
	
	NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, ZDCFileInfo*> *> *onDiskInfosDict =
	  [NSMutableDictionary dictionaryWithCapacity:onDiskInfos.count];
	
	for (ZDCFileInfo *info in onDiskInfos)
	{
		NSString *filename = [info.fileURL lastPathComponent];
		NSArray<NSString*> *components = [filename componentsSeparatedByString:@"."];
		
		if (components.count == 2)
		{
			NSString *random_uuid = components[0];
			NSString *hashed_auth0ID = components[1];
			
			NSString *userID  = map_userID[random_uuid];
			NSString *auth0ID = map_auth0ID[hashed_auth0ID];
			
			if (userID && auth0ID)
			{
				NSMutableDictionary<NSString*, ZDCFileInfo*> *usersDict = onDiskInfosDict[userID];
				if (usersDict == nil)
				{
					usersDict = [[NSMutableDictionary alloc] init];
					onDiskInfosDict[userID] = usersDict;
				}
				
				info.userID = userID;
				info.auth0ID = auth0ID;
				
				usersDict[auth0ID] = info;
			}
		}
	}
	
	dispatch_async(cacheQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		
		NSMutableSet<NSString*> *unprocessedUserIDs = [NSMutableSet setWithArray:[dict allKeys]];
		NSMutableSet<NSString*> *changedUserIDs = [NSMutableSet set];
		
		for (NSString *userID in onDiskInfosDict)
		{
			[unprocessedUserIDs removeObject:userID];
			
			NSMutableArray<ZDCFileInfo *> *cachedInfos = dict[userID];
			if (cachedInfos == nil)
			{
				cachedInfos = [[NSMutableArray alloc] initWithCapacity:1];
				dict[userID] = cachedInfos;
			}
			
			NSMutableSet<NSString*> *unprocessedAuth0IDs = [NSMutableSet set];
			for (ZDCFileInfo *cachedInfo in cachedInfos)
			{
				if ([cachedInfo matchesMode:mode type:type format:format] && cachedInfo.auth0ID)
				{
					[unprocessedAuth0IDs addObject:cachedInfo.auth0ID];
				}
			}
			
			for (NSString *auth0ID in onDiskInfosDict[userID])
			{
				[unprocessedAuth0IDs removeObject:auth0ID];
				
				ZDCFileInfo *matchingInfo = nil;
				for (ZDCFileInfo *cachedInfo in cachedInfos)
				{
					if ([cachedInfo matchesMode:mode type:type format:format auth0ID:auth0ID])
					{
						matchingInfo = cachedInfo;
					}
				}
				
				ZDCFileInfo *onDiskInfo = onDiskInfosDict[userID][auth0ID];
				
				// If matchingInfo exists, then leave it be.
				// We need to preserve the following:
				// - info.fileRetainCount
				//
				if (matchingInfo)
				{
					matchingInfo.fileSize = onDiskInfo.fileSize;
					
					// Merge dates to give us a more accurate picture.
					//
					matchingInfo.lastAccessed = ZDCLaterDate(matchingInfo.lastAccessed, onDiskInfo.lastAccessed);
					matchingInfo.lastModified = ZDCLaterDate(matchingInfo.lastModified, onDiskInfo.lastModified);
				}
				else // if (matchingInfo == nil)
				{
					[cachedInfos addObject:onDiskInfo];
					[changedUserIDs addObject:userID];
				}
			}
			
			for (NSString *unprocessedAuth0ID in unprocessedAuth0IDs)
			{
				NSUInteger matchingIndex = NSNotFound;
				NSUInteger i = 0;
				
				for (ZDCFileInfo *cachedInfo in cachedInfos)
				{
					if ([cachedInfo matchesMode:mode type:type format:format auth0ID:unprocessedAuth0ID])
					{
						matchingIndex = i;
						break;
					}
					
					i++;
				}
				
				if (matchingIndex != NSNotFound)
				{
					[cachedInfos removeObjectAtIndex:matchingIndex];
					[changedUserIDs addObject:userID];
					
					if (cachedInfos.count == 0) {
						[dict removeObjectForKey:userID];
					}
				}
			}
		}
		
		for (NSString *unprocessedUserID in unprocessedUserIDs)
		{
			NSMutableArray<ZDCFileInfo*> *cachedInfos = dict[unprocessedUserID];
			
			NSUInteger i = 0;
			while (i < cachedInfos.count)
			{
				ZDCFileInfo *cachedInfo = cachedInfos[i];
				
				if ([cachedInfo matchesMode:mode type:type format:format /* auth0ID:ANY */ ])
				{
					[cachedInfos removeObjectAtIndex:i];
					[changedUserIDs addObject:unprocessedUserID];
				}
				else
				{
					i++;
				}
			}
			
			if (cachedInfos.count == 0) {
				[dict removeObjectForKey:unprocessedUserID];
			}
		}
		
		if (changedUserIDs.count > 0)
		{
			[changes_userAvatars unionSet:changedUserIDs];
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}});
}

/**
 * Invoked by retainTokens (during dealloc) in order to decrement the retainCount for the file.
**/
- (void)decrementRetainCountForInfo:(ZDCFileInfo *)infoToDecrement
{
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict;
		NSString *key = nil;
		
		ZDCFileType type = infoToDecrement.type;
		
		if (type == ZDCFileType_NodeData)
		{
			dict = dict_nodeData;
			key = infoToDecrement.fileURL.lastPathComponent; // nodeID
		}
		else if (type == ZDCFileType_NodeThumbnail)
		{
			dict = dict_nodeThumbnails;
			key = infoToDecrement.fileURL.lastPathComponent; // nodeID
		}
		else
		{
			dict = dict_userAvatars;
			key = infoToDecrement.userID;
		}
		
		BOOL shouldPostNotification = NO;
		
		NSMutableArray <ZDCFileInfo *> *infos = dict[key];
		if (infos)
		{
			ZDCStorageMode mode = infoToDecrement.mode;
			ZDCFileType type = infoToDecrement.type;
			ZDCCryptoFileFormat format = infoToDecrement.format;
			NSString *auth0ID = infoToDecrement.auth0ID;
			
			NSUInteger matchingIndex = NSNotFound;
			NSUInteger i = 0;
			
			for (ZDCFileInfo *info in infos)
			{
				if ([info matchesMode:mode type:type format:format auth0ID:auth0ID])
				{
					matchingIndex = i;
					break;
				}
				
				i++;
			}
			
			if (matchingIndex != NSNotFound)
			{
				ZDCFileInfo *matchingInfo = infos[matchingIndex];
				
				if ([matchingInfo decrementFileRetainCount] == 0 && matchingInfo.pendingDelete)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:matchingInfo.fileURL error:&error];
					
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [matchingInfo.fileURL path], error);
					}
					
					[infos removeObjectAtIndex:matchingIndex];
					shouldPostNotification = YES;
					
					if (infos.count == 0) {
						[dict removeObjectForKey:key];
					}
				}
			}
		}
		
		if (shouldPostNotification)
		{
			if (dict == dict_nodeData) {
				[changes_nodeData addObject:key];
			}
			else if (dict == dict_nodeThumbnails) {
				[changes_nodeThumbnails addObject:key];
			}
			else {
				[changes_userAvatars addObject:key];
			}
			
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_async(cacheQueue, block);
}

- (nullable ZDCUser *)findUserWithRandom:(NSString *)random
                             transaction:(YapDatabaseReadTransaction *)transaction
{
	YapDatabaseSecondaryIndexTransaction *secondaryIndexTransaction = [transaction ext:Ext_Index_Users];
	
	__block ZDCUser *match = nil;
	
	if (secondaryIndexTransaction)
	{
		// Use secondary index for best performance (uses sqlite indexes)
		//
		// WHERE random = ?
		
		NSString *queryString = [NSString stringWithFormat:@"WHERE %@ = ?", Index_Users_Column_RandomUUID];
		YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryString, random];
		
		[secondaryIndexTransaction enumerateKeysAndObjectsMatchingQuery:query usingBlock:
			^(NSString *collection, NSString *key, ZDCUser *user, BOOL *stop)
		{
			match = user;
			*stop = YES;
		}];
	}
	else
	{
		// Backup Plan (defensive programming)
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Users usingBlock:
			^(NSString *key, ZDCUser *user, BOOL *stop)
		{
			if ([random isEqualToString:user.random_uuid])
			{
				match = user;
				*stop = YES;
			}
		}];
	}
	
	return match;
}

- (void)findAuth0IDsMatchingHashes:(NSMutableSet<NSString*> *)hashes
                           forUser:(ZDCUser *)user
                           withMap:(NSMutableDictionary<NSString*, NSString*> *)map_auth0ID
{
	// 99% of the time we're storing the preferred auth0ID
	
	NSString *preferredAuth0ID = user.auth0_preferredID;
	
	if (preferredAuth0ID)
	{
		NSString *hash = [self hashAuth0ID:preferredAuth0ID forUser:user];
		if ([hashes containsObject:hash])
		{
			map_auth0ID[hash] = preferredAuth0ID;
			
			[hashes removeObject:hash];
			if (hashes.count == 0) return;
		}
	}
	
	for (NSString *auth0ID in user.auth0_profiles)
	{
		if ([auth0ID isEqual:preferredAuth0ID]) {
			// Already checked this one
			continue;
		}
		
		NSString *hash = [self hashAuth0ID:auth0ID forUser:user];
		if ([hashes containsObject:hash])
		{
			map_auth0ID[hash] = auth0ID;
			
			[hashes removeObject:hash];
			if (hashes.count == 0) return;
		}
	}
}

- (NSString *)hashAuth0ID:(NSString *)auth0ID forUser:(ZDCUser *)user
{
	// Purpose:
	//
	// We want to store the user avatar on disk.
	// But we don't want to leak any information concerning who the user may be communicating with.
	
	NSData *encryptionKey = user.random_encryptionKey;
	NSData *auth0IDBytes = [auth0ID dataUsingEncoding:NSUTF8StringEncoding];
	
	NSMutableData *hashMe = [NSMutableData dataWithCapacity:(encryptionKey.length + auth0IDBytes.length)];
	[hashMe appendData:encryptionKey];
	[hashMe appendData:auth0IDBytes];
	
	NSData *hashedData = [hashMe hashWithAlgorithm:kHASH_Algorithm_SHA256 error:nil];
	
	return [hashedData zBase32String];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Setup all the various tasks that need to be performed after a new launch.
 */
- (void)launchCleanup
{
	__weak typeof(self) weakSelf = self;
	
	// First we have to wait for all the directory scans to complete.
	dispatch_async(refreshQueue, ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		// Then we have to wait for the results to be pushed into the cache.
		dispatch_async(strongSelf->cacheQueue, ^{ @autoreleasepool {
			
			// Now we can delete any files that shouldn't exist
			[weakSelf garbageCollection:^{ @autoreleasepool {
				
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf == nil) return;
				
				dispatch_async(strongSelf->cacheQueue, ^{ @autoreleasepool {
					
					// And finally we can delete expired files
					[weakSelf timerFire];
				}});
			}}];
		}});
	}});
}

/**
 * The DiskManager deletes items from the filesystem in response to changes in the database.
 * For example, if a node is deleted:
 *
 * - YapDatabase publishes a notification that includes the list of deleted nodeIDs
 * - The DiskManager receives the notification and processes it asynchronously
 * - The DiskManager ultimately deletes the associated files
 *
 * However, since this cleanup process is asynchronous,
 * it's always possible the app is quit before the cleanup occurs.
 *
 * The garbage collection process corrects this possible disconnect by
 * ensuring that everything on disk has a match in the database.
 */
- (void)garbageCollection:(dispatch_block_t)completionBlock
{
	DDLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	// Step 1 of 5:
	//
	// Collect the list of nodeID's for which we currently have files cached on disk.
	
	NSMutableSet<NSString *> *cachedNodeIDs = [NSMutableSet set];
	[cachedNodeIDs addObjectsFromArray:[dict_nodeData allKeys]];
	[cachedNodeIDs addObjectsFromArray:[dict_nodeThumbnails allKeys]];
	
	// Step 2 of 5:
	//
	// Collect the list of <userID, auth0ID> tuples for which we currently have files cached on disk.
	
	NSMutableDictionary<NSString*, NSMutableSet<NSString*> *> *cachedAvatars =
	  [NSMutableDictionary dictionaryWithCapacity:dict_userAvatars.count];
	
	[dict_userAvatars enumerateKeysAndObjectsUsingBlock:
		^(NSString *userID, NSMutableArray<ZDCFileInfo *> *infos, BOOL *stop)
	{
		NSMutableSet<NSString*> *cachedAuth0IDs = [NSMutableSet set];
		
		for (ZDCFileInfo *info in infos)
		{
			if (info.auth0ID) {
				[cachedAuth0IDs addObject:info.auth0ID];
			}
		}
		
		cachedAvatars[userID] = cachedAuth0IDs;
	}];
	
	// Step 3 of 5:
	//
	// Make sure we have associated items in the database.
	// If not, the files are garbage, and need to be deleted.
	
	NSMutableArray<NSString*> *missingNodeIDs = [NSMutableArray array];
	NSMutableArray<NSString*> *missingUserIDs = [NSMutableArray array];
	NSMutableArray<YapCollectionKey*> *missingTuples = [NSMutableArray array];
	
	__weak typeof(self) weakSelf = self;
	
	[zdc.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (NSString *nodeID in cachedNodeIDs)
		{
			if (![transaction hasObjectForKey:nodeID inCollection:kZDCCollection_Nodes])
			{
				[missingNodeIDs addObject:nodeID];
			}
		}
		
		for (NSString *userID in cachedAvatars)
		{
			ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
			if (user)
			{
				NSSet *cachedAuth0IDs = cachedAvatars[userID];
				for (NSString *auth0ID in cachedAuth0IDs)
				{
					if (user.auth0_profiles[auth0ID] == nil)
					{
						[missingTuples addObject:YapCollectionKeyCreate(userID, auth0ID)];
					}
				}
			}
			else // if (user == nil)
			{
				[missingUserIDs addObject:userID];
			}
		}
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		if (missingNodeIDs.count > 0)
		{
			[strongSelf deleteNodeDataForNodeIDs:missingNodeIDs];
			[strongSelf deleteNodeThumbnailsForNodeIDs:missingNodeIDs];
		}
		
		if (missingUserIDs.count > 0)
		{
			[strongSelf deleteUserAvatarsForUserIDs:missingUserIDs];
		}
		
		if (missingTuples.count > 0)
		{
			[strongSelf deleteUserAvatarsForTuples:missingTuples];
		}
	}];
}

- (void)maybeTrimCachePool:(ZDCFileType)type
{
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = nil;
	NSMutableSet<NSString*> *changes = nil;
	uint64_t targetSize = 0;
	
	switch (type)
	{
		case ZDCFileType_NodeData:
		{
			dict = dict_nodeData;
			changes = changes_nodeData;
			targetSize = self.maxNodeDataCacheSize;
			break;
		}
		case ZDCFileType_NodeThumbnail:
		{
			dict = dict_nodeThumbnails;
			changes = changes_nodeThumbnails;
			targetSize = self.maxNodeThumbnailsCacheSize;
			break;
		}
		case ZDCFileType_UserAvatar:
		{
			dict = dict_userAvatars;
			changes = changes_userAvatars;
			targetSize = self.maxUserAvatarsCacheSize;
			break;
		}
		default:
		{
			NSAssert(NO, @"Invalid directory passed to %@", THIS_METHOD);
			break;
		}
	}
	
	NSMutableArray<ZDCFileInfo*> *targetInfos = [NSMutableArray array];
	uint64_t totalSize = 0;
	
	for (NSArray<ZDCFileInfo *> *infos in [dict objectEnumerator])
	{
		for (ZDCFileInfo *info in infos)
		{
			if ((info.mode == ZDCStorageMode_Cache) && (info.type == type) && !info.pendingDelete)
			{
				[targetInfos addObject:info];
				totalSize += info.fileSize;
			}
		}
	}
	
	if (totalSize <= targetSize) {
		return;
	}
	
	// From the docs (NSArray):
	//
	// > [sorts the array] in ascending order
	//
	[targetInfos sortUsingComparator:^NSComparisonResult(ZDCFileInfo *infoA, ZDCFileInfo *infoB) {
		
		// From the docs (NSDate):
		//
		// > NSOrderedDescending : The receiver is later in time than anotherDate
		// > NSOrderedAscending  : The receiver is earlier in time than anotherDate
		
		return [infoA.lastAccessed compare:infoB.lastAccessed];
	}];
	
	// So at this point, the earliest date should be at index 0, and the latest date at the end of the array.
	
	while ((totalSize > targetSize) && (targetInfos.count > 0))
	{
		ZDCFileInfo *info = [targetInfos lastObject];
		[targetInfos removeLastObject];
		
		if (info.fileRetainCount == 0)
		{
			NSError *error = nil;
			[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
			
			if (error) {
				DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
			}
			
			NSString *key = info.nodeID ?: info.userID;
			
			[dict[key] removeObjectIdenticalTo:info];
			[changes addObject:key];
		}
		else
		{
			info.pendingDelete = YES;
		}
		
		totalSize -= info.fileSize;
	}
	
	[self postDiskManagerChangedNotification];
}

- (void)deleteExpiredItemsFromCachePool:(ZDCFileType)type
{
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = nil;
	NSMutableSet<NSString*> *changes = nil;
	NSTimeInterval defaultExpiration = 0;
	
	switch (type)
	{
		case ZDCFileType_NodeData:
		{
			dict = dict_nodeData;
			changes = changes_nodeData;
			defaultExpiration = self.defaultNodeDataCacheExpiration;
			break;
		}
		case ZDCFileType_NodeThumbnail:
		{
			dict = dict_nodeThumbnails;
			changes = changes_nodeThumbnails;
			defaultExpiration = self.defaultNodeThumbnailCacheExpiration;
			break;
		}
		case ZDCFileType_UserAvatar:
		{
			dict = dict_userAvatars;
			changes = changes_userAvatars;
			defaultExpiration = self.defaultUserAvatarCacheExpiration;
			break;
		}
		default:
		{
			NSAssert(NO, @"Invalid directory passed to %@", THIS_METHOD);
			break;
		}
	}
	
	NSDate *now = [NSDate date];
	
	for (NSMutableArray<ZDCFileInfo *> *infos in [dict objectEnumerator])
	{
		NSUInteger i = 0;
		while (i < infos.count)
		{
			ZDCFileInfo *info = infos[i];
			
			BOOL shouldDelete = NO;
			if (info.mode == ZDCStorageMode_Cache)
			{
				NSTimeInterval expirationInterval = info.expiration;
				if (expirationInterval == 0) {
					expirationInterval = defaultExpiration;
				}
				
				if (expirationInterval > 0)
				{
					NSDate *expirationDate = [info.lastModified dateByAddingTimeInterval:expirationInterval];
					shouldDelete = (expirationDate == nil) || [expirationDate isBeforeOrEqual:now];
				}
			}
			
			if (shouldDelete)
			{
				if (info.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
					
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
					}
					
					NSString *key = info.nodeID ?: info.userID;
					[changes addObject:key];
					
					[infos removeObjectAtIndex:i];
				}
				else
				{
					info.pendingDelete = YES;
					i++;
				}
			}
			else
			{
				i++;
			}
		}
	}
	
	if (changes.count > 0) {
		[self postDiskManagerChangedNotification];
	}
}

- (nullable NSDate *)nextExpirationDate:(ZDCFileType)type
{
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = nil;
	NSTimeInterval defaultExpiration = 0;
	
	switch (type)
	{
		case ZDCFileType_NodeData:
		{
			dict = dict_nodeData;
			defaultExpiration = self.defaultNodeDataCacheExpiration;
			break;
		}
		case ZDCFileType_NodeThumbnail:
		{
			dict = dict_nodeThumbnails;
			defaultExpiration = self.defaultNodeThumbnailCacheExpiration;
			break;
		}
		case ZDCFileType_UserAvatar:
		{
			dict = dict_userAvatars;
			defaultExpiration = self.defaultUserAvatarCacheExpiration;
			break;
		}
		default:
		{
			NSAssert(NO, @"Invalid directory passed to %@", THIS_METHOD);
			break;
		}
	}
	
	NSDate *next = nil;
	
	for (NSArray<ZDCFileInfo *> *infos in [dict objectEnumerator])
	{
		for (ZDCFileInfo *info in infos)
		{
			if (info.mode == ZDCStorageMode_Cache)
			{
				NSTimeInterval expirationInterval = info.expiration;
				if (expirationInterval <= 0) {
					expirationInterval = defaultExpiration;
				}
				
				if (expirationInterval > 0)
				{
					NSDate *expirationDate = [info.lastModified dateByAddingTimeInterval:expirationInterval];
					if (expirationDate)
					{
						if ((next == nil) || [next isAfter:expirationDate])
						{
							next = expirationDate;
						}
					}
				}
			}
		}
	}
	
	return next;
}

- (void)updateExpirationTimer
{
	nextExpirationDate_nodeData       = [self nextExpirationDate:ZDCFileType_NodeData];
	nextExpirationDate_nodeThumbnails = [self nextExpirationDate:ZDCFileType_NodeThumbnail];
	nextExpirationDate_userAvatars    = [self nextExpirationDate:ZDCFileType_UserAvatar];
	
	[self maybeUpdateExpirationTimer_UrMom];
}

- (void)maybeUpdateExpirationTimer:(ZDCFileType)type
{
	switch (type)
	{
		case ZDCFileType_NodeData      : nextExpirationDate_nodeData       = [self nextExpirationDate:type]; break;
		case ZDCFileType_NodeThumbnail : nextExpirationDate_nodeThumbnails = [self nextExpirationDate:type]; break;
		case ZDCFileType_UserAvatar    : nextExpirationDate_userAvatars    = [self nextExpirationDate:type]; break;
	}
	
	[self maybeUpdateExpirationTimer_UrMom];
}

- (void)maybeUpdateExpirationTimer_UrMom
{
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	NSDate *next_a = nextExpirationDate_nodeData;
	NSDate *next_b = nextExpirationDate_nodeThumbnails;
	NSDate *next_c = nextExpirationDate_userAvatars;
	
	NSDate *oldDate = nextExpirationDate;
	NSDate *newDate = ZDCEarlierDate(next_a, ZDCEarlierDate(next_b, next_c));
	
	BOOL needsUpdateTimer;
	if (oldDate)
	{
		if (newDate) {
			needsUpdateTimer = ![oldDate isEqualToDate:newDate];
		} else {
			needsUpdateTimer = YES;
		}
	}
	else // oldDate == nil
	{
		if (newDate) {
			needsUpdateTimer = YES;
		} else {
			needsUpdateTimer = NO;
		}
	}
	
	if (!needsUpdateTimer) {
		return;
	}
	
	nextExpirationDate = newDate;
	
	if (expirationTimer == nil)
	{
		expirationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, cacheQueue);
		
		__weak typeof(self) weakSelf = self;
		dispatch_source_set_event_handler(expirationTimer, ^{ @autoreleasepool {
			
			[weakSelf timerFire];
		}});
		
		expirationTimerSuspended = YES;
	}
	
	if (newDate)
	{
		dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW,
		                           (uint64_t)([newDate timeIntervalSinceNow] * NSEC_PER_SEC));
		
		uint64_t interval = DISPATCH_TIME_FOREVER;
		uint64_t leeway = (30 * NSEC_PER_SEC); // flexibility here for reduced power consumption
		
		dispatch_source_set_timer(expirationTimer, start, interval, leeway);
		
		if (expirationTimerSuspended) {
			expirationTimerSuspended = NO;
			dispatch_resume(expirationTimer);
		}
	}
	else
	{
		if (!expirationTimerSuspended) {
			expirationTimerSuspended = YES;
			dispatch_suspend(expirationTimer);
		}
	}
}
	
- (void)timerFire
{
	DDLogAutoTrace();
	
	[self deleteExpiredItemsFromCachePool:ZDCFileType_NodeData];
	[self deleteExpiredItemsFromCachePool:ZDCFileType_NodeThumbnail];
	[self deleteExpiredItemsFromCachePool:ZDCFileType_UserAvatar];
	
	[self updateExpirationTimer];
}

- (void)migrateOrDeleteAfterUpload:(NSSet<NSString*> *)enqueuedNodeIDs
{
	NSAssert(dispatch_get_specific(IsOnCacheQueueKey), @"MUST be invoked within the cacheQueue");
	
	BOOL isInitialization;
	NSMutableSet<NSString*> *finishedUpload = nil;
	
	if (uploadQueue_nodeIDs == nil)
	{
		isInitialization = YES;
	}
	else
	{
		isInitialization = NO;
		
		// Find the set of nodeIDS for which:
		// - the nodeID was in the old set
		// - the nodeID is NOT in the new set
		
		finishedUpload = [uploadQueue_nodeIDs mutableCopy];
		[finishedUpload minusSet:enqueuedNodeIDs];
	}
	
	uploadQueue_nodeIDs = enqueuedNodeIDs;
	
	for (NSDictionary *dict in @[ dict_nodeData, dict_nodeThumbnails ])
	{
		for (NSString *nodeID in [dict allKeys])
		{
			NSArray<ZDCFileInfo *> *fileInfos = dict[nodeID];
			
			BOOL shouldDelete = NO;
			BOOL shouldMigrate = NO;
			
			for (ZDCFileInfo *info in fileInfos)
			{
				if (info.deleteAfterUpload)
				{
					if (isInitialization) {
						shouldDelete = shouldDelete || ![uploadQueue_nodeIDs containsObject:nodeID];
					}
					else {
						shouldDelete = shouldDelete || [finishedUpload containsObject:nodeID];
					}
				}
				else if (info.isStoredPersistently && info.migrateAfterUpload)
				{
					if (isInitialization) {
						shouldMigrate = shouldMigrate || ![uploadQueue_nodeIDs containsObject:nodeID];
					}
					else {
						shouldMigrate = shouldMigrate || [finishedUpload containsObject:nodeID];
					}
				}
			}
			
			if (shouldDelete)
			{
				if (dict == dict_nodeData)
					[self deleteNodeData:nodeID];
				else
					[self deleteNodeThumbnail:nodeID];
			}
			else if (shouldMigrate)
			{
				if (dict == dict_nodeData)
					[self makeNodeDataPersistent:NO forNodeID:nodeID];
				else
					[self makeNodeThumbnailPersistent:NO forNodeID:nodeID];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (uint64_t)maxNodeDataCacheSize
{
	ZDCFileType type = ZDCFileType_NodeData;
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: type
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	return [self maxCacheSizeForURL:url withDefaultValue:kDefaultConfiguration_maxNodeDataCacheSize];
}

- (void)setMaxNodeDataCacheSize:(uint64_t)numBytes
{
	ZDCFileType type = ZDCFileType_NodeData;
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: type
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	[self setMaxCacheSize:numBytes forURL:url];
	
	dispatch_async(cacheQueue, ^{ @autoreleasepool {
		
		[self maybeTrimCachePool:type];
	}});
}

- (uint64_t)maxNodeThumbnailsCacheSize
{
	ZDCFileType type = ZDCFileType_NodeThumbnail;
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: type
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	return [self maxCacheSizeForURL:url withDefaultValue:kDefaultConfiguration_maxNodeThumbnailsCacheSize];
}

- (void)setMaxNodeThumbnailsCacheSize:(uint64_t)numBytes
{
	ZDCFileType type = ZDCFileType_NodeThumbnail;
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: type
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	[self setMaxCacheSize:numBytes forURL:url];
	
	dispatch_async(cacheQueue, ^{ @autoreleasepool {
		
		[self maybeTrimCachePool:type];
	}});
}

- (uint64_t)maxUserAvatarsCacheSize
{
	ZDCFileType type = ZDCFileType_UserAvatar;
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: type
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	return [self maxCacheSizeForURL:url withDefaultValue:kDefaultConfiguration_maxUserAvatarsCacheSize];
}

- (void)setMaxUserAvatarsCacheSize:(uint64_t)numBytes
{
	ZDCFileType type = ZDCFileType_UserAvatar;
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: type
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	[self setMaxCacheSize:numBytes forURL:url];
	
	dispatch_async(cacheQueue, ^{ @autoreleasepool {
		
		[self maybeTrimCachePool:type];
	}});
}

- (NSTimeInterval)defaultNodeDataCacheExpiration
{
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: ZDCFileType_NodeData
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	NSTimeInterval interval = 0;
	if ([self getExpiration:&interval forURL:url]) {
		return interval;
	} else {
		return kDefaultConfiguration_nodeDataExpiration;
	}
}

- (void)setDefaultNodeDataCacheExpiration:(NSTimeInterval)interval
{
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: ZDCFileType_NodeData
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	[self setExpiration:interval forURL:url];
}

- (NSTimeInterval)defaultNodeThumbnailCacheExpiration
{
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: ZDCFileType_NodeThumbnail
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	NSTimeInterval interval = 0;
	if ([self getExpiration:&interval forURL:url]) {
		return interval;
	} else {
		return kDefaultConfiguration_nodeThumbnailExpiration;
	}
}

- (void)setDefaultNodeThumbnailCacheExpiration:(NSTimeInterval)interval
{
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: ZDCFileType_NodeThumbnail
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	[self setExpiration:interval forURL:url];
}

- (NSTimeInterval)defaultUserAvatarCacheExpiration
{
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: ZDCFileType_UserAvatar
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	NSTimeInterval interval = 0;
	if ([self getExpiration:&interval forURL:url]) {
		return interval;
	} else {
		return kDefaultConfiguration_userAvatarExpiration;
	}
}

- (void)setDefaultUserAvatarCacheExpiration:(NSTimeInterval)interval
{
	NSURL *url = [self URLForMode: ZDCStorageMode_Cache
	                         type: ZDCFileType_UserAvatar
	                       format: ZDCCryptoFileFormat_CacheFile];
	
	[self setExpiration:interval forURL:url];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Xattrs
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (uint64_t)maxCacheSizeForURL:(NSURL *)url withDefaultValue:(uint64_t)defaultValue
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_maxCacheSize UTF8String];
	
	uint64_t value = 0;
	
	ssize_t result = getxattr(path, name, &value, sizeof(value), 0, 0);
	
	if (result < 0)
	{
		if (errno != ENOATTR) {
			DDLogError(@"%@: getxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	
	if (result != sizeof(value) || value == 0)
	{
		value = defaultValue;
	}
	
	return value;
}

- (void)setMaxCacheSize:(uint64_t)value forURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_maxCacheSize UTF8String];
	
	int result = setxattr(path, name, &value, sizeof(value), 0, 0);
	
	if (result < 0) {
		DDLogError(@"%@: setxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
	}
}

- (BOOL)shouldMigrateAfterUploadForURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_migrateAfterUpload UTF8String];
	
	ssize_t result = getxattr(path, name, NULL, 0, 0, 0);
	
	if (result < 0)
	{
		if (errno != ENOATTR) {
			DDLogError(@"%@: getxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	
	return (result > 0);
}

- (void)setShouldMigrateAfterUpload:(BOOL)flag forURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_migrateAfterUpload UTF8String];
	
	if (flag)
	{
		int32_t value = 1;
		
		int result = setxattr(path, name, &value, sizeof(value), 0, 0);
		
		if (result < 0) {
			DDLogError(@"%@: setxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	else
	{
		int result = removexattr(path, name, 0);
		
		if (result < 0) {
			DDLogError(@"%@: removexattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
}

- (BOOL)shouldDeleteAfterUploadForURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_deleteAfterUpload UTF8String];
	
	ssize_t result = getxattr(path, name, NULL, 0, 0, 0);
	
	if (result < 0)
	{
		if (errno != ENOATTR) {
			DDLogError(@"%@: getxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	
	return (result > 0);
}

- (void)setShouldDeleteAfterUpload:(BOOL)flag forURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_deleteAfterUpload UTF8String];
	
	if (flag)
	{
		int32_t value = 1;
		
		int result = setxattr(path, name, &value, sizeof(value), 0, 0);
		
		if (result < 0) {
			DDLogError(@"%@: setxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	else
	{
		int result = removexattr(path, name, 0);
		
		if (result < 0) {
			DDLogError(@"%@: removexattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
}

- (BOOL)getExpiration:(NSTimeInterval *)outExpiration forURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_expiration UTF8String];
	
	int64_t value = 0;
	ssize_t result = getxattr(path, name, &value, sizeof(value), 0, 0);
	
	if (result < 0)
	{
		if (errno != ENOATTR) {
			DDLogError(@"%@: getxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	
	if (result == sizeof(value))
	{
		int64_t numMilliseconds = value;
		NSTimeInterval interval = (double)numMilliseconds / 1000.0;
		
		if (outExpiration) *outExpiration = interval;
		return YES;
	}
	else
	{
		if (outExpiration) *outExpiration = 0;
		return NO;
	}
}

- (void)setExpiration:(NSTimeInterval)interval forURL:(NSURL *)url
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_expiration UTF8String];
	
	int64_t numMilliseconds = (int64_t)(interval * 1000);
	
	int result = setxattr(path, name, &numMilliseconds, sizeof(numMilliseconds), 0, 0);
	
	if (result < 0) {
		DDLogError(@"%@: setxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
	}
}

- (BOOL)getETag:(NSString **)outETag forURL:(NSURL *)url withEncryptionKey:(NSData *)encryptionKey
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_eTag UTF8String];
	
	const size_t bufferSize = 256;
	uint8_t buffer[bufferSize];
	
	ssize_t result = getxattr(path, name, &buffer, bufferSize, 0, 0);
	
	NSString *eTag = nil;
	BOOL success = NO;
	
	if (result < 0)
	{
		if (errno == ENOATTR) {
			success = YES;
		}
		else {
			DDLogError(@"%@: getxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
	else if (result == 0)
	{
		success = YES;
	}
	else // if (result > 0)
	{
		NSData *encrypted = [NSData dataWithBytesNoCopy:buffer length:result freeWhenDone:NO];
		
		NSError *error = nil;
		NSData *decrypted = [encrypted decryptedDataWithSymmetricKey:encryptionKey error:&error];
		
		if (error) {
			DDLogError(@"%@: decryption error: %@", THIS_METHOD, error);
		}
		else {
			eTag = [[NSString alloc] initWithData:decrypted encoding:NSUTF8StringEncoding];
			success = (eTag != nil);
		}
	}
	
	if (outETag) *outETag = nil;
	return success;
}

- (void)setETag:(NSString *)eTag forURL:(NSURL *)url withEncryptionKey:(NSData *)encryptionKey
{
	const char *path = [[url path] UTF8String];
	const char *name = [kXattrName_eTag UTF8String];
	
	if (eTag)
	{
		NSData *decrypted = [eTag dataUsingEncoding:NSUTF8StringEncoding];
		
		NSError *error = nil;
		NSData *encrypted = [decrypted encryptedDataWithSymmetricKey:encryptionKey error:&error];
		
		if (error)
		{
			DDLogError(@"%@: encryption error: %@", THIS_METHOD, error);
		}
		else if (encrypted)
		{
			const void *buffer = [encrypted bytes];
			
			int result = setxattr(path, name, buffer, encrypted.length, 0, 0);
			
			if (result < 0) {
				DDLogError(@"%@: setxattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
			}
		}
	}
	else
	{
		int result = removexattr(path, name, 0);
		
		if (result < 0) {
			DDLogError(@"%@: removexattr(%@): error = %s", THIS_METHOD, [url path], strerror(errno));
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (nullable ZDCCryptoFile *)importNodeData:(ZDCDiskImport *)import
                                   forNode:(ZDCNode *)node
                                     error:(NSError *_Nullable *_Nullable)outError
{
	NSError *error = nil;
	
	if (import == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: import is nil"];
	}
	else if (node == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: node is nil"];
	}
	else if (import.isNilPlaceholder) {
		NSString *msg = @"Bad parameter: import.isNilPlaceholder: Not valid for nodeData";
		error = [NSError errorWithClass:[self class] code:400 description:msg];
	}
	else if (import.cleartextFileURL || import.cryptoFile)
	{
		NSURL *fileURL = import.cleartextFileURL ?: import.cryptoFile.fileURL;
		
		BOOL isAlreadyManaged = [self getMode:nil type:nil format:nil forFileURL:fileURL];
		if (isAlreadyManaged)
		{
			// The file cannot be imported because it's already imported.
			error = [NSError errorWithClass: [self class]
			                           code: 400
			                    description: @"Bad parameter: cryptoFile is already managed"];
		}
	}
	
	if (error)
	{
		if (outError) *outError = error;
		return nil;
	}
	
	NSURL *srcURL = nil;
	
	void (^WarnIfMainThread)(void) = ^{
		if ([NSThread isMainThread]) {
			DDLogWarn(@"Performing synchronous disk IO (+encryption) on the main thread."
			          @" This is NOT recommended."
						 @" (via: [%@ %@]", THIS_FILE, THIS_METHOD);
		}
	};
	
	if (import.cleartextData)
	{
		WarnIfMainThread();
		
		srcURL = [ZDCDirectoryManager generateTempURL];
		[ZDCFileConversion encryptCleartextData: import.cleartextData
		                     toCacheFileWithKey: node.encryptionKey
		                              outputURL: srcURL
		                                  error: &error];
		if (error) {
			DDLogWarn(@"Error encrypting import.cleartextData: %@", error);
		}
	}
	else if (import.cleartextFileURL)
	{
		WarnIfMainThread();
		
		srcURL = [ZDCDirectoryManager generateTempURL];
		[ZDCFileConversion encryptCleartextFile: import.cleartextFileURL
		                     toCacheFileWithKey: node.encryptionKey
		                              outputURL: srcURL
		                                  error: &error];
		if (error) {
			DDLogWarn(@"Error encrypting import.cleartextFileURL: %@", error);
		}
	}
	else
	{
		if ([import.cryptoFile.encryptionKey isEqual:node.encryptionKey])
		{
			srcURL = import.cryptoFile.fileURL;
		}
		else
		{
			WarnIfMainThread();
			
			srcURL = [ZDCDirectoryManager generateTempURL];
			[ZDCFileConversion reEncryptFile: import.cryptoFile.fileURL
			                         fromKey: import.cryptoFile.encryptionKey
			                          toFile: srcURL
			                           toKey: node.encryptionKey
			                           error: &error];
			if (error) {
				DDLogWarn(@"Error re-encrypting import.cryptoFile: %@", error);
			}
		}
	}
	
	if (error)
	{
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCFileType type = ZDCFileType_NodeData;
	ZDCStorageMode mode = import.storePersistently ? ZDCStorageMode_Persistent : ZDCStorageMode_Cache;
	ZDCCryptoFileFormat format = import.cryptoFile ? import.cryptoFile.fileFormat : ZDCCryptoFileFormat_CacheFile;
	
	NSURL *dir = [self URLForMode:mode type:type format:format];
	NSURL *dstURL = [dir URLByAppendingPathComponent:node.uuid isDirectory:NO];
	
	[fileManager moveItemAtURL:srcURL toURL:dstURL error:&error];
	
	if (error)
	{
		DDLogWarn(@"Error moving file: src(%@) -> dst(%@): %@",
		            [srcURL path], [dstURL path], error);
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSNumber *fileSize = nil;
	[dstURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
	
	__block ZDCFileRetainToken *retainToken = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeData;
		NSMutableSet<NSString*> *changes = changes_nodeData;
		
		NSMutableArray <ZDCFileInfo *> *infos = dict[node.uuid];
		if (infos == nil)
		{
			infos = [[NSMutableArray alloc] initWithCapacity:1];
			dict[node.uuid] = infos;
		}
		
		ZDCFileInfo *matchingInfo = nil;
		
		NSUInteger i = 0;
		while (i < infos.count)
		{
			ZDCFileInfo *info = infos[i];
			
			if ([info matchesMode:mode type:type format:format])
			{
				matchingInfo = info;
				i++;
			}
			else
			{
				// The info doesn't match what's being imported (different format, different persistent setting, etc).
				// This means the particular file is now outdated, and needs to be deleted.
				
				if (info.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
					
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
					}
					
					[infos removeObjectAtIndex:i];
				}
				else
				{
					info.pendingDelete = YES;
					i++;
				}
			}
		}
		
		// If matchingInfo exists, then leave it be.
		// We need to preserve the following:
		//
		// - info.fileRetainCount
		//
		if (matchingInfo == nil)
		{
			matchingInfo = [[ZDCFileInfo alloc] initWithMode:mode type:type format:format fileURL:dstURL];
			matchingInfo.nodeID = node.uuid;
			
			[infos addObject:matchingInfo];
		}
		
		matchingInfo.fileSize = [fileSize unsignedLongLongValue];
		
		NSDate *now = [NSDate date];
		matchingInfo.lastAccessed = now;
		matchingInfo.lastModified = now;
		
		matchingInfo.migrateAfterUpload = import.migrateToCacheAfterUpload;
		matchingInfo.deleteAfterUpload = import.deleteAfterUpload;
		matchingInfo.expiration = import.expiration;
		matchingInfo.eTag = import.eTag ?: [NSNull null];
		
		if (import.storePersistently && import.migrateToCacheAfterUpload) {
			[self setShouldMigrateAfterUpload:YES forURL:dstURL];
		}
		if (import.deleteAfterUpload) {
			[self setShouldDeleteAfterUpload:YES forURL:dstURL];
		}
		if (import.expiration != 0) {
			// Write xattr even if not persistent (in case file is migrated)
			[self setExpiration:import.expiration forURL:dstURL];
		}
		if (import.eTag) {
			[self setETag:import.eTag forURL:dstURL withEncryptionKey:node.encryptionKey];
		}
		
		[matchingInfo incrementFileRetainCount];
		retainToken = [[ZDCFileRetainToken alloc] initWithInfo:matchingInfo owner:self];
		
		[changes addObject:node.uuid];
		if (!import.storePersistently)
		{
			[self maybeTrimCachePool:type];
			[self maybeUpdateExpirationTimer:type];
		}
		[self postDiskManagerChangedNotification];
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	ZDCCryptoFile *result =
		result = [[ZDCCryptoFile alloc] initWithFileURL: dstURL
		                                     fileFormat: format
													 encryptionKey: node.encryptionKey
		                                    retainToken: retainToken];
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)hasNodeData:(NSString *)nodeID
{
	DDLogAutoTrace();
	
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeData;
		
		NSArray <ZDCFileInfo *> *infos = dict[nodeID];
		for (ZDCFileInfo *info in infos)
		{
			if (!info.pendingDelete) {
				result = YES;
				break;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	return result;
}

/**
 * See header file for description.
 */
- (nullable ZDCDiskExport *)nodeData:(ZDCNode *)node
{
	DDLogAutoTrace();
	
	return [self nodeData:node preferredFormat:ZDCCryptoFileFormat_Unknown];
}

/**
 * See header file for description.
 */
- (nullable ZDCDiskExport *)nodeData:(ZDCNode *)node
                     preferredFormat:(ZDCCryptoFileFormat)preferredFormat
{
	DDLogAutoTrace();
	if (node == nil) return nil;
	
	__block NSURL *fileURL = nil;
	__block ZDCCryptoFileFormat format = ZDCCryptoFileFormat_Unknown;
	
	__block ZDCFileRetainToken *retainToken = nil;
	
	__block BOOL isPersistent = NO;
	__block NSString *eTag = nil;
	__block NSTimeInterval expiration = 0;
	
	BOOL hasPreferredFormat = (preferredFormat != ZDCCryptoFileFormat_Unknown);

	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeData;
		
		NSArray <ZDCFileInfo *> *infos = dict[node.uuid];
		if (infos.count > 0)
		{
			ZDCFileInfo * (^PreferredInfo)(ZDCFileInfo *, ZDCFileInfo *);
			PreferredInfo = ^ZDCFileInfo *(ZDCFileInfo *info1, ZDCFileInfo *info2) {
				
				if (hasPreferredFormat)
				{
					if (info1.format == preferredFormat)
						return info1;
					if (info2.format == preferredFormat)
						return info2;
				}
				
				if (info1.format == ZDCCryptoFileFormat_CacheFile)
					return info1;
				if (info2.format == ZDCCryptoFileFormat_CacheFile)
					return info2;
				
				return info1;
			};
			
			ZDCFileInfo *pInfo = nil;
			
			for (ZDCFileInfo *info in infos)
			{
				if (!info.pendingDelete)
				{
					if (pInfo == nil)
						pInfo = info;
					else
						pInfo = PreferredInfo(info, pInfo);
				}
			}
			
			if (pInfo)
			{
				fileURL = pInfo.fileURL;
				format = pInfo.format;
				
				[pInfo incrementFileRetainCount];
				retainToken = [[ZDCFileRetainToken alloc] initWithInfo:pInfo owner:self];
				
				pInfo.lastAccessed = [NSDate date];
				
				isPersistent = pInfo.isStoredPersistently;
				
				if (pInfo.eTag == nil) // we read eTag xattr only on demand
				{
					NSString *eTag = nil;
					if ([self getETag:&eTag forURL:pInfo.fileURL withEncryptionKey:node.encryptionKey])
					{
						pInfo.eTag = eTag ?: [NSNull null];
					}
				}
				
				if ([pInfo.eTag isKindOfClass:[NSString class]]) {
					eTag = (NSString *)pInfo.eTag;
				}
				expiration = pInfo.expiration;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	ZDCCryptoFile *cryptoFile = nil;
	if (fileURL && node.encryptionKey)
	{
		cryptoFile = [[ZDCCryptoFile alloc] initWithFileURL: fileURL
		                                         fileFormat: format
		                                      encryptionKey: node.encryptionKey
		                                        retainToken: retainToken];
	}
	
	ZDCDiskExport *export = nil;
	if (cryptoFile)
	{
		export = [[ZDCDiskExport alloc] initWithCryptoFile: cryptoFile
		                                      isPersistent: isPersistent
		                                              eTag: eTag
		                                        expiration: expiration];
	}
	
	return export;
}

/**
 * See header file for description.
 */
- (void)deleteNodeData:(NSString *)nodeID
{
	[self deleteNodeDataForNodeIDs:@[ nodeID ]];
}

/**
 * See header file for description.
 */
- (void)deleteNodeDataForNodeIDs:(NSArray<NSString*> *)nodeIDs
{
	DDLogAutoTrace();
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeData;
		NSMutableSet<NSString*> *changes = changes_nodeData;
		
		BOOL shouldPostNotification = NO;
		
		for (NSString *nodeID in nodeIDs)
		{
			NSMutableArray<ZDCFileInfo *> *infos = dict[nodeID];
			if (infos)
			{
				NSUInteger i = 0;
				while (i < infos.count)
				{
					ZDCFileInfo *info = infos[i];
		
					if (info.fileRetainCount == 0)
					{
						NSError *error = nil;
						[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
			
						if (error) {
							DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
						}
						
						[infos removeObjectAtIndex:i];
						[changes addObject:[nodeID copy]]; // mutable string protection
						shouldPostNotification = YES;
					}
					else
					{
						info.pendingDelete = YES;
						i++;
					}
				}
			
				if (infos.count == 0) {
					[dict removeObjectForKey:nodeID];
				}
			}
		}
		
		if (shouldPostNotification) {
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

/**
 * See header file for description.
 */
- (void)makeNodeDataPersistent:(BOOL)persistent forNodeID:(NSString *)nodeID
{
	ZDCFileType type = ZDCFileType_NodeData;
	ZDCStorageMode dstMode = persistent ? ZDCStorageMode_Persistent : ZDCStorageMode_Cache;
	
	dispatch_block_t block = ^{ @autoreleasepool{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeData;
		
		NSMutableArray <ZDCFileInfo *> *infos = dict[nodeID];
		if (infos.count == 0) return; // from block
		
		NSMutableArray<ZDCFileInfo *> *infosToMigrate = [NSMutableArray arrayWithCapacity:infos.count];
		
		for (ZDCFileInfo *info in infos)
		{
			if (info.mode != dstMode)
			{
				[infosToMigrate addObject:info];
			}
		}
		
		for (ZDCFileInfo *srcInfo in infosToMigrate)
		{
			ZDCFileInfo *matchingDstInfo = nil;
			for (ZDCFileInfo *info in infos)
			{
				if ([info matchesMode:dstMode type:type format:srcInfo.format])
				{
					matchingDstInfo = info;
					break;
				}
			}
		
			if (matchingDstInfo)
			{
				// Destination file & info already exists.
				// Just delete the src file & info.
		
				if (srcInfo.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:srcInfo.fileURL error:&error];
			
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [srcInfo.fileURL path], error);
					}
					else
					{
						[infos removeObjectIdenticalTo:srcInfo];
					}
				}
				else
				{
					srcInfo.pendingDelete = YES;
				}
		
				// Edge case:
				// User has been moving files back-and-forth (between persistent & non-persistent).
				// So undo a potential pendingDelete on the matchingDstInfo if needed.
				//
				matchingDstInfo.pendingDelete = NO;
			}
			else // if (!matchingDstInfo)
			{
				NSURL *dstDirURL = [self URLForMode:dstMode type:type format:srcInfo.format];
				NSURL *dstFileURL = [dstDirURL URLByAppendingPathComponent:nodeID isDirectory:NO];
				
				ZDCFileInfo *dstInfo = [srcInfo duplicateWithMode:dstMode fileURL:dstFileURL];
				
				NSDate *now = [NSDate date];
				dstInfo.lastModified = now;
				dstInfo.lastAccessed = now;
				
				if (srcInfo.fileRetainCount == 0)
				{
					// We can safely move the file into it's new place.
					
					NSError *error = nil;
					[fileManager moveItemAtURL:srcInfo.fileURL toURL:dstFileURL error:&error];
					
					if (error)
					{
						DDLogWarn(@"Error moving file: src(%@) -> dst(%@): %@",
						            [srcInfo.fileURL path], [dstFileURL path], error);
					}
					else
					{
						[infos removeObjectIdenticalTo:srcInfo];
						[infos addObject:dstInfo];
					}
				}
				else
				{
					// We can't move the file because there's a retainToken for it.
					// So we need to perform a copy instead.
					
					NSError *error = nil;
					[fileManager copyItemAtURL:srcInfo.fileURL toURL:dstFileURL error:&error];
					
					if (error)
					{
						DDLogWarn(@"Error copying file: src(%@) -> dst(%@): %@",
						           [srcInfo.fileURL path], [dstFileURL path], error);
					}
					else
					{
						srcInfo.pendingDelete = YES;
						[infos addObject:dstInfo];
					}
				}
				
				if (!persistent && dstInfo.migrateAfterUpload)
				{
					[self setShouldMigrateAfterUpload:NO forURL:dstFileURL];
					dstInfo.migrateAfterUpload = NO;
				}
			}
		}
		
		if (infosToMigrate.count > 0 && !persistent)
		{
			[self maybeTrimCachePool:type];
			[self maybeUpdateExpirationTimer:type];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Thumbnails
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (nullable ZDCCryptoFile *)importNodeThumbnail:(ZDCDiskImport *)import
                                        forNode:(ZDCNode *)node
                                          error:(NSError *_Nullable *_Nullable)outError
{
	DDLogAutoTrace();
	
	NSError *error = nil;
	
	if (import == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: import is nil"];
	}
	else if (node == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: node is nil"];
	}
	else if (node.encryptionKey == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: node.encryptionKey is nil"];
	}
	else if (import.cleartextFileURL || import.cryptoFile)
	{
		NSURL *fileURL = import.cleartextFileURL ?: import.cryptoFile.fileURL;
		
		BOOL isAlreadyManaged = [self getMode:nil type:nil format:nil forFileURL:fileURL];
		if (isAlreadyManaged)
		{
			// The file cannot be imported because it's already imported.
			error = [NSError errorWithClass: [self class]
			                           code: 400
			                    description: @"Bad parameter: cryptoFile is already managed"];
		}
	}
	
	if (error)
	{
		if (outError) *outError = error;
		return nil;
	}
	
	void (^WarnIfMainThread)(void) = ^{
		if ([NSThread isMainThread]) {
			DDLogWarn(@"Performing synchronous disk IO (+encryption) on the main thread."
			          @" This is NOT recommended."
						 @" (via: [%@ %@]", THIS_FILE, THIS_METHOD);
		}
	};
	
	NSURL *srcURL = nil;
	
	if (import.cleartextData)
	{
		WarnIfMainThread();
		
		srcURL = [ZDCDirectoryManager generateTempURL];
		[ZDCFileConversion encryptCleartextData: import.cleartextData
		                     toCacheFileWithKey: node.encryptionKey
		                              outputURL: srcURL
		                                  error: &error];
		if (error) {
			DDLogWarn(@"Error encrypting import.cleartextData: %@", error);
		}
	}
	else if (import.cleartextFileURL)
	{
		WarnIfMainThread();
		
		srcURL = [ZDCDirectoryManager generateTempURL];
		[ZDCFileConversion encryptCleartextFile: import.cleartextFileURL
		                     toCacheFileWithKey: node.encryptionKey
		                              outputURL: srcURL
		                                  error: &error];
		if (error) {
			DDLogWarn(@"Error encrypting import.cleartextFileURL: %@", error);
		}
	}
	else if (import.cryptoFile)
	{
		if ([import.cryptoFile.encryptionKey isEqual:node.encryptionKey])
		{
			srcURL = import.cryptoFile.fileURL;
		}
		else
		{
			WarnIfMainThread();
			
			srcURL = [ZDCDirectoryManager generateTempURL];
			[ZDCFileConversion reEncryptFile: import.cryptoFile.fileURL
			                         fromKey: import.cryptoFile.encryptionKey
			                          toFile: srcURL
			                           toKey: node.encryptionKey
			                           error: &error];
			if (error) {
				DDLogWarn(@"Error re-encrypting import.cryptoFile: %@", error);
			}
		}
	}
	else // import.isNilPlaceholder
	{
		srcURL = [ZDCDirectoryManager generateTempURL];
		[[NSData data] writeToURL:srcURL options:0 error:&error];
	}
	
	if (error)
	{
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCFileType type = ZDCFileType_NodeThumbnail;
	ZDCStorageMode mode = import.storePersistently ? ZDCStorageMode_Persistent : ZDCStorageMode_Cache;
	ZDCCryptoFileFormat format = import.cryptoFile ? import.cryptoFile.fileFormat : ZDCCryptoFileFormat_CacheFile;
	
	NSURL *dir = [self URLForMode:mode type:type format:format];
	NSURL *dstURL = [dir URLByAppendingPathComponent:node.uuid isDirectory:NO];
	
	[fileManager moveItemAtURL:srcURL toURL:dstURL error:&error];
	
	if (error)
	{
		DDLogWarn(@"Error moving file: src(%@) -> dst(%@): %@",
		            [srcURL path], [dstURL path], error);
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSNumber *fileSize = nil;
	if (import.isNilPlaceholder) {
		fileSize = @(0);
	} else {
		[dstURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
	}
	
	__block ZDCFileRetainToken *retainToken = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeThumbnails;
		NSMutableSet<NSString*> *changes = changes_nodeThumbnails;
		
		NSMutableArray<ZDCFileInfo *> *infos = dict[node.uuid];
		if (infos == nil)
		{
			infos = [[NSMutableArray alloc] initWithCapacity:1];
			dict[node.uuid] = infos;
		}
		
		ZDCFileInfo *matchingInfo = nil;
		
		NSUInteger i = 0;
		while (i < infos.count)
		{
			ZDCFileInfo *info = infos[i];
			
			if ([info matchesMode:mode type:type format:format])
			{
				matchingInfo = info;
				i++;
			}
			else
			{
				// The info doesn't match what's being imported (different format, different persistent setting, etc).
				// This means the particular file is now outdated, and needs to be deleted.
				
				if (info.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
					
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
					}
					
					[infos removeObjectAtIndex:i];
				}
				else
				{
					info.pendingDelete = YES;
					i++;
				}
			}
		}
		
		// If matchingInfo exists, then leave it be.
		// We need to preserve the following:
		//
		// - info.fileRetainCount
		//
		if (matchingInfo == nil)
		{
			matchingInfo = [[ZDCFileInfo alloc] initWithMode:mode type:type format:format fileURL:dstURL];
			matchingInfo.nodeID = node.uuid;
			
			[infos addObject:matchingInfo];
		}
		
		matchingInfo.fileSize = [fileSize unsignedLongLongValue];
		
		NSDate *now = [NSDate date];
		matchingInfo.lastAccessed = now;
		matchingInfo.lastModified = now;
		
		matchingInfo.migrateAfterUpload = import.migrateToCacheAfterUpload;
		matchingInfo.deleteAfterUpload = import.deleteAfterUpload;
		matchingInfo.expiration = import.expiration;
		matchingInfo.eTag = import.eTag ?: [NSNull null];
		
		if (import.storePersistently && import.migrateToCacheAfterUpload) {
			[self setShouldMigrateAfterUpload:YES forURL:dstURL];
		}
		if (import.deleteAfterUpload) {
			[self setShouldDeleteAfterUpload:YES forURL:dstURL];
		}
		if (import.expiration != 0) {
			// Write xattr even if not persistent (in case file is migrated)
			[self setExpiration:import.expiration forURL:dstURL];
		}
		if (import.eTag) {
			[self setETag:import.eTag forURL:dstURL withEncryptionKey:node.encryptionKey];
		}
		
		[matchingInfo incrementFileRetainCount];
		retainToken = [[ZDCFileRetainToken alloc] initWithInfo:matchingInfo owner:self];
		
		[changes addObject:node.uuid];
		if (!import.storePersistently)
		{
			[self maybeTrimCachePool:type];
			[self maybeUpdateExpirationTimer:type];
		}
		[self postDiskManagerChangedNotification];
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	ZDCCryptoFile *result =
	  [[ZDCCryptoFile alloc] initWithFileURL: dstURL
	                              fileFormat: format
	                           encryptionKey: node.encryptionKey
	                             retainToken: retainToken];
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)hasNodeThumbnail:(NSString *)nodeID
{
	DDLogAutoTrace();
	
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeThumbnails;
		
		NSArray <ZDCFileInfo *> *infos = dict[nodeID];
		for (ZDCFileInfo *info in infos)
		{
			if (!info.pendingDelete) {
				result = YES;
				break;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	return result;
}

/**
 * See header file for description.
 */
- (nullable ZDCDiskExport *)nodeThumbnail:(ZDCNode *)node
{
	DDLogAutoTrace();
	if (node == nil) return nil;
	
	__block NSURL *fileURL = nil;
	__block ZDCCryptoFileFormat format = ZDCCryptoFileFormat_Unknown;
	
	__block BOOL isNilPlaceholder = NO;
	__block ZDCFileRetainToken *retainToken = nil;
	
	__block BOOL isPersistent = NO;
	__block NSString *eTag = nil;
	__block NSTimeInterval expiration = 0;

	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeThumbnails;
		
		NSArray <ZDCFileInfo *> *infos = dict[node.uuid];
		ZDCFileInfo *info = nil;
		
		for (ZDCFileInfo *i in infos)
		{
			if (!i.pendingDelete) {
				info = i;
				break;
			}
		}
		
		if (infos)
		{
			fileURL = info.fileURL;
			format = info.format;
			
			if (info.fileSize == 0)
			{
				isNilPlaceholder = YES;
			}
			else
			{
				[info incrementFileRetainCount];
				retainToken = [[ZDCFileRetainToken alloc] initWithInfo:info owner:self];
			}
			
			info.lastAccessed = [NSDate date];
			
			isPersistent = info.isStoredPersistently;
			
			if (info.eTag == nil) // we read eTag xattr only on demand
			{
				NSString *eTag = nil;
				if ([self getETag:&eTag forURL:info.fileURL withEncryptionKey:node.encryptionKey])
				{
					info.eTag = eTag ?: [NSNull null];
				}
			}
			
			if ([info.eTag isKindOfClass:[NSString class]]) {
				eTag = (NSString *)info.eTag;
			}
			expiration = info.expiration;
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	ZDCCryptoFile *cryptoFile = nil;
	if (fileURL && node.encryptionKey && !isNilPlaceholder)
	{
		cryptoFile = [[ZDCCryptoFile alloc] initWithFileURL: fileURL
		                                         fileFormat: format
		                                      encryptionKey: node.encryptionKey
		                                        retainToken: retainToken];
	}
	
	ZDCDiskExport *export = nil;
	if (isNilPlaceholder || cryptoFile)
	{
		export = [[ZDCDiskExport alloc] initWithCryptoFile: cryptoFile
		                                      isPersistent: isPersistent
		                                              eTag: eTag
		                                        expiration: expiration];
	}
	
	return export;
}

/**
 * See header file for description.
 */
- (void)deleteNodeThumbnail:(NSString *)nodeID
{
	[self deleteNodeThumbnailsForNodeIDs:@[ nodeID ]];
}

/**
 * See header file for description.
 */
- (void)deleteNodeThumbnailsForNodeIDs:(NSArray<NSString*> *)nodeIDs
{
	DDLogAutoTrace();
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeThumbnails;
		NSMutableSet<NSString*> *changes = changes_nodeThumbnails;
		
		BOOL shouldPostNotification = NO;
		
		for (NSString *nodeID in nodeIDs)
		{
			NSMutableArray<ZDCFileInfo *> *infos = dict[nodeID];
			if (infos)
			{
				NSUInteger i = 0;
				while (i < infos.count)
				{
					ZDCFileInfo *info = infos[i];
		
					if (info.fileRetainCount == 0)
					{
						NSError *error = nil;
						[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
			
						if (error) {
								DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
						}
			
						[infos removeObjectAtIndex:i];
						[changes addObject:[nodeID copy]]; // mutable string protection
						shouldPostNotification = YES;
					}
					else
					{
						info.pendingDelete = YES;
						i++;
					}
				}
			
				if (infos.count == 0) {
					[dict removeObjectForKey:nodeID];
				}
			}
		}
		
		if (shouldPostNotification) {
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

/**
 * See header file for description.
 */
- (void)makeNodeThumbnailPersistent:(BOOL)persistent forNodeID:(NSString *)nodeID
{
	ZDCFileType type = ZDCFileType_NodeThumbnail;
	ZDCStorageMode dstMode = persistent ? ZDCStorageMode_Persistent : ZDCStorageMode_Cache;
	
	dispatch_block_t block = ^{ @autoreleasepool{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_nodeThumbnails;
		
		NSMutableArray <ZDCFileInfo *> *infos = dict[nodeID];
		if (infos.count == 0) return; // from block
		
		NSMutableArray<ZDCFileInfo *> *infosToMigrate = [NSMutableArray arrayWithCapacity:infos.count];
		
		for (ZDCFileInfo *info in infos)
		{
			if (info.mode != dstMode)
			{
				[infosToMigrate addObject:info];
			}
		}
		
		for (ZDCFileInfo *srcInfo in infosToMigrate)
		{
			ZDCFileInfo *matchingDstInfo = nil;
			for (ZDCFileInfo *info in infos)
			{
				if ([info matchesMode:dstMode type:type format:srcInfo.format])
				{
					matchingDstInfo = info;
					break;
				}
			}
		
			if (matchingDstInfo)
			{
				// Destination file & info already exists.
				// Just delete the src file & info.
		
				if (srcInfo.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:srcInfo.fileURL error:&error];
			
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [srcInfo.fileURL path], error);
					}
					else
					{
						[infos removeObjectIdenticalTo:srcInfo];
					}
				}
				else
				{
					srcInfo.pendingDelete = YES;
				}
		
				// Edge case:
				// User has been moving files back-and-forth (between persistent & non-persistent).
				// So undo a potential pendingDelete on the matchingDstInfo if needed.
				//
				matchingDstInfo.pendingDelete = NO;
			}
			else // if (!matchingDstInfo)
			{
				NSURL *dstDirURL = [self URLForMode:dstMode type:type format:srcInfo.format];
				NSURL *dstFileURL = [dstDirURL URLByAppendingPathComponent:nodeID isDirectory:NO];
				
				ZDCFileInfo *dstInfo = [srcInfo duplicateWithMode:dstMode fileURL:dstFileURL];
				
				NSDate *now = [NSDate date];
				dstInfo.lastModified = now;
				dstInfo.lastAccessed = now;
				
				if (srcInfo.fileRetainCount == 0)
				{
					// We can safely move the file into it's new place.
					
					NSError *error = nil;
					[fileManager moveItemAtURL:srcInfo.fileURL toURL:dstFileURL error:&error];
					
					if (error)
					{
						DDLogWarn(@"Error moving file: src(%@) -> dst(%@): %@",
						            [srcInfo.fileURL path], [dstFileURL path], error);
					}
					else
					{
						[infos removeObjectIdenticalTo:srcInfo];
						[infos addObject:dstInfo];
					}
				}
				else
				{
					// We can't move the file because there's a retainToken for it.
					// So we need to perform a copy instead.
					
					NSError *error = nil;
					[fileManager copyItemAtURL:srcInfo.fileURL toURL:dstFileURL error:&error];
					
					if (error)
					{
						DDLogWarn(@"Error copying file: src(%@) -> dst(%@): %@",
						           [srcInfo.fileURL path], [dstFileURL path], error);
					}
					else
					{
						srcInfo.pendingDelete = YES;
						[infos addObject:dstInfo];
					}
				}
				
				if (!persistent && dstInfo.migrateAfterUpload)
				{
					[self setShouldMigrateAfterUpload:NO forURL:dstFileURL];
					dstInfo.migrateAfterUpload = NO;
				}
			}
		}
		
		if (infosToMigrate.count > 0 && !persistent)
		{
			[self maybeTrimCachePool:type];
			[self maybeUpdateExpirationTimer:type];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Avatars
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (nullable ZDCCryptoFile *)importUserAvatar:(ZDCDiskImport *)import
                                     forUser:(ZDCUser *)user
                                     auth0ID:(NSString *)auth0ID
                                       error:(NSError *_Nullable *_Nullable)outError
{
	NSError *error = nil;
	
	if (import == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: import is nil"];
	}
	else if (user == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: user is nil"];
	}
	else if (user.random_encryptionKey == nil) {
		NSString *msg = @"Bad parameter: user.random_encryptionKey is nil";
		error = [NSError errorWithClass:[self class] code:400 description:msg];
	}
	else if (auth0ID == nil) {
		error = [NSError errorWithClass:[self class] code:400 description:@"Bad parameter: auth0ID is nil"];
	}
	else if (import.cleartextFileURL || import.cryptoFile)
	{
		NSURL *fileURL = import.cleartextFileURL ?: import.cryptoFile.fileURL;
		
		BOOL isAlreadyManaged = [self getMode:nil type:nil format:nil forFileURL:fileURL];
		if (isAlreadyManaged)
		{
			// The file cannot be imported because it's already imported.
			error = [NSError errorWithClass: [self class]
			                           code: 400
			                    description: @"Bad parameter: cryptoFile is already managed"];
		}
	}
	
	if (error)
	{
		if (outError) *outError = error;
		return nil;
	}
	
	void (^WarnIfMainThread)(void) = ^{
		if ([NSThread isMainThread]) {
			DDLogWarn(@"Performing synchronous disk IO (+encryption) on the main thread."
			          @" This is NOT recommended."
						 @" (via: [%@ %@]", THIS_FILE, THIS_METHOD);
		}
	};
	
	NSURL *srcURL = nil;
	
	if (import.cleartextData)
	{
		WarnIfMainThread();
		
		srcURL = [ZDCDirectoryManager generateTempURL];
		[ZDCFileConversion encryptCleartextData: import.cleartextData
		                     toCacheFileWithKey: user.random_encryptionKey
		                              outputURL: srcURL
		                                  error: &error];
		if (error) {
			DDLogWarn(@"Error encrypting import.cleartextData: %@", error);
		}
	}
	else if (import.cleartextFileURL)
	{
		WarnIfMainThread();
		
		srcURL = [ZDCDirectoryManager generateTempURL];
		[ZDCFileConversion encryptCleartextFile: import.cleartextFileURL
		                     toCacheFileWithKey: user.random_encryptionKey
		                              outputURL: srcURL
		                                  error: &error];
		if (error) {
			DDLogWarn(@"Error encrypting import.cleartextFileURL: %@", error);
		}
	}
	else if (import.cryptoFile)
	{
		if ([import.cryptoFile.encryptionKey isEqual:user.random_encryptionKey])
		{
			srcURL = import.cryptoFile.fileURL;
		}
		else
		{
			WarnIfMainThread();
			
			srcURL = [ZDCDirectoryManager generateTempURL];
			[ZDCFileConversion reEncryptFile: import.cryptoFile.fileURL
			                         fromKey: import.cryptoFile.encryptionKey
			                          toFile: srcURL
			                           toKey: user.random_encryptionKey
			                           error: &error];
			if (error) {
				DDLogWarn(@"Error re-encrypting import.cryptoFile: %@", error);
			}
		}
	}
	else // import.isNilPlaceholder
	{
		srcURL = [ZDCDirectoryManager generateTempURL];
		[[NSData data] writeToURL:srcURL options:0 error:&error];
	}
	
	if (error)
	{
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCFileType type = ZDCFileType_UserAvatar;
	ZDCStorageMode mode = import.storePersistently ? ZDCStorageMode_Persistent : ZDCStorageMode_Cache;
	ZDCCryptoFileFormat format = ZDCCryptoFileFormat_CacheFile;
	
	NSString *filename = [NSString stringWithFormat:@"%@.%@",
	  user.random_uuid,
	  [self hashAuth0ID:auth0ID forUser:user]];
	
	NSURL *dir = [self URLForMode:mode type:type format:format];
	NSURL *dstURL = [dir URLByAppendingPathComponent:filename isDirectory:NO];
	
	[fileManager moveItemAtURL:srcURL toURL:dstURL error:&error];
	
	if (error)
	{
		DDLogWarn(@"Error moving file: src(%@) -> dst(%@): %@",
		            [srcURL path], [dstURL path], error);
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSNumber *fileSize = nil;
	if (import.isNilPlaceholder) {
		fileSize = @(0);
	} else {
		[dstURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
	}
	
	__block ZDCFileRetainToken *retainToken = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		NSMutableSet<NSString*> *changes = changes_userAvatars;
		
		NSMutableArray <ZDCFileInfo *> *infos = dict[user.uuid];
		if (infos == nil)
		{
			infos = [[NSMutableArray alloc] initWithCapacity:1];
			dict[user.uuid] = infos;
		}
		
		ZDCFileInfo *matchingInfo = nil;
		
		NSUInteger i = 0;
		while (i < infos.count)
		{
			ZDCFileInfo *info = infos[i];
			
			if ([info matchesMode:mode type:type format:format auth0ID:auth0ID])
			{
				matchingInfo = info;
				i++;
			}
			else
			{
				// The info doesn't match what's being imported (different format, different persistent setting, etc).
				// This means the particular file is now outdated, and needs to be deleted.
				
				if (info.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
					
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
					}
					
					[infos removeObjectAtIndex:i];
				}
				else
				{
					info.pendingDelete = YES;
					i++;
				}
			}
		}
		
		// If matchingInfo exists, then leave it be.
		// We need to preserve the following:
		//
		// - info.fileRetainCount
		//
		if (matchingInfo == nil)
		{
			matchingInfo = [[ZDCFileInfo alloc] initWithMode:mode type:type format:format fileURL:dstURL];
			matchingInfo.userID = user.uuid;
			matchingInfo.auth0ID = auth0ID;
			
			[infos addObject:matchingInfo];
		}
		
		matchingInfo.fileSize = [fileSize unsignedLongLongValue];
		
		NSDate *now = [NSDate date];
		matchingInfo.lastAccessed = now;
		matchingInfo.lastModified = now;
		
		matchingInfo.migrateAfterUpload = import.migrateToCacheAfterUpload;
		matchingInfo.deleteAfterUpload = import.deleteAfterUpload;
		matchingInfo.expiration = import.expiration;
		matchingInfo.eTag = import.eTag ?: [NSNull null];
		
		if (import.storePersistently && import.migrateToCacheAfterUpload) {
			[self setShouldMigrateAfterUpload:YES forURL:dstURL];
		}
		if (import.deleteAfterUpload) {
			[self setShouldDeleteAfterUpload:YES forURL:dstURL];
		}
		if (import.expiration != 0) {
			// Write xattr even if not persistent (in case file is migrated)
			[self setExpiration:import.expiration forURL:dstURL];
		}
		if (import.eTag) {
			[self setETag:import.eTag forURL:dstURL withEncryptionKey:user.random_encryptionKey];
		}
		
		[matchingInfo incrementFileRetainCount];
		retainToken = [[ZDCFileRetainToken alloc] initWithInfo:matchingInfo owner:self];
		
		[changes addObject:user.uuid];
		if (!import.storePersistently)
		{
			[self maybeTrimCachePool:type];
			[self maybeUpdateExpirationTimer:type];
		}
		[self postDiskManagerChangedNotification];
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	ZDCCryptoFile *result =
	  [[ZDCCryptoFile alloc] initWithFileURL: dstURL
	                              fileFormat: format
	                           encryptionKey: user.random_encryptionKey
	                             retainToken: retainToken];
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)hasUserAvatar:(NSString *)userID
{
	return [self hasUserAvatar:userID forAuth0ID:nil];
}

/**
 * See header file for description.
 */
- (BOOL)hasUserAvatar:(NSString *)userID forAuth0ID:(nullable NSString *)auth0ID
{
	DDLogAutoTrace();
	
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{ @autoreleasepool{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		
		NSArray <ZDCFileInfo *> *infos = dict[userID];
		for (ZDCFileInfo *info in infos)
		{
			if (!info.pendingDelete)
			{
				if (auth0ID == nil || [info.auth0ID isEqualToString:auth0ID])
				{
					result = YES;
					break;
				}
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	return result;
}

/**
 * See header file for description.
 */
- (nullable ZDCDiskExport *)userAvatar:(ZDCUser *)user
{
	return [self userAvatar:user forAuth0ID:nil];
}

/**
 * See header file for description.
 */
- (nullable ZDCDiskExport *)userAvatar:(ZDCUser *)user forAuth0ID:(nullable NSString *)auth0ID
{
	DDLogAutoTrace();
	
	if (user == nil) return nil;
	NSParameterAssert([user isKindOfClass:[ZDCUser class]]);
	
	__block NSURL *fileURL = nil;
	__block ZDCCryptoFileFormat format = ZDCCryptoFileFormat_Unknown;
	
	__block BOOL isNilPlaceholder = NO;
	__block ZDCFileRetainToken *retainToken = nil;
	
	__block BOOL isPersistent = NO;
	__block NSString *eTag = nil;
	__block NSTimeInterval expiration = 0;

	// If auth0ID is nil, we should attempt to return the ZDCFileInfo that matches user.auth0_preferredID.
	// If we fail to find it, then return none. This will force us to look it up.
	//
	if (auth0ID == nil)
	{
		auth0ID = user.auth0_preferredID;
	}
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		
		NSArray <ZDCFileInfo *> *infos = dict[user.uuid];
		if (infos.count > 0)
		{
			ZDCFileInfo *matchingInfo = nil;
			
			for (ZDCFileInfo *info in infos)
			{
				if (!info.pendingDelete && [info.auth0ID isEqualToString:auth0ID])
				{
					matchingInfo = info;
					break;
				}
			}
			
			if (matchingInfo)
			{
				fileURL = matchingInfo.fileURL;
				format = matchingInfo.format;
				
				if (matchingInfo.fileSize == 0)
				{
					isNilPlaceholder = YES;
				}
				else
				{
					[matchingInfo incrementFileRetainCount];
					retainToken = [[ZDCFileRetainToken alloc] initWithInfo:matchingInfo owner:self];
				}
				
				matchingInfo.lastAccessed = [NSDate date];
				
				isPersistent = matchingInfo.isStoredPersistently;
				
				if (matchingInfo.eTag == nil) // we read eTag xattr only on demand
				{
					NSString *eTag = nil;
					if ([self getETag:&eTag forURL:matchingInfo.fileURL withEncryptionKey:user.random_encryptionKey])
					{
						matchingInfo.eTag = eTag ?: [NSNull null];
					}
				}
				
				if ([matchingInfo.eTag isKindOfClass:[NSString class]]) {
					eTag = (NSString *)matchingInfo.eTag;
				}
				expiration = matchingInfo.expiration;
			}
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
	
	ZDCCryptoFile *cryptoFile = nil;
	if (fileURL && user.random_encryptionKey && !isNilPlaceholder)
	{
		cryptoFile = [[ZDCCryptoFile alloc] initWithFileURL: fileURL
		                                         fileFormat: format
		                                      encryptionKey: user.random_encryptionKey
		                                        retainToken: retainToken];
	}
	
	ZDCDiskExport *export = nil;
	if (isNilPlaceholder || cryptoFile)
	{
		export = [[ZDCDiskExport alloc] initWithCryptoFile: cryptoFile
		                                      isPersistent: isPersistent
		                                              eTag: eTag
		                                        expiration: expiration];
	}
	
	return export;
}

/**
 * See header file for description.
 */
- (void)deleteUserAvatar:(NSString *)userID
{
	if (userID == nil) return;
	
	[self deleteUserAvatarsForUserIDs:@[ userID ]];
}

/**
 * See header file for description.
 */
- (void)deleteUserAvatarsForUserIDs:(NSArray<NSString*> *)userIDs
{
	DDLogAutoTrace();
	
	if (userIDs.count == 0) return;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		NSMutableSet<NSString*> *changes = changes_userAvatars;
		
		BOOL shouldPostNotification = NO;
		
		for (NSString *userID in userIDs)
		{
			NSMutableArray<ZDCFileInfo *> *infos = dict[userID];
			if (infos)
			{
				NSUInteger i = 0;
				while (i < infos.count)
				{
					ZDCFileInfo *info = infos[i];
		
					if (info.fileRetainCount == 0)
					{
						NSError *error = nil;
						[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
			
						if (error) {
								DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
						}
			
						[infos removeObjectAtIndex:i];
						[changes addObject:[userID copy]]; // mutable string protection
						shouldPostNotification = YES;
					}
					else
					{
						info.pendingDelete = YES;
						i++;
					}
				}
			
				if (infos.count == 0) {
					[dict removeObjectForKey:userID];
				}
			}
		}
		
		if (shouldPostNotification) {
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

/**
 * See header file for description.
 */
- (void)deleteUserAvatar:(NSString *)userID forAuth0ID:(NSString *)auth0ID
{
	if (userID == nil) return;
	if (auth0ID == nil) return;
	
	[self deleteUserAvatarsForTuples:@[ YapCollectionKeyCreate(userID, auth0ID) ]];
}

/**
 * Used by garbage collection routine.
 */
- (void)deleteUserAvatarsForTuples:(NSArray<YapCollectionKey*> *)tuples
{
	DDLogAutoTrace();
	
	if (tuples.count == 0) return;
	
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		NSMutableSet<NSString*> *changes = changes_userAvatars;
		
		BOOL shouldPostNotification = NO;
		
		for (YapCollectionKey *tuple in tuples)
		{
			NSString *userID = tuple.collection;
			NSString *auth0ID = tuple.key;
			
			NSMutableArray<ZDCFileInfo *> *infos = dict[userID];
		
			NSUInteger i = 0;
			while (i < infos.count)
			{
				ZDCFileInfo *info = infos[i];
				
				if ([info.auth0ID isEqualToString:auth0ID])
				{
					if (info.fileRetainCount == 0)
					{
						NSError *error = nil;
						[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
						
						if (error) {
							DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
						}
						
						[infos removeObjectAtIndex:i];
						[changes addObject:[userID copy]]; // mutable string protection
						shouldPostNotification = YES;
					}
					else
					{
						info.pendingDelete = YES;
						i++;
					}
				}
				else
				{
					i++;
				}
			}
		}
		
		if (shouldPostNotification) {
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

/**
 * Used by cleanup routine.
 *
 * @see `databaseModified:`
 */
- (void)deleteUserAvatars:(NSString *)userID excluding:(NSSet<NSString*> *)auth0IDs
{
	dispatch_block_t block = ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		NSMutableSet<NSString*> *changes = changes_userAvatars;
		
		BOOL shouldPostNotification = NO;
		
		NSMutableArray<ZDCFileInfo *> *infos = dict[userID];
		
		NSUInteger i = 0;
		while (i < infos.count)
		{
			ZDCFileInfo *info = infos[i];
			
			if (info.auth0ID && ![auth0IDs containsObject:info.auth0ID])
			{
				if (info.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:info.fileURL error:&error];
					
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [info.fileURL path], error);
					}
					
					[infos removeObjectAtIndex:i];
					[changes addObject:[userID copy]]; // mutable string protection
					shouldPostNotification = YES;
				}
				else
				{
					info.pendingDelete = YES;
					i++;
				}
			}
			else
			{
				i++;
			}
		}
		
		if (shouldPostNotification) {
			[self postDiskManagerChangedNotification];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

/**
 * See header file for description.
 */
- (void)makeUserAvatarPersistent:(BOOL)persistent forUserID:(NSString *)userID
{
	ZDCFileType type = ZDCFileType_UserAvatar;
	ZDCStorageMode dstMode = persistent ? ZDCStorageMode_Persistent : ZDCStorageMode_Cache;
	
	dispatch_block_t block = ^{ @autoreleasepool{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableDictionary<NSString *, NSMutableArray<ZDCFileInfo *> *> *dict = dict_userAvatars;
		
		NSMutableArray <ZDCFileInfo *> *infos = dict[userID];
		if (infos.count == 0) return; // from block
		
		NSMutableArray<ZDCFileInfo *> *infosToMigrate = [NSMutableArray arrayWithCapacity:infos.count];
		
		for (ZDCFileInfo *info in infos)
		{
			if (info.mode != dstMode)
			{
				[infosToMigrate addObject:info];
			}
		}
		
		for (ZDCFileInfo *srcInfo in infosToMigrate)
		{
			ZDCFileInfo *matchingDstInfo = nil;
			for (ZDCFileInfo *info in infos)
			{
				if ([info matchesMode:dstMode type:type format:srcInfo.format /* auth0ID:ANY */ ])
				{
					matchingDstInfo = info;
					break;
				}
			}
		
			if (matchingDstInfo)
			{
				// Destination file & info already exists.
				// Just delete the src file & info.
		
				if (srcInfo.fileRetainCount == 0)
				{
					NSError *error = nil;
					[[NSFileManager defaultManager] removeItemAtURL:srcInfo.fileURL error:&error];
			
					if (error) {
						DDLogWarn(@"Error deleting fileURL(%@): %@", [srcInfo.fileURL path], error);
					}
					else
					{
						[infos removeObjectIdenticalTo:srcInfo];
					}
				}
				else
				{
					srcInfo.pendingDelete = YES;
				}
		
				// Edge case:
				// User has been moving files back-and-forth (between persistent & non-persistent).
				// So undo a potential pendingDelete on the matchingDstInfo if needed.
				//
				matchingDstInfo.pendingDelete = NO;
			}
			else // if (!matchingDstInfo)
			{
				NSString *dstFileName = [srcInfo.fileURL lastPathComponent];
				
				NSURL *dstDirURL = [self URLForMode:dstMode type:type format:srcInfo.format];
				NSURL *dstFileURL = [dstDirURL URLByAppendingPathComponent:dstFileName isDirectory:NO];
				
				ZDCFileInfo *dstInfo = [srcInfo duplicateWithMode:dstMode fileURL:dstFileURL];
				
				NSDate *now = [NSDate date];
				dstInfo.lastModified = now;
				dstInfo.lastAccessed = now;
				
				if (srcInfo.fileRetainCount == 0)
				{
					// We can safely move the file into it's new place.
					
					NSError *error = nil;
					[fileManager moveItemAtURL:srcInfo.fileURL toURL:dstFileURL error:&error];
					
					if (error)
					{
						DDLogWarn(@"Error moving file: src(%@) -> dst(%@): %@",
						            [srcInfo.fileURL path], [dstFileURL path], error);
					}
					else
					{
						[infos removeObjectIdenticalTo:srcInfo];
						[infos addObject:dstInfo];
					}
				}
				else
				{
					// We can't move the file because there's a retainToken for it.
					// So we need to perform a copy instead.
					
					NSError *error = nil;
					[fileManager copyItemAtURL:srcInfo.fileURL toURL:dstFileURL error:&error];
					
					if (error)
					{
						DDLogWarn(@"Error copying file: src(%@) -> dst(%@): %@",
						           [srcInfo.fileURL path], [dstFileURL path], error);
					}
					else
					{
						srcInfo.pendingDelete = YES;
						[infos addObject:dstInfo];
					}
				}
			}
		}
		
		if (infosToMigrate.count > 0 && !persistent)
		{
			[self maybeTrimCachePool:type];
			[self maybeUpdateExpirationTimer:type];
		}
		
	#pragma clang diagnostic pop
	}};
	
	if (dispatch_get_specific(IsOnCacheQueueKey))
		block();
	else
		dispatch_sync(cacheQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Storage Sizes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForAllNodeData
{
	uint64_t total = 0;
	total += [self storageSizeForPersistentNodeData];
	total += [self storageSizeForCachedNodeData];
	
	return total;
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForPersistentNodeData
{
	uint64_t total = 0;
	total += [self storageSizeForMode: ZDCStorageMode_Persistent
	                             type: ZDCFileType_NodeData
	                           format: ZDCCryptoFileFormat_CacheFile];
	
	total += [self storageSizeForMode: ZDCStorageMode_Persistent
	                             type: ZDCFileType_NodeData
	                           format: ZDCCryptoFileFormat_CloudFile];
	
	return total;
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForCachedNodeData
{
	uint64_t total = 0;
	total += [self storageSizeForMode: ZDCStorageMode_Cache
	                             type: ZDCFileType_NodeData
	                           format: ZDCCryptoFileFormat_CacheFile];
	
	total += [self storageSizeForMode: ZDCStorageMode_Cache
	                             type: ZDCFileType_NodeData
	                           format: ZDCCryptoFileFormat_CloudFile];
	
	return total;
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForAllNodeThumbnails
{
	uint64_t total = 0;
	total += [self storageSizeForPersistentNodeThumbnail];
	total += [self storageSizeForCachedNodeThumbnails];
	
	return total;
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForPersistentNodeThumbnail
{
	return [self storageSizeForMode: ZDCStorageMode_Persistent
	                           type: ZDCFileType_NodeThumbnail
	                         format: ZDCCryptoFileFormat_CacheFile];
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForCachedNodeThumbnails
{
	return [self storageSizeForMode: ZDCStorageMode_Cache
	                           type: ZDCFileType_NodeThumbnail
	                         format: ZDCCryptoFileFormat_CacheFile];
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForAllUserAvatars
{
	uint64_t total = 0;
	total += [self storageSizeForPersistentUserAvatars];
	total += [self storageSizeForCachedUserAvatars];
	
	return total;
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForPersistentUserAvatars
{
	return [self storageSizeForMode: ZDCStorageMode_Persistent
	                           type: ZDCFileType_UserAvatar
	                         format: ZDCCryptoFileFormat_CacheFile];
}

/**
 * See header file for description.
 */
- (uint64_t)storageSizeForCachedUserAvatars
{
	return [self storageSizeForMode: ZDCStorageMode_Cache
	                           type: ZDCFileType_UserAvatar
	                         format: ZDCCryptoFileFormat_CacheFile];
}

- (uint64_t)storageSizeForMode:(ZDCStorageMode)mode
                          type:(ZDCFileType)type
                        format:(ZDCCryptoFileFormat)format
{
	uint64_t total = 0;
	
	NSURL *directoryURL = [self URLForMode:mode type:type format:format];
	
	NSDirectoryEnumerationOptions options =
	  NSDirectoryEnumerationSkipsSubdirectoryDescendants |
	  NSDirectoryEnumerationSkipsPackageDescendants      |
	  NSDirectoryEnumerationSkipsHiddenFiles;

	NSArray<NSString *> *keys = @[
		NSURLFileSizeKey
	];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL: directoryURL
	                       includingPropertiesForKeys: keys
	                                          options: options
	                                     errorHandler: NULL];
	
	for (NSURL *url in enumerator)
	{
		NSNumber *fileSize = nil;
		[url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
		
		total += [fileSize unsignedLongLongValue];
	}
	
	return total;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)deleteFileIfUnmanaged:(NSURL *)fileURL
{
	if (fileURL == nil) return;
	
	if ([self getMode:nil type:nil format:nil forFileURL:fileURL])
	{
		// File is being managed by us.
		// Do not delete.
	}
	else
	{
		[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDiskImport

@synthesize cleartextData = cleartextData;
@synthesize cleartextFileURL = cleartextFileURL;
@synthesize cryptoFile = cryptoFile;
@dynamic isNilPlaceholder;
@synthesize storePersistently;
@synthesize migrateToCacheAfterUpload;
@synthesize deleteAfterUpload;
@synthesize eTag;
@synthesize expiration;

- (instancetype)init
{
	if ((self = [super init])) {}
	return self;
}

- (instancetype)initWithCleartextData:(NSData *)inCleartextData
{
	if ((self = [super init]))
	{
		cleartextData = inCleartextData;
	}
	return self;
}

- (instancetype)initWithCleartextFileURL:(NSURL *)inCleartextFileURL
{
	if ((self = [super init]))
	{
		cleartextFileURL = inCleartextFileURL;
	}
	return self;
}

- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)inCryptoFile
{
	if ((self = [super init]))
	{
		cryptoFile = inCryptoFile;
	}
	return self;
}

- (BOOL)isNilPlaceholder
{
	return (cleartextData == nil) && (cleartextFileURL == nil) && (cryptoFile == nil);
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDiskExport

@synthesize cryptoFile = _cryptoFile;
@dynamic isNilPlaceholder;
@synthesize isStoredPersistently = _isStoredPersistently;
@synthesize eTag = _eTag;
@synthesize expiration = _expiration;

- (instancetype)initWithCryptoFile:(nullable ZDCCryptoFile *)inCryptoFile
                      isPersistent:(BOOL)isPersistent
                              eTag:(nullable NSString *)inETag
								expiration:(NSTimeInterval)inExpiration
{
	if ((self = [super init]))
	{
		_cryptoFile = inCryptoFile;
		_isStoredPersistently = isPersistent;
		_eTag = inETag;
		_expiration = inExpiration;
	}
	return self;
}

- (BOOL)isNilPlaceholder
{
	return (_cryptoFile == nil);
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDiskManagerChanges

@synthesize changedNodeIDs = changedNodeIDs;
@synthesize changedNodeData = changedNodeData;
@synthesize changedNodeThumbnails = changedNodeThumbnails;
@synthesize changedUsersIDs = changedUsersIDs;

- (instancetype)init
{
	if ((self = [super init]))
	{
		NSSet *emptySet = [NSSet set];
		
		changedNodeIDs        = emptySet;
		changedNodeData       = emptySet;
		changedNodeThumbnails = emptySet;
		changedUsersIDs       = emptySet;
	}
	return self;
}

@end
