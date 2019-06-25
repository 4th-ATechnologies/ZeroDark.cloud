/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import "OSPlatform.h"
#import "ZDCDownloadManager.h"

@class ZDCNode;
@class ZDCUser;
@class ZDCFetchOptions;

NS_ASSUME_NONNULL_BEGIN

/**
 * The ImageProcessingBlock allows you to modify an image for presentation within your UI.
 * For example, you may wish to resize the image.
 * For user avatars, you may wish to make them round, give them a border, etc.
 *
 * The ImageProcessingBlock operates in a background thread,
 * and its results get cached in memory (into a configurable NSCache instance).
 */
typedef OSImage*_Nonnull (^ZDCImageProcessingBlock)(OSImage *image);

/**
 * The ImageManager simplifies the process of fetching, downloading & resizing images.
 * This includes both node thumbnails & user avatars.
 */
@interface ZDCImageManager : NSObject

#pragma mark Configuration

/**
 * Direct access to the underlying in-memory cache container.
 *
 * You can configure the cache directly (via either countLimit and/or totalCostLimit),
 * or you can flush the cache (via removeAllObjects function).
 *
 * All items put into the cache are assigned a cost value based on the size of the data in bytes.
 * So its generally recommended that you configure the cache using the totalCostLimit property.
 *
 * The default configuration is:
 * - countLimit = 0
 * - totalCostLimit = 5 MiB (i.e.: 1024 * 1024 * 5)
 */
@property (nonatomic, readonly) NSCache *nodeThumbnailsCache;

/**
 * Direct access to the underlying in-memory cache container.
 *
 * You can configure the cache directly (via either countLimit and/or totalCostLimit),
 * or you can flush the cache (via removeAllObjects function).
 *
 * All items put into the cache are assigned a cost value based on the size of the data in bytes.
 * So its generally recommended that you configure the cache using the totalCostLimit property.
 *
 * The default configuration is:
 * - countLimit = 0
 * - totalCostLimit = 5 MiB (i.e.: 1024 * 1024 * 5)
 */
@property (nonatomic, readonly) NSCache *userAvatarsCache;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Thumbnails
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the node's thumbnail.
 *
 * Here's how this works:
 * - First, the in-memory cache is consulted to see if we have a ready image.
 *   That is, an image that's already been loaded from an earlier request, and the result has been cached in memory.
 * - If there's a match in the cache, the preFetchBlock is invoked with it's `willFetch` parameter
 *   set to FALSE. After which the method execution terminates - meaning the postFetchBlock is NOT invoked.
 * - Otherwise the preFetchBlock is invoked with it's `willFetch` parameter to to TRUE.
 * - Then the node thumbnail is asynchronously loaded from disk (if available in the DiskManager),
 *   or downloaded from the cloud.
 * - If the thumbnail is downloaded from the cloud, it will be cached in the DiskManager automatically.
 * - After loading or downloading, the image is cached in memory, and forwarded to you via the postFetchBlock.
 *
 * &nbsp;
 * @note You can contol the size of the in-memory cache via the `nodeThumbnailsCache` property.
 *
 * @important Empty results are also cached to prevent duplicate lookups. For example, if a node
 *            doesn't have a thumbnail, the result of the lookup (the 404), will be cached.
 *            This results in the preFetchBlock being invoked with its `willFetch` parameter to to FALSE,
 *            and its `image` parameter set to nil.
 *
 * @param node
 *   The node for which you wish to display the thumbnail.
 *
 * @param options
 *   If nil, the default options will be used.
 *
 * @param preFetchBlock
 *   This block is always invoked.
 *   And it's invoked BEFORE this method returns.
 *   It only returns an image if there's a match in the cache that can immediately be used.
 *   If the preFetchBlock parameter `willFetch` if FALSE, the postFetchBlock will NOT be invoked.
 *   Keep in mind that (image==nil && !willFetch) is a valid combination representing a
 *   previous fetch which resulted in no image for the request.
 *
 * @param postFetchBlock
 *   This method is invoked after the image has been read from disk or downloaded from the cloud.
 *   This block is only invoked if the preFetchBlock is invoked with its `willFetch` parameter set to true.
 *   This block is always invoked on the main thread.
 */
