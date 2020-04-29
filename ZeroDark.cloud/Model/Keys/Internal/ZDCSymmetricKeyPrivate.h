/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import "ZDCSymmetricKey.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCSymmetricKey ()

/**
 * Generates a random symmetic key using the given algorithm.
 */
+ (nullable instancetype)createWithAlgorithm:(Cipher_Algorithm)algorithm
                                  storageKey:(S4KeyContextRef)storageKey
                                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Generates a symmetric key from the existing low-level key.
 */
+ (nullable instancetype)createWithS4Key:(S4KeyContextRef)symCtx
                              storageKey:(S4KeyContextRef)storageKey
                                   error:(NSError *_Nullable *_Nullable)outError;

@end

NS_ASSUME_NONNULL_END
