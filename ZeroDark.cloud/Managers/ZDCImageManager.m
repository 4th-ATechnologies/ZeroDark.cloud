/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCImageManagerPrivate.h"

#import "Auth0Utilities.h"
#import "ZDCDatabaseManagerPrivate.h"
#import "ZDCDownloadManagerPrivate.h"
#import "ZDCLogging.h"

// Categories
#import "NSError+ZeroDark.h"

// Libraries
#import <YapDatabase/YapCache.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelVerbose | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@interface ZDCCachedImageItem : NSObject

- (instancetype)initWithKey:(NSString *)key image:(nullable OSImage *)image eTag:(nullable NSString *)eTag;

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, strong, readonly, nullable) OSImage *image;
@property (nonatomic, copy, readonly, nullable) NSString *eTag;

@end

@implementation ZDCCachedImageItem

@synthesize key = _key;
@synthesize image = _image;
@synthesize eTag = _eTag;

- (instancetype)initWithKey:(NSString *)key image:(nullable OSImage *)image eTag:(nullable NSString *)eTag
{
	if ((self = [super init]))
	{
		_key = [key copy];
		_image = image;
		_eTag = [eTag copy];
	}
	return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCImageManager () <NSCacheDelegate>
@end

@implementation ZDCImageManager {
	
	__weak ZeroDarkCloud *zdc;
	
	YapDatabaseConnection *internal_roConnection;
	dispatch_queue_t processingQueue;
	
	NSCache<NSString*, ZDCCachedImageItem*> *nodeThumbnailsCache;
	NSCache<NSString*, ZDCCachedImageItem*> *userAvatarsCache;
	
	dispatch_queue_t cacheKeysQueue;
	void *IsOnCacheKeysQueue;
	
	NSMutableSet<NSString*> *cacheKeys_nodeThumnails;
	NSMutableSet<NSString*> *cacheKeys_userAvatars;
}

@synthesize nodeThumbnailsCache = nodeThumbnailsCache;
@synthesize userAvatarsCache = userAvatarsCache;

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.downloadManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		internal_roConnection = [zdc.databaseManager internal_roConnection];
		processingQueue = dispatch_queue_create("ZDCImageManager-processing", DISPATCH_QUEUE_SERIAL);
		
		nodeThumbnailsCache = [[NSCache alloc] init];
		userAvatarsCache = [[NSCache alloc] init];
		
		nodeThumbnailsCache.countLimit = 0;
		nodeThumbnailsCache.totalCostLimit = (1024 * 1024 * 5); // 5 MiB
		
		userAvatarsCache.countLimit = 0;
		userAvatarsCache.totalCostLimit = (1024 * 1024 * 5); // 5 MiB
		
		nodeThumbnailsCache.delegate = self;
		userAvatarsCache.delegate = self;
		
		// There's no way to enumerate the keys in NSCache !!!
		//
		// So our workaround for now is to keep track of it ourself.
		// We may create a thread-safe version of YapCache in the future as a better solution.
		
		cacheKeysQueue = dispatch_queue_create("ZDCImageManager-keys", DISPATCH_QUEUE_SERIAL);
		
		IsOnCacheKeysQueue = &IsOnCacheKeysQueue;
		dispatch_queue_set_specific(cacheKeysQueue, IsOnCacheKeysQueue, IsOnCacheKeysQueue, NULL);
		
		cacheKeys_nodeThumnails = [[NSMutableSet alloc] init];
		cacheKeys_userAvatars = [[NSMutableSet alloc] init];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(diskManagerChanged:)
		                                             name: ZDCDiskManagerChangedNotification
		                                           object: zdc.diskManager];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)cache:(NSCache *)cache willEvictObject:(id)obj
{
	if (![obj isKindOfClass:[ZDCCachedImageItem class]]) {
		return;
	}
	
	ZDCCachedImageItem *item = (ZDCCachedImageItem *)obj;
	NSString *key = item.key;
	
