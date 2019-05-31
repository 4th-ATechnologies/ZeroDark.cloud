/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>


@interface NSData (S4)

+ (NSData *)s4RandomBytes:(NSUInteger)length;

- (NSString *)hexString;
+ (NSData *)dataFromHexString:(NSString *)inString;

- (NSString *)zBase32String;
+ (NSData *)dataFromZBase32String:(NSString *)inString;

/**
 * xxHash is a fast non-cryptographic hashing algorithm.
**/
- (uint32_t)xxHash32;
- (uint64_t)xxHash64;

+ (instancetype)allocSecureDataWithLength:(NSUInteger)length;

- (NSData *)hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut;

@end

