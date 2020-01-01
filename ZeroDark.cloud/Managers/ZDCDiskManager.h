/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "ZDCCryptoFile.h" // For ZDCCryptoFileFormat enum

@class ZDCDiskImport;
@class ZDCDiskExport;
@class ZDCNode;
@class ZDCUser;

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZDCDiskManagerChangedNotification is posted to the main thread anytime items change in the cache.
 *
 * The notification will contain a userInfo dictionary with the following keys:
 * - kZDCDiskManagerChanges: An instance of `ZDCDiskManagerChanges`
 */
extern NSString *const ZDCDiskManagerChangedNotification;

/**
 * A key for the ZDCDiskManagerChangedNotification.userInfo dictionary,
 * which returns an instance of `ZDCDiskManagerChanges`.
 */
extern NSString *const kZDCDiskManagerChanges;

/**
 * The DiskManager simplifies the process of persisting & caching files to disk.
 *
 * The DiskManager supports two different storage modes:
 * - Persistent:
 *     Files stored in persistent mode won't be deleted unless you ask the DiskManager to delete them,
 *     or the underlying node/user is deleted from the database.
 * - Cache:
 *     File stored in cache mode are treated as a temporarily file.
 *     They are added to a "storage pool" managed by the DiskManager.
 *     And when the max size of the storage pool is exceeded, the DiskManager automatically starts deleting files.
 *     Further, the files are stored in an OS-designated Caches folder,
 *     and are available for deletion by the OS due to low-disk-space pressure.
 */
@interface ZDCDiskManager : NSObject

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Allows you to configure the max size of the "storage pool" for cached (non-persistent) nodeData files.
 *
 * The value is designated in bytes.
 * The default value is 25 MiB (1024 * 1024 * 25).
 *
 * @note Any value you configure is persisted to disk, and thus remains set between app launches.
 *
 * The DiskManager supports two different storage modes:
 * - Persistent:
 *     Files stored in persistent mode won't be deleted unless you ask the DiskManager to delete them,
 *     or the underlying node/user is deleted from the database.
 * - Cache:
 *     File stored in cache mode are treated as a temporarily file.
 *     They are added to a "storage pool" managed by the DiskManager.
 *     And when the max size of the storage pool is exceeded, the DiskManager automatically starts deleting files.
 *     Further, the files are stored in an OS-designated Caches folder,
 *     and are available for deletion by the OS due to low-disk-space pressure.
 */
@property (atomic, readwrite, assign) uint64_t maxNodeDataCacheSize;

/**
 * Allows you to configure the max size of the "storage pool" for cached (non-persistent) nodeThumbnail files.
 *
 * The value is designated in bytes.
 * The default value is 5 MiB (1024 * 1024 * 5).
 *
 * @note Any value you configure is persisted to disk, and thus remains set between app launches.
 *
 * The DiskManager supports two different storage modes:
 * - Persistent:
 *     Files stored in persistent mode won't be deleted unless you ask the DiskManager to delete them,
 *     or the underlying node/user is deleted from the database.
 * - Cache:
 *     File stored in cache mode are treated as a temporarily file.
 *     They are added to a "storage pool" managed by the DiskManager.
 *     And when the max size of the storage pool is exceeded, the DiskManager automatically starts deleting files.
 *     Further, the files are stored in an OS-designated Caches folder,
 *     and are available for deletion by the OS due to low-disk-space pressure.
 */
@property (atomic, readwrite, assign) uint64_t maxNodeThumbnailsCacheSize;

/**
 * Allows you to configure the max size of the "storage pool" for cached (non-persistent) userAvatar files.
 *
 * The value is designated in bytes.
 * The default value is 5 MiB (1024 * 1024 * 5).
 *
 * @note Any value you configure is persisted to disk, and thus remains set between app launches.
 *
 * The DiskManager supports two different storage modes:
 * - Persistent:
 *     Files stored in persistent mode won't be deleted unless you ask the DiskManager to delete them,
 *     or the underlying node/user is deleted from the database.
 * - Cache:
 *     File stored in cache mode are treated as a temporarily file.
 *     They are added to a "storage pool" managed by the DiskManager.
 *     And when the max size of the storage pool is exceeded, the DiskManager automatically starts deleting files.
 *     Further, the files are stored in an OS-designated Caches folder,
 *     and are available for deletion by the OS due to low-disk-space pressure.
 */
