/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseCloudCoreOperation.h>

#import "ZDCCloudLocator.h"
#import "ZDCCloudPath.h"

/**
 * The type of operation to be performed.
 */
typedef NS_ENUM(NSUInteger, ZDCCloudOperationType) {
	
	/** Represents an invalid type (generally used for errors) */
	ZDCCloudOperationType_Invalid = 0,
	
	/**
	 * Represents a 'put' operation, meaning a node is being uploaded to the cloud.
	 * This could be either a new node, or modifying an existing node.
	 */
	ZDCCloudOperationType_Put,
	
	/** Represents a 'move' operation, meaning a node is being moved from one location to another. */
	ZDCCloudOperationType_Move,
	
	/** Represents a 'delete' operation, where the node being deleted is a leaf (no children). */
	ZDCCloudOperationType_DeleteLeaf,
	
	/** Represents a 'delete' operation, where it's assumed the node might have children (not a leaf). */
	ZDCCloudOperationType_DeleteNode,
	
	/**
	 * Represents a 'copy' operation.
	 * The server is only capable of copying one file at a time.
	 * The copy may cross regions. (e.g. from Oregon to Ireland)
	 */
	ZDCCloudOperationType_CopyLeaf,
	
	/**
	 * Represents an update of the user's avatar.
	 * This is only for non-social identities.
	 */
	ZDCCloudOperationType_Avatar
};

/**
 * If the type is 'put', this specifies the type of the put operation.
 * That is, the type of node being uploaded to the cloud.
 */
typedef NS_ENUM(NSUInteger, ZDCCloudOperationPutType) {
	
	/** Represents an invalid put-type (generally used for errors) */
	ZDCCloudOperationPutType_Invalid = 0,
	
	/**
	 * Represents a put of the "*.rcrd" file for a node in the treesystem.
	 * The RCRD file contains only the filesystem metadata, which includes info such as:
	 * - permissions
	 * - filename (encrypted)
	 * - cloudID (server-assigned uuid, used to track a node during moves)
	 *
	 * The actual node data is NOT stored in the RCRD. (It's stored in the DATA fork.)
	 */
	ZDCCloudOperationPutType_Node_Rcrd,
	
	/**
	 * Represents the put of the "*.data" file for a node in the treesystem.
	 * The DATA file represents the actual content of the node.
	 * That is, the content delivered to the framework via:
	 * - `-[ZeroDarkCloudDelegate dataForNode:atPath:transaction:]`
	 * - `-[ZeroDarkCloudDelegate metadataForNode:atPath:transaction:]`
	 * - `-[ZeroDarkCloudDelegate thumbnailForNode:atPath:transaction:]`
	 *
	 * The data is automatically encrypted before being uploaded to the cloud.
	 */
	ZDCCloudOperationPutType_Node_Data,
	
	/**
	 * Represents a put of a special "*.rcrd" file, which contains a pointer to another node.
	 * The pointer information gets encrypted (not readable by the server).
	 */
	ZDCCloudOperationPutType_Pointer,
	
	/**
	 * Represents a put of the "*.rcrd" file for a message in another user's 'msgs' container.
	 * The RCRD file contains only the metadata, which includes info such as:
	 * - permissions
	 * - cloudID (server-assigned uuid)
	 */
	ZDCCloudOperationPutType_Message_Rcrd,
	
	/**
	 * Represents a put of the "*.data" file for a message in another user's 'msgs' container.
	 * The DATA file represents the actual content of the message.
	 * That is, the content delivered to the framework via:
	 * - `-[ZeroDarkCloudDelegate messageDataForUser:withMessageID:transaction:]`
	 *
	 * The data is automatically encrypted before being uploaded to the cloud.
	 */
	ZDCCloudOperationPutType_Message_Data
};

/**
 * When you queue an operation to delete a node in the cloud,
 * it's possible the state of the cloud may change between when you issued the delete request,
 * and when the request arrives at the server.
 *
 * These options specify how you'd like the server to handle the request, in the event it finds changes.
 */
