/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSDate+ZeroDark.h"
#import "ZDCDateFormatterCache.h"

@interface NSCalendar (ZeroDark)

/**
 * Similar to NSDateFormatter, NSCalendar's are somewhat expensive to create and they are not thread-safe.
 *
 * For speed, we prefer to use Apple's autoupdatingCurrentCalendar, and store it in the thread dictionary.
 * This class helps facilitate this.
 *
 * Contrary to popular belief, [NSCalendar currentCalendar] is NOT a singleton.
 * A new instance is created each time you invoke the method.
 *
 * Use this method for extra fast access to a NSCalendar instance.
 **/
+ (NSCalendar *)cachedAutoupdatingCurrentCalendar;
@end


@implementation NSCalendar (ZeroDark)

/**
 * Similar to NSDateFormatter, NSCalendar's are somewhat expensive to create and they are not thread-safe.
 *
 * For speed, we prefer to use Apple's autoupdatingCurrentCalendar, and store it in the thread dictionary.
 * This class helps facilitate this.
 *
 * Contrary to popular belief, [NSCalendar currentCalendar] is NOT a singleton.
 * A new instance is created each time you invoke the method.
 *
 * Use this method for extra fast access to a NSCalendar instance.
 **/
+ (NSCalendar *)cachedAutoupdatingCurrentCalendar
{
	NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
	NSCalendar *calendar = [threadDictionary objectForKey:@"autoupdatingCurrentCalendar"];
	
	if (calendar == nil)
	{
		calendar = [NSCalendar autoupdatingCurrentCalendar];
		[threadDictionary setObject:calendar forKey:@"autoupdatingCurrentCalendar"];
	}
	
	return calendar;
}

@end


NSDate* ZDCEarlierDate(NSDate *date1, NSDate *date2)
{
	if (date1)
	{
		if (date2)
			return [date1 earlierDate:date2]; // if equal, returns date1
		else
			return date1;
	}
	else
	{
		return date2;
	}
}

NSDate* ZDCLaterDate(NSDate *date1, NSDate *date2)
{
	if (date1)
	{
		if (date2)
			return [date1 laterDate:date2]; // if equal, returns date1
		else
			return date1;
	}
	else
	{
		return date2;
	}
}

BOOL ZDCEqualDates(NSDate *date1, NSDate *date2)
{
	if (date1)
	{
		if (date2)
		{
			// date1 && date2
			return [date1 isEqualToDate:date2];
		}
		else
		{
			// date1 && !date2
			return NO;
		}
	}
	else if (date2)
	{
		// !date1 && date2
		return NO;
	}
	else
	{
		// !date1 && !date2
		return YES;
	}
}


@implementation NSDate (ZeroDark)

- (BOOL)isBefore:(NSDate *)date
{
	return ([self compare:date] == NSOrderedAscending);
}

- (BOOL)isAfter:(NSDate *)date
{
	return ([self compare:date] == NSOrderedDescending);
}

- (BOOL)isBeforeOrEqual:(NSDate *)date
{
	// [dateA compare:dateB]
	//
	// NSOrderedSame       : dateA & dateB are the same
	// NSOrderedDescending : dateA is later in time than dateB
	// NSOrderedAscending  : dateA is earlier in time than dateB
	
	NSComparisonResult result = [self compare:date];
	return (result == NSOrderedAscending ||
	        result == NSOrderedSame);
}

- (BOOL)isAfterOrEqual:(NSDate *)date
{
	// [dateA compare:dateB]
	//
	// NSOrderedSame       : dateA & dateB are the same
	// NSOrderedDescending : dateA is later in time than dateB
	// NSOrderedAscending  : dateA is earlier in time than dateB
	
	NSComparisonResult result = [self compare:date];
	return (result == NSOrderedDescending ||
	        result == NSOrderedSame);
}

- (NSString *)rfc3339String
{
    NSString *const kZuluTimeFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"; // ISO 8601 time.
	
    // Quinn "The Eskimo" pointed me to:
    // <https://developer.apple.com/library/ios/#qa/qa1480/_index.html>.
    // The contained advice recommends all internet time formatting to use US POSIX standards.
    NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"];
	
    NSTimeZone *gmtTimeZone = [NSTimeZone timeZoneForSecondsFromGMT: 0];
	
    // Use cached dateFormatter in thread dictionary
    NSDateFormatter *formatter =
    [ZDCDateFormatterCache dateFormatterWithLocalizedFormat:kZuluTimeFormat
                                               locale:enUSPOSIXLocale
                                             timeZone:gmtTimeZone];
	
    return [formatter stringFromDate:self];
}


