/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A few simple methods for NSString.
 */
@interface NSString (ZeroDark)

/**
 * Returns a string with the following format:
 * 32 characters (encoded using hexadecimal).
 *
 * This is generated via NSUUID (with the dashes removed).
 */
+ (NSString *_Nonnull)zdcUUIDString;

/**
 * The character set used by our cloud naming system.
 */
+ (NSCharacterSet *_Nonnull)zBase32CharacterSet;

/**
 * Returns YES if all the characters in the string are part of the zBase32 character set.
 */
- (BOOL)isZBase32;

/**
 * When converting a string to UTF-8 bytes, it's important to remember that 1 UTF-8 character != 1 byte.
 * Each UTF-8 "character" may be 1, 2, 3 or 4 bytes.
 *
 * This method returns the actual size (in bytes) of the string when represented in UTF-8.
 * It's named similar to the common "UTF8String" method to make it easy to remember.
 */
- (NSUInteger)UTF8LengthInBytes;

/**
 * This method first deletes the existing extension (if any, and only the last),
 * and then appends the given extension.
 */
- (NSString *)stringBySettingPathExtension:(NSString *)str;

/**
 * Write some doocumentation here
 *
 */

+ (NSString *)hexEncodeBytesWithSpaces:(const uint8_t *)bytes
                                length:(NSUInteger)length;


/**
 * convert NSData to base58 representation as defined in
 * https://en.wikipedia.org/wiki/Base58
 */
+ (NSString *__nullable)base58WithData:(NSData *__nullable)data;

/**
 * convert base58 NSString representation into NSData as defined in
 * https://en.wikipedia.org/wiki/Base58
 */
- (NSData * __nullable )base58ToData;

@end

NS_ASSUME_NONNULL_END
