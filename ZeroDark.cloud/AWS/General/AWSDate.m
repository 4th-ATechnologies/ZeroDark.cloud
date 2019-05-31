#import "AWSDate.h"


@implementation AWSDate

static dispatch_queue_t dateFormatterQueue = NULL;

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		dateFormatterQueue = dispatch_queue_create("S3DateHelper", DISPATCH_QUEUE_SERIAL);
		initialized = YES;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark DateFormatters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSDateFormatter *)RFC1123DateFormatter
{
	static NSDateFormatter *rfc1123DateFormatter = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		rfc1123DateFormatter = [[NSDateFormatter alloc] init];
		rfc1123DateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss z";
		rfc1123DateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
		rfc1123DateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	});
	
	return rfc1123DateFormatter;
}

+ (NSDateFormatter *)RFC1036DateFormatter
{
	static NSDateFormatter *rfc1036DateFormatter = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		rfc1036DateFormatter = [[NSDateFormatter alloc] init];
		rfc1036DateFormatter.dateFormat = @"EEEE, dd-MMM-yy HH:mm:ss z";
		rfc1036DateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
		rfc1036DateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	});
	
	return rfc1036DateFormatter;
}

+ (NSDateFormatter *)asctimeDateFormatter
{
	static NSDateFormatter *asctimeDateFormatter = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		asctimeDateFormatter = [[NSDateFormatter alloc] init];
		asctimeDateFormatter.dateFormat = @"EEE MMM d HH:mm:ss yyyy";
		asctimeDateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
		asctimeDateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	});
	
	return asctimeDateFormatter;
}

+ (NSDateFormatter *)ISO8601DateFormatter
{
	static NSDateFormatter *iso8601DateFormatter = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		iso8601DateFormatter = [[NSDateFormatter alloc] init];
		iso8601DateFormatter.dateFormat = @"yyyyMMdd'T'HHmmss'Z'"; // Set to match Amazon's style
		iso8601DateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
		iso8601DateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	});
	
	return iso8601DateFormatter;
}

+ (NSDateFormatter *)shortDateFormatter
{
	static NSDateFormatter *shortDateFormatter = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		shortDateFormatter = [[NSDateFormatter alloc] init];
		shortDateFormatter.dateFormat = @"yyyyMMdd";
		shortDateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
		shortDateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	});
	
	return shortDateFormatter;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Date -> String
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Common HTTP date format.
 * Example: Sun, 06 Nov 1994 08:49:37 GMT
 */
+ (NSString *)RFC1123TimestampFromDate:(NSDate *)date
{
	if (date == nil) return nil;
	
	__block NSString *timestamp = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		timestamp = [[self RFC1123DateFormatter] stringFromDate:date];
	}});
	
	return timestamp;
}

/**
 * Older date format.
 * Example: Sun, 06-Nov-94 08:49:37 GMT
 */
+ (NSString *)RFC1036TimestampFromDate:(NSDate *)date
{
	if (date == nil) return nil;
	
	__block NSString *timestamp = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		timestamp = [[self RFC1036DateFormatter] stringFromDate:date];
	}});
	
	return timestamp;
}

/**
 * Really old date format. (format for C asctime() date string)
 * Example: Sun Nov 6 08:49:37 1994
 */
+ (NSString *)asctimeTimestampFromDate:(NSDate *)date
{
	if (date == nil) return nil;
	
	__block NSString *timestamp = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		timestamp = [[self asctimeDateFormatter] stringFromDate:date];
	}});
	
	return timestamp;
}

/**
 * Standard Internet date format.
 * Example: 2016-07-11T21:05:46Z
 */
+ (NSString *)ISO8601TimestampFromDate:(NSDate *)date
{
	if (date == nil) return nil;
	
	__block NSString *timestamp = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		timestamp = [[self ISO8601DateFormatter] stringFromDate:date];
	}});
	
	return timestamp;
}

/**
 * Short date format used by Amazon (during request signing).
 * Example: 20160711
 */
+ (NSString *)shortTimestampFromDate:(NSDate *)date
{
	if (date == nil) return nil;
	
	__block NSString *timestamp = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		timestamp = [[self shortDateFormatter] stringFromDate:date];
	}});
	
	return timestamp;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark String -> Date
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (nullable NSDate *)parseRFC1123Timestamp:(NSString *)dateTimeStr
{
	if (dateTimeStr == nil) return nil;
	
	__block NSDate *date = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		date = [[self RFC1123DateFormatter] dateFromString:dateTimeStr];
	}});
	
	return date;
}