	BOOL isNodeThumbnails = (cache == nodeThumbnailsCache);
	
	__weak typeof(self) weakSelf = self;
	dispatch_async(cacheKeysQueue, ^{ @autoreleasepool {
	
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		if (isNodeThumbnails) {
			[strongSelf->cacheKeys_nodeThumnails removeObject:key];
		}
		else {
			[strongSelf->cacheKeys_userAvatars removeObject:key];
		}
	}});
}

- (void)diskManagerChanged:(NSNotification *)notification
{
	if (notification.object != zdc.diskManager) return;
	
	ZDCDiskManagerChanges *changes = notification.userInfo[kZDCDiskManagerChanges];
	
	if (![changes isKindOfClass:[ZDCDiskManagerChanges class]]) return;
	
	[self _flushNodeThumbnailCache:changes.changedNodeThumbnails];
	[self _flushUserAvatarsCache:changes.changedUsersIDs];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Thumbnails
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)cacheKeyForNodeID:(NSString *)nodeID processingID:(NSString *)processingID
{
	return [NSString stringWithFormat:@"%@|%@", nodeID, processingID];
}

- (void)cacheNodeThumbnail:(nullable OSImage *)image
                    forKey:(NSString *)key
                  withETag:(NSString *)eTag
                      cost:(NSUInteger)cost
{
	ZDCCachedImageItem *item = [[ZDCCachedImageItem alloc] initWithKey:key image:image eTag:eTag];
	
	[nodeThumbnailsCache setObject:item forKey:key cost:cost];
	
	dispatch_sync(cacheKeysQueue, ^{ @autoreleasepool {
		[self->cacheKeys_nodeThumnails addObject:key];
	}});
}

- (BOOL)getNodeID:(NSString **)outNodeID fromCacheKey:(NSString *)cacheKey
{
	NSString *nodeID = nil;
	
	NSArray<NSString*> *components = [cacheKey componentsSeparatedByString:@"|"];
	if (components.count > 0)
	{
		NSString *first = components[0];
		if (first.length == 36) {
			nodeID = first;
		}
	}
	
	if (outNodeID) *outNodeID = nodeID;
	return (nodeID != nil);
}

/**
 * See header file for description.
 */
- (nullable ZDCDownloadTicket *)
        fetchNodeThumbnail:(ZDCNode *)node
               withOptions:(nullable ZDCFetchOptions *)options
             preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
            postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	ZDCLogAutoTrace();
	
	return [self _fetchNodeThumbnail: node
	                    withCacheKey: node.uuid
	                         options: options
	                 processingBlock: nil
	                   preFetchBlock: preFetchBlock
	                  postFetchBlock: postFetchBlock];
}

/**
 * See header file for description.
 */
- (nullable ZDCDownloadTicket *)
        fetchNodeThumbnail:(ZDCNode *)node
               withOptions:(nullable ZDCFetchOptions *)options
              processingID:(nullable NSString *)processingID
           processingBlock:(ZDCImageProcessingBlock)imageProcessingBlock
             preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
            postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	ZDCLogAutoTrace();
	
	NSString *cacheKey = nil;
	if (processingID) {
		cacheKey = [self cacheKeyForNodeID:node.uuid processingID:processingID];
	}
	
	return [self _fetchNodeThumbnail: node
	                    withCacheKey: cacheKey
	                         options: options
	                 processingBlock: imageProcessingBlock
	                   preFetchBlock: preFetchBlock
	                  postFetchBlock: postFetchBlock];
}

