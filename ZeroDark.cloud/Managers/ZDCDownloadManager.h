/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

@class ZDCCloudDataInfo;
@class ZDCCryptoFile;
@class ZDCNode;
@class ZDCUser;

@class ZDCDownloadOptions;
@class ZDCDownloadTicket;

NS_ASSUME_NONNULL_BEGIN

/**
 * Bitmask for specifiying which "meta" components to download from the cloud.
 */
typedef NS_OPTIONS(NSUInteger, ZDCNodeMetaComponents) {
	
	/** Bitmask flag that specifies the header should be downloaded. */
	ZDCNodeMetaComponents_Header    = (1 << 0), // 0001
	
	/** Bitmask flag that specifies the metadata section should be downloaded (if present). */
	ZDCNodeMetaComponents_Metadata  = (1 << 1), // 0010
	
	/** Bitmask flag that specifies the thumbnail section should be downloaded (if present). */
	ZDCNodeMetaComponents_Thumbnail = (1 << 2), // 0100
	
	/** Bitmask flag that specifies all non-data sections should be downloaded (header + metadata + thumbnail). */
	ZDCNodeMetaComponents_All = (ZDCNodeMetaComponents_Header    |
	                             ZDCNodeMetaComponents_Metadata  |
	                             ZDCNodeMetaComponents_Thumbnail ) // 0111
};

/**
 * CompletionBlock for downloading a node's "meta" components.
 *
 * @param header
 *   The header block for the file,
 *   which contains the offsets of the various sections within the encrypted file.
 *   (The header block is also encrypted in the cloud - but it's always at the very beginning of the file.
 *    So the framework knows how to fetch it & then decrypt it.)
 *   The header is automatically downloaded (if needed), and then cached in `-[ZDCNode cloudDataInfo]`.
 *
 * @param metadata
 *   The (raw) metadata information stored in the node's DATA file.
 *
 * @param thumbnail
 *   The (raw) thumbnail information stored in the node's DATA file.
 *
 * @param error
 *   If an error occurs, this value is non-nil.
 *   Common errors, such as S3 throttling requests, are automatically handled for you.
 */
typedef void (^NodeMetaDownloadCompletionBlock)(ZDCCloudDataInfo *_Nullable header, NSData *_Nullable metadata,
                                                NSData *_Nullable thumbnail, NSError *_Nullable error);

/**
 * CompletionBlock for downloading a node.
 *
 * On success, the file is downloaded and stored in a temporary location.
 * It's your responsibility to cleanup this file when you're done - either by deleting the file,
 * or moving it into a permananet location (e.g. by handing it over to the DiskManager).
 * If you forget to cleanup the file, it's stored in a temp directory,
 * so theoretically the OS will eventually clean it up for you. But don't play that game.
 * That's not cool. Cleanup your disk junk.
 *
 * The file is stored on disk in an encrypted format. See the `ZDCCryptoFile` class for
 * information about the multiple tools available for decrypting & reading the file.
 *
 * @param header
 *   The header block for the file,
 *   which contains the offsets of the various sections within the encrypted file.
 *   (The header block is also encrypted in the cloud - but it's always at the very beginning of the file.
 *    So the framework knows how to fetch it & then decrypt it.)
 *   The header is automatically downloaded (if needed), and then cached in `-[ZDCNode cloudDataInfo]`.
 *
 * @param cryptoFile
 *   The cryptoFile provides everything you need to read an encrypted file.
 *
 * @param error
 *   If an error occurs, this value is non-nil.
 *   Common errors, such as S3 throttling requests, are automatically handled for you.
 */
typedef void (^NodeDataDownloadCompletionBlock)(ZDCCloudDataInfo *_Nullable header,
                                                ZDCCryptoFile *_Nullable cryptoFile, NSError *_Nullable error);

/**
 * CompletionBlock for downloading an avatar.
 *
 * @param avatar
 *   The (raw) avatar information downloaded from the URL.
 *
 * @param error
 *   If an error occurs, this value is non-nil.
 */
typedef void (^UserAvatarDownloadCompletionBlock)(NSData *_Nullable avatar, NSError *_Nullable error);