@property (atomic, readwrite, assign) uint64_t maxUserAvatarsCacheSize;

/**
 * Allows you to configure a default expiration interval for cached (non-persistent) nodeData files,
 * after which time the DiskManager will automatically delete the cached file from disk.
 *
 * A positive value indicates the DiskManager should automatically delete cached nodeData files after
 * the given internal. For example, if you specify an interval of 7 days, then the DiskManager will
 * delete a cached nodeData file once its lastModified value exceeds 7 days old.
 *
 * A non-positive value (zero or negative value) indicates the DiskManager
 * should NOT automatically delete cached nodeData files.
 *
 * Keep in mind:
 *
 * - This value only applies to cached (non-persistent) nodeData files.
 *   That is, imported nodeData files where the `storePersistently` flag was NOT set.
 *
 * - This default value can be overriden on a per-file basis,
 *   by explicitly setting a non-zero value for the `[ZDCDiskImport expiration]` property.
 *
 * The default value is zero.
 *
 * @note NSTimeInterval is designated in seconds.
 */
@property (atomic, readwrite, assign) NSTimeInterval defaultNodeDataCacheExpiration;

/**
 * Allows you to configure a default expiration interval for cached (non-persistent) nodeThumbnail files,
 * after which time the DiskManager will automatically delete the cached file from disk.
 *
 * A positive value indicates the DiskManager should automatically delete cached nodeThumbnail files after
 * the given internal. For example, if you specify an interval of 7 days, then the DiskManager will
 * delete a cached nodeThumbnail file once its lastModified value exceeds 7 days old.
 *
 * A non-positive value (zero or negative value) indicates the DiskManager
 * should NOT automatically delete cached nodeThumbnail files.
 *
 * Keep in mind:
 *
 * - This value only applies to cached (non-persistent) nodeThumbnail files.
 *   That is, imported nodeThumbnail files where the `storePersistently` flag was NOT set.
 *
 * - This default value can be overriden on a per-file basis,
 *   by explicitly setting a non-zero value for the `[ZDCDiskImport expiration]` property.
 *
 * The default value is zero.
 *
 * @note NSTimeInterval is designated in seconds.
 */
@property (atomic, readwrite, assign) NSTimeInterval defaultNodeThumbnailCacheExpiration;

/**
 * Allows you to configure a default expiration interval for cached (non-persistent) userAvatar files,
 * after which time the DiskManager will automatically delete the cached file from disk.
 *
 * A positive value indicates the DiskManager should automatically delete cached userAvatar files after
 * the given internal. For example, if you specify an interval of 7 days, then the DiskManager will
 * delete a cached userAvatar file once its lastModified value exceeds 7 days old.
 *
 * A non-positive value (zero or negative value) indicates the DiskManager
 * should NOT automatically delete cached userAvatar files.
 *
 * Keep in mind:
 *
 * - This value only applies to non-persistent userAvatar files.
 *   That is, imported userAvatar files where the `storePersistently` flag was NOT set.
 *
 * - This default value can be overriden on a per-file basis,
 *   by explicitly setting a non-zero value for the `[ZDCDiskImport expiration]` property.
 *
 * The default value is 7 days.
 *
 * @note NSTimeInterval is designated in seconds.
 */
@property (atomic, readwrite, assign) NSTimeInterval defaultUserAvatarCacheExpiration;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is designed to take an import, migrate it to an encrypted format,
 * and then store it in a directory that's being managed by the DiskManager.
 *
 * For example, you might download a file using the `ZDCDownloadManager`,
 * and then pass the resulting CryptoFile into this method.
 *
 * By utilizing the DiskManager, you can efficiently manage your app's storage.
 * This is because the DiskManager has the notion of persistent vs non-persistent (cached) files.
 * Persistent files stick around until you manually delete them (or until the corresponding node is deleted).
 * Non-persistent files, however, are part of a configurable storage pool.
 * You can set limits on the size of the storage pool,
 * and the DiskManager automatically handles deleting data when the pool gets too big.
 * You can also set optional expiration intervals for imported files,
 * and the DiskManager automatically handles deleting the files when they get too old.
 *
 * @note Non-persistent files may also be deleted by the OS due to low disk space.
 *
 * @param import
 *   The data can be imported to the DiskManager from multiple formats.
 *
 * @param node
 *   The corresponding node for the file.
 *
 * @return The CryptoFile will be MOVED from its current location to a new location.
 *         So the old fileURL will no longer exist upon completion of this method.
 *         A new CryptoFile is returned with an updated fileURL property.
 */
