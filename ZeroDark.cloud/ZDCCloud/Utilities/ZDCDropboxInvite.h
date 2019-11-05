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
 * A "dropbox invite" encompasses the information required for another user to write into your treesystem.
 *
 * Imagine that Alice has a node in her treesystem at: /foo/bar/filesFromFriends
 *
 * She wants to setup the node as a dropbox for Bob:
 * That is:
 * - Bob should be allowed to write files into this directory
 * - But Bob doesn't have permission to read the files in this directory
 * - And Bob doesn't have permission to delete files from this directory
 *
 * Alice can accomplish this by:
 * - giving Bob write permission on the node
 * - sending Bob a "dropbox invite" for the node
 *
 * What's nice about this system is that Bob doesn't see the parentNode.
 * That is, Bob cannot discover the location of "/foo/bar/filesFromFriends".
 * So he wouldn't be able to determine, for example, who else Alice has given Dropbox permission to.
 *
 * Further, since Bob doesn't have read permission, he won't be able to see the other children of the node.
 * So he also won't be able to determine which other friends have sent Alice files.
 */
@interface ZDCDropboxInvite : NSObject <NSCopying>

/**
 * Standard initializer.
 */
- (instancetype)initWithTreeID:(NSString *)treeID dirPrefix:(NSString *)dirPrefix;

/**
 * Represents a component of a ZDCCloudPath (#1 of 3)
 *
 * @see `ZDCCloudPath`
 */
@property (nonatomic, copy, readonly) NSString *treeID;

/**
 * Represents a component of a ZDCCloudPath (#2 of 3)
 *
 * @see `ZDCCloudPath`
 */
@property (nonatomic, copy, readonly) NSString *dirPrefix;

@end

NS_ASSUME_NONNULL_END
