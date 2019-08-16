/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "ZDCDownloadManager.h"

@class ZDCCloudOperation;
@class ZDCProgress;

NS_ASSUME_NONNULL_BEGIN

/**
 * This notification is posted (to the main thread) whenever the progress list changes.
 * 
 * The notification will contain a userInfo dictionary with the following keys:
 * - kZDCProgressManagerChanges: An instance of `ZDCProgressManagerChanges`
 */
extern NSString *const ZDCProgressListChangedNotification;

/**
 * A key for the ZDCProgressListChangedNotification.userInfo dictionary,
 * which returns an instance of `ZDCProgressManagerChanges`.
 */
extern NSString *const kZDCProgressManagerChanges;

/**
 * Represents the type of operation being tracked by the progress item.
 */
typedef NS_ENUM(NSInteger, ZDCProgressType) {
	
	/**
	 * The progress item represents a download created via the ZDCDownloadManager (downloadNodeMeta...)
	 */
	ZDCProgressType_MetaDownload,
	
	/**
	 * The progress item represents a download created via the ZDCDownloadManager (downloadNodeData...)
	 */
	ZDCProgressType_DataDownload,
	
	/**
	 * The progress item represents an upload operation (ZDCCloudOperation).
	 * This upload operation was created in response to one or more changes made to a ZDCNode.
	 */
	ZDCProgressType_Upload,
};

/**
 * Reports the results of an upload attempt.
 * If an upload fails the PushManager may still be able to recover.
 */
typedef void (^UploadCompletionBlock)(BOOL success);

/**
 * The ProgressManager provides real-time progress information for active operations.
 *
 * This includes:
 * - downloads : as in the downloads of node data that you request through the DownloadManager
 * - uploads   : which get queued for the push manager, and then get uploaded when possible
 *
 * The ProgressManager automatically monitors its progress items,
 * and provides you with the following useful information:
 *
 * - Bandwidth calculations:
 *   - Estimated bytes-per-second.
 *   - Available via progress.userInfo[NSProgressThroughputKey]
 *
 * - Time remaining calculations:
 *   - Estimated time remaining based on averaged throughput & remaining bytes.
 *   - Available via progress.userInfo[NSProgressEstimatedTimeRemainingKey]
 */
@interface ZDCProgressManager : NSObject

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads - General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the list of nodeIDs that currently have associated downloads.
 * The downloads can be of any type - either meta or data.
 */
- (NSSet<NSString *> *)allDownloadingNodeIDs;

/**
 * Returns the list of nodeIDs (for the given user) that currently have associated downloads.
 * The downloads can be of any type - either 'meta' or 'data'.
 *
 * @param localUserID
 *   The user you're interested in. (localUserID == ZDCLocalUser.uuid)
 */
- (NSSet<NSString *> *)allDownloadingNodeIDs:(NSString *)localUserID;

/**
 * If available, returns the download progress of the node.
 * If there are currently multiple downloads for the node,
 * the priority is (from highest to lowest): 'data', 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @return The download progress, if available.
 */
- (nullable NSProgress *)downloadProgressForNodeID:(NSString *)nodeID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads - Meta
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the list of nodeIDs that currently have associated 'meta' downloads.
 *
 * @note Downloads are started via the `ZDCDownloadManager`.
 */
- (NSSet<NSString *> *)allMetaDownloadingNodeIDs;

/**
 * Returns the list of nodeIDs (for the given user) that currently have associated 'meta' downloads.
 *
 * @note Downloads are started via the `ZDCDownloadManager`.
 *
 * @param localUserID
 *   The user you're interested in. (localUserID == ZDCLocalUser.uuid)
 */
- (NSSet<NSString *> *)allMetaDownloadingNodeIDs:(NSString *)localUserID;

