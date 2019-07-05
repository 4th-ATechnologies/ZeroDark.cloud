/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The treesystem has several different containers at the root level.
 *
 * For more information about the ZeroDark.cloud treesystem, check out the docs:
 * - https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
 */
typedef NS_ENUM(NSInteger, ZDCTreesystemContainer) {
	
	/** The 'Home' container is where your app stores the majority of its data. */
	ZDCTreesystemContainer_Home,
	
	/** A simple container designed for storing (synced) user preferences. */
	ZDCTreesystemContainer_Prefs,
	
	/**
	 * A special container for incoming messages.
	 * See the [docs](https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/) for more information.
	 */
	ZDCTreesystemContainer_Inbox,
	
	/**
	 * A special container for outgoing messages.
	 * See the [docs](https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/) for more information.
	 */
	ZDCTreesystemContainer_Outbox,
	
	/** Special value used to indicate an invalid container. Don't use this value. */
	ZDCTreesystemContainer_Invalid = NSIntegerMax,
};

/** Converts from enum value to string. */
extern NSString* NSStringFromTreesystemContainer(ZDCTreesystemContainer);

/** Converts from string to enum value. */
extern ZDCTreesystemContainer TreesystemContainerFromString(NSString*);

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
 * Creates a path with the given components in the given container.
 *
 * For example, if the string based representation of the path is "/foo/bar",
 * then you'd pass in ["foo", "bar"].
 *
 * @param pathComponents
 *   The ordered list of pathComponents, with the destination node being the last item in the array.
 *
 * @param container
 *   The specific container for the node.
 *   For most nodes, this is the home container (ZDCTreesystemContainer_Home).
 */
- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents
                             container:(ZDCTreesystemContainer)container;

/**
 * The "container" the path is rooted within.
 * Typically this is "home", which means the primary filesystem for the user/app.
 */
@property (nonatomic, assign, readonly) ZDCTreesystemContainer container;

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
 * Returns YES if the path represents the root of the container.
 * That is, the pathComponents array is empty.
 */
@property (nonatomic, readonly) BOOL isContainerRoot;

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
 * If the pathComponents array is empty, returns nil.
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
