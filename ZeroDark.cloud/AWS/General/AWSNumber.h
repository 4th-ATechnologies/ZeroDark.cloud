#import <Foundation/Foundation.h>


/**
 * Provides number tools required for working with AWS.
 */
@interface AWSNumber : NSObject

/**
 * Attempts to parse an unsigned 64-bit value from the given string.
 *
 * @param valuePtr
 *   On success, the value is set to the parsed 64-bit value.
 *
 * @param string
 *   The string to parse
 *
 * @return On success, returns YES. If unable to parse the number, returns NO.
 */
+ (BOOL)parseUInt64:(uint64_t *)valuePtr fromString:(NSString *)string;

@end
