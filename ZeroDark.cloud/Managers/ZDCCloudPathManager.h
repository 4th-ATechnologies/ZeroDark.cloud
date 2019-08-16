/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCCloudLocator.h"
#import "ZDCCloudPath.h"
#import "ZDCNode.h"
#import "ZDCUser.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZeroDark.cloud framework encrypts node-names before storing them in the cloud.
 * This is to maintain zero-knowledge, and protect the customer in situations
 * where the node-names themselves may reveal sensitive information.
 *
 * For more information about how the encryption works, see this article:
 * https://zerodarkcloud.readthedocs.io/en/latest/overview/encryption/
 *
 * Here's the high-level overview:
 *
 * 1. All files are stored in AWS S3.<br/>
 *    It should be noted that S3 is NOT a filesystem - it's actually a key/value store.
 *    So each treepath needs to get translated to a string that uniquely identifies it.
 *    This string is called the "key" in S3 parlance.
 *    And keys in S3 have certain restrictions, such as a max length of 1024.
 *
 * 2. ZeroDark maps from (cleartext) treepath to (encrypted) S3 key.<br/>
 *    This mapping is done to ensure the server cannot read node names. Here's an example
 *    - Treepath: /foo/bar
 *    - S3 key: com.company.app/F8622C33B26C43C7B7DB3A6B26C60057/58fidhxeyyfzgp73hgefpr956jaxa6xs.rcrd
 *
 *    The S3 key components are: **{zAppID}/{dirPrefix}/{hasedNodeName}.ext**
 *
 * 3. The first path component is the app container.<br/>
 *    Your company may create multiple applications.
 *    So each application gets its own container.
 *
 * 4. The second path component is called the dirPrefix.<br/>
 *    A dirPrefix is a UUID - 32 characters of hexadecimal.
 *    For example: "F8622C33B26C43C7B7DB3A6B26C60057"
 *    Every parent node registers a dirPrefix.
 *    And every direct child of the parent node will use this dirPrefix within its key.
 *
 * 5. The last path component is the encrypted name.<br/>
 *    To generate the hashedNodeName, the framework hashes the (cleartext) node name
 *    (e.g. "Secret coca-cola formula.txt"), combined with the parent directory's salt.
 *    Thus 2 nodes with the same name, but different parents, will have a different hashedNodeName.
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
 * - cloudPath (AWS S3 keyPath) (encrypted version of cleartext treepath)
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
 * - cloudPath (AWS S3 keyPath) (encrypted version of cleartext treepath)
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
 * The cloudPath is the AWS S3 keyPath, which is the encrypted version of the cleartext treepath.
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
 * The cloudPath is the AWS S3 keyPath, which is the encrypted version of the cleartext treepath.
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