- (nullable ZDCCryptoFile *)importNodeData:(ZDCDiskImport *)import
                                   forNode:(ZDCNode *)node
                                     error:(NSError *_Nullable *_Nullable)outError;

/**
 * Returns whether or not the DiskManager currently has a data file for the given node.
 *
 * @warning This method only provides a snapshot of the current state, which may quickly change.
 *          Moments after you invoke this method, the cached file may be deleted (for various reasons).
 *          If you need to ensure the cached file sticks around for awhile,
 *          use a method that returns a `ZDCCryptoFile` (with its retainToken) for the file.
 *
 * @param nodeID
 *   The node you're interested in (nodeID == ZDCNode.uuid)
 */
- (BOOL)hasNodeData:(NSString *)nodeID;

/**
 * Exports the CryptoFile and associated info for the node's data, if available on disk.
 * The informaion is bundled in a ZDCDiskExport instance.
 *
 * If a CryptoFile is returned, it will have a non-nil `-[ZDCCryptoFile retainToken]` property.
 * This prevents the DiskManager from deleting the file for as long as this retainToken isn't deallocated.
 *
 * Keep in mind that while the retainToken will prevent the DiskManager from deleting the file,
 * the OS is free to do what it pleases, and may decide to delete the file while the app is backgrounded.
 *
 * @param node
 *   The node you're interested in.
 */
- (nullable ZDCDiskExport *)nodeData:(ZDCNode *)node;

/**
 * Returns a CryptoFile and associated info for the node's data, if available on disk.
 * The information is bundled in a ZDCDiskExport instance.
 *
 * If a CryptoFile is returned, it will have a non-nil `-[ZDCCryptoFile retainToken]` property.
 * This prevents the DiskManager from deleting the file for as long as this retainToken isn't deallocated.
 *
 * Keep in mind that although the retainToken will prevent the DiskManager from deleting the file,
 * if the file is non-persistent (i.e. stored in an OS designated Caches folder),
 * then the OS is free to do what it pleases, and may decide to delete the file while the app is backgrounded.
 *
 * @param node
 *   The node you're interested in.
 *
 * @param preferredFormat
 *   If you prefer a specific format, pass it here.
 *   If you don't care, just pass ZDCCryptoFileFormat_Unknown.
 */
- (nullable ZDCDiskExport *)nodeData:(ZDCNode *)node
                     preferredFormat:(ZDCCryptoFileFormat)preferredFormat;

/**
 * Deletes data files for the given nodeID from disk.
 *
 * The files are deleted in a safe manner.
 * That is, if any files are currently being retained (a retainToken is being held for them),
 * then the files are simply marked for future deletion. And the file will be deleted as soon
 * as its retainCount drops back to zero.
 */
- (void)deleteNodeData:(NSString *)nodeID;

/**
 * Deletes data files for the given nodeIDs from disk.
 *
 * The files are deleted in a safe manner.
 * That is, if any files are currently being retained (a retainToken is being held for them),
 * then the files are simply marked for future deletion. And the file will be deleted as soon
 * as its retainCount drops back to zero.
 */
- (void)deleteNodeDataForNodeIDs:(NSArray<NSString*> *)nodeIDs;

/**
 * Migrates node data files between persistent & non-persistent.
 *
 * The files are migrated in a safe manner.
 * That is, if any files are currently being retained (a retainToken/CryptoFile is being held for them),
 * then file is instead copied, and the original file is marked for future deletion.
 * And the file will be deleted as soon as its retainCount drops to zero.
 *
 * @param persistent
 *   If YES, then non-persistent data files will moved moved to a persistent location on disk.
 *   If NO, then persistent files will be moved to a non-persistent location on disk.
 *
 * @param nodeID
 *   The node for which you want to migrate files (nodeID == ZDCNode.uuid)
 */
