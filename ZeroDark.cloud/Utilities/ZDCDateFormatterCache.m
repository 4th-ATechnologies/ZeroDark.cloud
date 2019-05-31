#import "ZDCDateFormatterCache.h"

@implementation ZDCDateFormatterCache


/**
 * This method is extensively documented in the header file.
 * Please read the header file as "templates" can be confusing.
 **/
+ (NSDateFormatter *)localizedDateFormatterFromTemplate:(NSString *)templateString
{
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSString *localizedDateFormatString = [NSDateFormatter dateFormatFromTemplate:templateString
                                                                          options:0
                                                                           locale:currentLocale];
    
    return [self dateFormatterWithLocalizedFormat:localizedDateFormatString
                                           locale:currentLocale
                                         timeZone:nil
                       doesRelativeDateFormatting:NO
                                            cache:YES];
}

/**
 * This method is extensively documented in the header file.
 * Please read the header file as "templates" can be confusing.
 **/
+ (NSDateFormatter *)localizedDateFormatterFromTemplate:(NSString *)templateString
                                                  cache:(BOOL)shouldCacheInThreadDictionary
{
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSString *localizedDateFormatString = [NSDateFormatter dateFormatFromTemplate:templateString
                                                                          options:0
                                                                           locale:currentLocale];
    
    return [self dateFormatterWithLocalizedFormat:localizedDateFormatString
                                           locale:currentLocale
                                         timeZone:nil
                       doesRelativeDateFormatting:NO
                                            cache:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Styles
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithDateStyle:(NSDateFormatterStyle)dateStyle
                                      timeStyle:(NSDateFormatterStyle)timeStyle
{
    return [self dateFormatterWithDateStyle:dateStyle
                                  timeStyle:timeStyle
                 doesRelativeDateFormatting:NO
                                      cache:YES];
}

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithDateStyle:(NSDateFormatterStyle)dateStyle
                                      timeStyle:(NSDateFormatterStyle)timeStyle
                     doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting
{
    return [self dateFormatterWithDateStyle:dateStyle
                                  timeStyle:timeStyle
                 doesRelativeDateFormatting:doesRelativeDateFormatting
                                      cache:YES];
}

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithDateStyle:(NSDateFormatterStyle)dateStyle
                                      timeStyle:(NSDateFormatterStyle)timeStyle
                     doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting
                                          cache:(BOOL)shouldCacheInThreadDictionary
{
    if (shouldCacheInThreadDictionary)
    {
        NSString *key = [NSString stringWithFormat:@"S4DateFormatter(%lu,%lu) %@",
                         (unsigned long)dateStyle,
                         (unsigned long)timeStyle,
                         doesRelativeDateFormatting ? @"Y" : @"N"];
        
        NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
        NSDateFormatter *dateFormatter = [threadDictionary objectForKey:key];
        
        if (dateFormatter == nil)
        {
            dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateStyle = dateStyle;
            dateFormatter.timeStyle = timeStyle;
            
            if (doesRelativeDateFormatting)
                dateFormatter.doesRelativeDateFormatting = doesRelativeDateFormatting;
            
            [threadDictionary setObject:dateFormatter forKey:key];
        }
        
        return dateFormatter;
    }
    else
    {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateStyle = dateStyle;
        dateFormatter.timeStyle = timeStyle;
        
        if (doesRelativeDateFormatting)
            dateFormatter.doesRelativeDateFormatting = doesRelativeDateFormatting;
        
        return dateFormatter;
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Formats
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
{
    return [self dateFormatterWithLocalizedFormat:localizedDateFormatString
                                           locale:nil
                                         timeZone:nil
                       doesRelativeDateFormatting:NO
                                            cache:YES];
}

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
{
    return [self dateFormatterWithLocalizedFormat:localizedDateFormatString
                                           locale:locale
                                         timeZone:nil
                       doesRelativeDateFormatting:NO
                                            cache:YES];
}

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
                                             timeZone:(NSTimeZone *)timeZone
{
    return [self dateFormatterWithLocalizedFormat:localizedDateFormatString
                                           locale:locale
                                         timeZone:timeZone
                       doesRelativeDateFormatting:NO
                                            cache:YES];
}

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
                                             timeZone:(NSTimeZone *)timeZone
                           doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting;
{
    return [self dateFormatterWithLocalizedFormat:localizedDateFormatString
                                           locale:locale
                                         timeZone:timeZone
                       doesRelativeDateFormatting:doesRelativeDateFormatting
                                            cache:YES];
}

/**
 * See header file for documentation.
 **/
+ (NSDateFormatter *)dateFormatterWithLocalizedFormat:(NSString *)localizedDateFormatString
                                               locale:(NSLocale *)locale
                                             timeZone:(NSTimeZone *)timeZone
                           doesRelativeDateFormatting:(BOOL)doesRelativeDateFormatting
                                                cache:(BOOL)shouldCacheInThreadDictionary
{
    if (shouldCacheInThreadDictionary)
    {
        NSString *key = [NSString stringWithFormat:@"S4DateFormatter(%@) %@ %@ %@",
                         localizedDateFormatString,
                         locale ? [locale localeIdentifier] : @"nil",
                         timeZone ? [timeZone name] : @"nil",
                         doesRelativeDateFormatting ? @"Y" : @"N"];
        
        NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
        NSDateFormatter *dateFormatter = [threadDictionary objectForKey:key];
        
        if (dateFormatter == nil)
        {
            dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateFormat = localizedDateFormatString;
            
            if (locale)
                dateFormatter.locale = locale;
            
            if (timeZone)
                dateFormatter.timeZone = timeZone;
            
            if (doesRelativeDateFormatting)
                dateFormatter.doesRelativeDateFormatting = doesRelativeDateFormatting;
            
            [threadDictionary setObject:dateFormatter forKey:key];
        }
        
        return dateFormatter;
    }
    else
    {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = localizedDateFormatString;
        
        if (locale)
            dateFormatter.locale = locale;
        
        if (timeZone)
            dateFormatter.timeZone = timeZone;
        
        if (doesRelativeDateFormatting)
            dateFormatter.doesRelativeDateFormatting = doesRelativeDateFormatting;
        
        return dateFormatter;
    }
}

@end

/**
 * See header file for documentation.
 **/

@implementation NSByteCountFormatterCache


+(NSByteCountFormatter*) byteCountFormatterWithCountStyle:(NSByteCountFormatterCountStyle)countStyle
                                  includesActualByteCount:(BOOL)includesActualByteCount
                                                    cache:(BOOL)shouldCacheInThreadDictionary

{
    if (shouldCacheInThreadDictionary)
    {
        NSString *key = [NSString stringWithFormat:@"S4SByteCountFormatter(%lu) %@",
                         (unsigned long)countStyle,
                         includesActualByteCount ? @"Y" : @"N"];
        
        
        NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
        NSByteCountFormatter *bcFormatter = [threadDictionary objectForKey:key];
        
        if (bcFormatter == nil)
        {
            bcFormatter = [[NSByteCountFormatter alloc] init];
            bcFormatter.includesActualByteCount = includesActualByteCount;
            bcFormatter.countStyle = countStyle;
            
            [threadDictionary setObject:bcFormatter forKey:key];
        }
        
        return bcFormatter;
        
    }
    else
    {
        NSByteCountFormatter* bcFormatter = [[NSByteCountFormatter alloc] init];
        bcFormatter.includesActualByteCount = includesActualByteCount;
        bcFormatter.countStyle = countStyle;
        return bcFormatter;
    }
}

+(NSByteCountFormatter*) byteCountFormatterForFileSizes
{
    return [self byteCountFormatterWithCountStyle:NSByteCountFormatterCountStyleDecimal
                          includesActualByteCount:YES
                                            cache:YES];
}

@end