+ (nullable NSDate *)parseRFC1036Timestamp:(NSString *)dateTimeStr
{
	if (dateTimeStr == nil) return nil;
	
	__block NSDate *date = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		date = [[self RFC1036DateFormatter] dateFromString:dateTimeStr];
	}});
	
	return date;
}

+ (nullable NSDate *)parseAsctimeTimestamp:(NSString *)dateTimeStr
{
	if (dateTimeStr == nil) return nil;
	
	__block NSDate *date = nil;
	dispatch_sync(dateFormatterQueue, ^{ @autoreleasepool {
		
		date = [[self asctimeDateFormatter] dateFromString:dateTimeStr];
	}});
	
	return date;
}

+ (NSDate *)parseISO8601Timestamp:(NSString *)dateTimeStr
{
	// This code is inspired from the XMPPFramework's XEP-0082 Date/Time parsing:
	// https://github.com/robbiehanson/XMPPFramework/blob/master/Extensions/XEP-0082/XMPPDateTimeProfiles.m
	//
	// I think I originally wrote it.
	// Although that was many lines of code ago, so memory is a bit hazy...
	
	if (dateTimeStr == nil) return nil;
	
	dateTimeStr = [dateTimeStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	
	// The DateTime profile is used to specify a non-recurring moment in time to an accuracy of seconds (or,
	// optionally, fractions of a second). The format is as follows:
	// 
	// YYYY-MM-DDThh:mm:ss[.sss]{TZD}
	//
	// Although, apparently, the dashes and colons are OPTIONAL. (At least according to Amazon's examples.)
	//
	// Examples:
	// 
	// 1969-07-21T02:56:15
	// 1969-07-21T02:56:15Z
	// 1969-07-20T21:56:15-05:00
	// 1969-07-21T02:56:15.123
	// 1969-07-21T02:56:15.123Z
	// 1969-07-20T21:56:15.123-05:00
	// 19690721T02:56:15Z
	// 19690721T025615Z
	
	if (dateTimeStr.length < 16) return nil;
	
	BOOL hasDashes = NO;
	BOOL hasColons = NO;
	
	BOOL hasTimeZoneInfo = NO;
	
	NSString *millisecondsString = nil;
	NSString *timeZoneString = nil;
	
	// Check for dashes, 'T', and colons
	
	hasDashes = ([dateTimeStr characterAtIndex:4] == '-');
	
	NSUInteger locationOfT = hasDashes ? 10 : 8;
	if ([dateTimeStr characterAtIndex:locationOfT] != 'T') {
		return nil;
	}
	
	hasColons = ([dateTimeStr characterAtIndex:(locationOfT + 3)] == ':');
	
	NSUInteger locationAfterSeconds = 15;
	if (hasDashes)
		locationAfterSeconds += 2;
	if (hasColons)
		locationAfterSeconds += 2;
	
	if (dateTimeStr.length < locationAfterSeconds)
		return nil;
	
	if (dateTimeStr.length > locationAfterSeconds)
	{
		unichar c = [dateTimeStr characterAtIndex:locationAfterSeconds];
		
		NSUInteger locationAfterMillis = locationAfterSeconds;
		
		// Check for optional milliseconds
		if (c == '.')
		{
			NSRange range;
			range.location = locationAfterSeconds + 1;
			range.length = 0;
			
			while ((range.location + range.length) < dateTimeStr.length)
			{
				c = [dateTimeStr characterAtIndex:(range.location + range.length)];
				
				if (c >= '0' && c <= '9')
				{
					range.length += 1;
				}
				else
				{
					break;
				}
			}
			
			if (range.length > 0)
			{
				millisecondsString = [NSString stringWithFormat:@"0.%@", [dateTimeStr substringWithRange:range]];
			}
			locationAfterMillis = range.location + range.length;
		}
		
		// Check for optional time zone info.
		// If present, it should be either 'Z' (indicating GMT),
		// or something of the format '-05:00'.
		
		c = [dateTimeStr characterAtIndex:locationAfterMillis];
		
		if (c == 'Z')
		{
			hasTimeZoneInfo = YES;
		}
		else if (c == '+' || c == '-')
		{
			NSRange range = NSMakeRange(locationAfterMillis, 6);
			
			if (dateTimeStr.length >= (range.location + range.length))
			{
				hasTimeZoneInfo = YES;
				timeZoneString = [dateTimeStr substringWithRange:range];
			}
			else
			{
				return nil;
			}
		}
	}
	
	NSDateFormatter *df = [[NSDateFormatter alloc] init];
	df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	
	if (hasDashes)
	{
		if (hasColons)
			df.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
		else
			df.dateFormat = @"yyyy-MM-dd'T'HHmmss";
	}
	else
	{
		if (hasColons)
			df.dateFormat = @"yyyyMMdd'T'HH:mm:ss";
		else
			df.dateFormat = @"yyyyMMdd'T'HHmmss";
	}

	NSDate *result = nil;
	NSString *dateAndTimeOnly = [dateTimeStr substringToIndex:locationAfterSeconds];

	if (hasTimeZoneInfo)
	{
		if (timeZoneString)
		{
			NSTimeZone *tz = [self parseISO8601TimeZoneOffset:timeZoneString];
			if (tz == nil) {
				return nil;
			}
			
			df.timeZone = tz;
		}
		else
		{
			df.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		}
	}

	result = [df dateFromString:dateAndTimeOnly];
	
	if (millisecondsString.length > 0)
	{
		static NSNumberFormatter *numberFormatter = nil;
		
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			numberFormatter = [[NSNumberFormatter alloc] init];
			numberFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
			numberFormatter.decimalSeparator = @".";
		});

		NSTimeInterval fractionInterval = [[numberFormatter numberFromString:millisecondsString] doubleValue];
		NSTimeInterval current = [result timeIntervalSinceReferenceDate];
		result = [NSDate dateWithTimeIntervalSinceReferenceDate:floor(current) + fractionInterval];
	}

	return result;
}