- (void)makeNodeDataPersistent:(BOOL)persistent forNodeID:(NSString *)nodeID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Thumbnails
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is designed to take a downloaded thumbnail and store it to disk
 * into a directory that's being managed by the DiskManager.
 *
 * For example, you might download a thumbnail using the `ZDCDownloadManager`,
 * and then pass the resulting data into this method.
 *
 * By utilizing the DiskManager, you can efficiently manage your app's storage.
 * This is because the DiskManager has the notion of persistent vs non-persistent files.
 * Persistent files stick around until you manually delete them (or until the corresponding node is deleted).
 * Non-persistent files, however, are part of a cache with a configurable storage pool.
 * You can set limits on the size of the storage pool,
 * and the DiskManager automatically handles deleting data when the pool gets too big.
 * You can also set optional expiration intervals for imported files,
 * and the DiskManager automatically handles deleting the files when they get too old.
 *
 * @note Non-persistent files may also be deleted by the OS due to low disk space.
 *
 * @param import
 *   The data can be imported to the DiskManager from multiple formats.
 *
 * @param node
 *   The corresponding node for the file.
 *
 * @return The data will be saved to disk in an encrypted format.
 *         A new CryptoFile reference is returned that can be used to read the file.
 */
- (nullable ZDCCryptoFile *)importNodeThumbnail:(ZDCDiskImport *)import
                                        forNode:(ZDCNode *)node
                                          error:(NSError *_Nullable *_Nullable)outError;

/**
 * Returns whether or not the DiskManager currently has a thumbnail for the given node.
 *
 * @warning This method only provides a snapshot of the current state, which may quickly change.
 *          Moments after you invoke this method, the cached file may be deleted (for various reasons).
 *          If you need to ensure the cached file sticks around for awhile,
 *          use a method that returns a `ZDCCryptoFile` (with its retainToken) for the file.
 *
 * @param nodeID
 *   The node you're interested in (nodeID == ZDCNode.uuid)
 */
- (BOOL)hasNodeThumbnail:(NSString *)nodeID;

/**
 * Returns a CryptoFile and associated info for the node's thumbnail, if available on disk.
 * The information is bundled in a ZDCDiskExport instance.
 *
 * If a CryptoFile is returned, it will have a non-nil `-[ZDCCryptoFile retainToken]` property.
 * This prevents the DiskManager from deleting the file for as long as this retainToken isn't deallocated.
 *
 * Keep in mind that although the retainToken will prevent the DiskManager from deleting the file,
 * if the file is non-persistent (i.e. stored in an OS designated Caches folder),
 * then the OS is free to do what it pleases, and may decide to delete the file while the app is backgrounded.
 *
 * @param node
 *   The node you're interested in.
 */
- (nullable ZDCDiskExport *)nodeThumbnail:(ZDCNode *)node;

/**
 * Deletes thumbnail files for the given nodeID from disk.
 *
 * The files are deleted in a safe manner.
 * That is, if any files are currently being retained (a retainToken is being held for them),
 * then the files are simply marked for future deletion. And the file will be deleted as soon
 * as its retainCount drops back to zero.
 */
- (void)deleteNodeThumbnail:(NSString *)nodeID;

/**
 * Deletes thumbnail files for the given nodeID's from disk.
 *
 * The files are deleted in a safe manner.
 * That is, if any files are currently being retained (a retainToken is being held for them),
 * then the files are simply marked for future deletion. And the file will be deleted as soon
 * as its retainCount drops back to zero.
 */
- (void)deleteNodeThumbnailsForNodeIDs:(NSArray<NSString*> *)nodeIDs;

/**
 * Migrates node thumbnail files between persistent & non-persistent.
 *
 * The files are migrated in a safe manner.
 * That is, if any files are currently being retained (a retainToken/CryptoFile is being held for them),
 * then file is instead copied, and the original file is marked for future deletion.
 * And the file will be deleted as soon as its retainCount drops to zero.
 *
 * @param persistent
 *   If YES, then non-persistent data files will moved moved to a persistent location on disk.
 *   If NO, then persistent files will be moved to a non-persistent location on disk.
 *
 * @param nodeID
 *   The node for which you want to migrate files (nodeID == ZDCNode.uuid)
 */
