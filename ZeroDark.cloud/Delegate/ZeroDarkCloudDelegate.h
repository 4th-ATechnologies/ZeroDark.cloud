/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCTreesystemPath.h"
#import "ZDCNode.h"
#import "ZDCData.h"
#import "ZDCDownloadManager.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Used as a flag passed to `-[ZeroDarkCloudDelegate didModifyNode::::]`,
 * which tells the delegate how the node was modified.
 */
typedef NS_ENUM(NSInteger, ZDCNodeChange) {
	
	/**
	 * Only treesystem information was changed, such as the node's name, permissions, etc.
	 * (i.e. the RCRD file in the cloud was changed)
	 *
	 * In other words, only the metadata stored in the treesystem,
	 * and not the node's data (that your app creates).
	 */
	ZDCNodeChange_Treesystem,
	
	/**
	 * The node's data was changed (the data that your app creates).
	 * (i.e. the DATA file in the cloud was changed)
	 */
	ZDCNodeChange_Data
};

/**
 * The ZeroDarkCloudDelegate assists in push & pull operations,
 * and facilitates communication about cloud changes.
 */
@protocol ZeroDarkCloudDelegate <NSObject>
@required

#pragma mark Push - Nodes

/**
 * When the PushManager is ready to upload a node, it uses this method to request the node's data.
 *
 * The framework supports everything from empty nodes, to multi-gigabyte nodes.
 * The `ZDCData` class helps to support this diversity by providing multiple ways
 * in which you can reference the data that is to be encrypted & uploaded.
 *
 * For small nodes, you can simply serialize the data, and create a ZDCData holding those bytes.
 * For larger files, you can provide a reference to a fileURL.
 *
 * The framework also supports files that are stored on disk in an encrypted format via `ZDCCryptoFile`.
 * For example, you can use the `ZDCDiskManager` to store files on disk in an encrypted manner.
 * And files stored by the ZDCDiskManager can be easily uploaded by initializing a ZDCData
 * instance from a ZDCCryptoFile returned from the DiskManager.
 *
 * @note The data that you return will be properly encrypted by the framework (as needed)
 *       before uploading it to the cloud.
 *
 * @param node
 *   The node that is being uploaded
 *
 * @param path
 *   The treesystem path of the node.
 *
 * @param transaction
 *   An atomic transaction in which its safe to read any needed information from the database.
 *
 * @return A ZDCData instance that wraps the data to be uploaded.
 */