/**
 * The DownloadManager is your one-stop-shop for downloading data from the cloud.
 *
 * Recall that the ZeroDark.cloud framework will automatically fetch the filesystem outline for you.
 * That is, it will tell you about the nodes that exist in the cloud, what their names are,
 * and what the tree/heirarchy looks like. But you're in complete control when it comes to downloading
 * the actual data (node content). This allows you to optimize for your app. For example:
 *
 * - speed up new app logins by not downloading old content
 * - save disk space by deleting local copies of node data that are no longer being used
 * - optimize per-device by downloading certain content on demand
 *
 * When you're ready to download the node content, the DownloadManager simplifies the process for you.
 * It will automatically coalesce multiple requests to download the same item.
 * And it supports optional background downloads,
 * so that downloads can continue while the app is backgrounded (or even quit).
 *
 * For downloads of very large items, the DownloadManager will automatically download the item in parts.
 * If the download is interrupted, it can automatically pick up where it left off.
 *
 * It also provides an NSProgress instance for all downloads,
 * allowing you to display progress items in your UI.
 * And it works in concert with the ProgressManager to simplify UI development.
 */
@interface ZDCDownloadManager : NSObject

/**
 * Downloads a small portion of the node's content.
 *
 * Recall that the ZeroDark.cloud framework allows you to include 3 sections for every node:
 * - metadata (optional)
 * - thumbnail (optional)
 * - data (required - actual content)
 *
 * By including additional sections, such as a thumbnail, you allow other devices to quickly
 * fetch small amounts of data from the cloud. Just enough to drive your UI, but without
 * forcing a full download of a potentially large item.
 * This method provides the ability to dowload just these components - the "meta" components.
 *
 * @param node
 *   The node you want to download.
 *
 * @param components
 *   Allows you to specify which components you're interested in downloading.
 *
 * @param options
 *   Various options regarding how to download the file, and whether it should be cached via the DiskManager.
 *   If nil, the default options are used: {cacheToDiskManager: YES, canDownloadWhileInBackground: NO}
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return A ticket that can be used to track the download.
 *         The ticket includes a NSProgress item that can be used for tracking.
 *         The progress item is also registered with the `ZDCProgressManager`,
 *         and can be fetched from there as well. (Meaning you also get throughput
 *         & estimated time remaining for this progress item.)
 */
- (ZDCDownloadTicket *)downloadNodeMeta:(ZDCNode *)node
                             components:(ZDCNodeMetaComponents)components
                                options:(nullable ZDCDownloadOptions *)options
                        completionQueue:(nullable dispatch_queue_t)completionQueue
                        completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock;

/**
 * Downloads the full DATA file from the cloud.
 *
 * @param node
 *   The node you want to download.
 *
 * @param options
 *   Various options regarding how to download the file, and whether it should be cached via the DiskManager.
 *   If nil, the default options are used: {cacheToDiskManager: NO, canDownloadWhileInBackground: NO}
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return A ticket that can be used to track the download.
 *         The ticket includes a NSProgress item that can be used for tracking.
 *         The progress item is also registered with the `ZDCProgressManager`,
 *         and can be fetched from there as well. (Meaning you also get throughput
 *         & estimated time remaining for this progress item.)
 */
- (ZDCDownloadTicket *)downloadNodeData:(ZDCNode *)node
                                options:(nullable ZDCDownloadOptions *)options
                        completionQueue:(nullable dispatch_queue_t)completionQueue
                        completionBlock:(NodeDataDownloadCompletionBlock)completionBlock;

/**
 * Downloads the avatar for a user.
 *
 * @note This method doesn't support background downloads (on iOS).
 *
 * @param user
 *   The associated user. (userID == ZDCUser.uuid)
 *
 * @param auth0ID
 *   Users are allowed to link multiple social identities to their user account.
 *   For example, they may link Facebook, LinkedIn, Google, etc.
 *   This specifies the particular social identifier associated with the download.
 *
 * @param options
 *   Various options regarding how to download the file, and whether it should be cached via the DiskManager.
 *   If nil, the default options are used: {cacheToDiskManager: YES, canDownloadWhileInBackground: NO}
 *   This method doesn't support background downloads (on iOS).
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return A ticket that can be used to track the download.
 *         The ticket includes a NSProgress item that can be used for tracking.
 *         The progress item is also registered with the `ZDCProgressManager`,
 *         and can be fetched from there as well. (Meaning you also get throughput
 *         & estimated time remaining for this progress item.)
 */
