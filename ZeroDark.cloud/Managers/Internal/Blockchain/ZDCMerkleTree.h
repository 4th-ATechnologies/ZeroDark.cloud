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
 * Utility class for parsing & reading merkingTree files, as downloaded from ZDC servers.
 */
@interface ZDCMerkleTree : NSObject

/**
 * Attempts to parse the given dictionary.
 * If the file doesn't contain the proper key/value pairs, returns nil & sets error.
 */
+ (nullable instancetype)parseFile:(NSDictionary *)file error:(NSError *_Nullable *_Nullable)outError;

/**
 * This method performs a self-verify operation:
 * - parses all the contained values
 * - rebuilds the tree
 * - verifies that the hashes match
 * - verifies that the root hash value is correct
 */
- (BOOL)hashAndVerify:(NSError *_Nullable *_Nullable)outError;

/**
 * Returns the merkleTree root value, as specified within the JSON.
 * This value is only valid IF the `hashAndVerify` method returns true.
 */
- (NSString *)rootHash;

/**
 * Returns the set of userID's contained within the merkle tree file.
 */
- (NSSet<NSString *> *)userIDs;

/**
 * Extracts the pubKey & keyID values from the JSON.
 */
- (BOOL)getPubKey:(NSString *_Nullable *_Nullable)outPubKey
            keyID:(NSString *_Nullable *_Nullable)outKeyID
        forUserID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
