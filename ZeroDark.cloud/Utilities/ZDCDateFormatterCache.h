#import <Foundation/Foundation.h>

/**
* NSDateFormatter instances are expensive to create and they are not thread-safe.
* Apple recommends creating them once, and storing them in the thread dictionary.
* This class helps facilitate this.
**/

@interface ZDCDateFormatterCache : NSObject

#pragma mark Templates

/**
 * A template is NOT a specific format. It is ONLY a list of included format specifiers.
 * To be clear:
 *
 * This is --NOT-- a template: "MM/dd/yy hh:ss"    <-- BAD !!! NOT a template !!!
 *
 *
 * EXAMPLE 1:
 * If you wanted to display the time to the user (hours + minutes), the template would be:
 *
 * TIME TEMPLATE = "jm" --> j = preferred hour format (either h or H), m = minutes
 *
 * The result may be something like "h:m a", "H:m", or "H-m" depending on locale.
 *
 * Notice the last format uses the proper '-' character instead of ':'.
 * This highlights why templates only specify desired format specifiers.
 *
 * EXAMPLE 2:
 * If you wanted to display the date to the user (month, day, weekday), the template would be:
 *
 * DATE TEMPLATE = "EdMMM" --> E = day of week (Tues), d = day of month, MMM = month (Sept)
 *
 * The result for en_US : "EEE, MMM d"
 * The result for en_GB : "EEE d MMM"
 *
 * The template is passed to the built-in [NSDateFormatter dateFormatFromTemplate:options:locale:] method.
 *
 * After converting the date format template to the current locale,
 * this method invokes dateFormatterWithLocalizedFormat:timeZone:cache:
 * and passes a nil timeZone and YES for the cache parameter.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)localizedDateFormatterFromTemplate:(NSString *)templateStringWithoutAnyFormatting;

/**
 * A template is NOT a specific format. It is ONLY a list of included format specifiers.
 * To be clear:
 *
 * This is --NOT-- a template: "MM/dd/yy hh:ss"    <-- BAD !!! NOT a template !!!
 *
 *
 * For a full discussion, see localizedDateFormatterFromTemplate.
 *
 * After converting the date format template to the current locale,
 * this method invokes dateFormatterWithLocalizedFormat:timeZone:cache:.
 *
 * IMPORTANT NOTE:
 *
 * IF you choose to cache the formatter, then you MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)localizedDateFormatterFromTemplate:(NSString *)templateStringWithoutAnyFormatting
                                                  cache:(BOOL)shouldCacheInThreadDictionary;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Styles
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a dateFormatter with the given style(s).
 *
 * @param dateStyle
 *     The date style of the formatter, such as NSDateFormatterShortStyle for output like "11/23/37"
 *
 * @param timeStyle
 *     The time style of the formatter, such as NSDateFormatterShortStyle for output like "3:30pm"
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithDateStyle:(NSDateFormatterStyle)dateStyle
                                      timeStyle:(NSDateFormatterStyle)timeStyle;

/**
 * Returns a dateFormatter with the given style(s).
 *
 * @param dateStyle
 *     The date style of the formatter, such as NSDateFormatterShortStyle for output like "11/23/37"
 *
 * @param timeStyle
 *     The time style of the formatter, such as NSDateFormatterShortStyle for output like "3:30pm"
 *
 * @param doesRelativeDateFormatting
 *     Whether the dateFormatter uses phrases such as “today” and “tomorrow” for the date component.
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithDateStyle:(NSDateFormatterStyle)dateStyle
                                      timeStyle:(NSDateFormatterStyle)timeStyle
                     doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting;

/**
 * Returns a dateFormatter with the given style(s).
 *
 * @param dateStyle
 *     The date style of the formatter, such as NSDateFormatterShortStyle for output like "11/23/37"
 *
 * @param timeStyle
 *     The time style of the formatter, such as NSDateFormatterShortStyle for output like "3:30pm"
 *
 * @param doesRelativeDateFormatting
 *     Whether the dateFormatter uses phrases such as “today” and “tomorrow” for the date component.
 *
 * @param shouldCacheInThreadDictionary
 *     If the shouldCacheInThreadDictionary is YES,
 *     this method will cache NSDateFormatter instances in the thread dictionary.
 *     Otherwise a new NSDateFormatter instance is created.
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithDateStyle:(NSDateFormatterStyle)dateStyle
                                      timeStyle:(NSDateFormatterStyle)timeStyle
                     doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting
                                          cache:(BOOL)shouldCacheInThreadDictionary;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Formats
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Given an alreday-localized date format string, returns a proper NSDateFormatter instance.
 *
 * @param localizedDateFormatString
 *     An alreday-localized date format string, such as "HH:mm:ss".
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString;

/**
 * Given an alreday-localized date format string, and optional config, returns a proper NSDateFormatter instance.
 *
 * @param localizedDateFormatString
 *     An alreday-localized date format string, such as "HH:mm:ss".
 *
 * @param locale
 *     If a locale is passed, then the returned dateFormatter will have its locale set to the given locale.
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale;

/**
 * Given an alreday-localized date format string, and optional config, returns a proper NSDateFormatter instance.
 *
 * @param localizedDateFormatString
 *     An alreday-localized date format string, such as "HH:mm:ss".
 *
 * @param locale
 *     If a locale is passed, then the returned dateFormatter will have its locale set to the given locale.
 *
 * @param timeZone
 *     If a timeZone is passed, then the returned dateFormatter will have its timeZone set to the given timeZone.
 *     This is particularly useful if you're parsing strings without timezone information,
 *     but which are in a known timezone such as GMT.
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * You MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
                                             timeZone:(NSTimeZone *)timeZone;

/**
 * Given an already-localized date format string, and optional config, returns a proper NSDateFormatter instance.
 *
 * @param localizedDateFormatString
 *     An alreday-localized date format string, such as "HH:mm:ss".
 *
 * @param locale
 *     If a locale is passed, then the returned dateFormatter will have its locale set to the given locale.
 *
 * @param timeZone
 *     If a timeZone is passed, then the returned dateFormatter will have its timeZone set to the given timeZone.
 *     This is particularly useful if you're parsing strings without timezone information,
 *     but which are in a known timezone such as GMT.
 *
 * @param doesRelativeDateFormatting
 *     Whether the dateFormatter uses phrases such as “today” and “tomorrow” for the date component.
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * IF you choose to cache the formatter, then you MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
                                             timeZone:(NSTimeZone *)timeZone
                           doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting;

/**
 * Given an already-localized date format string, and optional config, returns a proper NSDateFormatter instance.
 *
 * @param localizedDateFormatString
 *     An alreday-localized date format string, such as "HH:mm:ss".
 *
 * @param locale
 *     If a locale is passed, then the returned dateFormatter will have its locale set to the given locale.
 *
 * @param timeZone
 *     If a timeZone is passed, then the returned dateFormatter will have its timeZone set to the given timeZone.
 *     This is particularly useful if you're parsing strings without timezone information,
 *     but which are in a known timezone such as GMT.
 *
 * @param shouldCacheInThreadDictionary
 *     If the shouldCacheInThreadDictionary is YES,
 *     this method will cache NSDateFormatter instances in the thread dictionary.
 *     Otherwise a new NSDateFormatter instance is created.
 *
 * @return
 *     If a pre-cached version already exists for this thread, it is returned.
 *     Otherwise a new NSDateFormatter instance is created, cached, and returned.
 *
 * IMPORTANT NOTE:
 *
 * IF you choose to cache the formatter, then you MUST NOT change the formatter that is returned to you.
 * Do NOT change its dateFormat, locale, timeZone, or configure it in any way.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
                                             timeZone:(NSTimeZone *)timeZone
                           doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting
                                                cache:(BOOL)shouldCacheInThreadDictionary;


@end
#pragma mark - 

@interface NSByteCountFormatterCache : NSObject


/** 
 same as above but for byte count formatting
 **/

+(NSByteCountFormatter*) byteCountFormatterWithCountStyle:(NSByteCountFormatterCountStyle)countStyle
                                  includesActualByteCount:(BOOL)includesActualByteCount
                                                    cache:(BOOL)shouldCacheInThreadDictionary;

+(NSByteCountFormatter*) byteCountFormatterForFileSizes;



@end