/**
 * If available, returns the 'meta' download progress of the node.
 *
 * If multiple 'meta' downloads exist for the given node,
 * the priority is (from highest to lowest): 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID;

/**
 * If available, returns the 'meta' download progress of the node.
 *
 * If you pass nil for the components parameter, and multiple downloads exist,
 * the priority is (from highest to lowest): 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param components
 *   Pass non-nil wrapped ZDCNodeMetaComponents if you're interested in a particular meta download.
 *   Otherwise pass nil to receive based on the standard priority.
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
                                            components:(nullable NSNumber *)components;

/**
 * If available, returns the 'meta' download progress of the node.
 * If the completionBlock is non-nil, then it will be invoked upon download completion.
 *
 * If multiple 'meta' downloads exist for the given node,
 * the priority is (from highest to lowest): 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * @note The progress manager supports multiple {completionBlock, completionQueue} tuples.
 *       All of them will be invoked upon download completion.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
                                       completionQueue:(nullable dispatch_queue_t)completionQueue
                                       completionBlock:(nullable NodeMetaDownloadCompletionBlock)completionBlock;

/**
 * If available, returns the 'meta' download progress of the node.
 * If the completionBlock is non-nil, then it will be invoked upon download completion.
 *
 * If you pass nil for the components parameter,
 * and multiple 'meta' downloads exist for the given node,
 * the priority is (from highest to lowest): 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * @note The progress manager supports multiple {completionBlock, completionQueue} tuples.
 *       All of them will be invoked upon download completion.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param components
 *   Pass non-nil wrapped ZDCNodeMetaComponents if you're interested in a particular meta download.
 *   Otherwise pass nil to receive based on the standard priority.
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
                                            components:(nullable NSNumber *)components
                                       completionQueue:(nullable dispatch_queue_t)completionQueue
                                       completionBlock:(nullable NodeMetaDownloadCompletionBlock)completionBlock;

/**
 * Adds the given listener.
 * That is, a {completionQueue, completionBlock} for the download.
 *
 * If multiple 'meta' downloads exist for the given node,
 * the priority is (from highest to lowest): 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * This method is the same as calling `metaDownloadProgressForNodeID:completionQueue:completionBlock:`,
 * and then ignoring the return value. It's just named better. And you won't have to worry
 * about the compiler whining that you ignored the return value.
 *
 * @note The progress manager supports multiple {completionBlock, completionQueue} tuples.
 *       All of them will be invoked upon download completion.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return YES if there's an existing 'data' download for the given nodeID,
 *         and the {completionQueue, completionBlock} was added to the list. NO otherwise.
 */
- (BOOL)addMetaDownloadListenerForNodeID:(NSString *)nodeID
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock;

/**
 * Adds the given listener.
 * That is, a {completionQueue, completionBlock} for the download.
 *
 * If you pass nil for the components parameter,
 * and multiple 'meta' downloads exist for the given node,
 * the priority is (from highest to lowest): 'all-meta', 'thumbnail', 'metadata', 'header'.
 *
 * This method is the same as calling `metaDownloadProgressForNodeID:components:completionQueue:completionBlock:`,
 * and then ignoring the return value. It's just named better. And you won't have to worry
 * about the compiler whining that you ignored the return value.
 *
 * @note The progress manager supports multiple {completionBlock, completionQueue} tuples.
 *       All of them will be invoked upon download completion.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return YES if there's an existing 'data' download for the given nodeID,
 *         and the {completionQueue, completionBlock} was added to the list. NO otherwise.
 */
- (BOOL)addMetaDownloadListenerForNodeID:(NSString *)nodeID
                              components:(nullable NSNumber *)components
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock;

/**
 * Associates the given progress with a download of the node.
 * If there is already a download for this {localUserID, nodeID} tuple, then the request is ignored.
 *
 * @param progress
 *   An NSProgress associated with the download.
 *
 * @param nodeID
 *   Every node has a unique ID. (nodeID == ZDCNode.uuid)
 *
 * @param components
 *   The specific components being downloaded (with extraneous flags removed).
 *
 * @param localUserID
 *   The download is going through this account. (localUserID == ZDCLocalUser.uuid)
 *
 * @return YES if the download was added to the list.
 *         NO if there was already a download in the list for the {localUserID, nodeID} tuple.
 */
- (BOOL)setMetaDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                     components:(ZDCNodeMetaComponents)components
                    localUserID:(NSString *)localUserID;

/**
 * Removes the associated download listener.
 * This doesn't stop the download, it just removes the listener.
 *
 * @note The completionBlock may still be invoked if it's already be dispatched.
 */
- (void)removeMetaDownloadListenerForNodeID:(NSString *)nodeID
                                 components:(ZDCNodeMetaComponents)components
                            completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock;

/**
 * Removes the associated download progress,
 * and then invokes all the queued completionBlocks with the given parameters.
 */
