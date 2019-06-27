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

NSDate *_Nullable ZDCEarlierDate(NSDate *_Nullable date1, NSDate *_Nullable date2);
NSDate *_Nullable ZDCLaterDate(NSDate *_Nullable date1, NSDate *_Nullable date2);
BOOL ZDCEqualDates(NSDate *_Nullable date1, NSDate *_Nullable date2);


@interface NSDate (ZeroDark)


- (BOOL)isBefore:(NSDate *)date;
- (BOOL)isAfter:(NSDate *)date;

- (BOOL)isBeforeOrEqual:(NSDate *)date;
- (BOOL)isAfterOrEqual:(NSDate *)date;

+ (NSDate *)dateFromRfc3339String:(NSString *)dateString;
- (NSString *)rfc3339String;

- (NSString *)whenString;

@end

NS_ASSUME_NONNULL_END