- (nullable ZDCDownloadTicket *)
        fetchNodeThumbnail:(ZDCNode *)node
               withOptions:(nullable ZDCFetchOptions *)options
             preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
            postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock;

/**
 * Fetches the node's thumbnail, and allows you to process the image.
 *
 * Here's how this works:
 * - A key is generated using a combination of the nodeID + processingID.
 * - This key is used to check the in-memory cache to see if we have a ready image.
 *    That is, an image that's already been loaded & processed from an earlier request,
 *    and the result (post-processing) has been cached in memory.
 * - If there's a match in the cache, the preFetchBlock is invoked with it's `willFetch` parameter
 *   set to FALSE. After which the method execution terminates - meaning the postFetchBlock is NOT invoked.
 * - Otherwise the preFetchBlock is invoked with it's `willFetch` parameter to to TRUE.
 * - Then the node thumbnail is asynchronously loaded from disk (if available in the DiskManager),
 *   or downloaded from the cloud.
 * - If the thumbnail is downloaded from the cloud, it will be cached in the DiskManager automatically.
 * - After loading or downloading, the processingBlock is invoked (on a background thread).
 * - The image returned from the processingBlock will be cached in-memory,
 *   and forwarded to the user via the postFetchBlock.
 *
 * &nbsp;
 * @note You can contol the size of the in-memory cache via the `nodeThumbnailsCache` property.
 *
 * @important Empty results are also cached to prevent duplicate lookups. For example, if a node
 *            doesn't have a thumbnail, the result of the lookup (the 404), will be cached.
 *            This results in the preFetchBlock being invoked with its `willFetch` parameter to to FALSE,
 *            and its `image` parameter set to nil.
 *
 * @param node
 *   The node for which you wish to display the thumbnail.
 *
 * @param options
 *   If nil, the default options will be used.
 *
 * @param processingID
 *   A unique identifier that distinguishes the results of this imageProcessingBlock from
 *   other imageProcessingBlocks that you may be using in other parts of your application.
 *   For example, if your block resizes the image to 64*64, then you might pass the string "64*64".
 *   If you pass a nil processingID, then the image won't be cached in memory.
 *
 * @param imageProcessingBlock
 *   A block you can use to modify the image.
 *   For example you might scale the image to a certain size, round the corners, give it tint, etc.
 *   The block will be invoked on a background thread.
 *
 * @param preFetchBlock
 *   This block is always invoked.
 *   And it's invoked BEFORE this method returns.
 *   It only returns an image if there's a match in the cache that can immediately be used.
 *   If the preFetchBlock parameter `willFetch` if FALSE, the postFetchBlock will NOT be invoked.
 *   Keep in mind that (image==nil && !willFetch) is a valid combination representing a
 *   previous fetch which resulted in no image for the request.
 *
 * @param postFetchBlock
 *   This method is invoked after the image has been read from disk or downloaded from the cloud.
 *   And after the processingBlock has done its work.
 *   This block is only invoked if the preFetchBlock is invoked with its `willFetch` parameter set to true.
 *   This block is always invoked on the main thread.
 */
- (nullable ZDCDownloadTicket *)
        fetchNodeThumbnail:(ZDCNode *)node
               withOptions:(nullable ZDCFetchOptions *)options
              processingID:(nullable NSString *)processingID
           processingBlock:(ZDCImageProcessingBlock)imageProcessingBlock
             preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
            postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock;

/**
 * Removes all cached thumbnail images for the given node.
 *
 * There's usually little reason to use this method because the
 * ImageManager automatically flushes its cache in response to changes in the DiskManager.
 *
 * @param nodeID
 *   Which node's thumbnail to flush from the cache (nodeID == ZDCNode.uuid)
 */