- (nullable ZDCDownloadTicket *)
        _fetchNodeThumbnail:(ZDCNode *)node
               withCacheKey:(nullable NSString *)cacheKey
                    options:(nullable ZDCFetchOptions *)inOptions
            processingBlock:(nullable ZDCImageProcessingBlock)imageProcessingBlock
              preFetchBlock:(void(^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
             postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	ZDCFetchOptions *options = inOptions ? [inOptions copy] : [[ZDCFetchOptions alloc] init];
	
	__block BOOL nodeIsMarkedAsNeedsDownload = NO;
	if (options.downloadIfMarkedAsNeedsDownload)
	{
		[internal_roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			ZDCCloudTransaction *cloudTransaction =
			  [self->zdc cloudTransaction:transaction forLocalUserID:node.localUserID];
			
			nodeIsMarkedAsNeedsDownload =
			  [cloudTransaction nodeIsMarkedAsNeedsDownload: node.uuid
			                                     components: ZDCNodeComponents_Thumbnail];
		}];
	}
	
	ZDCCachedImageItem *cachedItem = nil;
	if (cacheKey)
	{
		cachedItem = [nodeThumbnailsCache objectForKey:cacheKey];
		if (cachedItem)
		{
			BOOL willFetch = NO;
			if (options.downloadIfMarkedAsNeedsDownload && nodeIsMarkedAsNeedsDownload)
			{
				willFetch = YES;
			}
			
			preFetchBlock(cachedItem.image, willFetch);
			if (!willFetch) {
				return nil;
			}
		}
	}
	
	ZDCDiskExport *export = [zdc.diskManager nodeThumbnail:node];
	
	BOOL requiresDownload = NO;
	if (export)
	{
		if (options.downloadIfMarkedAsNeedsDownload && nodeIsMarkedAsNeedsDownload)
		{
			requiresDownload = YES; // version in DiskManager is out-of-date
		}
	}
	else
	{
		requiresDownload = YES; // missing from DiskManager
	}
	
	if (!cachedItem)
	{
		if (export.isNilPlaceholder)
		{
			preFetchBlock(nil, requiresDownload);
			if (!requiresDownload) {
				return nil;
			}
		}
	
		preFetchBlock(nil, YES);
	}
	
	__weak typeof(self) weakSelf = self;
	void (^processingBlock)(NSData*, NSString*, NSError*, BOOL) =
		^(NSData *imageData, NSString *eTag, NSError *error, BOOL isDownload){ @autoreleasepool
	{
		// Executing on the processingQueue now
		
		OSImage *image = nil;
		if (imageData)
		{
			image = [[OSImage alloc] initWithData:imageData];
			
			if (image == nil)
			{
				NSString *msg = @"Unable to create image from cached thumbnail data";
				error = [NSError errorWithClass:[self class] code:500 description:msg];
			}
		}
		
		if (image && imageProcessingBlock)
		{
			image = imageProcessingBlock(image);
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			if (cacheKey && !error)
			{
				NSUInteger cost = imageData.length ?: 1;
				[strongSelf cacheNodeThumbnail:image forKey:cacheKey withETag:eTag cost:cost];
			}
			
			if (isDownload && options.downloadIfMarkedAsNeedsDownload && imageData)
			{
				__strong ZeroDarkCloud *_zdc = strongSelf->zdc;
				
				YapDatabaseConnection *rwConnection = _zdc.databaseManager.rwDatabaseConnection;
				[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
					
					ZDCCloudTransaction *cloudTransaction =
					  [_zdc cloudTransaction:transaction forLocalUserID:node.localUserID];
					
					[cloudTransaction unmarkNodeAsNeedsDownload: node.uuid
					                                 components: ZDCNodeComponents_Thumbnail
					                              ifETagMatches: eTag];
				}];
			}
		}
		
		if (postFetchBlock)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				postFetchBlock(image, error);
			});
		}
	}};
	
	
	ZDCDownloadTicket *downloadTicket = nil;
	__block BOOL didDownload = NO;
	
	if (export.cryptoFile)
	{
		// Read the file from disk.
		//
		// We return this even if the image is going to be downloaded, as the download could be slow,
		// and it's generally preferred to show stale data rather than no data.
		
		[ZDCFileConversion decryptCryptoFileIntoMemory: export.cryptoFile
		                               completionQueue: processingQueue
		                               completionBlock:^(NSData *cleartext, NSError *error)
		{
			if (!didDownload) {
				processingBlock(cleartext, export.eTag, error, /*isDownload:*/ NO);
			}
		}];
	}
	
	if (requiresDownload)
	{
		ZDCDownloadOptions *opts = [[ZDCDownloadOptions alloc] init];
		opts.cacheToDiskManager = YES;
		
		downloadTicket =
		  [zdc.downloadManager downloadNodeMeta: node
		                             components: ZDCNodeMetaComponents_Thumbnail
		                                options: opts
		                        completionQueue: processingQueue
		                        completionBlock:
			^(ZDCCloudDataInfo *header, NSData *metadata, NSData *thumbnail, NSError *error)
		{
			didDownload = (thumbnail != nil);
			processingBlock(thumbnail, header.eTag, error, /*isDownload:*/ YES);
		}];
	}
	
	return downloadTicket;
}

