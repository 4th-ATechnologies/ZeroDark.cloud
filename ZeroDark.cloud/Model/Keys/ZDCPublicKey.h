/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <S4Crypto/S4Crypto.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The PublicKey class holds the information necessary to create a public key within the S4Crypto library.
 * It may optionally hold the information for the corresponding private key (if the key is for a local user).
 */
@interface ZDCPublicKey : ZDCObject <NSCoding, NSCopying>

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
 *
 * @param userID
 *   The corresponding userID (userID == ZDCUser.uuid)
 *
 * @param pubKeyDict
 *   A dictionary that contains the parameters which can be used to create the public key.
 *   This contains information such as the ECC curve,
 *   and other such parameters needed for the type of public key.
 */
- (instancetype)initWithUserID:(NSString *)userID
                    pubKeyDict:(NSDictionary *)pubKeyDict;

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns YES if privKeyJSON is non-nil.
 */
@property (nonatomic, readonly) BOOL isPrivateKey;

/**
 * Returns a parsed version of `pubKeyJSON`.
 * The parsed version is kept cached in memory for performance.
 */
@property (nonatomic, readonly) NSDictionary *keyDict;

/**
 * Reads & returns the pubKey value from the keyDict.
 * This is the raw pubKey bits, encoded using base64.
 */
@property (nonatomic, readonly, nullable) NSString * pubKey;

/**
 * Reads & returns the keyID value from the keyDict.
 */
@property (nonatomic, readonly, nullable) NSString * keyID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Performs self-test by attempting to create an S4KeyContext from the pubKeyJSON.
 */
- (BOOL)checkKeyValidityWithError:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Modifies the pubKeyJSON and/or privKeyJSON by setting the given property.
 */
- (BOOL)updateKeyProperty:(NSString *)propertyID
                    value:(NSData *)value
               storageKey:(S4KeyContextRef)storageKey
                    error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Used when migrating a PrivateKey to a PublicKey.
 */
- (void)copyToPublicKey:(ZDCPublicKey *)copy;

@end

NS_ASSUME_NONNULL_END
