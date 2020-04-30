/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (ZeroDark)

/**
 * Takes a string in hexadecimal format, and converts it to raw data.
 *
 * The implementation automatically ignores common "fluff" characters: ['<', '>', ' '].
 * The implementation stops if it encounters a non-hexadecimal character.
 */
+ (NSData *)dataFromHexString:(NSString *)string;

/**
 * Standardized routine for encrypting a **small** blob of data using a symmetric key.
 * For the corresponding decryption see `-decryptedWithSymmetricKey:error:`
 *
 * For medium/large amounts of data, it's recommended you use one of the routines in ZDCFileConversion.
 */
- (NSData *)encryptedWithSymmetricKey:(NSData *)key error:(NSError **)errorOut;

/**
 * Standardized routine for decrypting a **small** blob of data using a symmetric key.
 * For the corresponding encryption see `-encryptedWithSymmetricKey:error:`
 *
 * For medium/large amounts of data, it's recommended you use one of the routines in ZDCFileConversion.
*/
- (NSData *)decryptedWithSymmetricKey:(NSData *)key error:(NSError **)errorOut;

/**
 * Converts data to base58 representation as defined in
 * https://en.wikipedia.org/wiki/Base58
 */
- (NSString *)base58String;

/**
 * Converts base58 representation into raw data as defined in
 * https://en.wikipedia.org/wiki/Base58
 */
+ (nullable NSData *)dataFromBase58String:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
