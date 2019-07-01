/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import <YapDatabase/YapDatabaseCloudCoreTransaction.h>
#import <YapDatabase/YapCollectionKey.h>

#import "ZDCContainerNode.h"
#import "ZDCCloudLocator.h"
#import "ZDCCloudOperation.h"
#import "ZDCTreesystemPath.h"
#import "ZDCNode.h"
#import "ZDCUser.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * All errors returned from ZDCCloudTransaction will use an error code defined in this enumeration.
 */
typedef NS_ENUM(NSInteger, ZDCCloudErrorCode) {
	/**
	 * One of the parameters was invalid.
	 * The error description will tell you which parameter, and why it was invalid.
	 */
	ZDCCloudErrorCode_InvalidParameter = 1000,
	
	/**
	 * If you attempt to create a node from a path,
	 * all parents leading up to the last path component must already exist in the treesystem.
	 */
	ZDCCloudErrorCode_MissingParent,
	
	/**
	 * If you attempt to send a message to a user,
	 * the receiving user must exist in the database.
	 *
	 * (You can use the ZDCRemoteUserManager to create the user if needed.)
	 */
	ZDCCloudErrorCode_MissingReceiver,
	
	/**
	 * A conflict occurred.
	 * For example, you attempted to create a node at `/foo/bar`, but there's already a node at that path.
	 */
	ZDCCloudErrorCode_Conflict
};

/**
 * Bitmask for specifiying which "meta" components to download from the cloud.
 */
typedef NS_OPTIONS(NSUInteger, ZDCNodeComponents) {
	
	/** Bitmask flag that specifies the header should be downloaded. */
	ZDCNodeComponents_Header    = (1 << 0), // 00001
	
	/** Bitmask flag that specifies the metadata section should be downloaded (if present). */
	ZDCNodeComponents_Metadata  = (1 << 1), // 00010
	
	/** Bitmask flag that specifies the thumbnail section should be downloaded (if present). */
	ZDCNodeComponents_Thumbnail = (1 << 2), // 00100
	
	/** Bitmask flag that specifies the data section should be downloaded. */
	ZDCNodeComponents_Data      = (1 << 3), // 01000
	
	/** Bitmask flag that specifies all sections should be downloaded. */
	ZDCNodeComponents_All = (ZDCNodeComponents_Header    |
	                         ZDCNodeComponents_Metadata  |
	                         ZDCNodeComponents_Thumbnail |
	                         ZDCNodeComponents_Data      ) // 01111
};

/**
 * ZDCCloud is a YapDatabase extension.
 *
 * It manages the storage of the upload queue.
 * This allows your application to work offline.
 * Any changes that need to be pushed to the cloud will get stored in the database using
 * a lightweight operation object that encodes the minimum information necessary
 * to execute the operation at a later time.
 *
 * It extends YapDatabaseCloudCore, which we also developed,
 * and contributed to the open source community.
 */
@interface ZDCCloudTransaction : YapDatabaseCloudCoreTransaction

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Messaging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Messages are first uploaded into the sender's outbox,
 * and then copied server-side into the recipient's inbox.
 *
 * You supply the data for the message via `[ZeroDarkCloudDelegate dataForMessage:transaction:]`.
 * And you'll be informed of the message deliveries via `[ZeroDarkCloudDelegate didSendMessage:transaction:]`
 *
 * For more information about messaging, see the docs:
 * https://zerodarkcloud.readthedocs.io/en/latest/client/messaging/
 *
 * @param message
 *   A node that represents the message to send.
 *
 * @param userIDs
 *   A list of recipients that should receive the message. (userID == ZDCUser.uuid)
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
- (BOOL)sendMessage:(ZDCNode *)message
                 to:(NSArray<NSString*> *)userIDs
              error:(NSError *_Nullable *_Nullable)outError;

/**
 * A signal is a lightweight message. Signals are delivered into the inbox of the recipient,
 * but are NOT copied into the outbox of the sender. In other words, they are lightweight messages,
 * that don't cause additional overhead for the sender.
 *
 * You supply the data for the message via `[ZeroDarkCloudDelegate dataForMessage:transaction:]`.
 * And you'll be informed of the message deliveries via `[ZeroDarkCloudDelegate didSendMessage:transaction:]`
 * 
 * For more information about messaging, see the docs:
 * https://zerodarkcloud.readthedocs.io/en/latest/client/messaging/
 *
 * @param signal
 *   The message to send.
 *
 * @param recipient
 *   The user to send the message to. (userID == ZDCUser.uuid)
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
- (BOOL)sendSignal:(ZDCNode *)signal
                to:(ZDCUser *)recipient
             error:(NSError *_Nullable *_Nullable)outError;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the corresponding top-level container node.
 *
 * This method is short-hand for `[ZDCNodeManager containerNodeForLocalUserID:zAppID:container:transaction:]`
 */