+ (NSDate *)dateFromRfc3339String:(NSString *)dateString {
	
    // Create date formatter
    static NSDateFormatter *Rfc3339dateFormatter = nil;
    if (!Rfc3339dateFormatter) {
        NSLocale *en_US_POSIX = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        Rfc3339dateFormatter = [[NSDateFormatter alloc] init];
        [Rfc3339dateFormatter setLocale:en_US_POSIX];
        [Rfc3339dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
     }
	
    // Process date
    NSDate *date = nil;
    NSString *RFC3339String = [[NSString stringWithString:dateString] uppercaseString];
    RFC3339String = [RFC3339String stringByReplacingOccurrencesOfString:@"Z" withString:@"-0000"];
    // Remove colon in timezone as iOS 4+ NSDateFormatter breaks. See https://devforums.apple.com/thread/45837
    if (RFC3339String.length > 20) {
        RFC3339String = [RFC3339String stringByReplacingOccurrencesOfString:@":"
                                                                 withString:@""
                                                                    options:0
                                                                      range:NSMakeRange(20, RFC3339String.length-20)];
    }
    if (!date) { // 1996-12-19T16:39:57-0800
        [Rfc3339dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZZZ"];
        date = [Rfc3339dateFormatter dateFromString:RFC3339String];
    }
    if (!date) { // 1937-01-01T12:00:27.87+0020
        [Rfc3339dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSZZZ"];
        date = [Rfc3339dateFormatter dateFromString:RFC3339String];
    }
    if (!date) { // 1937-01-01T12:00:27
        [Rfc3339dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss"];
        date = [Rfc3339dateFormatter dateFromString:RFC3339String];
    }
    if (!date) NSLog(@"Could not parse RFC3339 date: \"%@\" Possibly invalid format.", dateString);
    return date;
	
}

- (NSDate *)dateWithZeroTime
{
	// Contrary to popular belief, [NSCalendar currentCalendar] is NOT a singleton.
	// A new instance is created each time you invoke the method.
	// Use SCCalendar for extra fast access to a NSCalendar instance.
	NSCalendar *calendar = [NSCalendar cachedAutoupdatingCurrentCalendar];
	
	NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitWeekday;
	NSDateComponents *comps = [calendar components:units fromDate:self];
	[comps setHour:0];
	[comps setMinute:0];
	[comps setSecond:0];
	
	return [calendar dateFromComponents:comps];
}

- (NSString *)whenString
{
	NSDate *selfZero = [self dateWithZeroTime];
	NSDate *todayZero = [[NSDate date] dateWithZeroTime];
	NSTimeInterval interval = [todayZero timeIntervalSinceDate:selfZero];
	NSTimeInterval dayDiff = interval/(60*60*24);
	
	// IMPORTANT:
	// This method is used often.
	// Creating a new dateFormatter each time is very expensive.
	// Instead we use the S4DateFormatter class,
	// which caches these things for us automatically (and is thread-safe).
	NSDateFormatter *formatter;
	
	if (dayDiff == 0) // today: show time only
	{
		formatter = [ZDCDateFormatterCache dateFormatterWithDateStyle: NSDateFormatterNoStyle
																			timeStyle: NSDateFormatterShortStyle];
	}
	else if (fabs(dayDiff) == 1) // tomorrow or yesterday: use relative date formatting
	{
		formatter = [ZDCDateFormatterCache dateFormatterWithDateStyle: NSDateFormatterMediumStyle
																			timeStyle: NSDateFormatterNoStyle
													 doesRelativeDateFormatting: YES];
	}
	else if (fabs(dayDiff) < 7) // within next/last week: show weekday
	{
		formatter = [ZDCDateFormatterCache dateFormatterWithLocalizedFormat:@"EEEE"];
	}
	else if (fabs(dayDiff) > (365 * 4)) // distant future or past: show year
	{
		formatter = [ZDCDateFormatterCache dateFormatterWithLocalizedFormat:@"y"];
	}
	else if (dayDiff < 0 && (fabs(dayDiff) < 90)) // format for < 90  days in the future
	{
		NSDateComponentsFormatter* durationFormatter = [[NSDateComponentsFormatter alloc] init];
		durationFormatter.unitsStyle = NSDateComponentsFormatterUnitsStyleShort;
		durationFormatter.allowedUnits = NSCalendarUnitDay;
		
		return [durationFormatter stringFromTimeInterval: fabs(interval) ];
	}
	else // show date only
	{
		formatter = [ZDCDateFormatterCache dateFormatterWithDateStyle: NSDateFormatterShortStyle
																			timeStyle: NSDateFormatterNoStyle];
	}
	
	return [formatter stringFromDate:self];
}

@end
