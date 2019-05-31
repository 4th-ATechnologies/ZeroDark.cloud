#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

/**
 * A flexible date/time formatting & parsing class.
 *
 * It support the date formats used by Amazon,
 * as well as common HTTP date formats.
 */
@interface AWSDate : NSObject

#pragma mark Date -> String

/**
 * Common HTTP date format.
 * Example: Sun, 06 Nov 1994 08:49:37 GMT
 */
+ (NSString *)RFC1123TimestampFromDate:(NSDate *)date;

/**
 * Older date format.
 * Example: Sun, 06-Nov-94 08:49:37 GMT
 */
+ (NSString *)RFC1036TimestampFromDate:(NSDate *)date;

/**
 * Really old date format. (format for C asctime() date string)
 * Example: Sun Nov 6 08:49:37 1994
 */
+ (NSString *)asctimeTimestampFromDate:(NSDate *)date;

/**
 * Standard Internet date format.
 * Example: 2016-07-11T21:05:46Z
 */
+ (NSString *)ISO8601TimestampFromDate:(NSDate *)date;

/**
 * Short date format used by Amazon (during request signing).
 * Example: 20160711
 */
+ (NSString *)shortTimestampFromDate:(NSDate *)date;

#pragma mark String -> Date

/**
 * Attempts to parse a date string assumed to be in RFC 1123 format.
 * If you're unsure of the exact date format, you can use `-parseTimestamp:` instead.
 */
+ (nullable NSDate *)parseRFC1123Timestamp:(NSString *)dateTimeStr;

/**
 * Attempts to parse a date string assumed to be in RFC 1036 format.
 * If you're unsure of the exact date format, you can use `-parseTimestamp:` instead.
 */
+ (nullable NSDate *)parseRFC1036Timestamp:(NSString *)dateTimeStr;

/**
 * Attempts to parse a date string assumed to be in asctime format.
 * If you're unsure of the exact date format, you can use `-parseTimestamp:` instead.
 */
+ (nullable NSDate *)parseAsctimeTimestamp:(NSString *)dateTimeStr;

/**
 * Attempts to parse a date string assumed to be in SO 8601 format.
 * If you're unsure of the exact date format, you can use `-parseTimestamp:` instead.
 */
+ (nullable NSDate *)parseISO8601Timestamp:(NSString *)dateTimeStr;

/**
 * Will parse a date in any of the following formats:
 * - RFC 1123
 * - RFC 1036
 * - asctime
 * - ISO 8601
 *
 * This is the smart parsing method that generally just works.
 */
+ (nullable NSDate *)parseTimestamp:(NSString *)dateTimeStr;

@end

NS_ASSUME_NONNULL_END