- (nullable ZDCContainerNode *)containerNode:(ZDCTreesystemContainer)container;

/**
 * Returns the existing node with the given path.
 *
 * @note You can find many other utility functions for inspecting the node treesystem in the `ZDCNodeManager`.
 *
 * @param path
 *   The treesystem path of the node.
 *
 * @return Returns the matching node, if it exists. Nil otherwise.
 */
- (nullable ZDCNode *)nodeWithPath:(ZDCTreesystemPath *)path
 NS_SWIFT_NAME(nodeWithPath(_:));

/**
 * Creates a new node with the given path,
 * and queues upload operation(s) to push the node to the cloud.
 *
 * @param path
 *   The treesystem path of the node.
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return The newly created node.
 */
- (nullable ZDCNode *)createNodeWithPath:(ZDCTreesystemPath *)path
                                   error:(NSError *_Nullable *_Nullable)outError
 NS_SWIFT_NAME(createNode(withPath:));

/**
 * Inserts the given node into the treesystem (as configured),
 * and queues upload operation(s) to push the node to the cloud.
 *
 * @param node
 *   The node to insert into the treesystem.
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return True on succeess. False otherwise.
 */
- (BOOL)createNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError;

/**
 * Use this method to modify an existing node. For example, you can use it to:
 * - rename a node (i.e. you change node.name value)
 * - move a node (i.e. you change node.parentID value)
 * - change permissions (i.e. you modify node.shareList entries)
 *
 * If you didn't change the node metadata, but rather the node data (i.e. the data generated by your app),
 * then you should instead use the `queueDataUploadForNodeID::` method.
 *
 * @param node
 *   The node you want to modify.
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return YES if the modification was successful. NO otherwise (in which case, outError will be set).
 */
- (BOOL)modifyNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError;

/**
 * Use this method to queue a data upload operation for the given node.
 *
 * That is, you've modified the underlying data for a node.
 * Now you want the changed data (generated by your app) to be pushed to the cloud.
 * However, the node metadata hasn't changed (name, permissions, etc),
 * so there's no need to use the `modifyNode::` method.
 *
 * Invoking this method will create an return an operation to push the changes to the cloud.
 *
 * @param nodeID
 *   The node for which the data has changed. (nodeID == ZDCNode.uuid)
 *
 * @param changeset
 *   An optional changeset to store within the operation.
 */
- (nullable ZDCCloudOperation *)queueDataUploadForNodeID:(NSString *)nodeID
                                           withChangeset:(nullable NSDictionary *)changeset;

/**
 * Removes the given node from the treesystem, and enqueues a delete operation to delete it from the cloud.
 *
 * @param node
 *   The node you want to delete.
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return YES if the modification was successful. NO otherwise (in which case, outError will be set).
 */
- (BOOL)deleteNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError;

/**
 * Removes the given node from the treesystem, and enqueues a delete operation to delete it from the cloud.
 *
 * @param node
 *   The node which you wish to delete.
 *
 * @param options
 *   A bitmask that specifies the options to use when deleting the node.
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return YES if the modification was successful. NO otherwise (in which case, outError will be set).
 */
- (BOOL)deleteNode:(ZDCNode *)node
       withOptions:(ZDCDeleteNodeOptions)options
             error:(NSError *_Nullable *_Nullable)outError;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Linking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Call this method to link an object in the database to an existing node.
 *
 * The node should already exist in the database.
 * (If you just created the node, use `createNode:shouldUpload:operations:` to add it to the database.)
 * The node should not already be linked to a different collection/key tuple.
 *
 * @note You can link a {collection, key} tuple that doesn't yet exist in the database.
 *       However, you must add the corresponding object to the database before the
 *       transaction completes, or the linkage will be dropped.
 *
 * @param nodeID
 *   The node that you'd like to link. (nodeID == ZDCNode.uuid)
 *
 * @param key
 *   The key component of the {collection, key} tuple of your own object
 *   that you wish to link to the node.
 *
 * @param collection
 *   The collection component of the {collection, key} tuple of your own object
 *   that you wish to link to the node.
 *
 * @param outError
 *   Set to nil on success.
 *   Otherwise returns an error that explains what went wrong.
 *
 * @return Returns YES if successful, NO otherwise (and sets outError parameter if given).
 */