- (ZDCDownloadTicket *)downloadUserAvatar:(ZDCUser *)user
                                  auth0ID:(nullable NSString *)auth0ID
                                  options:(nullable ZDCDownloadOptions *)options
                          completionQueue:(nullable dispatch_queue_t)completionQueue
                          completionBlock:(UserAvatarDownloadCompletionBlock)completionBlock;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A simple container for holding several different download options.
 */
@interface ZDCDownloadOptions: NSObject <NSCoding, NSCopying>

/**
 * If set to YES, then after downloading the file, the DownloadManager will store the file to disk via the DiskManager.
 *
 * The file will be stored in a non-persistent mode.
 * That is, the file will be part of a storage pool cache managed by the DiskManager.
 * And the DiskManager will automatically delete files from this pool when its (configurable) max size is exceeded.
 * Also, the OS is allowed to delete the file due to low-disk-space pressure.
 *
 * The default value is NO.
 */
@property (nonatomic, assign, readwrite) BOOL cacheToDiskManager;

/**
 * If set to YES, then after downloading the file, the DownloadManager will store the file to disk via the DiskManager.
 *
 * The file will be stored in a persistent mode.
 * That is, the file won't be deleted unless you ask the DiskManager to delete it.
 * If you simply want to cache the value to disk temporarily,
 * while allowing the DiskManager or the OS to delete it as needed,
 * then use the cacheToDiskManager property instead.
 *
 * @important You are storing the file to disk in a persistent manner,
 *            and your app is responsible for deleting the file via the DiskManager.
 *
 * The default value is NO.
 */
@property (nonatomic, assign, readwrite) BOOL savePersistentlyToDiskManager;

#if TARGET_OS_IPHONE
/**
 * Set to YES if you want to allow the download to continue while the app is backgrounded.
 *
 * This value only applies to iOS-based platforms.
 * The default value is NO.
 */
@property (nonatomic, assign, readwrite) BOOL canDownloadWhileInBackground;
#endif

/**
 * The completionTag acts as a consolidation tool, and prevents multiple callbacks.
 *
 * For example, you may have code that requests all missing downloads.
 * The DownloadManager consolidates requests, so the same resource is only downloaded once.
 * However, the DownloadManager will invoke every completionBlock when the download completes.
 * This may not be what you want. A particular class may instead wish to receive only a single callback.
 * When this is the case, you can set a non-nil completionTag value.
 * And if there's already a queued completionBlock, then the passed completionBlock won't be added to the queue.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *completionTag;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The DownloadManager automatically consolidates multiple requests for the same item into a single task.
 * This minimizes bandwidth and improves app response time.
 *
 * However, it also means that your particular request may not be the only requester for a resource.
 * For example, there may be other ViewControllers within your app that are also waiting for the same data.
 * As such, it's not safe to cancel downloads directly.
 * Rather you're encouraged to cancel requests through the ticket instance.
 * This allows the ticket to handle complex cases where there are multiple requests for the resource.
 * And it also handles cancelling the downloads such that they can be resumed later.
 */
@interface ZDCDownloadTicket : NSObject

/**
 * The progress item can be used to track the download.
 *
 * This progress item is also registered with the `ZDCProgressManager`, and can be fetched from there as well.
 * This also means you get throughput information (NSProgressThroughputKey)
 * and estimated time remaining (NSProgressEstimatedTimeRemainingKey) for this progress item.
 *
 * @important Do NOT cancel the download directly through the progress instance.
 *            Use `-[ZDCDownloadTicket cancel]` or `-[ZDCDownloadTicket ignore]` instead.
 */
@property (nonatomic, readonly) NSProgress *progress;

/**
 * Indicates to the DownloadManager that you no longer need the data,
 * and that its free to cancel the download (as long as all other tickets agree).
 *
 * If the download is in progress, it will cancelled in a resumable manner.
 * Future requests for the same resource will resume where this download left off.
 *
 * Your completionBlock will be removed from the array of listeners.
 */
- (void)cancel;

/**
 * Indicates to the DownloadManager that you no longer need the data,
 * but that you wish the download to continue as planned.
 *
 * This is commonly used when the request included
 * either `-[ZDCDownloadOptions cacheToDiskManager]` or `-[ZDCDownloadOptions savePersistentlyToDiskManager]`.
 * In other words, you anticipate needing the object again in the near future,
 * and you want the download to complete so that it's cached on disk, and ready for next time.
 *
 * Your completionBlock will be removed from the array of listeners.
 */
- (void)ignore;

@end

NS_ASSUME_NONNULL_END