- (void)makeNodeThumbnailPersistent:(BOOL)persistent forNodeID:(NSString *)nodeID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Avatars
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is designed to take a CryptoFile that's stored in a temp location,
 * and move it into a directory that's being managed by the DiskManager.
 *
 * For example, you might download a file using the `ZDCDownloadManager`,
 * and then pass the resulting CryptoFile into this method.
 *
 * By utilizing the DiskManager, you can efficiently manage your app's storage.
 * This is because the DiskManager has the notion of persistent vs non-persistent (cached) files.
 * Persistent files stick around until you manually delete them (or until the corresponding node is deleted).
 * Non-persistent files, however, are part of a configurable storage pool.
 * You can set limits on the size of the storage pool,
 * and the DiskManager automatically handles deleting data when the pool gets too big.
 * You can also set optional expiration intervals for imported files,
 * and the DiskManager automatically handles deleting the files when they get too old.
 *
 * @note Non-persistent files may also be deleted by the OS due to low disk space.
 *
 * @param import
 *   The data can be imported to the DiskManager from multiple formats.
 *
 * @param user
 *   The corresponding user for the file.
 *
 * @param identityID
 *   The social identitythat corresponds to the avatar that was downloaded.
 */
- (nullable ZDCCryptoFile *)importUserAvatar:(ZDCDiskImport *)import
                                     forUser:(ZDCUser *)user
                                  identityID:(NSString *)identityID
                                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Returns whether or not the DiskManager currently has any avatars for the given user.
 *
 * @warning This method only provides a snapshot of the current state, which may quickly change.
 *          Moments after you invoke this method, the cached file may be deleted (for various reasons).
 *          If you need to ensure the cached file sticks around for awhile,
 *          use a method that returns a `ZDCCryptoFile` (with its retainToken) for the file.
 *
 * @param userID
 *   The user you're interested in (userID == ZDCUser.uuid)
 */
- (BOOL)hasUserAvatar:(NSString *)userID;

/**
 * Returns whether or not the DiskManager currently has an avatar for the given {userID, auth0ID} tuple.
 * If you pass a nil auth0ID, it returns whether there are ANY avatars for the user.
 *
 * @warning This method only provides a snapshot of the current state, which may quickly change.
 *          Moments after you invoke this method, the cached file may be deleted (for various reasons).
 *          If you need to ensure the cached file sticks around for awhile,
 *          use a method that returns a `ZDCCryptoFile` (with its retainToken) for the file.
 *
 * @param userID
 *   The user you're interested in (userID == ZDCUser.uuid)
 *
 * @param identityID
 *   If you're interested in a particular social identity.
 */
- (BOOL)hasUserAvatar:(NSString *)userID forIdentityID:(nullable NSString *)identityID;

/**
 * Returns the list of identityID's for which we have a stored user avatar within the DiskManager.
 *
 * @note This list includes any stored information, including nil placholders.
 */
- (NSArray<NSString*> *)storedIdentityIDs:(NSString *)userID;

/**
 * Returns a CryptoFile and associated info for the user avatar, if available on disk.
 * The information is bundled in a ZDCDiskExport instance.
 *
 * If a CryptoFile is returned, it will have a non-nil `-[ZDCCryptoFile retainToken]` property.
 * This prevents the DiskManager from deleting the file for as long as this retainToken isn't deallocated.
 *
 * Keep in mind that although the retainToken will prevent the DiskManager from deleting the file,
 * if the file is non-persistent (i.e. stored in an OS designated Caches folder),
 * then the OS is free to do what it pleases, and may decide to delete the file while the app is backgrounded.
 *
 * @param user
 *   The user you're interested in.
 */
- (nullable ZDCDiskExport *)userAvatar:(ZDCUser *)user;

/**
 * Returns a CryptoFile and associated info for the user avatar, if available on disk.
 * The information is bundled in a ZDCDiskExport instance.
 *
 * If a CryptoFile is returned, it will have a non-nil `-[ZDCCryptoFile retainToken]` property.
 * This prevents the DiskManager from deleting the file for as long as this retainToken isn't deallocated.
 *
 * Keep in mind that although the retainToken will prevent the DiskManager from deleting the file,
 * if the file is non-persistent (i.e. stored in an OS designated Caches folder),
 * then the OS is free to do what it pleases, and may decide to delete the file while the app is backgrounded.
 *
 * @param user
 *   The user you're interested in.
 *
 * @param identityID
 *   If you're interested in the avatar for a particular social identity.
 */