- (void)removeMetaDownloadProgressForNodeID:(NSString *)nodeID
                                 components:(ZDCNodeMetaComponents)components
                                 withHeader:(nullable ZDCCloudDataInfo *)header
                                   metadata:(nullable NSData *)metadata
                                  thumbnail:(nullable NSData *)thumbnail
                                      error:(nullable NSError *)error;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads - Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the list of nodeIDs that currently have associated 'data' downloads.
 *
 * @note Downloads are started via the `ZDCDownloadManager`.
 */
- (NSSet<NSString *> *)allDataDownloadingNodeIDs;

/**
 * Returns the list of nodeIDs (for the given user) that currently have associated 'data' downloads.
 *
 * @note Downloads are started via the `ZDCDownloadManager`.
 *
 * @param localUserID
 *   The user you're interested in. (localUserID == ZDCLocalUser.uuid)
 */
- (NSSet<NSString *> *)allDataDownloadingNodeIDs:(NSString *)localUserID;

/**
 * If available, returns the 'data' download progress of the node.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 */
- (nullable NSProgress *)dataDownloadProgressForNodeID:(NSString *)nodeID;

/**
 * If available, returns the 'data' download progress of the node.
 * If the completionBlock is non-nil, then it will be invoked upon download completion.
 *
 * @note The progress manager supports multiple {completionBlock, completionQueue} tuples.
 *       All of them will be invoked upon download completion.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 */
- (nullable NSProgress *)dataDownloadProgressForNodeID:(NSString *)nodeID
                                       completionQueue:(nullable dispatch_queue_t)completionQueue
                                       completionBlock:(nullable NodeDataDownloadCompletionBlock)completionBlock;

/**
 * Adds the given listener.
 * That is, a {completionQueue, completionBlock} for the download.
 *
 * This method is the same as calling `dataDownloadProgressForNodeID:completionQueue:completionBlock:`,
 * and then ignoring the return value. It's just named better. And you won't have to worry
 * about the compiler whining that you ignored the return value.
 *
 * @note The progress manager supports multiple {completionBlock, completionQueue} tuples.
 *       All of them will be invoked upon download completion.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon download completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return YES if there's an existing 'data' download for the given nodeID,
 *         and the {completionQueue, completionBlock} was added to the list. NO otherwise.
 */
- (BOOL)addDataDownloadListenerForNodeID:(NSString *)nodeID
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(NodeDataDownloadCompletionBlock)completionBlock;

/**
 * Associates the given progress with a download of the node.
 * If there is already a download for this {localUserID, nodeID} tuple, then the request is ignored.
 *
 * @param progress
 *   An NSProgress associated with the download.
 *
 * @param nodeID
 *   Every node has a unique ID. (nodeID == ZDCNode.uuid)
 *
 * @param localUserID
 *   The download is going through this account. (localUserID == ZDCLocalUser.uuid)
 *
 * @return YES if the download was added to the list.
 *         NO if there was already a download in the list for the {localUserID, nodeID} tuple.
 */
- (BOOL)setDataDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                    localUserID:(NSString *)localUserID;

/**
 * Removes the associated download listener.
 * This doesn't stop the download, it just removes the listener.
 *
 * @note The completionBlock may still be invoked if it's already be dispatched.
 */
- (void)removeDataDownloadListenerForNodeID:(NSString *)nodeID
                            completionBlock:(NodeDataDownloadCompletionBlock)completionBlock;

/**
 * Removes the associated download progress,
 * and then invokes all the queued completionBlocks with the given parameters.
 */
- (void)removeDataDownloadProgressForNodeID:(NSString *)nodeID
                                 withHeader:(nullable ZDCCloudDataInfo *)header
                                 cryptoFile:(nullable ZDCCryptoFile *)cryptoFile
                                      error:(nullable NSError *)error;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Uploads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the list of operationUUIDs that currently have an associated upload progress.
 */
- (NSSet<NSUUID *> *)allUploadingOperationUUIDs;

/**
 * Returns the list of operationUUIDs (for the given user) that currently have associated upload progress.
 */
- (NSSet<NSUUID *> *)allUploadingOperationUUIDs:(NSString *)localUserID;

/**
 * Returns the list of nodeIDs that currently have associated downloads.
 */
- (NSSet<NSString *> *)allUploadingNodeIDs;

/**
 * Returns the list of nodeIDs (for the given user) that currently have associated upload progress.
 */
- (NSSet<NSString *> *)allUploadingNodeIDs:(NSString *)localUserID;