typedef NS_OPTIONS(NSUInteger, ZDCDeleteNodeOptions) {
	
	/**
	 * This option indicates that "outdated" nodes should still be deleted.
	 * An "outdated" node is one which has been changed between when the request was created,
	 * and when the request arrived at the server.
	 *
	 * For example, the data has been modified, or the node has been renamed.
	 *
	 * This option specifies that you want outdated nodes to also be deleted.
	 * If this flag is NOT set, then outdated nodes will NOT be deleted.
	 * And, as such, the server will not delete any nodes in the hierarchy between the outdated node & the target node.
	 */
	ZDCDeleteOutdatedNodes = 1 << 0,
	
	/**
	 * This option indicates that "unknown" nodes should still be deleted.
	 * An "unknown" node is one which has been added between when the request was created,
	 * and when the request arrived at the server.
	 *
	 * For example, a child node (in one of the subdirectories, at any level) was added.
	 *
	 * This option specifies that you want unknown nodes to also be deleted.
	 * If this flag is NOT set, then unknown nodes will NOT be deleted.
	 * And, as such, the server will not delete any nodes in the hierarchy between the unknown node & the target node.
	 */
	ZDCDeleteUnknownNodes  = 1 << 1
};

NS_ASSUME_NONNULL_BEGIN

/**
 * ZDCCloudOperation is a lightweight representation of a push task that needs to be performed.
 *
 * It encodes the minimum information necessary to to execute the task at a later date,
 * possibly after an app re-launch.
 *
 * The operation objects get stored in the database as part of ZDCCloud,
 * which manages the operation objects in a semi-queue-like fashion.
 *
 * @note ZDCCloudOperation extends YapDatabaseCloudCoreOperation.
 *       (YapDatabaseCloudCore was also developed by us,
 *       which we contributed to the open source community.)
 *       The YapDatabaseCloudCoreOperation class is where you'll find the
 *       basic operation stuff, such as the uuid, dependencies, and priority.
 */
@interface ZDCCloudOperation : YapDatabaseCloudCoreOperation <NSCoding, NSCopying>

/**
 * Creates a new instance with the basics.
 * You'll need to fill out the remaining information based on the requirements for the particular type.
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             zAppID:(NSString *)zAppID
                               type:(ZDCCloudOperationType)type;

/**
 * Creates a new instance with the basics.
 * You'll need to fill out the remaining information based on the requirements for the particular putType.
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             zAppID:(NSString *)zAppID
                            putType:(ZDCCloudOperationPutType)putType;

/** The value specified during init. */
@property (nonatomic, copy, readonly) NSString *localUserID;

/** The value specified during init. */
@property (nonatomic, copy, readonly) NSString *zAppID;

/** Corresponds to the operation to be performed on the server. */
@property (nonatomic, assign, readwrite) ZDCCloudOperationType type;

/** For put operations, corresponds to the type of put operation being performed. */
@property (nonatomic, assign, readwrite) ZDCCloudOperationPutType putType;

/** Points to the corresponding node (nodeID == ZDCNode.uuid) */
@property (nonatomic, copy, readwrite, nullable) NSString *nodeID;

/** Points to the corresponding cloudNode (cloudNodeID == ZDCCloudNode.uuid) */
@property (nonatomic, copy, readwrite, nullable) NSString *cloudNodeID;

/** Points to the corresponding outgoing message (messageID == ZDCOutgoingMessage.uuid) */
@property (nonatomic, copy, readwrite, nullable) NSString *messageID;

/** The cloud location of the operation. */
@property (nonatomic, copy, readwrite, nullable) ZDCCloudLocator *cloudLocator;

/**
 * For move & copy operations, represents the target destination.
 * That is, the `cloudLocator` property represents the 'source' location,
 * and this property represents the 'destination' location.
 */
@property (nonatomic, copy, readwrite, nullable) ZDCCloudLocator *dstCloudLocator;

/**
 * The eTag is used for put-node-data operations.
 * It designates the currently know version of the data in the cloud.
 *
 * For example, imagine the current version of a node is 'A'.
 * If we queue an operation to update that node, then our operation will specify
 * that we expect the current versio of the node to be 'A'.
 * When the operation hits the cloud, that operation will succeed as long as the node is still at 'A'.
 * However, if the node has been updated by another device, we may discover it's actually at 'B' now.
 *
 * When this is the case, we will need to perform one of the following actions:
 *
 * - download the latest version of the node, and merge changes
 * - skip our queued put-node-data operations
 */
