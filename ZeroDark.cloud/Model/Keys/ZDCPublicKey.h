/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <S4Crypto/S4Crypto.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The PublicKey class holds the information necessary to create a public key within the S4Crypto library.
 * It may optionally hold the information for the corresponding private key (typically for local users).
 */
@interface ZDCPublicKey : ZDCObject <NSCoding, NSCopying>

/**
 * Generates a random public/private key pair.
 */
+ (id)privateKeyWithOwner:(NSString *)userID
               storageKey:(S4KeyContextRef)storageKey
                algorithm:(Cipher_Algorithm)algorithm;

/**
 * Creates a new PublicKey instance from the given parameters.
 *
 * @param userID
 *   The corresponding userID (userID == ZDCUser.uuid)
 *
 * @param pubKeyJSON
 *   A string that contains the serialized JSON parameters which can be used to create the public key.
 *   This information contains information such as the ECC curve,
 *   and other such parameters needed for the type of public key.
 */
- (instancetype)initWithUserID:(NSString *)userID
                    pubKeyJSON:(NSString *)pubKeyJSON;

/**
 * Creates a new PublicKey instance from the given parameters.
 * If a privKeyJSON parameter is passed, the key will also contain the corresponding private key.
 *
 * @param userID
 *   The corresponding userID (userID == ZDCUser.uuid)
 *
 * @param pubKeyJSON
 *   A string that contains the serialized JSON parameters which can be used to create the public key.
 *   This contains information such as the ECC curve,
 *   and other such parameters needed for the type of public key.
 *
 * @param privKeyJSON
 *   A string that contains the serialized JSON parameters which can be used to create the private key.
 *   This contains information such as the ECC curve,
 *   and other such parameters needed for the type of public key.
 */
- (instancetype)initWithUserID:(NSString *)userID
                    pubKeyJSON:(NSString *)pubKeyJSON
                   privKeyJSON:(nullable NSString *)privKeyJSON;

/**
 * Creates a new PublicKey instance from the given parameters.
 * If a privKeyDict parameter is passed, the key will also contain the corresponding private key.
 *
 * @param userID
 *   The corresponding userID (userID == ZDCUser.uuid)
 *
 * @param pubKeyDict
 *   A dictionary that contains the parameters which can be used to create the public key.
 *   This contains information such as the ECC curve,
 *   and other such parameters needed for the type of public key.
 *
 * @param privKeyDict
 *   A dictionary that contains the parameters which can be used to create the private key.
 *   This contains information such as the ECC curve,
 *   and other such parameters needed for the type of public key.
 */
- (instancetype)initWithUserID:(NSString *)userID
                    pubKeyDict:(NSDictionary *)pubKeyDict
                   privKeyDict:(nullable NSDictionary *)privKeyDict;

/**
 * Every PublicKey instance has a randomly generated UUID.
 * This is commonly referred to as the pubKeyID.
 *
 * This is also the key used to store the item in the database (within collection kZDCCollection_PublicKey).
 */
@property (nonatomic, copy, readonly) NSString * uuid;

/**
 * A reference to the user who owns this public key.
 * (userID == ZDCUser.uuid)
 *
 * The inverse relationship can be found via `-[ZDCUser publicKeyID]`
 */
@property (nonatomic, copy, readonly) NSString * userID;

/**
 * A string that contains the serialized JSON parameters that can be used to create the public key.
 *
 * This contains information such as the ECC curve,
 * and other such parameters needed for the type of public key.
 */
@property (nonatomic, copy, readonly) NSString * pubKeyJSON;

/**
 * A string that contains the serialized JSON parameters that can be used to create the private key.
 *
 * This contains information such as the ECC curve,
 * and other such parameters needed for the type of public key.
 */
@property (nonatomic, copy, readonly, nullable) NSString * privKeyJSON;

/**
 * Convenience method - returns YES if privKeyJSON is non-nil.
 */
@property (nonatomic, readonly) BOOL isPrivateKey;

// Extracted info from parsed keyJSON

@property (nonatomic, readonly) NSDictionary *keyDict; // Parsed keyJSON
@property (nonatomic, readonly, nullable) NSString * keyID;
@property (nonatomic, readonly, nullable) NSString * eTag;

- (BOOL)updateKeyProperty:(NSString *)propertyID
                    value:(NSData *)value
               storageKey:(S4KeyContextRef)storageKey
                    error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Performs self-test by attempting to create an S4KeyContext from the pubKeyJSON.
 */
- (BOOL)checkKeyValidityWithError:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Used when migrating a PrivateKey to a PublicKey.
 */
- (void)copyToPublicKey:(ZDCPublicKey *)copy;

@end

NS_ASSUME_NONNULL_END