- (void)flushNodeThumbnailCache:(NSString *)nodeID;

/**
 * Removes all cached thumbnail images for the given processingID.
 *
 * You might use this method if you have an infrequently used ViewController,
 * and you'd prefer to flush the cache of all images it created since
 * you don't anticipate needing them again anytime soon.
 *
 * @param processingID
 *   A processingID that was used in `fetchNodeThumbnail:withProcessingID::::`
 */
- (void)flushNodeThumbnailCacheWithProcessingID:(NSString *)processingID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Avatars
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the user's avatar.
 *
 * Here's how this works:
 * - First, the in-memory cache is consulted to see if we have a ready image.
 *   That is, an image that's already been loaded from an earlier request,
 *   and the result has been cached in memory.
 * - If there's a match in the cache, the preFetchBlock is invoked with it's `willFetch` parameter
 *   set to FALSE. After which the method execution terminates - meaning the postFetchBlock is NOT invoked.
 * - Otherwise the preFetchBlock is invoked with it's `willFetch` parameter to to TRUE.
 * - Then the user avatar is asynchronously loaded from disk (if available in the DiskManager),
 *   or downloaded from the cloud.
 * - If the thumbnail is downloaded from the cloud, it will be cached in the DiskManager automatically.
 * - After loading or downloading, the image is cached in memory, and forwarded to you via the postFetchBlock.
 *
 * &nbsp;
 * @note You can contol the size of the in-memory cache via the `userAvatarsCache` property.
 *
 * @important Empty results are also cached to prevent duplicate lookups. For example, if a user
 *            doesn't have an avatar, the result of the lookup (the 404), will be cached.
 *            This results in the preFetchBlock being invoked with its `willFetch` parameter to to FALSE,
 *            and its `image` parameter set to nil.
 *
 * @param user
 *   The user for which you wish to display the avatar.
 *
 * @param preFetchBlock
 *   This block is always invoked.
 *   And it's invoked BEFORE this method returns.
 *   It only returns an image if there's a match in the cache that can immediately be used.
 *   If the preFetchBlock parameter `willFetch` if FALSE, the postFetchBlock will NOT be invoked.
 *   Keep in mind that (image==nil && !willFetch) is a valid combination representing a
 *   previous fetch which resulted in no image for the request.
 *
 * @param postFetchBlock
 *   This method is invoked after the image has been read from disk or downloaded from the cloud.
 *   This block is only invoked if the preFetchBlock is invoked with its `willFetch` parameter set to true.
 *   This block is always invoked on the main thread.
 */
- (nullable ZDCDownloadTicket *)
        fetchUserAvatar:(ZDCUser *)user
          preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
         postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock;