@property (nonatomic, copy, readwrite, nullable) NSString *eTag;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delete Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * An 'orphaned' node is where a RCRD file exists on the server, however there's no corresponding DATA file.
 * This may occur if a client is taken offline between uploading the RCRD and DATA files.
 *
 * If a node remains orphaned for an extended period of time,
 * other clients may automatically ask the server to delete the node.
 * When they perform this request, they send a special 'if-orphan' flag
 * to the server to clarify the intent of the delete operation.
 */
@property (nonatomic, assign, readwrite) BOOL ifOrphan;

/**
 * A serialized version of the JSON request that's sent during a delete-node operation.
 */
@property (nonatomic, copy, readwrite, nullable) NSData *deleteNodeJSON;

/**
 * A list of cloudID's that are being deleted (for both delete-leaf & delete-node operations).
 */
@property (nonatomic, copy, readwrite, nullable) NSSet<NSString *> *deletedCloudIDs;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Avatar Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For ZDCCloudOperationType_Avatar.
 * Specifies the particular identity for which we're uploading the avatar.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *avatar_auth0ID;

/**
 * For ZDCCloudOperationType_Avatar.
 * Specifies the old eTag, representing the avatar we're replacing.
 * This can be nil if the particular identity doesn't have a current eTag.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *avatar_oldETag;

/**
 * For ZDCCloudOperationType_Avatar.
 * Specifies the new eTag, representing the avatar we're expecting to upload.
 * This can be nil if we're deleting the current avatar.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *avatar_newETag;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changesets
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used for RCRD operations when the permissions have changed.
 * Stores the changeset obtained via ZDCShareList.
 * Since ZDCShareList implements the ZDCSyncable protocol, this allows us to easily merge changes.
 */
@property (nonatomic, copy, readwrite, nullable) NSDictionary *changeset_permissions;

/**
 * Used for DATA operations.
 * This value is supplied by the framework user,
 * either via the ZDCNodeLink protocol, or the user can set it manually.
 *
 * It's recommended (but not required) that the ZDCSyncable protocol is used
 * to simplify the process of merging changes.
 */
@property (nonatomic, copy, readwrite, nullable) NSDictionary *changeset_obj;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns true if both the receiver and 'another' have the same target.
 * Two operations with the same target will result in the same operation being generated.
 */
- (BOOL)hasSameTarget:(ZDCCloudOperation *)another;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Convenience method: returns YES if:
 * - type == ZDCCloudOperationType_Put AND
 * - putType == ZDCCloudOperationPutType_Node_Rcrd
 */
- (BOOL)isPutNodeRcrdOperation;

/**
 * Convenience method: returns YES if:
 * - type == ZDCCloudOperationType_Put AND
 * - putType == ZDCCloudOperationPutType_Node_Data
 */
- (BOOL)isPutNodeDataOperation;

/**
 * Convenience method: returns YES if:
 * - type == ZDCCloudOperationType_Put AND
 * - putType == ZDCCloudOperationPutType_Pointer
 */
- (BOOL)isPutPointerOperation;

/**
 * Convenience method: returns YES if:
 * - type == ZDCCloudOperationType_Put AND
 * - putType == ZDCCloudOperationPutType_Message_Rcrd
 */
- (BOOL)isPutMessageRcrdOperation;

/**
 * Convenience method: returns YES if:
 * - type == ZDCCloudOperationType_Put AND
 * - putType == ZDCCloudOperationPutType_Message_Data
 */
- (BOOL)isPutMessageDataOperation;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Utility method: converts from enum to string.
 * Used during encoding/decoding to protect against the possibility of enum values changing over time.
 */
+ (NSString *)stringForType:(ZDCCloudOperationType)type;

/**
 * Utility method: converts from string to enum.
 * Used during encoding/decoding to protect against the possibility of enum values changing over time.
 */
+ (ZDCCloudOperationType)typeForString:(NSString *)string;

/**
 * Utility method: converts from enum to string.
 * Used during encoding/decoding to protect against the possibility of enum values changing over time.
 */
+ (NSString *)stringForPutType:(ZDCCloudOperationPutType)putType;

/**
 * Utility method: converts from string to enum.
 * Used during encoding/decoding to protect against the possibility of enum values changing over time.
 */
+ (ZDCCloudOperationPutType)putTypeForString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
