/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCSyncableObjC.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Permissions are represented as a string, where each character in the string has a special meaning.
 */
typedef NS_OPTIONS(unichar, ZDCSharePermission) {
	
	/**
	 * Read permission for the user.
	 * If a user has this flag, the server assumes the user knows how to decrypt the content,
	 * and will send push notifications to the user when the file is uploaded, modified or deleted.
	 *
	 * If the node has children, the read permission also means the user is allowed to list the children.
	 * By default, only the owner of a bucket is allowed to list items within that bucket.
	 * All other users must be given read permission for each node in which they're allowed to list the direct children.
	 */
	ZDCSharePermission_Read = 'r',

	/**
	 * Write permission for the user.
	 * If the user has this flag, they are are allowed to modify the content of the node.
	 * Keep in mind that this permission (by itself) does not allow the user to modify the
	 * permissions set of a node - only the content.
	 *
	 * If the node has children, the write permission also means the user is allowed to delete children.
	 */
	ZDCSharePermission_Write = 'w',

	/**
	 * The share permission means the user is allowed to modify the node's set of permissions.
	 * This means they can add someone to the list, remove someone, or even modify existing permissions.
	 * However, the bucket owner's permissions can never be modified.
	 * That is, if the node exists in Alice's bucket, and Bob has share permission on the node,
	 * Bob cannot remove Alice from the list of permissions, nor can he modify her permissions.
	 */
	ZDCSharePermission_Share = 's',

	/**
	 * All children of the node are restricted to RCRD files - DATA files are not allowed.
	 * Keep in mind that the server always restricts the size of RCRD files to 1 MiB.
	 *
	 * By default, ZeroDark.cloud supports nodes of all sizes - everything from a few bytes, up to multi-gigabyte files.
	 * Using this permission can be thought of as a way of preventing abuse.
	 * For examle, a user's 'msgs' container uses this flag.
	 */
	ZDCSharePermission_RecordsOnly = 'R',

	/**
	 * All children of the node are restricted to leafs.
	 * That is, the children cannot have their own children.
	 * Using this permission is another way of preventing abuse.
	 * A user's 'inbox' & 'msgs' folders use this permission.
	 */
	ZDCSharePermission_LeafsOnly = 'L',

	/**
	 * Users with this permission are allowed to create/modify a single child node, whose name matches their userID.
	 * For example, if Alice's userID is 'z55tqmfr9kix1p1gntotqpwkacpuoyno',
	 * then she will be allowed to create/modify a file called 'z55tqmfr9kix1p1gntotqpwkacpuoyno.{ext}'.
	 */
	ZDCSharePermission_UserOnly = 'U',

	/**
	 * Users with this permission are allowed to create child nodes.
	 * However, the nodes are considered "write once", in that the user can create them,
	 * but doesn't have permission to modify them afterwards.
	 *
	 * A user's 'msgs' folder utilizes this flag.
	 * For example, Alice is allowed to write a message into Bob's messages folder,
	 * but Alice doesn't have permission to modify that message afterwards.
	 *
	 * @see ZDCSharePermission_BurnIfOwner
	 */
	ZDCSharePermission_WriteOnce = 'W',

	/**
	 * The node can be deleted if they have a 'B' permission in the node itself.
	 * In other words, they don't need 'w' permission on the parent node,
	 * just the 'B' permission on the node to be deleted.
	 */
	ZDCSharePermission_BurnIfOwner = 'B'
};

/**
 * A ShareItem encapsulates the permissions for a particular resource.
 * Typically this means the permissions for another user.
 *
 * Recall that ZeroDark.cloud uses cryptography to enforce permissions.
 * In order to read the content of a node, you need to know the node's encryptionKey.
 * (And every node has a different randomly generated encryptionKey.)
 * Each encryptionKey is wrapped using the publicKey of a resource with read permissions for the node.
 * So each ShareItem includes permissions, and a wrapped key.
 */
@interface ZDCShareItem : ZDCObject <NSCoding, NSCopying, ZDCSyncable>

/**
 * Creates an empty shareItem.
 *
 * You'll want to add permissions, but you don't need to worry about setting the key.
 * The framework will handle setting the key for you.
 */
- (instancetype)init;

/**
 * Creates a shareItem by parsing the given dictionary.
 *
 * @note The use of this method automatically sets the `canAddKey` property to false.
 */
- (instancetype)initWithDictionary:(nullable NSDictionary *)dictionary;

/** Returns the "raw" version of the shareList, as it would appear in the cloud. */
@property (nonatomic, readonly) NSDictionary *rawDictionary;

/**
 * The permsissions for the resource.
 * Permissions are represented as a string, where each character in the string has a special meaning.
 *
 * There are a number of permissions constants:
 * - `ZDCSharePermission_Read`
 * - `ZDCSharePermission_Write`
 * - `ZDCSharePermission_Share`
 * - `ZDCSharePermission_RecordsOnly`
 * - `ZDCSharePermission_LeafsOnly`
 * - `ZDCSharePermission_UserOnly`
 * - `ZDCSharePermission_WriteOnce`
 * - `ZDCSharePermission_BurnIfOwner`
 *
 * @see `-hasPermission:`
 * @see `-addPermission:`
 * @see `-removePermission:`
 */
@property (nonatomic, readwrite, copy) NSString *permissions;

/**
 * The wrapped encryptionKey that's being used to encrypt the node's content.
 *
 * @note The framework can automatically generate the key for you.
 *       You really only need to worry about setting the permissions.
 *
 * The node.encryptionKey is wrapped using the resource's public key.
 * Thus the corresponding private key is needed to unwrap the node.encryptionKey.
 * And since only the target resource has access to their private key,
 * only the target resource will be able to decrypt this wrapped key.
 */
@property (nonatomic, readwrite, copy, nullable) NSData *key;

/**
 * Additional security measure to prevent against a possible attack.
 *
 * The framework has the ability to automatically create & set the ZDCShareItem.key property.
 * However it will only do so if:
 * - the `canAddKey` property is true
 * - the permissions include ZDCSharePermission_Read
 *
 * The `canAddKey` property only gets set to true if you explicitly add `read` permission.
 * The `canAddKey` property doesn't get modified as a result of pulling down information from the cloud.
 */
@property (nonatomic, readwrite, assign) BOOL canAddKey;

/**
 * Returns YES if the given permission is included in the set of permissions.
 */
- (BOOL)hasPermission:(ZDCSharePermission)perm;

/**
 * Adds the given permission to the set of permissions (if it's not already included).
 *
 * @warning Attempting to invoke this method on an immutable instance will result in an exception.
 *          Check to see if your node is immutable via inherited property `-[ZDCObject isImmutable]`.
 *          If the node is immutable, you should make a copy of the node, and then modify the copy.
 */
- (void)addPermission:(ZDCSharePermission)perm;

/**
 * Removes the given permission from the set of permissions (if it's already included).
 *
 * @warning Attempting to invoke this method on an immutable instance will result in an exception.
 *          Check to see if your node is immutable via inherited property `-[ZDCObject isImmutable]`.
 *          If the node is immutable, you should make a copy of the node, and then modify the copy.
 */
- (void)removePermission:(ZDCSharePermission)perm;

/**
 * Returns true if the parameter is of type ZDCShareItem, and all values are the same.
 */
- (BOOL)isEqual:(nullable id)another;

/**
 * Returns true if all values are the same.
 */
- (BOOL)isEqualToShareItem:(ZDCShareItem *)another;

@end

NS_ASSUME_NONNULL_END
