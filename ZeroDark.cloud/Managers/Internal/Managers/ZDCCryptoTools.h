/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZeroDarkCloud.h"

#import "ZDCCloudRcrd.h"
#import "ZDCLocalUser.h"
#import "ZDCPublicKey.h"
#import "ZDCSymmetricKey.h"
#import "ZDCTrunkNode.h"

@class ZDCMissingInfo;

NS_ASSUME_NONNULL_BEGIN

/**
 * Common crypto routines used throughout the framework.
 */
@interface ZDCCryptoTools : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Encrypts the given key using the public key.
 * To decrypt the result will require the matching private key.
 *
 * This process is called "wrapping a key" in cryptography.
 *
 * @return
 *   The encrypted data, or nil if an error occurs.
 *   In the event of an error, the errorOut parameter will be set (if non-null).
 */
- (nullable NSData *)wrapSymmetricKey:(NSData *)symKey
                       usingPublicKey:(ZDCPublicKey *)pubKey
                                error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Decrypts the given data using the corresponding private key.
 * This is the inverse of the `wrapKey:usingPubKey:transaction:error:` method.
 *
 * This process is called "unwrapping a key" in cryptography.
 *
 * @return
 *   The decrypted data, or nil if an error occurs.
 *   In the event of an error, the errorOut parameter will be set (if non-null).
 */
- (nullable NSData *)unwrapSymmetricKey:(NSData *)symKeyWrappedData
                        usingPrivateKey:(ZDCPublicKey *)privKey
                                  error:(NSError *_Nullable *_Nullable)errorOut;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud RCRD
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates the RCRD file content for the given node.
 *
 * @param node
 *   The node to generate the RCRD for.
 *
 * @param transaction
 *   A database transaction - used to read from the database in atomic fashion.
 *
 * @param outMissingInfo
 *   If the database is missing required information,
 *   then this parameter will detail the list of missing items.
 *
 * @param outError
 *   In case something goes wrong.
 *
 * @return A serialized JSON file which contains the RCRD file for the cloud.
 *         All the sensitive data is encrypted with the node.encryptionKey.
 *         And the node.encryptionKey has been wrapped using the publicKey's of those with read-access.
 */
- (nullable NSData *)cloudRcrdForNode:(ZDCNode *)node
                          transaction:(YapDatabaseReadTransaction *)transaction
                          missingInfo:(ZDCMissingInfo *_Nullable *_Nonnull)outMissingInfo
                                error:(NSError *_Nullable *_Nonnull)outError;

/**
 * If `cloudRcrdForNode:` or `cloudRcrdForMessage:` returns a non-empty list of `missingKeys`,
 * then you should call this method to fix it.
 *
 * @return The number of ZDCShareItem.key's that were populated.
 */
- (NSUInteger)fixMissingKeysForShareList:(ZDCShareList *)shareList
                           encryptionKey:(NSData *)encryptionKey
                             transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Parses & decrypts information from the given JSON dict.
 *
 * @param dict
 *   The JSON content of a RCRD file.
 *
 * @param localUserID
 *   The ZDCLocalUser.uuid to use when attempting to decrypt information.
 *   The corresponding private key will be used to attempt unwrapping the file encryption key.
 *
 * @param transaction
 *   This method needs a transaction to fetch various information from the database.
 *
 * @return
 *   An instance of ZDCCloudRcrd, which contains all the cleartext & decrypted information
 *   extracted from the RCRD file. If errors occur, the ZDCCloudRcrd.errors array will be non-empty.
 */
- (ZDCCloudRcrd *)parseCloudRcrdDict:(NSDictionary *)dict
                         localUserID:(NSString *)localUserID
                         transaction:(YapDatabaseReadTransaction *)transaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark KeyGen
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates a Private/Public Key (ZDCPublicKey) from JSON.
 * The private portion of the key is encypted to the accesskey, and so we decrypt it.
 *
 * @param keyJSON
 *   The JSON content of a private key file.
 *
 * @param accessKey
 *   The NSData representation of the access key that the private portion of the keyJSON
 *   is encrypted to.
 *
 * @param encryptionAlgorithm
 *   The S4 Cipher_Algorithm that the private key portion of the keyJSON is encrypted to.
 *   Typically this is kCipher_Algorithm_2FISH256
 *
 * @param localUserID
 *   The S4LocalUser.uuid to use when attempting to create the ZDCPublicKey.
 *
  * @param errorOut
 *   If an error occurs, the corresponding error may be returned via this parameter.
 *
 * @return
 *   An instance of ZDCPublicKey, which contains all the public and private key
 *   extracted from the keyJSON.
 */