/**
 * See header file for description.
 */
- (void)flushNodeThumbnailCache:(NSString *)nodeID
{
	if (nodeID == nil) return;
	
	[self _flushNodeThumbnailCache:[NSSet setWithObject:nodeID]];
}

- (void)_flushNodeThumbnailCache:(NSSet<NSString*> *)nodeIDs
{
	if (nodeIDs.count == 0) return;
	
	NSMutableArray *keys = [NSMutableArray array];
	dispatch_sync(cacheKeysQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (NSString *key in cacheKeys_nodeThumnails)
		{
			NSString *nodeID = nil;
			if ([self getNodeID:&nodeID fromCacheKey:key])
			{
				if ([nodeIDs containsObject:nodeID]) {
					[keys addObject:key];
				}
			}
		}
		
		for (NSString *key in keys)
		{
			[cacheKeys_nodeThumnails removeObject:key];
		}
		
	#pragma clang diagnostic pop
	}});
	
	for (NSString *key in keys)
	{
		[nodeThumbnailsCache removeObjectForKey:key];
	}
}

/**
 * See header file for description.
 */
- (void)flushNodeThumbnailCacheWithProcessingID:(NSString *)processingID
{
	if (processingID == nil) return;
	
	// ZDCNode.uuid is a NSUUID.
	// Example NSUUID string (from Apple's docs): E621E1F8-C36C-495A-93FC-0C247A3E6E5F
	
	NSString *suffix = [NSString stringWithFormat:@"|%@", processingID];
	NSUInteger expectedLength = 36 + 1 + processingID.length;
	
	NSMutableArray *keys = [NSMutableArray array];
	dispatch_sync(cacheKeysQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (NSString *key in cacheKeys_nodeThumnails)
		{
			if ((key.length == expectedLength) && [key hasSuffix:suffix]) {
				[keys addObject:key];
			}
		}
		
		for (NSString *key in keys)
		{
			[cacheKeys_nodeThumnails removeObject:key];
		}
		
	#pragma clang diagnostic pop
	}});
	
	for (NSString *key in keys)
	{
		[nodeThumbnailsCache removeObjectForKey:key];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Avatars
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)cacheKeyForUserID:(NSString *)userID auth0ID:(NSString *)auth0ID
{
	return [NSString stringWithFormat:@"%@|%@", userID, auth0ID];
}

- (NSString *)cacheKeyForUserID:(NSString *)userID auth0ID:(NSString *)auth0ID processingID:(NSString *)processingID
{
	return [NSString stringWithFormat:@"%@|%@|%@", userID, auth0ID, processingID];
}

- (BOOL)getUserID:(NSString **)outUserID fromCacheKey:(NSString *)cacheKey
{
	NSString *userID = nil;
	
	NSArray<NSString*> *components = [cacheKey componentsSeparatedByString:@"|"];
	if (components.count > 0)
	{
		NSString *first = components[0];
		if (first.length == 32)
		{
			userID = first;
		}
	}
	
	if (outUserID) *outUserID = userID;
	return (userID != nil);
}

