#import <Foundation/Foundation.h>

/**
 * AWS category class.
 */
@interface NSData (AWSUtilities)

/**
 * Converts the data to a string by encoding it using hexadecimal-based representation.
 * The hex characters are lowercase (0123456789abcdef).
 */
- (NSString *)lowercaseHexString;

@end
