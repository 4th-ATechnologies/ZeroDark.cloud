/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCNode.h"
#import "ZDCTreesystemPath.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZeroDark.cloud framework provides a treesystem in the cloud.
 *
 * It's important to understand: Treesystem != Filesystem
 *
 * A traditional filesystem has directories & files.
 * This design forces all content to reside in the leaves.
 * That is, if you think about a traditional filesystem as a tree,
 * you can see that all files are leaves, and all non-leaves are directories.
 *
 * In contrast, the ZeroDark.cloud treesystem acts as a generic tree,
 * where each item in the tree is simply called a "node".
 * A node can be whatever you want it to be - an object, a file, a container, etc.
 * Additionally, ALL nodes are allowed to have children.
 * (e.g. a node representing an object/file can have children).
 *
 * For more information about the treesystem, see the docs:
 * https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
 *
 * Every user gets their own treesystem. And within each treesystem are top-level root nodes called "trunks".
 * All user-generated treesystem nodes will be rooted in one of these trunks.
 *
 * A ZDCTrunkNode represents one of these top-level trunk nodes.
 * ZDCTrunkNode instances are automatically added to the database when a localUser is created.
 */
@interface ZDCTrunkNode : ZDCNode <NSCoding, NSCopying>

/**
 * Returns the database key that can be used to fetch the trunkNode instance from the database.
 * (Use kZDCCollection_Nodes as the database collection.)
 *
 * @note Normal ZDCNode instances have a random uuid.
 *       That is, the uuid is specific to the local device, and cannot be derived from the cloud version of the node.
 *       ZDCTrunkNode's are a little different, as they represent the "virtual" nodes in the server.
 *       That is, hard-coded "root" nodes that don't actually exist on the server.
 */
+ (NSString *)uuidForLocalUserID:(NSString *)localUserID
                          zAppID:(NSString *)zAppID
                           trunk:(ZDCTreesystemTrunk)trunk;

/**
 * The zAppID container for the treesystem.
 */
@property (nonatomic, copy, readonly) NSString *zAppID;

/**
 * The trunk (top-level root node). E.g. "home", "prefs", "inbox", "outbox".
 */
@property (nonatomic, assign, readonly) ZDCTreesystemTrunk trunk;

@end

NS_ASSUME_NONNULL_END