- (nullable ZDCDiskExport *)userAvatar:(ZDCUser *)user forIdentityID:(nullable NSString *)identityID;

/**
 * Deletes all avatar files for the given userID from disk.
 *
 * @note The files are deleted in a safe manner.
 *       That is, if any files are currently being retained (a retainToken is being held for them),
 *       then the files are simply marked for future deletion. And the file will be deleted as soon
 *       as its retainCount drops back to zero.
 *
 * @param userID
 *   The user you're interested in (userID == ZDCUser.uuid)
 */
- (void)deleteUserAvatar:(NSString *)userID;

/**
 * Deletes avatar files for the given userID's from disk.
 *
 * @note The files are deleted in a safe manner.
 *       That is, if any files are currently being retained (a retainToken is being held for them),
 *       then the files are simply marked for future deletion. And the file will be deleted as soon
 *       as its retainCount drops back to zero.
 */
- (void)deleteUserAvatarsForUserIDs:(NSArray<NSString*> *)userIDs;

/**
 * Deletes the avatar file(s) for the given {userID, identityID} tuple from disk.
 *
 * @note The files are deleted in a safe manner.
 *       That is, if any files are currently being retained (a retainToken is being held for them),
 *       then the files are simply marked for future deletion. And the file will be deleted as soon
 *       as its retainCount drops back to zero.
 *
 * @param userID
 *   The user you're interested in (userID == ZDCUser.uuid)
 *
 * @param identityID
 *   If you're interested in the avatar for a particular social identity.
 */
- (void)deleteUserAvatar:(NSString *)userID forIdentityID:(NSString *)identityID;

/**
 * Migrates user avatar files between persistent & non-persistent.
 *
 * The files are migrated in a safe manner.
 * That is, if any files are currently being retained (a retainToken/CryptoFile is being held for them),
 * then file is instead copied, and the original file is marked for future deletion.
 * And the file will be deleted as soon as its retainCount drops to zero.
 *
 * @param persistent
 *   If YES, then non-persistent data files will moved moved to a persistent location on disk.
 *   If NO, then persistent files will be moved to a non-persistent location on disk.
 *
 * @param userID
 *   The user for which you want to migrate files (userID == ZDCUser.uuid)
 */
- (void)makeUserAvatarPersistent:(BOOL)persistent forUserID:(NSString *)userID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Storage Sizes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the total size (summation) of all nodeData files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 */
- (uint64_t)storageSizeForAllNodeData;

/**
 * Returns the total size (summation) of all persistent nodeData files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 */
- (uint64_t)storageSizeForPersistentNodeData;

/**
 * Returns the total size (summation) of all cached (non-persistent) nodeData files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 *
 * @note The current size may temporarily exceed the configured max size
 *       if a file is queued for deletion, but is currently being used
 *       by the app. (e.g. A ZDCCryptoFile.retainToken is keeping the file
 *       from being immediately deleted.)
 */
- (uint64_t)storageSizeForCachedNodeData;

/**
 * Returns the total size (summation) of all nodeThumbnail files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 */
- (uint64_t)storageSizeForAllNodeThumbnails;

/**
 * Returns the total size (summation) of all persistent nodeThumbnail files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 */
- (uint64_t)storageSizeForPersistentNodeThumbnail;

/**
 * Returns the total size (summation) of all cached (non-persistent) nodeThumbnail files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 *
 * @note The current size may temporarily exceed the configured max size
 *       if a file is queued for deletion, but is currently being used
 *       by the app. (e.g. A ZDCCryptoFile.retainToken is keeping the file
 *       from being immediately deleted.)
 */
- (uint64_t)storageSizeForCachedNodeThumbnails;

/**
 * Returns the total size (summation) of all userAvatar files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 */
- (uint64_t)storageSizeForAllUserAvatars;

/**
 * Returns the total size (summation) of all persistent userAvatar files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 */
- (uint64_t)storageSizeForPersistentUserAvatars;

