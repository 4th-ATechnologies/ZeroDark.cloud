/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The treesystem has several different "trunks", which represent root-level nodes.
 * All of the nodes in your treesystem will be rooted in one of these trunks.
 *
 * For more information about the ZeroDark.cloud treesystem, check out the docs:
 * - https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
 */
typedef NS_ENUM(NSInteger, ZDCTreesystemTrunk) {
	
	/**
	 * The 'Home' trunk is where your app stores the majority of its data.
	 * If you don't specify a trunk when creating a path, it will default to 'Home'.
	 */
	ZDCTreesystemTrunk_Home,
	
	/**
	 * The 'Prefs' trunk is designed for storing (synced) user preferences.
	 * Unlike the home trunk, it doesn't allow nodes to be shared with other users.
	 */
	ZDCTreesystemTrunk_Prefs,
	
	/**
	 * The 'Inbox' trunk is where you receive incoming messages from other users.
	 * See the [docs](https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/) for more information.
	 */
	ZDCTreesystemTrunk_Inbox,
	
	/**
	 * The 'Outbox' trunk is for outgoing messages.
	 * Messages in your outbox get copied into other users' 'Inbox',
	 * and all of your devices see the ougoing message via your 'Outbox'.
	 */
	ZDCTreesystemTrunk_Outbox,
	
	/**
	 * A special value used for nodes that aren't attached to a local treesystem.
	 * Don't use this value - it's reserved for special nodes (e.g. signals)
	 */
	ZDCTreesystemTrunk_Detached = NSIntegerMax,
};

/** Converts from enum value to string. */
extern NSString* NSStringFromTreesystemTrunk(ZDCTreesystemTrunk);

/** Converts from string to enum value. */
extern ZDCTreesystemTrunk TreesystemTrunkFromString(NSString*);

/**
 * ZDCTreesystemPath is a standardized class for storing paths to nodes in the tree.
 *
 * For more information about the ZeroDark.cloud treesystem, check out the docs:
 * - https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
 */
@interface ZDCTreesystemPath : NSObject <NSCoding, NSCopying>

/**
 * Constructs a path from the given components in the home container.
 *
 * For example, if the string based representation of the path is "/foo/bar",
 * then you'd pass in ["foo", "bar"].
 *
 * @param pathComponents
 *   The ordered list of pathComponents, with the destination node being the last item in the array.
 */
- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents;

/**
 * Creates a path with the given components in the given trunk.
 *
 * For example, if the string based representation of the path is "/foo/bar",
 * then you'd pass in ["foo", "bar"].
 *
 * @param pathComponents
 *   The ordered list of pathComponents, with the destination node being the last item in the array.
 *
 * @param trunk
 *   The specific trunk for the node.
 *   For most nodes, this is the home trunk (ZDCTreesystemTrunk_Home).
 */
- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents trunk:(ZDCTreesystemTrunk)trunk;

/**
 * The trunk (top-level root node) in which the path is rooted.
 * Typically this is "home", which is the primary trunk for the user's data.
 */
@property (nonatomic, assign, readonly) ZDCTreesystemTrunk trunk;

/**
 * An array of node-names, leading from the container node to the target node.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *pathComponents;

/**
 * Returns the name of the target node.
 * In other words, this method returns the last item in the pathComponents array.
 */
@property (nonatomic, readonly) NSString *nodeName;

/**
 * Returns YES if the path represents the root node (i.e. the trunk itself).
 * That is, the pathComponents array is empty.
 */
@property (nonatomic, readonly) BOOL isTrunk;

/**
 * Returns the pathComponents, joined using the separator '/'.
 * For example: "/foo/bar/buzz"
 *
 * The path is relative to it's container, which is not specified in the string.
 *
 * @note This method is a convenience method primarily intended for debugging.
 *       You are discouraged from treating paths as strings
 *       because names are allowed to contain any character,
 *       which includes the traditional separator '/'.
 *       This method does nothing to protect against this possibility.
 */
- (NSString *)relativePath;

/**
 * Returns the container, plus the relativePath.
 * For example: "home:/foo/bar/buzz"
 *
 * @note This method is a convenience method primarily intended for debugging.
 *       You are discouraged from treating paths as strings
 *       because names are allowed to contain any character,
 *       which includes the traditional separator '/'.
 *       This method does nothing to protect against this possibility.
 */
- (NSString *)fullPath;

/**
 * Returns the parent's path by removing the last item from the pathComponents array.
 * If the pathComponents array is empty (i.e. isTrunk == true), then this method returns nil.
 *
 * This method does not modify the receiver.
 */
- (nullable ZDCTreesystemPath *)parentPath;

/**
 * Returns a new path instance with the given component appended to the end.
 */
- (ZDCTreesystemPath *)pathByAppendingComponent:(NSString *)pathComponent;

@end

NS_ASSUME_NONNULL_END
