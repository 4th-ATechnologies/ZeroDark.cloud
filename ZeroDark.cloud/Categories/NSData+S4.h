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


@interface NSData (S4)

+ (NSData *)s4RandomBytes:(NSUInteger)length;

+ (NSData *)dataFromHexString:(NSString *)inString;

- (NSString *)zBase32String;
+ (NSData *)dataFromZBase32String:(NSString *)inString;

/**
 * Returns a 32 bit hash using the xxHash algorithm.
 * (xxHash is a fast non-cryptographic hashing algorithm)
 */
- (uint32_t)xxHash32;

/**
 * Returns a 64 bit hash using the xxHash algorithm.
 * (xxHash is a fast non-cryptographic hashing algorithm)
 */
- (uint64_t)xxHash64;

+ (instancetype)allocSecureDataWithLength:(NSUInteger)length;

/**
 * Convenience function for hashing data.
 */
- (NSData *)hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut;

@end

