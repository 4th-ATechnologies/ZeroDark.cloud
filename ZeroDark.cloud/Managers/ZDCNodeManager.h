#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCConstants.h"
#import "AWSRegions.h"
#import "ZDCCloud.h"
#import "ZDCCloudRcrd.h"
#import "ZDCNode.h"
#import "ZDCPublicKey.h"
#import "ZDCTreesystemPath.h"
#import "ZDCTrunkNode.h"
#import "ZDCUser.h"


NS_ASSUME_NONNULL_BEGIN

/**
 * Provides various methods for inspecting the node treesystem.
 */
@interface ZDCNodeManager : NSObject

/**
 * Returns the singleton instance.
 */
+ (instancetype)sharedInstance;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Trunks & Anchors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a specific trunk (top-level root node).
 * This method only returns nil if you pass an invalid parameter.
 *
 * @param localUserID
 *   The localUser for which you're interested (localUserID == ZDCLocalUser.uuid)
 *
 * @param zAppID
 *   The zAppID you registered in the ZeroDark.cloud dashboard.
 *   This is the same zAppID you passed when you created a ZeroDarkCloud instance.
 *
 * @param trunk
 *   The trunk you're looking for.
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 */
- (nullable ZDCTrunkNode *)trunkNodeForLocalUserID:(NSString *)localUserID
                                            zAppID:(NSString *)zAppID
                                             trunk:(ZDCTreesystemTrunk)trunk
                                       transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * A "trunk node" is a top-level root node.
 * This method walks up the tree until it finds the corresponding trunk.
 *
 * @param node
 *   Find the trunk for this node.
 *   (The node doesn't need to be stored in the database for this method to work.
 *    But it will need to have a proper `-[ZDCNode parentID]` property set.)
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 */
- (nullable ZDCTrunkNode *)trunkNodeForNode:(ZDCNode *)node
                                transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * An "anchor node" is the nearest node in the hierarchy that
 * provides a location anchor (e.g. an AWS region & bucket).
 *
 * This could be the trunkNode (a ZDCTrunkNode instance), meaning the user's own region & bucket.
 * Or it could be another node with a non-nil anchor property, meaning some other user's region & bucket.
 *
 * The anchorNode is found by traversing up the node hierarchy towards the trunkNode,
 * and searching for a node with anchor information.
 * If not found, the trunkNode is returned.
 */
- (ZDCNode *)anchorNodeForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns the owner of a given node.
 *
 * This is done by traversing the node hierarchy, up to the root,
 * searching for a node with an explicit ownerID property. If not found, the localUserID is returned.
 */
- (NSString *)ownerIDForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Invokes `ownerIDForNode:transaction:`, and then uses the result to fetch the corresponding ZDCUser.
 *
 * The ZDCUser instance may be nil if the system hasn't been able to download the user yet.
 */
- (nullable ZDCUser *)ownerForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Local Path
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns an array of all parent nodeID's of the given node, up to the containerNode.
 *
 * The containerNode will be at index 0,
 * and the immediate parentNodeID will be the last item in the array.
 *
 * @note The term nodeID is short for ZDCNode.uuid.
 *
 * @param node
 *   The node you're interested in.
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 */
- (NSArray<NSString *> *)parentNodeIDsForNode:(ZDCNode *)node
                                  transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns the path to the given node.
 *
 * @param node
 *   The node you're interested in.
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 */
- (nullable ZDCTreesystemPath *)pathForNode:(ZDCNode *)node
                                transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Walks the tree from nodeID up to the root,
 * and checks to see if potentialParentID is indeed in its hierarchy.
 *
 * @note The term nodeID is short for ZDCNode.uuid.
 */