- (ZDCData *)dataForNode:(ZDCNode *)node
                  atPath:(ZDCTreesystemPath *)path
             transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * When the PushManager is ready to upload a node, it uses this method request the node's optional metadata.
 *
 * The framework supports everything from empty nodes, to multi-gigabyte nodes.
 * If you're storing large files in the cloud, you may want to include an additional metadata section.
 * By doing so, you allow other devices to download the metadata independently from the (large) full node.
 *
 * For example, say the node is a movie file that's over 100 MB.
 * You could also include a small bit of metadata that includes the movie's length, format, etc.
 * This would allow other devices to download just the metadata and thumbnail,
 * and then have everything needed to display the movie within your UI.
 *
 * (Remember, the server cannot read the content that you store in the cloud.
 *  So it's impossible to ask the server to extract any information, such as metadata or a thumbnail.)
 *
 * @note The data that you return will be properly encrypted by the framework (as needed)
 *       before uploading it to the cloud.
 *
 * @param node
 *   The node that is being uploaded.
 *
 * @param path
 *   The treesystem path of the node.
 *
 * @param transaction
 *   An atomic transaction in which its safe to read any needed information from the database.
 *
 * @return Either nil, or a ZDCData instance that wraps the (serialized) metadata to be included in the upload.
 */
- (nullable ZDCData *)metadataForNode:(ZDCNode *)node
                               atPath:(ZDCTreesystemPath *)path
                          transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * When the PushManager is ready to upload a node, it uses this method to request the node's optional thumbnail.
 *
 * The framework supports everything from empty nodes, to multi-gigabyte nodes.
 * If you're storing large files in the cloud, you may want to include an additional metadata section.
 * By doing so, you allow other devices to download the thumbnail independently from the (large) full node.
 *
 * For example, say the node is a large image from a modern camera.
 * You could also include a small thumbnail version of the image.
 * This would allow other devices to download just the thumbnail,
 * and then have everything needed to display the image within your UI.
 * You'll use less bandwidth, and the client applications will use less storage for each image.
 * The full version of the image can be downloaded on demand.
 *
 * (Remember, the server cannot read the content that you store in the cloud.
 *  So it's impossible to ask the server to extract any information, such as metadata or a thumbnail.)
 *
 * @note The data that you return will be properly encrypted by the framework (as needed)
 *       before uploading it to the cloud.
 *
 * @param node
 *   The node that is being uploaded.
 *
 * @param path
 *   The treesystem path of the node.
 *
 * @param transaction
 *   An atomic transaction in which its safe to read any needed information from the database.
 *
 * @return Either nil, or a ZDCData instance that wraps the (serialized) thumbnail to be included in the upload.
 */
- (nullable ZDCData *)thumbnailForNode:(ZDCNode *)node
                                atPath:(ZDCTreesystemPath *)path
                           transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * This method is called by the framework after a node's data has been pushed to the cloud.
 *
 * When this method is called, the ZDCNode instance has already been updated within the database.
 * This method is being called within the same atomic transaction that modifies the node in the database.
 *
 * The information that may be useful to you is:
 * - node.eTag_data
 * - node.lastModified_data
 *
 * In particular, storing the `eTag_data` property in your custom model objects
 * will allow you to determine if your object is behind the server, and requires a download.
 *
 * @param node
 *   The updated node.
 *
 * @path
 *   The location of the node within the treesystem.
 *
 * @param transaction
 *   The atomic transaction in which the node was modified in the database.
 */
- (void)didPushNodeData:(ZDCNode *)node
                 atPath:(ZDCTreesystemPath *)path
            transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark Push - Messages

/**
 * When the PushManager is ready to send an outgoing message, it uses this method to request the message data.
 *
 * You are allowed to send messages that contain an unlimited amount of data, however,
 * there are restrictions regarding the location of the data.
 *
 * For example, imagine that Alice wants to send a 1 gigabyte file to Bob.
 *
 * The following is allowed:
 * - Alice stores the 1 gigabyte file somewhere in her own treesystem
 * - She gives Bob read permission to this file
 * - Then she sends a message to Bob that contains a link to the file
 *
 * The following is also allowed:
 * - Bob creates a "folder" in his treesystem, and gives Alice has write permission to it
 * - Alice then stores the 1 gigabyte file in that "folder" (within Bob's treesystem)
 *
 * However, the following is NOT allowed:
 * - Alice sends a message to Bob that contains the 1 gigabyte file
 *
 * In other words, raw messages are limited to a maximum of 1 MiB (1,048,576 bytes).
 * However there are no restrictions on the size of attachments.
 * And your app is free to decide exactly where & how attachments are stored.
 *
 * One common solution is to store attachments in the "outbox" folder.
 * For example, Alice would store that 1 gig file in her outbox folder.
 * And her message to Bob would contain a reference to the file.
 * She may be even set a "burn" time on the 1 gig file so it gets deleted automatically by the server after 30 days.
 *
 * @param user
 *   The user to which the message will be sent.
 *
 * @messageID
 *   The UUID of the message.
 *   You received this value when you originally queued the message via `[ZDCCloudTransaction sendMessageToUser:]`.
 *
 * @param transaction
 *   An atomic transaction in which its safe to read any needed information from the database.
 *
 * @return Either nil, or a ZDCData instance that wraps the message data to send.
 */
- (nullable ZDCData *)messageDataForUser:(ZDCUser *)user
                           withMessageID:(NSString *)messageID
                             transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * This method is called by the framework after a message has been sent.
 *
 * When this method is called, the queued ZDCCloudOperation has already been deleted from the database.
 * This method is being called within the same atomic transaction that modifies the the database.
 *
 * @param user
 *   The user to which the message was sent.
 *
 * @messageID
 *   The UUID of the message.
 *
 * @param transaction
 *   The atomic transaction in which the database was modified.
 *   This allows you to update your own objects within the same atomic transaction that
 *   removes the queued outgoing message.
 */
- (void)didSendMessageToUser:(ZDCUser *)user
               withMessageID:(NSString *)messageID
                 transaction:(YapDatabaseReadWriteTransaction *)transaction;;

#pragma mark Pull

/**
 * This method is called by the framework when a new node has been discovered in the cloud.
 *
 * This method is NOT called if you directly create a new node (in your app, on this device).
 * It's only called if a new node has been detected in the cloud.
 * In other words, you're being notified about some change in the cloud that the framework discovered while syncing.
 *
 * The framework automatically fetches the treesystem information from the cloud.
 * That is, the node's name, permissions, and its location within the tree.
 * However the framework does NOT automatically download the node's data (the content your app creates).
 * Instead the framework allows you to make those decisions, which allows you to optimize for your app.
 * For example, you may choose not to download all content. Or perhaps download certain content on demand.
 *
 * When you're ready to download the node's content,
 * the `ZDCDownloadManager` has multiple methods which allow you to download different things.
 *
 * To download the entire node data, you can use
 * `-[ZDCDownloadManager downloadNodeData:options:completionQueue:completionBlock:]`.
 *
 * Alternatively, you can choose just to download the node's metadata or thumbnail via
 * `-[ZDCDownloadManager downloadNodeMeta:components:options:completionQueue:completionBlock:]`.
 *
 * @note Recall that the server cannot read the content that's stored in the cloud.
 *       So the server has no idea if the content is an image. Which means it's impossible
 *       for the server to generate a thumbnail of your content on the fly.
 *       If you want to enable the download of smaller thumbnails, you must include these with the upload,
 *       via `-thumbnailForNode:atPath:transaction:`.
 *
 * When this method is called, the ZDCNode instance has already been added to the database.
 * This method is being called within the same atomic transaction that adds the node to the database.
 *
 * @param node
 *   The newly discovered node.
 *
 * @path
 *   The location of the node within the treesystem.
 *
 * @param transaction
 *   The atomic transaction in which the node was added to the database.
 */
- (void)didDiscoverNewNode:(ZDCNode *)node
                    atPath:(ZDCTreesystemPath *)path
               transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * This method is called by the framework when a node is discovered to have been modified in the cloud.
 *
 * This method is NOT called if you directly modify a node (in your app, on this device).
 * It's only called if a modified node has been detected in the cloud.
 * In other words, you're being notified about some change in the cloud that the framework discovered while syncing.
 *
 * There are two possibilities here.
 * - Only the treesystem info was modified (filename, permissions, etc)
 * - Only the node's data was modified (the content generated by your app)
 *
 * When this method is called, the ZDCNode instance has already been updated within the database.
 * This method is being called within the same atomic transaction that modifies the node in the database.
 *
 * @param node
 *   The modified node.
 *
 * @param path
 *   The location of the node within the treesystem.
 *
 * @param transaction
 *   The atomic transaction in which the node was modified in the database.
 */
- (void)didDiscoverModifiedNode:(ZDCNode *)node
                     withChange:(ZDCNodeChange)change
                         atPath:(ZDCTreesystemPath *)path
                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Invoked when the system discovers that a node was moved and/or renamed.
 *
 * This method is NOT called if you directly move/rename a node (in your app, on this device).
 * It's only called if a moved/renamed node has been detected in the cloud.
 * In other words, you're being notified about some change in the cloud that the framework discovered while syncing.
 *
 * When this method is called, the node has already been updated,
 * and the updates have been written to the database.
 * This method is being called within the same atomic transaction that modified the node in the database.
 *
 * @param node
 *   The node that was moved and/or renamed.
 *
 * @param oldPath
 *   The filesystem path of the node before it was moved.
 *
 * @param newPath
 *   The filesystem path of the node after it was moved.
 *
 * @param transaction
 *   An active read-write transaction.
 *   This is the same transaction in which the node was just deleted.
 *   Its recommended you update your own objects within the same atomic transaction.
 */
- (void)didDiscoverMovedNode:(ZDCNode *)node
                        from:(ZDCTreesystemPath *)oldPath
                          to:(ZDCTreesystemPath *)newPath
                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Invoked when the system discovers that a node has been deleted from the cloud.
 *
 * This method is NOT called if you directly delete a node (in your app, on this device).
 * It's only called if a deleted node has been detected in the cloud.
 * In other words, you're being notified about some change in the cloud that the framework discovered while syncing.
 *
 * When this method is called, the node has already been removed from the database.
 * This method is being called within the same atomic transaction that removed the node from the database.
 *
 * @param node
 *   The node that was deleted.
 *
 * @param path
 *   The filesystem path of the node that was deleted.
 *
 * @param timestamp
 *   The date & time the delete was performed by the server.
 *   If the client is relatively up-to-date, we'll have this information from the server.
 *   If not, this information won't be available for us.
 *
 * @param transaction
 *   An active read-write transaction.
 *   This is the same transaction in which the node was just deleted.
 *   Its recommended you update your own objects within the same atomic transaction.
 */
- (void)didDiscoverDeletedNode:(ZDCNode *)node
                        atPath:(ZDCTreesystemPath *)path
                     timestamp:(nullable NSDate *)timestamp
                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

@optional

/**
 * This (optional) method is called when:
 *
 * - the framework discovered that node X was deleted from the cloud
 * - but the framework still has operations queued to modify children of node X
 *
 * The proper way to handle such a situation is highly dependent on both the app & specific node.
 *
 * Here's what the framework does:
 * - It calculates a list of "clean" top-level nodes that are children/ancestors of 'node'.
 * - It invokes this method to inform you of the situation
 * - Afterwards it enumerates all the clean top-level nodes, and deletes them (if they still exist).
 *   For each deleted node, the `didDiscoverDeletedNode::::` delegate method is invoked.
 *
 * The deleted dirty node is NOT automatically deleted from the database.
 * Neither are any of the dirty ancestors, nor any parents that lead from 'node' to a dirty ancestor.
 *
 * When this delegate method is invoked, neither the node,
 * nor any of its ancestors (clean or dirty) have been deleted from the database.
 */
- (void)didDiscoverDeletedDirtyNode:(ZDCNode *)node
                     dirtyAncestors:(NSArray<NSString*> *)dirtyAncestors
                          timestamp:(nullable NSDate *)timestamp
                        transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * This (optional) method is called when:
 *
 * - there's a local node at path X
 * - it hasn't been uploaded to the cloud yet,
 *   or it's been moved, and the move operation hasn't hit the cloud yet
 * - a new node is discovered in the cloud with the same path X
 *
 * Since two nodes with the same path cannot both exist in the cloud, this means the local node will need to adapt.
 * The conflict can be resolved by performing one of the following options:
 *
 * Option A:
 * - rename the node so it's no longer a conflict (i.e. change node.name)
 * - be sure to invoke `[ZDCCloudTransaction modifyNode:]`
 *
 * Option B:
 * - delete the node
 * - be sure to invoke `[ZDCCloudTransaction deleteNode:]`
 *
 * If you do nothing, the system will automatically perform option A for you.
 *
 * @param node
 *   This is the local version of the node that is in conflict with the cloud.
 *   This node will need to be modified or deleted.
 *   When this method is called, the node is still stored in the database.
 *
 * @param path
 *   The treesystem path of the node in conflict.
 *
 * @param transaction
 *   An active read-write transaction.
 */
- (void)didDiscoverConflictNode:(ZDCNode *)node
                         atPath:(ZDCTreesystemPath *)path
                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark Background Downloads

#if TARGET_OS_IOS
/**
 * Background downloads can be tricky - and this delegate method is for an edge case.
 *
 * The edge case occurs when your app is terminated, but the background download ultimately completes,
 * and the app is notified about the completed download AFTER a NEW app launch.
 * In other words, the completionBlock you had initially installed to handle the download request
 * no longer exists because the app has been restarted since then.
 *
 * It's an edge case for sure, but also one that may not be too difficult to handle.
 * This method, if implemented, allows you to handle this edge case.
 *
 * @note: This method is ONLY used on iOS. It will never be invoked on macOS.
 * @note: This method is never invoked for failed downloads - only successful downloads
 *        where there's actual data your app may be interested in.
 *
 * @param node
 *   The node for which the meta download was requested.
 *
 * @param path
 *   The filesystem path of the node.
 *
 * @param components
 *   The meta components that were requested.
 *
 * @param header
 *   The header information for the DATA file in the cloud.
 *   Recall that the DATA file stores the node's contents (metadata, thumbnail & data).
 *
 * @param metadata
 *   If requested, and if the DATA file contains a metadata section, this value will be non-nil.
 *
 * @param thumbnail
 *   If requested, and if the DATA file contains a thumbanil section, this value will be non-nil.
 */
- (void)didBackgroundDownloadNodeMeta:(ZDCNode *)node
                               atPath:(ZDCTreesystemPath *)path
                       withComponents:(ZDCNodeMetaComponents)components
                               header:(ZDCCloudDataInfo *)header
                             metadata:(nullable NSData *)metadata
                            thumbnail:(nullable NSData *)thumbnail;

/**
 * Background downloads can be tricky - and this delegate method is for an edge case.
 *
 * The edge case occurs when your app is terminated, but the background download ultimately completes,
 * and the app is notified about the completed download AFTER a NEW app launch.
 * In other words, the completionBlock you had initially installed to handle the download request
 * no longer exists because the app has been restarted since then.
 *
 * It's an edge case for sure, but also one that may not be too difficult to handle.
 * This method, if implemented, allows you to handle this edge case.
 *
 * @note: This method is ONLY used on iOS. It will never be invoked on macOS.
 * @note: This method is never invoked for failed downloads - only successful downloads
 *        where there's actual data your app may be interested in.
 *
 * @param node
 *   The node for which the data download was requested.
 *
 * @param path
 *   The filesystem path of the node.
 *
 * @param cryptoFile
 *   The cryptoFile provides everything you need to read an encrypted file.
 */
- (void)didBackgroundDownloadNodeData:(ZDCNode *)node
                               atPath:(ZDCTreesystemPath *)path
                       withCryptoFile:(ZDCCryptoFile *)cryptoFile;
#endif
#pragma mark Optimizations

/**
 * The PullManager automatically downloads the tree hierarchy, sans data.
 * That is, it downloads the node filesystem metadata (filename & permissions),
 * but it doesn't download the node data (e.g. serialized objects, files, etc).
 *
 * This is typically very fast, because the tree hierarchy information is small,
 * and can be downloaded & decrypted very quickly. However, there are situations
 * in which this can appear slow. In particular:
 *
 * - the user just logged into your app, AND
 * - the user has thousands of nodes in the cloud, AND
 * - the user is trying to access a particular branch of the tree right NOW
 *
 * And this optimization is designed for this use case.
 * It allows you to influence the priority in which the PullManager downloads nodes.
 *
 * By default the PullManager uses the following simple algorithm:
 *   - prefer nodes that are more shallow
 *   - if nodes have the same depth, prefer nodes that were modified more recently
 *
 * For example, the node '/foo/bar' is preferred over '/cow/moo/milk'
 * because a depth of 2 is less than a depth of 3.
 *
 * And if '/cow/moo/milk' was modified yesterday,
 * and '/dog/bark/leash' was modified 2 months ago,
 * then '/cow/moo/milk' will be given priority.
 *
 * This simple algorithm usually results in the best experience for most tree designs.
 * But app specific knowledge is always preferred.
 */
- (nullable NSSet<NSString *> *)preferredNodeIDsForPullingRcrds;

@end

NS_ASSUME_NONNULL_END