- (void)cacheUserAvatar:(nullable OSImage *)image
                 forKey:(NSString *)key
               withETag:(NSString *)eTag
                   cost:(NSUInteger)cost
{
	ZDCCachedImageItem *item = [[ZDCCachedImageItem alloc] initWithKey:key image:image eTag:eTag];
	
	[userAvatarsCache setObject:item forKey:key cost:cost];
	
	dispatch_sync(cacheKeysQueue, ^{ @autoreleasepool {
		[self->cacheKeys_userAvatars addObject:key];
	}});
}

/**
 * See header file for description.
 */
- (nullable ZDCDownloadTicket *)
        fetchUserAvatar:(ZDCUser *)user
          preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
         postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	ZDCLogAutoTrace();
	
	NSString *auth0ID = user.auth0_preferredID;
	if (!auth0ID) {
		auth0ID = [Auth0Utilities firstAvailableAuth0IDFromProfiles:user.auth0_profiles];
	}
	
	NSString *cacheKey = [self cacheKeyForUserID:user.uuid auth0ID:auth0ID];
	
	return [self _fetchUserAvatar: user
	                      auth0ID: auth0ID
	                     cacheKey: cacheKey
	              processingBlock: nil
	                preFetchBlock: preFetchBlock
	               postFetchBlock: postFetchBlock];
}

/**
 * See header file for description.
 */
- (nullable ZDCDownloadTicket *)
        fetchUserAvatar:(ZDCUser *)user
       withProcessingID:(nullable NSString *)processingID
        processingBlock:(ZDCImageProcessingBlock)imageProcessingBlock
          preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
         postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	ZDCLogAutoTrace();
	
	NSString *auth0ID = user.auth0_preferredID;
	if (!auth0ID) {
		auth0ID = [Auth0Utilities firstAvailableAuth0IDFromProfiles:user.auth0_profiles];
	}
	
	NSString *cacheKey = nil;
	if (processingID) {
		cacheKey = [self cacheKeyForUserID:user.uuid auth0ID:auth0ID processingID:processingID];
	}
	
	return [self _fetchUserAvatar: user
	                      auth0ID: auth0ID
	                     cacheKey: cacheKey
	              processingBlock: imageProcessingBlock
	                preFetchBlock: preFetchBlock
	               postFetchBlock: postFetchBlock];
}

- (nullable ZDCDownloadTicket *)
        _fetchUserAvatar:(ZDCUser *)user
                 auth0ID:(nullable NSString *)auth0ID
                cacheKey:(nullable NSString *)cacheKey
         processingBlock:(nullable ZDCImageProcessingBlock)imageProcessingBlock
           preFetchBlock:(void(^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
          postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	if (cacheKey)
	{
		ZDCCachedImageItem *cachedItem = [userAvatarsCache objectForKey:cacheKey];
		if (cachedItem)
		{
			preFetchBlock(cachedItem.image, NO);
			return nil;
		}
	}
	
	ZDCDiskExport *export = [zdc.diskManager userAvatar:user forAuth0ID:auth0ID];
	if (export.isNilPlaceholder)
	{
		preFetchBlock(nil, NO);
		return nil;
	}
	
	preFetchBlock(nil, YES);
	
	__weak typeof(self) weakSelf = self;
	void (^processingBlock)(NSData*, NSError*) =
		^(NSData *imageData, NSError *error){ @autoreleasepool
	{
		// Executing on the processingQueue now
		
		OSImage *image = nil;
		if (imageData)
		{
			image = [[OSImage alloc] initWithData:imageData];
			
			if (image == nil)
			{
				NSString *msg = @"Unable to create image from cached thumbnail data";
				error = [NSError errorWithClass:[self class] code:500 description:msg];
			}
			else if (image.size.height < 16 || image.size.height < 16)
			{
				// Image has to be big enough.
				// Some providers (like box) give a 1x1 image for no image.
				image = nil;
			}
		}
		
		if (image && imageProcessingBlock)
		{
			image = imageProcessingBlock(image);
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf && cacheKey && !error)
		{
			NSUInteger cost = imageData.length ?: 1;
			[strongSelf cacheUserAvatar:image forKey:cacheKey withETag:nil cost:cost];
		}
		
		if (postFetchBlock)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				postFetchBlock(image, error);
			});
		}
	}};
	
	if (export.cryptoFile)
	{
		[ZDCFileConversion decryptCryptoFileIntoMemory: export.cryptoFile
		                               completionQueue: processingQueue
		                               completionBlock:^(NSData *cleartext, NSError *error)
		{
			processingBlock(cleartext, error);
		}];
		
		return nil;
	}
	else
	{
		ZDCDownloadOptions *opts = [[ZDCDownloadOptions alloc] init];
		if (user.isLocal) {
			opts.savePersistentlyToDiskManager = YES;
		} else {
			opts.cacheToDiskManager = YES;
		}
		
		ZDCDownloadTicket *ticket =
		  [zdc.downloadManager downloadUserAvatar: user
		                                  auth0ID: auth0ID
		                                  options: opts
		                          completionQueue: processingQueue
		                          completionBlock:^(NSData *avatar, NSError *error)
		{
			processingBlock(avatar, error);
		}];
		
		return ticket;
	}
}