/**
 * If available, returns the upload progress for the given operation.
 *
 * @param operationID
 *   The operation you're interested in (operationID == ZDCCloudOperation.uuid)
 *
 * @return The progress for the upload in-flight, if it exists. Nil otherwise.
 */
- (nullable NSProgress *)uploadProgressForOperationUUID:(NSUUID *)operationID;

/**
 * If available, returns the upload progress for the given operation.
 *
 * @param operationID
 *   The operation you're interested in (operationID == ZDCCloudOperation.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon upload completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return The progress for the upload in-flight, if it exists. Nil otherwise.
 */
- (nullable NSProgress *)uploadProgressForOperationUUID:(NSUUID *)operationID
                                        completionQueue:(nullable dispatch_queue_t)completionQueue
													 completionBlock:(nullable UploadCompletionBlock)completionBlock;

/**
 * If available, returns the upload progress for the node.
 *
 * A data upload is a ZDCCloudOperation whose `putType` is ZDCCloudOperationPutType_Node_Data.
 * That is, an upload of the node's data => the actual content.
 * As opposed to the RCRD => treesystem bookkeeping stuff.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @return The progress for the upload in-flight, if it exists. Nil otherwise.
 */
- (nullable NSProgress *)dataUploadProgressForNodeID:(NSString *)nodeID;

/**
 * If available, returns the upload progress for the node.
 *
 * A data upload is a ZDCCloudOperation whose `putType` is ZDCCloudOperationPutType_Node_Data.
 * That is, an upload of the node's data => the actual content.
 * As opposed to the RCRD => treesystem bookkeeping stuff.
 *
 * @param nodeID
 *   The node you're interested in. (nodeID == ZDCNode.uuid)
 *
 * @param completionQueue
 *   The GCD dispatch queue in which you'd like the completionBlock to be invoked.
 *   If not specified (nil), the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke upon upload completion.
 *   This block will be invoked asynchronously on the completionQueue.
 *
 * @return The progress for the upload in-flight, if it exists. Nil otherwise.
 */
- (nullable NSProgress *)dataUploadProgressForNodeID:(NSString *)nodeID
                                     completionQueue:(nullable dispatch_queue_t)completionQueue
                                     completionBlock:(nullable UploadCompletionBlock)completionBlock;

/**
 * Associates the given progress with the upload for the operation.
 *
 * @param progress
 *   An NSProgress associated with the upload.
 *
 * @param operation
 *   The associated operation.
 *
 * @return YES if the upload was added to the list.
 *         NO if there was already an upload in the list for the operation.
 */
- (BOOL)setUploadProgress:(NSProgress *)progress
             forOperation:(ZDCCloudOperation *)operation;

/**
 * Removes the associated upload progress,
 * and then invokes all the queued completionBlocks with the given parameter.
 */
- (void)removeUploadProgressForOperationUUID:(NSUUID *)operationID
                                 withSuccess:(BOOL)success;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Instances of this class are broadcast via `ZDCProgressManagerChangedNotification`.
 *
 * It can be extracted from the ZDCProgressManagerChangedNotification.userInfo dictionary
 * using the `ZDCProgressManagerChanges` key.
 */
@interface ZDCProgressManagerChanges : NSObject

/**
 * The type of progress item that changed.
 */
@property (nonatomic, readonly) ZDCProgressType progressType;

/**
 * The localUser for which the progress is associated. (localUserID == ZDCLocalUser.uuid)
 */
@property (nonatomic, readonly) NSString *localUserID;

/**
 * The node for which the progress is associated. (nodeID == ZDCNode.uuid)
 */
@property (nonatomic, readonly) NSString *nodeID;

/**
 * If the progressType is `ZDCProgressType_MetaDownload`,
 * represents the meta components that are being downloaded.
 */
@property (nonatomic, readonly) ZDCNodeMetaComponents metaComponents;

/**
 * If the progressType is `ZDCProgressType_Upload`,
 * represents the ZDCCloudOperation. (operationUUID == ZDCCloudOperation.uuid)
 */
@property (nonatomic, readonly, nullable) NSUUID *operationUUID;

/**
 * If the progressType is `ZDCProgressType_Upload`,
 * tells you whether or not: ZDCCloudOperation.putType == ZDCCloudOperationPutType_Node_Data
 *
 * In other words, is this the operation that's uploading the actual data for a node.
 * (As opposed to, say, the treesystem metadata.)
 */
@property (nonatomic, readonly) BOOL isDataUpload;

@end

NS_ASSUME_NONNULL_END