- (nullable ZDCPublicKey *)createPrivateKeyFromJSON:(NSString *)keyJSON
                                          accessKey:(NSData *)accessKey
                                encryptionAlgorithm:(Cipher_Algorithm)encryptionAlgorithm
                                        localUserID:(NSString *)localUserID
                                              error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Create a symmetric key from the given data & algorithm.
 * The data from the key is stored encypted to the storage key.
 *
 * @param keyData
 *   The data representation of the key that will be stored in a ZDCSymmetricKey
 *
 * @param encryptionAlgorithm
 *   The the S4 Cipher_Algorithm that used to create the key.
 *   Typically this is kCipher_Algorithm_2FISH256.
 *
 * @param errorOut
 *   If an error occurs, the corresponding error will be returned via this parameter.
 *
 * @return
 *   An instance of ZDCSymmetricKey
 */
- (nullable ZDCSymmetricKey *)createSymmetricKey:(NSData *)keyData
                             encryptionAlgorithm:(Cipher_Algorithm)encryptionAlgorithm
                                           error:(NSError *_Nullable *_Nullable)errorOut;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Key Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Write some doocumentation here
 *
 */

- (NSData *)exportPublicKey:(ZDCPublicKey *)privKey
					  error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Write some doocumentation here
 *
 */

- (NSData *)exportPrivateKey:(ZDCPublicKey *)privKey
				 encryptedTo:(ZDCSymmetricKey *)cloudKey
					   error:(NSError *_Nullable *_Nullable)errorOut;


/**
 * Write some doocumentation here
 *
 */

-(BOOL) checkPublicKeySelfSig:(ZDCPublicKey *)pubKey
						error:(NSError *_Nullable *_Nullable)errorOut;


/**
 * Write some doocumentation here
 *
 */

-(NSString*) keyIDforPrivateKeyData:(NSData*)dataIn
							  error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Write some doocumentation here
 *
 */

- (BOOL)updateKeyProperty:(NSString*)propertyID
					value:(NSData*)value
		  withPublicKeyID:(NSString *)publicKeyID
			  transaction:(YapDatabaseReadWriteTransaction *)transaction
					error:(NSError *_Nullable *_Nullable)errorOut;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark DirSalt
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standardized technique for deriving the dirSalt for container nodes.
 * This method modifies the given containerNode.
 *
 * @param trunkNode
 *   The trunk node to modify (set dirSalt property)
 *
 * @param localUser
 *   The corresponding localUser for the node
 *
 * @param accessKey
 *   The localUser's accessKey (the key they need to access their account - they one they backup)
 */
- (BOOL)setDirSaltForTrunkNode:(ZDCTrunkNode *)trunkNode
                 withLocalUser:(ZDCLocalUser *)localUser
                     accessKey:(ZDCSymmetricKey *)accessKey;

/**
 * Key derivation function (mac=skein, hash=skein256)
 */
- (nullable NSData *)kdfWithSymmetricKey:(ZDCSymmetricKey *)symKey
                                  length:(NSUInteger)length
                                   label:(NSString *)label
                                    salt:(NSData *)salt
                                   error:(NSError *_Nullable *_Nullable)errorOut;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCMissingInfo : NSObject

@property (nonatomic, readonly) NSArray<NSString*> *missingKeys;

@property (nonatomic, readonly) NSArray<NSString*> *missingUserIDs;
@property (nonatomic, readonly) NSArray<ZDCUser*> *missingUserPubKeys;

@property (nonatomic, readonly) NSArray<NSString*> *missingServerIDs;

@end

NS_ASSUME_NONNULL_END
