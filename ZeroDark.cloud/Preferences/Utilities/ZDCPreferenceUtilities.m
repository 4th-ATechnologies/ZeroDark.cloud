/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCPreferenceUtilities.h"

@implementation ZDCPreferenceUtilities

+ (BOOL)boolValueFromObject:(id)object
{
	if ([object respondsToSelector:@selector(boolValue)])
		return [object boolValue];
	else
		return NO;
}

+ (float)floatValueFromObject:(id)object
{
	if ([object respondsToSelector:@selector(floatValue)])
		return [object floatValue];
	else
		return 0.0F;
}

+ (double)doubleValueFromObject:(id)object
{
	if ([object respondsToSelector:@selector(doubleValue)])
		return [object doubleValue];
	else
		return 0.0;
}

+ (NSInteger)integerValueFromObject:(id)object
{
	if ([object respondsToSelector:@selector(integerValue)])
		return [object integerValue];
	else
		return (NSInteger)0;
}

+ (NSUInteger)unsignedIntegerValueFromObject:(id)object
{
	if ([object respondsToSelector:@selector(unsignedIntegerValue)])
		return [object unsignedIntegerValue];
	else
		return (NSUInteger)0;
}

+ (NSString *)stringValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSString class]])
		return (NSString *)object;
	else if ([object respondsToSelector:@selector(stringValue)])
		return [object stringValue];
	else
		return nil;
}

+ (NSNumber *)numberValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSNumber class]])
		return (NSNumber *)object;
	else
		return nil;
}

+ (NSData *)dataValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSData class]])
		return (NSData *)object;
	else
		return nil;
}

@end