/**
 * Returns the total size (summation) of all cached (non-persistent) userAvatar files on disk
 * (in directories being managed by the DiskManager).
 *
 * @note This method involves asking the OS filesystem for file sizes.
 *       It's normally quite fast, however this does involve disk IO.
 *       So you may prefer to invoke this method on a background thread.
 *
 * @note The current size may temporarily exceed the configured max size
 *       if a file is queued for deletion, but is currently being used
 *       by the app. (e.g. A ZDCCryptoFile.retainToken is keeping the file
 *       from being immediately deleted.)
 */
- (uint64_t)storageSizeForCachedUserAvatars;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Deletes the given file from the filesystem, so long as it's not being managed by the DiskManager.
 *
 * When you download files using the ZDCDownloadManager,
 * you're given the option of storing the downloaded file into the DiskManager automatically.
 * When you choose to do so, then the returned file is managed by the DiskManager, and thus you shouldn't delete it.
 * But when you choose not to do so, then the returned file is sitting in a temp directory.
 * And you're encouraged to delete it when you're done with it.
 * Having two very different requirements is just asking for bugs.
 * So instead, you can simply use this API every single time, which will always just do the right thing for you.
 */
- (void)deleteFileIfUnmanaged:(NSURL *)fileURL;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Encapsulates the parameters used when importing a file into the DiskManager.
 */
@interface ZDCDiskImport: NSObject

/**
 * Creates an "empty" import, which acts as a nil placeholder.
 *
 * This is used when a node's thumbnail is nil, or a user's avatar is nil,
 * and the intention is to cache this result to prevent unnecessary future HTTP requests.
 */
- (instancetype)init;

/**
 * Creates an import with the given cleartext data.
 * The import process will encrypt the given data, and then write it to disk.
 */
- (instancetype)initWithCleartextData:(NSData *)cleartextData;

/**
 * Creates an import with the given cleartext file.
 * The import process will create an encrypted copy of the file.
 */
- (instancetype)initWithCleartextFileURL:(NSURL *)cleartextFileURL;

/**
 * Creates an import with the given crypto file.
 * The import process will move the crypto file into a folder managed by the DiskManager.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile;

/** The parameter passed during init */
@property (nonatomic, strong, readonly, nullable) NSData *cleartextData;

/** The parameter passed during init */
@property (nonatomic, strong, readonly, nullable) NSURL *cleartextFileURL;

/** The parameter passed during init */
@property (nonatomic, strong, readonly, nullable) ZDCCryptoFile *cryptoFile;

/**
 * True if the all the following are nil: `cleartextData`, `cleartextFileURL`, & `cryptoFile`
 *
 * @note Nil placeholders are allowed for nodeThumbnail & userAvatar, but NOT for nodeData.
 */
@property (nonatomic, readonly) BOOL isNilPlaceholder;

/**
 * If YES, the file is stored using persistent mode.
 * Persistent mode is kinda like a "store offline" mode that you see in some apps.
 * That is, it won't be deleted by the OS. It will only be deleted if you manually delete it,
 * or if the corresponding node/user is deleted from the database.
 *
 * If NO, the file is stored using cache mode.
 * It becomes part of a storage pool, and the max size of the storage pool is configurable.
 * You can also set an optional expiration interval for temporarily cached files.
 *
 * The default value is NO/false.
 */
@property (nonatomic, assign, readwrite) BOOL storePersistently;

/**
 * This value applies to files being imported with the `storePersistently` flag set to true.
 * If this value is also true, then it instructs the DiskManager to automatically migrate the file
 * from persistent to cache mode after all queued PUT operations for the node have completed.
 *
 * This is a typical setting to use when you're creating a new node.
 * You want to ensure the file won't be deleted from disk before the system has pushed it up to the cloud.
 * But after the node was been pushed to the cloud, then the file can be deleted & so should be migrated to the cache.
 *
 * The default value is NO/false.
 */
@property (nonatomic, assign, readwrite) BOOL migrateToCacheAfterUpload;

/**
 * If set to true, it instructs the DiskManager to automatically delete the file after
 * all queued PUT operations for the node have completed.
 *
 * This flag can be applied regardless of the `storePersistently` flag.
 *
 * The default value is NO/false.
 */
@property (nonatomic, assign, readwrite) BOOL deleteAfterUpload;