- (nullable ZDCDownloadTicket *)
        fetchUserAvatar:(NSString *)userID
                auth0ID:(NSString *)auth0ID
                fromURL:(NSURL *)url
                options:(nullable ZDCDownloadOptions *)options
           processingID:(nullable NSString *)processingID
        processingBlock:(ZDCImageProcessingBlock)imageProcessingBlock
          preFetchBlock:(void(^)(OSImage *_Nullable image))preFetchBlock
         postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock
{
	NSString *cacheKey = nil;
	if (processingID) {
		cacheKey = [self cacheKeyForUserID:userID auth0ID:auth0ID processingID:processingID];
	}
	
	if (cacheKey)
	{
		ZDCCachedImageItem *cachedItem = [userAvatarsCache objectForKey:cacheKey];
		if (cachedItem)
		{
			preFetchBlock(cachedItem.image);
			return nil;
		}
	}
	
	preFetchBlock(nil);
	
	__weak typeof(self) weakSelf = self;
	void (^processingBlock)(NSData*, NSError*) =
		^(NSData *imageData, NSError *error){ @autoreleasepool
	{
		// Executing on the processingQueue now
		
		OSImage *image = nil;
		if (imageData)
		{
			image = [[OSImage alloc] initWithData:imageData];
			
			if (image == nil)
			{
				NSString *msg = @"Unable to create image from cached thumbnail data";
				error = [NSError errorWithClass:[self class] code:500 description:msg];
			}
			else if (image.size.height < 16 || image.size.height < 16)
			{
				// Image has to be big enough.
				// Some providers (like box) give a 1x1 image for no image.
				image = nil;
			}
		}
		
		if (image && imageProcessingBlock)
		{
			image = imageProcessingBlock(image);
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf && cacheKey)
		{
			NSUInteger cost = imageData.length ?: 1;
			[strongSelf cacheUserAvatar:image forKey:cacheKey withETag:nil cost:cost];
		}
		
		if (postFetchBlock)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				postFetchBlock(image, error);
			});
		}
	}};
	
	ZDCDownloadTicket *ticket =
	  [zdc.downloadManager downloadUserAvatar: userID
	                                  auth0ID: auth0ID
	                                  fromURL: url
	                                  options: options
	                          completionQueue: processingQueue
	                          completionBlock:^(NSData *avatar, NSError *error)
	{
		processingBlock(avatar, error);
	}];
	
	return ticket;
}

/**
 * See header file fro description.
 */
- (void)flushUserAvatarsCache:(NSString *)userID
{
	if (userID == nil) return;
	
	[self _flushUserAvatarsCache:[NSSet setWithObject:userID]];
}