- (BOOL)linkNodeID:(NSString *)nodeID
             toKey:(NSString *)key
      inCollection:(nullable NSString *)collection
             error:(NSError *_Nullable *_Nullable)outError;

/**
 * If an object in the database has been linked to a node,
 * then deleting that object from the database implicitly
 * creates an operation to delete the node from the cloud.
 *
 * However, this may not always be the desired outcome.
 * Sometimes a device wishes to delete an object simply because it's no longer needed locally.
 * For example, if the object was cached, and the system is clearing unneeded items from the cache.
 * In this case, simply unlink the node manually, and pass `shouldUpload` as NO.
 * This effectively removes the link without modifying the cloud.
 *
 * Alternatively, you may wish to delete a node from the cloud, but keep the local copy.
 * In this case, just use `deleteNode:shouldUpload:operations:`,
 *
 * @param key
 *   The key component of the {collection, key} tuple of your own object
 *   that you wish to link to the node.
 *
 * @param collection
 *   The collection component of the {collection, key} tuple of your own object
 *   that you wish to link to the node.
 *
 * @return If the collection/key tuple was linked to a node, returns the nodeID (after unlinking).
 */
- (nullable NSString *)unlinkKey:(NSString *)key inCollection:(nullable NSString *)collection;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Linked Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * If the given collection/key tuple is linked to a node, this method returns the linked nodeID.
 * (nodeID == ZDCNode.uuid)
 */
- (nullable NSString *)linkedNodeIDForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * If the given collection/key tuple is linked to a node, this method returns the linked node.
 *
 * This is the same as `linkedNodeIDForKey:inCollection:`,
 * but it also fetches the corresponding ZDCNode from the database for you.
 */
- (nullable ZDCNode *)linkedNodeForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Returns whether or not the node is currently linked to a {collection, key} tuple.
 *
 * @param nodeID
 *   The node for which to look for a link. (nodeID == ZDCNode.uuid)
 */
- (BOOL)isNodeLinked:(NSString *)nodeID;

/**
 * If the given node is linked to a collection/key tuple, this method returns the linked tuple information.
 *
 * @param key
 *   Returns the key component of the collection/key tuple (if found).
 *
 * @param collection
 *   Returns the collection component of the collection/key tuple (if found).
 *
 * @param nodeID
 *   The node for which to look for a link. (nodeID == ZDCNode.uuid)
 *
 * @return YES if the node is linked to an item in the database. No otherwise.
 */
- (BOOL)getLinkedKey:(NSString *_Nullable *_Nullable)key
          collection:(NSString *_Nullable *_Nullable)collection
           forNodeID:(NSString *)nodeID NS_REFINED_FOR_SWIFT;

/**
 * Combines several API's to return the linked object for a given nodeID.
 *
 * In particular, this method invokes `getLinkedKey:collection:forNodeID:` first.
 * And if that method returns a {collection, key} tuple,
 * then the corresponding object is fetched from the database.
 *
 * @param nodeID
 *   The node for which to look for a link. (nodeID == ZDCNode.uuid)
 *
 * @return If the node is linked to a {collection, key} tuple,
 *         then returns the result of querying the database for the object with the matching tuple.
 *         Otherwise returns nil.
 */
- (nullable id)linkedObjectForNodeID:(NSString *)nodeID;

/**
 * Combines several methods to return the linked object for a given treesystem path.
 *
 * In particular, this method invokes `-[ZDCNodeManager findNodeWithPath:localUserID:zAppID:transaction:]` first.
 * And if that method returns a node, then the `linkedObjectForNodeID:` method is utilized.
 *
 * @param path
 *   The treesystem path of the node.
 * 
 * @return If the corresponding node is linked to a {collection, key} tuple,
 *         then returns the result of querying the database for the object with the matching tuple.
 *         Otherwise returns nil.
 */
- (nullable id)linkedObjectForPath:(ZDCTreesystemPath *)path;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Download Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * When the ZeroDarkCloudDelegate is informed of a new/modified node, it may need to download the node's data.
 * However, the download may or may not succeed. And if the download fails,
 * then the delegate will likely want to retry the download later (i.e. when Internet connectivity is restored).
 *
 * This means the delegate will need to keep track of which nodes need to be downloaded.
 * This method is designed to assist in keeping track of that list.
 *
 * @param nodeID
 *   The node needing to be downloaded. (nodeID == ZDCNode.uuid)
 *
 * @param components
 *   Typically you pass ZDCNodeComponents_All to specify that all components of a node are out-of-date.
 *   However, you can customize this in advanced situations.
 */