/**
 * The DiskManager can store an associated eTag with every imported file.
 * This allows you to determine which version of a file is cached
 *
 * The eTag value is stored to disk in an encrypted manner.
 * In particular, it is encrypted & then stored via an xattr.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *eTag;

/**
 * The DiskManager supports an optional expiration interval (for non-persistent files).
 *
 * There are 2 values that control this:
 *
 * - The default value, configured via the ZDCDiskManager.
 *   (i.e. defaultNodeDataCacheExpiration, defaultNodeThumbnailCacheExpiration & defaultUserAvatarCacheExpiration)
 *
 * - The value you set here to (optionally) override the default value.
 *
 * Here's how it works:
 *
 * - If you leave this value set to zero, then the imported file will inherit the default value.
 * - If you set this value to a POSITIVE value, then the imported file will use this value as its expiration,
 *   regardless of the default settings.
 * - If you set this value to a NEGATIVE value, then the imported file will NOT expire,
 *   regardless of the default settings.
 *
 * The default value is zero (meaning the import will inherit the default settings).
 *
 * @note The DiskManager will not expire files while they are stored in persistent mode (storePersistently == true).
 *       However, the expiration value will be applied to the file. (It gets stored as an xattr.)
 *       And if the file is later migrated from persistent to cache mode,
 *       then the previously applied expiration will affect the file.
 */
@property (nonatomic, assign, readwrite) NSTimeInterval expiration;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Provides all the information about a file being managed by the DiskManager.
 */
@interface ZDCDiskExport: NSObject

/**
 * If the file exists on disk (and is not a nil placholder) then this property will be set.
 * A CryptoFile contains all the information needed to read & decrypt the file.
 *
 * @note ZDCFileConversion has a various functions you can use decrypt the file.
 *
 * If a CryptoFile is returned, it will have a non-nil `-[ZDCCryptoFile retainToken]` property.
 * This prevents the DiskManager from deleting the file for as long as this retainToken is alive (i.e not deallocated).
 *
 * Keep in mind that although the retainToken will prevent the DiskManager from deleting the file,
 * if the file is non-persistent (i.e. stored in an OS designated Caches folder),
 * then the OS is free to do what it pleases, and may decide to delete the file while the app is backgrounded.
 */
@property (nonatomic, strong, readonly, nullable) ZDCCryptoFile *cryptoFile;

/**
 * True if the file was imported as a nil placeholder.
 *
 * @note Nil placeholders are allowed for nodeThumbnail & userAvatar, but NOT for nodeData.
 */
@property (nonatomic, readonly) BOOL isNilPlaceholder;

/**
 * True if the file is stored in persistent mode.
 * False if the file is stored in cache mode.
 */
@property (nonatomic, readonly) BOOL isStoredPersistently;

/**
 * The eTag associated with the file when it was imported.
 */
@property (nonatomic, readonly, nullable) NSString *eTag;

/**
 * The expiration associated with the file when it was imported.
 * If this value is zero, that means the file will inherit the default configuration.
 */
@property (nonatomic, readonly) NSTimeInterval expiration;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Instances of this class are broadcast via `ZDCDiskManagerChangedNotification`.
 *
 * It can be extracted from the ZDCDiskManagerChangedNotification.userInfo dictionary
 * using the `ZDCDiskManagerChanges` key.
 */
@interface ZDCDiskManagerChanges : NSObject

/**
 * A set of nodeID's (ZDCNode.uuid) that have changed (added, deleted or modified).
 * This set pertains to either nodeData or nodeThumbnails being managed by the DiskManager.
 */
@property (nonatomic, readonly) NSSet<NSString*> *changedNodeIDs;

/**
 * A set of nodeID's (ZDCNode.uuid) that have changed (added, deleted or modified).
 * This set pertains only to nodeData being managed by the DiskManager.
 */
@property (nonatomic, readonly) NSSet<NSString*> *changedNodeData;

/**
 * A set of nodeID's (ZDCNode.uuid) that have changed (added, deleted or modified).
 * This set pertains only to nodeThumbnails being managed by the DiskManager.
 */
@property (nonatomic, readonly) NSSet<NSString*> *changedNodeThumbnails;

/**
 * A set of userID's (ZDCUser.uuid) that have changed (added, deleted or modified).
 * This set pertains only to avatars being managed by the DiskManager.
 */
@property (nonatomic, readonly) NSSet<NSString*> *changedUsersIDs;

@end

NS_ASSUME_NONNULL_END