- (BOOL)isNode:(NSString *)nodeID
 aDescendantOf:(NSString *)potentialParentID
   transaction:(YapDatabaseReadTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate Nodes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Enumerates all ZDCNode.uuid's whose parentID property matches the given parentID.
 * 
 * This method is slightly faster than enumerating the ZDCNode objects,
 * as it can skip fetching the objects from the database.
 * 
 * This only includes the direct children of the given parent.
 * Further ancestors (grandchildren, etc) are NOT enumerated.
 * If you want a deep recursion (including grandchildren, etc),
 * then use `recursiveEnumerateNodeIDsWithParentID:transaction:usingBlock:`.
 */
- (void)enumerateNodeIDsWithParentID:(NSString *)parentID
                         transaction:(YapDatabaseReadTransaction *)transaction
                          usingBlock:(void (^)(NSString *nodeID, BOOL *stop))enumBlock;

/**
 * Enumerates all ZDCNode.uuid's who are ancestors of the given parentID.
 * This includes direct children, as well as further ancestors (grandchildren, etc).
 *
 * The recursion process is performed using a depth first algorithm,
 * and the path to each nodeID is provided via the enumBlock.
 *
 * The `pathFromParent` array does not contain the parentID, nor the nodeID parameter.
 * It only contains all nodeIDs between the parentID & the nodeID.
 * Thus, direct children of the parentID will have an empty pathFromParent array.
 * The array is ordered such that the node closest to the parent is at index zero.
 *
 * @warning The `pathFromParent` array is mutable, and gets changed between each invocation of the block.
 *          So if you need to store it outside the block context, you'll need to make a copy.
 *
 * The `recurseInto` parameter can be set to NO
 * for any node's for which you aren't interested in the children/descendents.
 *
 * @note This method is slightly faster than enumerating the ZDCNode objects,
 *       as it can skip fetching the objects from the database.
 *
 * @param parentID
 *   The node for which you wish to enumerate the children & ancestors.
 *   (parentID == nodeID_of_parent == ZDCNode.uuid)
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 *
 * @param enumBlock
 *   The block to invoke for each encountered nodeID during the recursive process.
 */
- (void)recursiveEnumerateNodeIDsWithParentID:(NSString *)parentID
                                  transaction:(YapDatabaseReadTransaction *)transaction
                                   usingBlock:(void (^)(NSString *nodeID,
                                                        NSArray<NSString*> *pathFromParent,
																		  BOOL *recurseInto,
                                                        BOOL *stop))enumBlock;

/**
 * Enumerates all ZDCNode's whose parentID property matches the given parentID.
 * 
 * This only includes the direct children of the given parent.
 * Further ancestors (grandchildren, etc) are NOT enumerated.
 * If you want a deep recursion (including grandchildren, etc),
 * then use `recursiveEnumerateNodesWithParentID:transaction:usingBlock:`.
 */
- (void)enumerateNodesWithParentID:(NSString *)parentID
                       transaction:(YapDatabaseReadTransaction *)transaction
                        usingBlock:(void (^)(ZDCNode *node, BOOL *stop))enumBlock;

/**
 * Enumerates all ZDCNodes's who are ancestors of the given parentID.
 * This includes direct children, as well as further ancestors (grandchildren, etc).
 *
 * The recursion process is performed using a depth first algorithm,
 * and the path to each nodeID is provided via the enumBlock.
 *
 * The `pathFromParent` array is does not contain the parent, nor the node parameter.
 * It only contains all nodes between the parent & the node.
 * Thus, direct children of the parent will have an empty pathFromParent array.
 * The array is ordered such that the node closest to the parent is at index zero.
 *
 * @warning The `pathFromParent` array is mutable, and gets changed between each invocation of the block.
 *          So if you need to store it outside the block context, you'll need to make a copy.
 *
 * The `recurseInto` parameter can be set to NO
 * for any node's for which you aren't interested in the children/descendents.
 *
 * @param parentID
 *   The node for which you wish to enumerate the children & ancestors.
 *   (parentID == nodeID_of_parent == ZDCNode.uuid)
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 *
 * @param enumBlock
 *   The block to invoke for each encountered node during the recursive process.
 */
- (void)recursiveEnumerateNodesWithParentID:(NSString *)parentID
                                transaction:(YapDatabaseReadTransaction *)transaction
                                 usingBlock:(void (^)(ZDCNode *node,
                                                      NSArray<ZDCNode*> *pathFromParent,
                                                      BOOL *recurseInto,
                                                      BOOL *stop))enumBlock;

/**
 * Returns whether or not the node has any children.
**/
- (BOOL)isEmptyNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Find Nodes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Finds the node with the given name, if it exists, and returns it.
 *
 * In most cases this lookup is performed in O(log n),
 * where `n` is number of ZDCNode's where node.parentID == parentID.
 * 
 * @param name
 *   The ZDCNode.name to find. (i.e. the cleartext name, such as "Inventory.numbers")
 *   The name comparison is both case-insensitive & localized. (So in German: daß == dass)
 *
 * @param parentID
 *   A reference to the parent node. (parentID == nodeID == ZDCNode.uuid)
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 * 
 * @return The matching ZDCNode, or nil if it doesn't exist.
 */
- (nullable ZDCNode *)findNodeWithName:(NSString *)name
                              parentID:(NSString *)parentID
                           transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Finds the node with the given path components.
 * 
 * @param path
 *   The path of the node, such as "/Documents/Inventory.numbers".
 * 
 * @param localUserID
 *   This is the associated user account identifier. (localUserID == ZDCLocalUser.uuid)
 *
 * @param zAppID
 *   The zerodark.cloud app identifier.
 *   All nodes are segregated by zAppID, and then into their respective containers.
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 * 
 * @return The matching ZDCNode, or nil if it doesn't exist.
 */
- (nullable ZDCNode *)findNodeWithPath:(ZDCTreesystemPath *)path
                           localUserID:(NSString *)localUserID
                                zAppID:(NSString *)zAppID
                           transaction:(YapDatabaseReadTransaction *)transaction
NS_SWIFT_NAME(findNode(withPath:localUserID:zAppID:transaction:));

/**
 * Finds the node with the given cloudName.
 * This method is primarily for use by the PullManager.
 *
 * @note
 *   A cloudName is a hash of the cleartext name, combined with the parent diretory's salt.
 *   That is, a cloudName prevents the cleartext name from being revealed to the server.
 *   You can get the cloudName for any node via the various methods in `ZDCCloudPathManager`.
 *
 * @param cloudName
 *   The cloudName of the node to find. (e.g. "58fidhxeyyfzgp73hgefpr956jaxa6xs")
 *
 * @param parentID
 *   The parentID of the node. (parentID == ZDCNode.parentID == parentNode.uuid)
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 *
 * @return The matching ZDCNode, or nil if it doesn't exist.
 */
- (nullable ZDCNode *)findNodeWithCloudName:(NSString *)cloudName
                                   parentID:(NSString *)parentID
                                transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Finds the node with the given cloudID & localUserID.
 * This method is primarily for use by the PullManager.
 *
 * A SecondaryIndex in the database is utilized to make this a very fast lookup.
 *
 * @note
 *   Since nodes may be moved around (e.g. renamed or moved to different "directories"),
 *   the current location of the node in the cloud may not match the local path.
 *   However, the cloudID is immutable (set by the server, and cannot be changed),
 *   and is thus the most reliable way to lookup a matching node given the cloud version.
 *
 * @param cloudID
 *   The server-assigned identifier for the node.
 *   This value is immutable - the server doesn't allow it to be changed.
 *
 * @param localUserID
 *   This is the associated user account identifier. (localUserID == ZDCLocalUser.uuid)
 *
 * @param zAppID
 *   The zerodark.cloud app identifier.
 *   All nodes are segregated by zAppID, and then into their respective containers.
 *
 * @param transaction
 *   A database transaction - allows the method to read from the database.
 *
 * @return The matching ZDCNode, or nil if it doesn't exist.
 */
- (nullable ZDCNode *)findNodeWithCloudID:(NSString *)cloudID
                              localUserID:(NSString *)localUserID
                                   zAppID:(NSString *)zAppID
                              transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Locates the node using only the cloud path information.
 * This method is primarily for use by the PullManager.
 *
 * @return The matching ZDCNode, or nil if it doesn't exist.
 */
- (nullable ZDCNode *)findNodeWithCloudPath:(ZDCCloudPath *)cloudPath
                                     bucket:(NSString *)bucket
                                     region:(AWSRegion)region
                                localUserID:(NSString *)localUserID
                                     zAppID:(NSString *)zAppID
                                transaction:(YapDatabaseReadTransaction *)transaction
NS_SWIFT_NAME(findNode(withCloudPath:bucket:region:localUserID:zAppID:transaction:));

/**
 * Finds the node with a matching dirPrefix.
 *
 * A SecondaryIndex is utilized to make this a very fast lookup.
 */
- (nullable ZDCNode *)findNodeWithDirPrefix:(NSString *)prefix
                                     bucket:(NSString *)bucket
                                     region:(AWSRegion)region
                                localUserID:(NSString *)localUserID
                                     zAppID:(NSString *)zAppID
                                transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Finds the pointer node with the given pointeeID.
 */
- (nullable ZDCNode *)findNodeWithPointeeID:(NSString *)pointeeID
                                localUserID:(NSString *)localUserID
                                     zAppID:(NSString *)zAppID
                                transaction:(YapDatabaseReadTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Lists
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a list of all nodeID's belonging to the given user (regardless of zAppID).
 */
- (NSArray<NSString *> *)allNodeIDsWithLocalUserID:(NSString *)localUserID
                                       transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns a list of all nodeID's belonging to the given user.
 */
- (NSArray<NSString *> *)allNodeIDsWithLocalUserID:(NSString *)localUserID
                                            zAppID:(NSString *)zAppID
                                       transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns all ZDCNode.uuid's where ZDCNode.cloudID is non-nil.
 * That is, the node has been uploaded at least once.
 *
 * Important: uploaded once != fully synced right at this moment.
 * Rather it means that we expect it to be on the server.
 *
 * Note: This method has been optimized for performance, and is the recommended approach.
 */
- (NSArray<NSString *> *)allUploadedNodeIDsWithLocalUserID:(NSString *)localUserID
                                                    zAppID:(NSString *)zAppID
                                               transaction:(YapDatabaseReadTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Permissions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Updates the permissons for the node to match those of its parent.
 *
 * @param node
 *   The node to modify.
 *   The passed instance must not be immutable, as this method intends to modify node.shareList.
 *
 * @return YES on success. NO on failure (node is immutable, doesn't have parentID, etc)
 */
- (BOOL)resetPermissionsForNode:(ZDCNode *)node
                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Conflict Resolution
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method may be used to resolve a conflict that can occur when
 * two devices attempt to create a node with the same path.
 *
 * When this occurs, the system starts by asking the delegate to resolve the conflict.
 * If the delegate doesn't take appropriate action, the system will automatically resolve the conflict
 * by renaming the node.
 */
- (NSString *)resolveNamingConflictForNode:(ZDCNode *)node
                               transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
