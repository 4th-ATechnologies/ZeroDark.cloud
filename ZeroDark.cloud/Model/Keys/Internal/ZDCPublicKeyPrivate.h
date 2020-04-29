/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import "ZDCPublicKey.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPublicKey ()

/**
 * Generates a random public/private key pair.
 */
+ (nullable instancetype)createPrivateKeyWithUserID:(NSString *)userID
                                          algorithm:(Cipher_Algorithm)algorithm
                                         storageKey:(S4KeyContextRef)storageKey
                                              error:(NSError *_Nullable *_Nullable)outError;

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

@end

NS_ASSUME_NONNULL_END