+ (NSTimeZone *)parseISO8601TimeZoneOffset:(NSString *)tzo
{
	// The tzo value is supposed to start with '+' or '-'.
	// Spec says: (+-)hh:mm
	//
	// hh : two-digit hour portion (00 through 23)
	// mm : two-digit minutes portion (00 through 59)
	
	if (tzo.length != 6)
	{
		return nil;
	}
	
	NSString *hoursStr   = [tzo substringWithRange:NSMakeRange(1, 2)];
	NSString *minutesStr = [tzo substringWithRange:NSMakeRange(4, 2)];
	
	errno = 0;
	
	unsigned long hours = strtoul([hoursStr UTF8String], NULL, 10);
	if (errno != 0)
		return nil;
	
	unsigned long minutes = strtoul([minutesStr UTF8String], NULL, 10);
	if (errno != 0)
		return nil;
	
	if (hours > 23) return nil;
	if (minutes > 59) return nil;
	
	NSInteger secondsOffset = (NSInteger)((hours * 60 * 60) + (minutes * 60));
	
	if ([tzo hasPrefix:@"-"])
	{
		secondsOffset = -1 * secondsOffset;
	}
	else if (![tzo hasPrefix:@"+"])
	{
		return nil;
	}
	
	return [NSTimeZone timeZoneForSecondsFromGMT:secondsOffset];
}

+ (NSDate *)parseTimestamp:(NSString *)dateString
{
	if (dateString == nil) return nil;
	
	// What date/time format is used in HTTP headers ?
	// http://stackoverflow.com/questions/21120882/the-date-time-format-used-in-http-headers
	//
	// HTTP applications have historically allowed three different
	// formats for the representation of date/time stamps:
	//
	//   Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
	//   Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
	//   Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
	//
	// The first format is preferred as an Internet standard and represents
	// a fixed-length subset of that defined by RFC 1123 (an update to RFC 822).
	
	NSDate *date = nil;
	
	BOOL hasComma = ([dateString rangeOfString:@","].location != NSNotFound);
	BOOL hasDash  = ([dateString rangeOfString:@"-"].location != NSNotFound);
	BOOL hasColon = ([dateString rangeOfString:@":"].location != NSNotFound);
	
	if (hasComma && !hasDash && hasColon)
	{
		// Try RFC 1123:
		//
		// EEE, dd MMM yyyy HH:mm:ss z
		
		date = [[self RFC1123DateFormatter] dateFromString:dateString];
		if (date) {
			return date;
		}
	}
	
	if (hasComma && hasDash && hasColon)
	{
		// Try RFC 1036
		//
		// EEEE, dd-MMM-yy HH:mm:ss z
		
		date = [[self RFC1036DateFormatter] dateFromString:dateString];
		if (date) {
			return date;
		}
	}
		
	if (!hasComma && !hasDash && hasColon)
	{
		// Try asctime
		//
		// EEE MMM d HH:mm:ss yyyy
		
		date = [[self asctimeDateFormatter] dateFromString:dateString];
		if (date) {
			return date;
		}
	}
	
	// Try ISO 8601
	//
	// Lots of different format options supported.
	
	date = [self parseISO8601Timestamp:dateString];
	
	return date;
}

@end