- (void)_flushUserAvatarsCache:(NSSet<NSString *> *)userIDs
{
	if (userIDs.count == 0) return;
	
	NSMutableArray *keys = [NSMutableArray array];
	dispatch_sync(cacheKeysQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (NSString *key in cacheKeys_userAvatars)
		{
			NSString *userID = nil;
			if ([self getUserID:&userID fromCacheKey:key])
			{
				if ([userIDs containsObject:userID]) {
					[keys addObject:key];
				}
				
			}
		}
		
		for (NSString *key in keys)
		{
			[cacheKeys_userAvatars removeObject:key];
		}
		
	#pragma clang diagnostic pop
	}});
	
	for (NSString *key in keys)
	{
		[userAvatarsCache removeObjectForKey:key];
	}
}

/**
 * See header file for description.
 */
- (void)flushUserAvatarsCacheWithProcessingID:(NSString *)processingID
{
	if (processingID == nil) return;
	
	NSString *suffix = [NSString stringWithFormat:@"|%@", processingID];
	
	NSMutableArray *keys = [NSMutableArray array];
	dispatch_sync(cacheKeysQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (NSString *key in cacheKeys_userAvatars)
		{
			if ([key hasSuffix:suffix]) {
				[keys addObject:key];
			}
		}
		
		for (NSString *key in keys)
		{
			[cacheKeys_userAvatars removeObject:key];
		}
		
	#pragma clang diagnostic pop
	}});
	
	for (NSString *key in keys)
	{
		[userAvatarsCache removeObjectForKey:key];
	}
}

- (OSImage *)defaultUserAvatar
{
	NSString *const cacheKey = @"default_user";
    
	ZDCCachedImageItem *cachedItem = [userAvatarsCache objectForKey:cacheKey];
	if (cachedItem) {
		return cachedItem.image;
	}
    
#if TARGET_OS_IPHONE
	OSImage *image = [UIImage imageNamed: @"default_user"
	                            inBundle: [ZeroDarkCloud frameworkBundle]
	       compatibleWithTraitCollection: nil];
#else // OSX
	OSImage *image = [[ZeroDarkCloud frameworkBundle] imageForResource:@"default_user.png"];
#endif
	
	if (image)
	{
		cachedItem = [[ZDCCachedImageItem alloc] initWithKey:cacheKey image:image eTag:nil];
		[userAvatarsCache setObject:cachedItem forKey:cacheKey cost:10]; // low cost - no decryption required
	}
	
	return image;
}

- (OSImage *)defaultMultiUserAvatar
{
	NSString *const cacheKey = @"default_multi_user";
	
	ZDCCachedImageItem *cachedItem = [userAvatarsCache objectForKey:cacheKey];
	if (cachedItem) {
		return cachedItem.image;
	}
	
#if TARGET_OS_IPHONE
	OSImage *image = [UIImage imageNamed: @"all-users.png"
	                            inBundle: [ZeroDarkCloud frameworkBundle]
	       compatibleWithTraitCollection: nil];
#else // OSX
	OSImage *image = [[ZeroDarkCloud frameworkBundle] imageForResource:@"all-users.png"];
#endif
 
	if (image)
	{
		cachedItem = [[ZDCCachedImageItem alloc] initWithKey:cacheKey image:image eTag:nil];
		[userAvatarsCache setObject:cachedItem forKey:cacheKey cost:10]; // low cost - no decryption required
	}
	
	return image;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCFetchOptions

@synthesize downloadIfMarkedAsNeedsDownload = _downloadIfMarkedAsNeedsDownload;

- (instancetype)init
{
	if ((self = [super init]))
	{
		_downloadIfMarkedAsNeedsDownload = YES;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCFetchOptions *copy = [[ZDCFetchOptions alloc] init];
	copy->_downloadIfMarkedAsNeedsDownload = _downloadIfMarkedAsNeedsDownload;
	
	return copy;
}

@end
