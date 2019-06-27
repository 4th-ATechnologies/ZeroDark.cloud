/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Standardized routines to ensure the correct object type is returned.
 * Performs conversions when possible (e.g. number => string)
 */
@interface ZDCPreferenceUtilities : NSObject

/** Converts the object to a boolean. Returns NO if conversion fails. */
+ (BOOL)boolValueFromObject:(id)object;

/** Converts the object to a float. Returns zero if conversion fails. */
+ (float)floatValueFromObject:(id)object;

/** Converts the object to a double. Returns zero if conversion fails. */
+ (double)doubleValueFromObject:(id)object;

/** Converts the object to an NSInteger. Returns zero if conversion fails. */
+ (NSInteger)integerValueFromObject:(id)object;

/** Converts the object to an NSUInteger. Returns zero if conversion fails. */
+ (NSUInteger)unsignedIntegerValueFromObject:(id)object;

/** Converts the object to a string. Returns nil if conversion fails. */
+ (nullable NSString *)stringValueFromObject:(id)object;

/** Converts the object to a number. Returns nil if conversion fails. */
+ (nullable NSNumber *)numberValueFromObject:(id)object;

/** Checks to see if the given object is NSData. */
+ (nullable NSData *)dataValueFromObject:(id)object;

@end

NS_ASSUME_NONNULL_END
