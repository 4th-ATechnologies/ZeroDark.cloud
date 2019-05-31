/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCCloudLocator.h"
#import "ZDCCloudPath.h"
#import "ZDCNode.h"
#import "ZDCUser.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZeroDark.cloud framework encrypts node-names and paths before storing them in the cloud.
 * This is to maintain zero-knowledge, and protect the customer in situations
 * where the node-names themselves may reveal sensitive information.
 *
 * For more information about how the encryption works, see this article:
 * https://zerodarkcloud.readthedocs.io/en/latest/overview/encryption/
 *
 * Here's the high-level overview:
 *
 * 0. All files are stored in AWS S3.
 *    It should be noted that S3 is NOT a filesystem - it's actually a key value store.
 *    So each treepath needs to get translated to a string that uniquely identifies it.
 *    This string is called the "key" in S3.
 *    And keys in S3 also have certain restrictions, such as a max length of 1024.
 *
 * 1. The mapping from (cleartext) treepath to (encrypted) S3 key is achieved like so:
 *    Cleartext filepath: /foo/bar
 *    Encrypted S3 key:
 *    com.company.app/F8622C33B26C43C7B7DB3A6B26C60057/58fidhxeyyfzgp73hgefpr956jaxa6xs.rcrd
 *    <    zAppID   >/<          dirPrefix           >/<        hasedNodeName         >.ext
 *
 * 2. The first level is the app container.
 *    Your company may create multiple applications.
 *    So each application gets its own container.
 *
 * 3. Next, every node that has children has something called a "dirPrefix".
 *    The dirPrefix is a UUID string - 32 characters of hexadecimal.
 *    For example: "F8622C33B26C43C7B7DB3A6B26C60057"
 *    Every direct child of this node will include the dirPrefix within its key.
 *
 * 4. Similar to a filesystem, each node must have a name.
 *    And the name must be unique within its parent (case-insensitive).
 *    To generate the hashedNodeName, the framework hashes the cleartext name,
 *    combined with the parent directory's salt.
 */
@interface ZDCCloudPathManager : NSObject

/**
 * Returns singleton instance.
 */
+ (instancetype)sharedInstance;

/**
 * Returns the cloud locator for the given node, which specifies:
 *
 * - AWS region
 * - AWS bucket
 * - cloudPath (AWS S3 keyPath) (encrypted version of cleartext nodeName)
 *
 * @param node
 *   The node for which to calculate the cloudLocator.
 *
 * @param transaction
 *   A transaction is required to read from the database.
 */
- (nullable ZDCCloudLocator *)cloudLocatorForNode:(ZDCNode *)node
                                      transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns the cloud locator for the given node, which specifies:
 *
 * - AWS region
 * - AWS bucket
 * - cloudPath (AWS S3 keyPath) (encrypted version of cleartext nodeName)
 *
 * @param node
 *   The node for which to calculate the cloudLocator.
 *
 * @param fileExt
 *   If non-nil, the returned path will have the given file extension.
 *   This is typically `kZDCCloudFileExtension_Rcrd` or `kZDCCloudFileExtension_Data`.
 *
 * @param transaction
 *   A transaction is required to read from the database.
 */
- (nullable ZDCCloudLocator *)cloudLocatorForNode:(ZDCNode *)node
                                    fileExtension:(nullable NSString *)fileExt
                                      transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns the cloudPath for the node.
 * The cloudPath is the AWS S3 keyPath, which is the encrypted version of the cleartext node-name.
 *
 * A cloudPath has the general format: "{zAppID}/{dirPrefix}/{hashedNodeName}.{ext}"
 *
 * @param node
 *   The node for which to calculate the cloudLocator.
 *
 * @param transaction
 *   A transaction is required to read from the database.
 */
- (nullable ZDCCloudPath *)cloudPathForNode:(ZDCNode *)node
                                transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns the cloud path for the node.
 * The cloudPath is the AWS S3 keyPath, which is the encrypted version of the cleartext node-name.
 *
 * A cloudPath has the general format: "{zAppID}/{dirPrefix}/{hashedNodeName}.{ext}"
 *
 * @param node
 *   The node for which to calculate the cloudLocator.
 *
 * @param fileExt
 *   If non-nil, the returned path will have the given file extension.
 *   This is typically `kZDCCloudFileExtension_Rcrd` or `kZDCCloudFileExtension_Data`.
 *
 * @param transaction
 *   A transaction is required to read from the database.
 */
- (nullable ZDCCloudPath *)cloudPathForNode:(ZDCNode *)node
                              fileExtension:(nullable NSString *)fileExt
                                transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Calculates & returns the cloudName for the given node.
 *
 * The cloudName is calculated by hashing together node.name & parent.dirSalt.
 *
 * Returns nil if:
 * - the given node doesn't have a name
 * - the given node doesn't have a parentID
 * - the parent node doesn't exist in the database
 * - the parent node doesn't have a dirSalt value
 */
- (nullable NSString *)cloudNameForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