- (void)markNodeAsNeedsDownload:(NSString *)nodeID components:(ZDCNodeComponents)components
 NS_SWIFT_NAME(markNodeAsNeedsDownload(_:components:));

/**
 * After a download succeeds, invoke this method to remove the flag.
 *
 * @param nodeID
 *   The node you successfully downloaded. (nodeID == ZDCNode.uuid)
 *
 * @param components
 *   Pass ZDCNodeComponents_All to specify that all components are now up-to-date.
 *   However, if you only downloaded one component, such as the thumbnail, then just specify that component.
 *
 * @param eTag
 *   If you pass a non-nil eTag, then the flag will only be removed if ZDCNode.eTag_data matches the given eTag.
 *   You can get the eTag from the DownloadManager's completion block parameter, via `[ZDCCloudDataInfo eTag]`.
 */
- (void)unmarkNodeAsNeedsDownload:(NSString *)nodeID
                       components:(ZDCNodeComponents)components
                    ifETagMatches:(nullable NSString *)eTag
 NS_SWIFT_NAME(unmarkNodeAsNeedsDownload(_:components:ifETagMatches:));

/**
 * Returns YES/true if you've marked the node as needing to be downloaded.
 *
 * A bitwise comparison is performed between the currently marked components, and the passed components parameter.
 * YES is returned if ANY of the components (flags, bits) are currented marked as needing download.
 *
 * @param nodeID
 *   The node in question. (nodeID == ZDCNode.uuid)
 *
 * @param components
 *   The component(s) in question.
 */
- (BOOL)nodeIsMarkedAsNeedsDownload:(NSString *)nodeID components:(ZDCNodeComponents)components
 NS_SWIFT_NAME(nodeIsMarkedAsNeedsDownload(_:components:));;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * When you create, modify or delete a node, the system creates and queues operations
 * to push these changes to the cloud. The operations are stored safely in the database,
 * and are executed by the PushManager.
 *
 * Occassionally you may want to tweak an operation's dependencies or priority.
 * You can do that at any time using the underlying functions exposed by YapDatabaseCloudCore.
 *
 * However, the most common use case is to tweak these within the same database commit
 * in which you created the operation(s). This method returns the operations that were
 * added to the queue in THIS transaction.
 *
 * @param nodeID
 *   The node whose operations you're looking for. (nodeID == ZDCNode.uuid)
 */
- (NSArray<ZDCCloudOperation*> *)addedOperationsForNodeID:(NSString *)nodeID;

/**
 * Returns YES if there pending uploads for the given nodeID.
 * This information may be useful in determining why your data is out-of-sync with the cloud.
 */
- (BOOL)hasPendingDataUploadsForNodeID:(NSString *)nodeID;

/**
 * Enumerates all the operations in the queue,
 * and returns an array of values extracted from ZDCCloudOperation.changeset.
 *
 * If you're using the ZDCSyncable protocol, this is what you'll need to perform a merge.
 *
 * @param nodeID
 *   The node whose operations you're looking for. (nodeID == ZDCNode.uuid)
 */
- (NSArray<NSDictionary*> *)pendingChangesetsForNodeID:(NSString *)nodeID;

/**
 * Invoke this method after you've downloaded and processed the latest version of a node's data.
 *
 * This informs the system that your data is now up-to-date with the given version/eTag.
 * In particular, this tells the system to update all queued ZDCCloudOperation.eTag values.
 *
 * This method is one of the ways in which you can resolve a conflict.
 *
 * @see [ZeroDarkCloudDelegate didDiscoverConflict:forNode:atPath:transaction:]
 */
- (void)didMergeDataWithETag:(NSString *)eTag forNodeID:(NSString *)nodeID;

/**
 * Invoke this method if you've been notified of a conflict, and you've decided to let the cloud version "win".
 * In other words, you've decided not to overwrite the cloud version with the local version.
 *
 * This method is one of the ways in which you can resolve a conflict.
 *
 * @see [ZeroDarkCloudDelegate didDiscoverConflict:forNode:atPath:transaction:]
 */
- (void)skipDataUploadsForNodeID:(NSString *)nodeID;

@end

NS_ASSUME_NONNULL_END