/**
 * Fetches the node's thumbnail, and allows you to process the image.
 *
 * Here's how this works:
 * - A key is generated using a combination of the nodeID + processingID.
 * - This key is used to check the in-memory cache (`userAvatarsCache`) to see if we have a ready image.
 *   That is, an image that's already been loaded & processed from an earlier request,
 *   and the result (post-processing) has been cached in memory.
 * - If there's a match in the cache), the preFetchBlock is invoked with it's `willFetch` parameter
 *   set to FALSE. After which the method execution terminates - meaning
 *   neither the processingBlock nor the postFetchBlock are invoked.
 * - Otherwise the preFetchBlock is invoked with it's `willFetch` parameter to to TRUE.
 * - Then the user avatar is asynchronously is loaded from disk (if available in the DiskManager),
 *   or downloaded from the cloud.
 * - If the user avatar is downloaded from the cloud, it will be cached in the DiskManager automatically.
 * - After loading or downloading, the processingBlock is invoked (on a background thread).
 * - The image returned from the processingBlock will be cached in-memory,
 *   and forwarded to the user via the postFetchBlock.
 *
 * &nbsp;
 * @note You can contol the size of the in-memory cache via the `nodeThumbnailsCache` property.
 *
 * @important Empty results are also cached to prevent duplicate lookups. For example, if a user
 *            doesn't have an avatar, the result of the lookup (the 404), will be cached.
 *            This results in the preFetchBlock being invoked with its `willFetch` parameter to to FALSE,
 *            and its `image` parameter set to nil.
 *
 * @param user
 *   The user for which you wish to fetch the avatar.
 *
 * @param processingID
 *   A unique identifier that distinguishes the results of this imageProcessingBlock from
 *   other imageProcessingBlocks that you may be using in other parts of your application.
 *   For example, if your block resizes the image to 64*64, then you might pass the string "64*64".
 *   If you pass a nil processingID, then the image won't be cached in memory.
 *
 * @param imageProcessingBlock
 *   A block you can use to modify the image.
 *   For example you might scale the image to a certain size, round the corners, give it tint, etc.
 *   The block will be invoked on a background thread.
 *
 * @param preFetchBlock
 *   This block is always invoked.
 *   And it's invoked BEFORE this method returns.
 *   It only returns an image if there's a match in the cache that can immediately be used.
 *   If the preFetchBlock parameter `willFetch` if FALSE, the postFetchBlock will NOT be invoked.
 *   Keep in mind that (image==nil && !willFetch) is a valid combination representing a
 *   previous fetch which resulted in no image for the request.
 *
 * @param postFetchBlock
 *   This method is invoked after the image has been read from disk or downloaded from the cloud.
 *   And after the processingBlock has done its work.
 *   This block is only invoked if the preFetchBlock is invoked with its `willFetch` parameter set to true.
 *   This block is always invoked on the main thread.
 */
- (nullable ZDCDownloadTicket *)
        fetchUserAvatar:(ZDCUser *)user
       withProcessingID:(nullable NSString *)processingID
        processingBlock:(ZDCImageProcessingBlock)imageProcessingBlock
          preFetchBlock:(void(NS_NOESCAPE^)(OSImage *_Nullable image, BOOL willFetch))preFetchBlock
         postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock;

/**
 * Removes all cached avatar images for the given user.
 *
 * There's usually little reason to use this method because the
 * ImageManager automatically flushes its cache in response to changes in the DiskManager.
 *
 * @param userID
 *   Which user's thumbnail to flush from the cache (userID == ZDCUser.uuid)
 */
- (void)flushUserAvatarsCache:(NSString *)userID;

/**
 * Removes all cached avatar images for the given processingID.
 *
 * You might use this method if you have an infrequently used ViewController,
 * and you'd prefer to flush the cache of all images it created since
 * you don't anticipate needing them again anytime soon.
 *
 * @param processingID
 *   A processingID that was used in `fetchUserAvatar:withProcessingID::::`
 */
- (void)flushUserAvatarsCacheWithProcessingID:(NSString *)processingID;

/**
 * Returns the default user avatar used by the framework.
 */
- (OSImage *)defaultUserAvatar;

/**
 * Returns the default multi-user avatar used by the framework.
 */
- (OSImage *)defaultMultiUserAvatar;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * FetchOptions allow you to configure the scenarios in which the image is downloaded from the cloud.
 */
@interface ZDCFetchOptions : NSObject <NSCopying>

/**
 * If set to YES, then the ImageManager will automatically attempt to download the latest version as needed.
 *
 * More specifically:
 * - If this property is set to YES/true
 * - And the thumbnail is marked as "needs download" for the ZDCComponent_Thumbnail flag
 *   (via `[ZDCCloudTransaction markNodeAsNeedsDownload:components:]`).
 * - Then a download will be initiated via the DownloadManager for the most recent version.
 *   (The DownloadManager will automatically consolidate multiple requests.)
 * - And the ImageManager will unmark the ZDCComponent_Thumbnail flag as "needs download" upon completion.
 *
 * The default value is YES.
 */
@property (nonatomic, assign, readwrite) BOOL downloadIfMarkedAsNeedsDownload;

@end

NS_ASSUME_NONNULL_END
