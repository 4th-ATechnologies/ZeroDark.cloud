/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (S4)

/**
 * Allocates and returns a data instance backed by a deallocation routine that automatically zeros the bits.
 */
+ (instancetype)secureDataWithLength:(NSUInteger)length;

/**
 * Generates random data.
 *
 * (The S4 library is used, which uses Apple's CommonCrypto.)
 */
+ (nullable NSData *)s4RandomBytes:(NSUInteger)lengthInBytes;

/**
 * Converts the data into a zBase32 representation.
 */
- (NSString *)zBase32String;

/**
 * Converts from zBase32 representation into the raw data.
 *
 * Returns nil if the given string isn't in zBase32.
 */
+ (nullable NSData *)dataFromZBase32String:(NSString *)string;

/**
 * Returns a 32-bit hash using the xxHash algorithm.
 * (xxHash is a fast non-cryptographic hashing algorithm)
 */
- (uint32_t)xxHash32;

/**
 * Returns a 64-bit hash using the xxHash algorithm.
 * (xxHash is a fast non-cryptographic hashing algorithm)
 */
- (uint64_t)xxHash64;

/**
 * The S4 library supports many different hashing algorithm.
 * This is a convenience function for hashing data using any of them.
 */
- (nullable NSData *)hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut;

@end

NS_ASSUME_NONNULL_END
