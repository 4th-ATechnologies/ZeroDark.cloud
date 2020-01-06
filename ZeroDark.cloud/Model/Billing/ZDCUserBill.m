/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserBillPrivate.h"

#define CLAMP(min, num, max) (MAX(min, MIN(max, num)))

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
@implementation ZDCUserBill {
	
	ZDCUserBillMetadata *_metadata;
	NSDictionary<NSString*, ZDCAppBill*> *_apps;
}

@synthesize rawDictionary = _dict;

@dynamic metadata;
@dynamic rates;
@dynamic apps;

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary
{
	if ((self = [super init]))
	{
		_dict = [rawDictionary copy];
	}
	return self;
}

- (ZDCUserBillMetadata *)metadata
{
	ZDCUserBillMetadata *result = _metadata;
	if (result == nil)
	{
		NSDictionary *dict = nil;
		
		id value = _dict[@"metadata"];
		if ([value isKindOfClass:[NSDictionary class]]) {
			dict = (NSDictionary *)value;
		} else {
			dict = [NSDictionary dictionary];
		}
		
		result = [[ZDCUserBillMetadata alloc] initWithDictionary:dict];
		_metadata = result; // cache it
	}
	
	return result;
}

- (NSDictionary *)rates
{
	id value = _dict[@"rates"];
	if ([value isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary *)value;
	}
	
	return [NSDictionary dictionary];
}

- (NSDictionary<NSString*, ZDCAppBill*> *)apps
{
	NSDictionary<NSString*, ZDCAppBill*> *result = _apps;
	if (result == nil)
	{
		NSMutableDictionary<NSString*, ZDCAppBill*> *mResult = nil;
		
		id value = _dict[@"apps"];
		if ([value isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *container = (NSDictionary *)value;
			mResult = [NSMutableDictionary dictionaryWithCapacity:(container.count + 1)];
			
			[container enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
				
				if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]])
				{
					NSString *treeID = (NSString *)key;
					NSDictionary *app_dict = (NSDictionary *)obj;
					
					mResult[treeID] = [[ZDCAppBill alloc] initWithDictionary:app_dict];
				}
			}];
		}
		
		value = _dict[@"totals"];
		if ([value isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *container = (NSDictionary *)value;
			
			if (mResult == nil) {
				mResult = [NSMutableDictionary dictionaryWithCapacity:1];
			}
			
			mResult[@"*"] = [[ZDCAppBill alloc] initWithDictionary:container];
		}
		
		result = mResult ? [mResult copy] : [[NSDictionary alloc] init];
		_apps = result; // cache it
	}
	
	return result;
}

- (nullable ZDCAppCost *)calculateCost:(NSString *)treeID
{
	ZDCAppBill *appBill = self.apps[treeID ?: @"*"];
	if (appBill == nil) {
		return nil;
	}
	
	NSUInteger year = self.metadata.year;
	NSUInteger month = self.metadata.month;
	
	NSDateComponents *dateComponents = [[NSDateComponents alloc] init];
	dateComponents.year = year;
	dateComponents.month = month;
	dateComponents.day = 1;
	dateComponents.hour = 0;
	dateComponents.minute = 0;
	dateComponents.second = 0;
	dateComponents.nanosecond = 0;
	
	NSCalendar *calendar = [NSCalendar currentCalendar];
	calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	
	NSDate *beginningOfMonth = [calendar dateFromComponents:dateComponents];
	NSDate *endOfMonth = [calendar dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:beginningOfMonth options:0];
	
	uint64_t ts_beginningOfMonth = (uint64_t)([beginningOfMonth timeIntervalSince1970] * 1000);
	uint64_t ts_endOfMonth = (uint64_t)([endOfMonth timeIntervalSince1970] * 1000);
	
	uint64_t ts_monthSpan = ts_endOfMonth - ts_beginningOfMonth;
	
	double hours_in_month = ts_monthSpan / (1000 * 60 * 60);
	
	uint64_t ts = (uint64_t)([appBill.timestamp timeIntervalSince1970] * 1000);
		
	int64_t elapsed   = (int64_t)(ts - ts_beginningOfMonth);
	int64_t remaining = (int64_t)(ts_endOfMonth - ts);
			
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wambiguous-macro"
	elapsed   = CLAMP((int64_t)0, elapsed,   (int64_t)ts_monthSpan); // careful: casting is required !
	remaining = CLAMP((int64_t)0, remaining, (int64_t)ts_monthSpan); // careful: casting is required !
#pragma clang pop
	
	ZDCAppCost *appCost = [[ZDCAppCost alloc] init];
	appCost.monthStart = beginningOfMonth;
	appCost.monthEnd = endOfMonth;
	appCost.elapsed = (double)elapsed / 1000.0;
	appCost.remaining = (double)remaining / 1000.0;
	
	const uint64_t KB_in_bytes  = 1000;
	const uint64_t MB_in_bytes  = 1000 * KB_in_bytes;
	const uint64_t GB_in_bytes  = 1000 * MB_in_bytes;
	const uint64_t TB_in_bytes  = 1000 * GB_in_bytes;
	const uint64_t PB_in_bytes  = 1000 * TB_in_bytes;
	
	const uint64_t KiB_in_bytes  = 1024;
	const uint64_t MiB_in_bytes  = 1024 * KiB_in_bytes;
	const uint64_t GiB_in_bytes  = 1024 * MiB_in_bytes;
	const uint64_t TiB_in_bytes  = 1024 * GiB_in_bytes;
	const uint64_t PiB_in_bytes  = 1024 * TiB_in_bytes;

	// From server:
	//
	// export interface BillingRatesRate {
	//   flat  ?: [number, string|number],                 // [price_per_unit, unit_size]
	//   range ?: [number, string|number, string|number][] // [price_per_unit, unit_size, range_size]
	// }
	//
	// So this helper converts the string|number to a double.
	//
	double (^valueToDouble)(id) = ^double (id value){
		
		if ([value isKindOfClass:[NSNumber class]]) {
			return [(NSNumber *)value doubleValue];
		}
		
		if (![value isKindOfClass:[NSString class]]) {
			return 0.0;
		}
		
		NSString *str = (NSString *)value;
		
		if ([str isEqualToString:@"∞"]) {
			return DBL_MAX;
		}
		
		NSArray<NSString *> *split = [str componentsSeparatedByString:@" "];
		
		// Caution: commas break strtoull function.
		// strtoull("10,000", NULL, 10) => 10 !
		//
		NSString *numStr = [split[0] stringByReplacingOccurrencesOfString:@"," withString:@""];
		uint64_t number = strtoull([numStr UTF8String], NULL, 10);
		
		if (split.count == 1)
		{
			return number;
		}
		else
		{
			uint64_t multiplier = 1;
			NSString *type = split[1];
			
			     if ([type hasPrefix:@"KB"]) { multiplier =  KB_in_bytes; }    // KB, KB/m, KBM
			else if ([type hasPrefix:@"MB"]) { multiplier =  MB_in_bytes; }    // MB, MB/m, MBM
			else if ([type hasPrefix:@"GB"]) { multiplier =  GB_in_bytes; }    // GB, GB/m, GBM
			else if ([type hasPrefix:@"TB"]) { multiplier =  TB_in_bytes; }    // TB, TB/m, TBM
			else if ([type hasPrefix:@"PB"]) { multiplier =  PB_in_bytes; }    // PB, PB/m, PBM
			
			else if ([type hasPrefix:@"KiB"]) { multiplier =  KiB_in_bytes; }  // KiB, KiB/m, KiBM
			else if ([type hasPrefix:@"MiB"]) { multiplier =  MiB_in_bytes; }  // MiB, MiB/m, MiBM
			else if ([type hasPrefix:@"GiB"]) { multiplier =  GiB_in_bytes; }  // GiB, GiB/m, GiBM
			else if ([type hasPrefix:@"TiB"]) { multiplier =  TiB_in_bytes; }  // TiB, TiB/m, TiBM
			else if ([type hasPrefix:@"PiB"]) { multiplier =  PiB_in_bytes; }  // PiB, PiB/m, PiBM
			
			return number * multiplier;
		}
	};
	
	double (^calculateServiceCost)(double, NSDictionary *) = ^double (double value, NSDictionary *rateContainer){
		
		NSArray *flat_pricing  = rateContainer[@"flat"];
		NSArray *range_pricing = rateContainer[@"range"];
		
		if (flat_pricing)
		{
			// [price_per_unit, unit_size]
			//
			// Examples:
			// - [0.004, "10,000"] => 0.4 cents per 10,000 => So 5,000 would cost 0.2 cents (i.e. $0.002)
			// - [0.50, "1,000,000"] => 50 cents per 1 million = > So 100 would cost $0.00005
			
			double price_per_unit = valueToDouble(flat_pricing[0]);
			double unit_size      = valueToDouble(flat_pricing[1]);
			
			if (unit_size == DBL_MAX) {
				return 0.0;
			} else {
				return ((value / unit_size) * price_per_unit);
			}
		}
		else if (range_pricing)
		{
			// [
			//   [price_per_unit, unit_size, first_range_size],
			//   [price_per_unit, unit_size, second_range_size],
			//   ...
			// ]
			//
			// Example: (bandwidth)
			//
			// [0.09,  "1 GB", "10 TB"],
			// [0.085, "1 GB", "40 TB"],
			// [0.070, "1 GB", "100 TB"],
			// [0.050, "1 GB", "∞"]
			//
			// Translation:
			// - The first 10 terabytes of bandwidth are charged a 9 cents per gigabyte.
			// - After that, the next 40 terabytes of bandwidth are charged at 8.5 cents per gigabyte.
			//   In other words, the range: 10 TB - 50 TB
			// - After that, the next 100 terabytes of bandwidth are charged at 7 cents per gigabyte.
			//   In other words, the range: 50 TB - 150 TB
			// - After that, every gigabyte is charged at 5 cents per gigabyte.
			//   In other words, the range: 150 TB - Infinity
			
			double cost = 0.0;
			NSUInteger range_index = 0;
			
			while (value > 0)
			{
				NSArray *range = range_pricing[range_index];
				
				double price_per_unit = valueToDouble(range[0]);
				double unit_size      = valueToDouble(range[1]);
				double range_size     = valueToDouble(range[2]);
				
				if (value > range_size)
				{
					cost += ((range_size / unit_size) * price_per_unit);
					value -= range_size;
				}
				else
				{
					cost += ((value / unit_size) * price_per_unit);
					value = 0;
				}
				
				range_index++;
			}
			
			return cost;
		}
		else
		{
			return 0.0;
		}
	};
	
	NSDictionary *rates = self.rates;
	
	NSDictionary * rate_s3_storage          = rates[@"s3"][@"gigabyteMonths"];
	if (!rate_s3_storage) rate_s3_storage   = rates[@"s3"][@"byteHours"];      // Old server name
	
	NSDictionary * rate_s3_getCount         = rates[@"s3"][@"getCount"];
	NSDictionary * rate_s3_putCount         = rates[@"s3"][@"putCount"];
	NSDictionary * rate_sns_publishCount    = rates[@"sns"][@"publishCount"];
	NSDictionary * rate_sns_mobilePushCount = rates[@"sns"][@"mobilePushCount"];
	NSDictionary * rate_lambda_requestCount = rates[@"lambda"][@"requestCount"];
	NSDictionary * rate_lambda_millisCount  = rates[@"lambda"][@"millisCount"];
	NSDictionary * rate_bandwidth_byteCount = rates[@"bandwidth"][@"byteCount"];
	
	ZDCAppCostDetails* (^calculateCost)(ZDCAppBill*) = ^ZDCAppCostDetails* (ZDCAppBill *bill){
		
		ZDCAppCostDetails *cost = [[ZDCAppCostDetails alloc] init];
		
		cost.bandwidth_byteCount = calculateServiceCost(bill.bandwidth_byteCount, rate_bandwidth_byteCount);
		
		cost.s3_getCount += calculateServiceCost(bill.s3_getCount, rate_s3_getCount);
		cost.s3_putCount += calculateServiceCost(bill.s3_putCount, rate_s3_putCount);
		
		NSMutableDictionary<NSString*, NSNumber*> *s3_storage          = [NSMutableDictionary dictionary];
		NSMutableDictionary<NSString*, NSNumber*> *s3_multipartStorage = [NSMutableDictionary dictionary];
		
		[bill.s3_storage enumerateKeysAndObjectsUsingBlock:
			^(NSString *storageType, ZDCStorageBill *storageBill, BOOL *stop)
		{
			double byte_months = storageBill.byteHours / hours_in_month;
			
			double value = calculateServiceCost(byte_months, rate_s3_storage);
			s3_storage[storageType] = @(value);
		}];
		
		[bill.s3_multipartStorage enumerateKeysAndObjectsUsingBlock:
			^(NSString *multipartID, ZDCStorageBill *storageBill, BOOL *stop)
		{
			double byte_months = storageBill.byteHours / hours_in_month;
			
			double value = calculateServiceCost(byte_months, rate_s3_storage);
			s3_multipartStorage[multipartID] = @(value);
		}];
		
		cost.s3_storage = [s3_storage copy];
		cost.s3_multipartStorage = [s3_multipartStorage copy];
		
		cost.sns_mobilePushCount = calculateServiceCost(bill.sns_mobilePushCount, rate_sns_mobilePushCount);
		cost.sns_publishCount    = calculateServiceCost(bill.sns_publishCount,    rate_sns_publishCount);
		
		cost.lambda_millisCount  = calculateServiceCost(bill.lambda_millisCount,  rate_lambda_millisCount);
		cost.lambda_requestCount = calculateServiceCost(bill.lambda_requestCount, rate_lambda_requestCount);
		
		return cost;
	};
	
	if (self.metadata.isFinal)
	{
		appCost.finalCost = calculateCost(appBill);
	}
	else
	{
		appCost.accumulatedCost = calculateCost(appBill);
		
		// Project current usage patterns to the end of the month.
		
		double multiplier = 1.0 + ((double)remaining / (double)elapsed);
		
		double estimated_bandwidth_byteCount = appBill.bandwidth_byteCount * multiplier;
		double estimated_s3_getCount         = appBill.s3_getCount         * multiplier;
		double estimated_s3_putCount         = appBill.s3_putCount         * multiplier;
		double estimated_sns_mobilePushCount = appBill.sns_mobilePushCount * multiplier;
		double estimated_sns_publishCount    = appBill.sns_publishCount    * multiplier;
		double estimated_lambda_millisCount  = appBill.lambda_millisCount  * multiplier;
		double estimated_lambda_requestCount = appBill.lambda_requestCount * multiplier;
		
		NSMutableDictionary<NSString*, NSDictionary*> *estimated_s3_storage          = [NSMutableDictionary dictionary];
		NSMutableDictionary<NSString*, NSDictionary*> *estimated_s3_multipartStorage = [NSMutableDictionary dictionary];
		
		double remaining_hours = (double)remaining / (double)(1000 * 60 * 60);
		
		[appBill.s3_storage enumerateKeysAndObjectsUsingBlock:
			^(NSString *storageType, ZDCStorageBill *storageBill, BOOL *stop)
		{
			double remaining_byteHours = storageBill.byteCount * remaining_hours;
			double estimated_byteHours = storageBill.byteHours + remaining_byteHours;
			
			estimated_s3_storage[storageType] = @{
				@"byteCount" : @(storageBill.byteCount),
				@"byteHours" : @(estimated_byteHours)
			};
		}];
		
		[appBill.s3_multipartStorage enumerateKeysAndObjectsUsingBlock:
			^(NSString *multipartID, ZDCStorageBill *storageBill, BOOL *stop)
		{
			double remaining_byteHours = storageBill.byteCount * remaining_hours;
			double estimated_byteHours = storageBill.byteHours + remaining_byteHours;
			
			estimated_s3_multipartStorage[multipartID] = @{
				@"byteCount" : @(storageBill.byteCount),
				@"byteHours" : @(estimated_byteHours)
			};
		}];
		
		NSDictionary *estimate = @{
			@"bandwidth": @{
				@"byteCount" : @(estimated_bandwidth_byteCount)
			},
			@"s3": @{
				@"getCount"  : @(estimated_s3_getCount),
				@"putCount"  : @(estimated_s3_putCount),
				@"storage"   : [estimated_s3_storage copy],
				@"multipart" : [estimated_s3_multipartStorage copy]
			},
			@"sns": @{
				@"mobilePushCount" : @(estimated_sns_mobilePushCount),
				@"publishCount"    : @(estimated_sns_publishCount)
			},
			@"lambda": @{
				@"millisCount"  : @(estimated_lambda_millisCount),
				@"requestCount" : @(estimated_lambda_requestCount)
			}
		};
		
		ZDCAppBill *estimatedBill = [[ZDCAppBill alloc] initWithDictionary:estimate];
		
		appCost.estimatedBill = estimatedBill;
		appCost.estimatedCost = calculateCost(estimatedBill);
	}
	
	return appCost;
}

- (NSString *)debugDescription
{
	return [NSString stringWithFormat:@"<%@:%p>: %@", NSStringFromClass([self class]), self, _dict];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Example:
//
// metadata =     {
//   final = 0;
//   lastChange = 1577750443878;
//   month = 11;
//   "month_str" = december;
//   timezoneOffset = 0;
//   version = 1;
//   year = 2019;
// };

/**
 * See header file for description.
 */
@implementation ZDCUserBillMetadata

@synthesize rawDictionary = _dict;

@dynamic isFinal;
@dynamic month;
@dynamic year;
@dynamic timestamp;

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary
{
	if ((self = [super init]))
	{
		_dict = [rawDictionary copy];
	}
	return self;
}

- (BOOL)isFinal
{
	id value = _dict[@"final"];
	if ([value isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *)value boolValue];
	}
	
	return NO;
}

- (NSInteger)month
{
	id value = _dict[@"month"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		// javascript months are 0-based (january==0, ..., december=11)
		// NSCalendar months are 1-based (january==1, ..., december=12)
		
		NSInteger javascript_month = [(NSNumber *)value integerValue];
		NSInteger nscalendar_month = javascript_month + 1;
		
		if (nscalendar_month >= 1 || nscalendar_month <= 12) {
			return nscalendar_month;
		}
	}
	
	return 1;
}

- (NSInteger)year
{
	id value = _dict[@"year"];
	if ([value isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *)value integerValue];
	}
	
	return 0;
}

- (NSDate *)timestamp
{
	id value = _dict[@"lastChange"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		// javascript dates are in milliseconds since unix epoch
		
		double millis = [(NSNumber *)value doubleValue];
		double seconds = millis / 1000;
		
		return [NSDate dateWithTimeIntervalSince1970:seconds];
	}
	
	return [NSDate dateWithTimeIntervalSince1970:0];
}

- (NSString *)debugDescription
{
	return [NSString stringWithFormat:@"<%@:%p>: %@", NSStringFromClass([self class]), self, _dict];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
@implementation ZDCAppBill {
	
	NSDictionary<NSString*, ZDCStorageBill*> *_s3_storage;
	NSDictionary<NSString*, ZDCStorageBill*> *_s3_multipartStorage;
}

@synthesize rawDictionary = _dict;

@dynamic bandwidth_byteCount;
@dynamic s3_getCount;
@dynamic s3_putCount;
@dynamic s3_storage;
@dynamic s3_multipartStorage;
@dynamic sns_mobilePushCount;
@dynamic s3_storage_total;
@dynamic s3_multipartStorage_total;
@dynamic sns_publishCount;
@dynamic lambda_millisCount;
@dynamic lambda_requestCount;
@dynamic timestamp;

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary
{
	if ((self = [super init]))
	{
		_dict = [rawDictionary copy];
	}
	return self;
}

- (uint64_t)bandwidth_byteCount
{
	id value = _dict[@"bandwidth"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"byteCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (uint64_t)s3_getCount
{
	id value = _dict[@"s3"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"getCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (uint64_t)s3_putCount
{
	id value = _dict[@"s3"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"putCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (NSDictionary<NSString*, ZDCStorageBill*> *)s3_storage
{
	NSDictionary<NSString*, ZDCStorageBill*> *result = _s3_storage;
	if (result == nil)
	{
		NSMutableDictionary<NSString*, ZDCStorageBill*> *mResult = nil;
		
		id value = _dict[@"s3"];
		if ([value isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *container = (NSDictionary *)value;
			
			value = container[@"storage"];
			if ([value isKindOfClass:[NSDictionary class]])
			{
				container = (NSDictionary *)value;
				mResult = [NSMutableDictionary dictionaryWithCapacity:container.count];
				
				[container enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
					
					if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]])
					{
						NSString *storageType = (NSString *)key;
						NSDictionary *storageDict = (NSDictionary *)obj;
						
						mResult[storageType] = [[ZDCStorageBill alloc] initWithDictionary:storageDict];
					}
				}];
			}
		}
		
		result = mResult ? [mResult copy] : [[NSDictionary alloc] init];
		_s3_storage = result; // cache it
	}
	
	return result;
}

- (NSDictionary<NSString*, ZDCStorageBill*> *)s3_multipartStorage
{
	NSDictionary<NSString*, ZDCStorageBill*> *result = _s3_multipartStorage;
	if (result == nil)
	{
		NSMutableDictionary<NSString*, ZDCStorageBill*> *mResult = nil;
		
		id value = _dict[@"s3"];
		if ([value isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *container = (NSDictionary *)value;
			
			value = container[@"multipart"];
			if ([value isKindOfClass:[NSDictionary class]])
			{
				container = (NSDictionary *)value;
				mResult = [NSMutableDictionary dictionaryWithCapacity:container.count];
				
				[container enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
					
					if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]])
					{
						NSString *uploadID = (NSString *)key;
						NSDictionary *storageDict = (NSDictionary *)obj;
						
						mResult[uploadID] = [[ZDCStorageBill alloc] initWithDictionary:storageDict];
					}
				}];
			}
		}
		
		result = mResult ? [mResult copy] : [[NSDictionary alloc] init];
		_s3_multipartStorage = result; // cache it
	}
	
	return result;
}

- (ZDCStorageBill *)s3_storage_total
{
	__block uint64_t total_byteCount = 0;
	__block double   total_byteHours = 0.0;
	
	[self.s3_storage enumerateKeysAndObjectsUsingBlock:
		^(NSString *storageType, ZDCStorageBill *storageBill, BOOL *stop)
	{
		total_byteCount += storageBill.byteCount;
		total_byteHours += storageBill.byteHours;
	}];
	
	return [[ZDCStorageBill alloc] initWithDictionary:@{
		@"byteCount" : @(total_byteCount),
		@"byteHours" : @(total_byteHours)
	}];
}

- (ZDCStorageBill *)s3_multipartStorage_total
{
	__block uint64_t total_byteCount = 0;
	__block double   total_byteHours = 0.0;
	
	[self.s3_multipartStorage enumerateKeysAndObjectsUsingBlock:
		^(NSString *storageType, ZDCStorageBill *storageBill, BOOL *stop)
	{
		total_byteCount += storageBill.byteCount;
		total_byteHours += storageBill.byteHours;
	}];
	
	return [[ZDCStorageBill alloc] initWithDictionary:@{
		@"byteCount" : @(total_byteCount),
		@"byteHours" : @(total_byteHours)
	}];
}

- (uint64_t)sns_mobilePushCount
{
	id value = _dict[@"sns"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"mobilePushCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (uint64_t)sns_publishCount
{
	id value = _dict[@"sns"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"publishCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (uint64_t)lambda_millisCount
{
	id value = _dict[@"lambda"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"millisCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (uint64_t)lambda_requestCount
{
	id value = _dict[@"lambda"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *container = (NSDictionary *)value;
		
		value = container[@"requestCount"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			return [value unsignedLongLongValue];
		}
	}
	
	return 0;
}

- (NSDate *)timestamp
{
	id value = _dict[@"timestamp"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		// javascript dates are in milliseconds since unix epoch
		
		double millis = [(NSNumber *)value doubleValue];
		double seconds = millis / 1000;
		
		return [NSDate dateWithTimeIntervalSince1970:seconds];
	}

	return [NSDate dateWithTimeIntervalSince1970:0];
}

- (NSString *)debugDescription
{
	return [NSString stringWithFormat:@"<%@:%p>: %@", NSStringFromClass([self class]), self, _dict];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
@implementation ZDCStorageBill

@synthesize rawDictionary = _dict;

@dynamic byteCount;
@dynamic byteHours;

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary
{
	if ((self = [super init]))
	{
		_dict = [rawDictionary copy];
	}
	return self;
}

- (uint64_t)byteCount
{
	id value = _dict[@"byteCount"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		return [(NSNumber *)value unsignedLongLongValue];
	}
	
	return 0;
}

- (double)byteHours
{
	id value = _dict[@"byteHours"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		double result = [(NSNumber *)value doubleValue];
		if (result >= 0.0) {
			return result;
		}
	}
	
	return 0.0;
}

- (NSString *)debugDescription
{
	return [NSString stringWithFormat:@"<%@:%p>: %@", NSStringFromClass([self class]), self, _dict];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCAppCost

@synthesize monthStart;
@synthesize monthEnd;

@synthesize elapsed;
@synthesize remaining;

@synthesize finalCost;
@synthesize accumulatedCost;
@synthesize estimatedCost;
@synthesize estimatedBill;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
@implementation ZDCAppCostDetails

@synthesize bandwidth_byteCount;
@synthesize s3_getCount;
@synthesize s3_putCount;
@synthesize s3_storage;
@synthesize s3_multipartStorage;
@synthesize sns_mobilePushCount;
@synthesize sns_publishCount;
@synthesize lambda_millisCount;
@synthesize lambda_requestCount;

@dynamic total;
@dynamic s3_storage_total;
@dynamic s3_multipartStorage_total;

- (double)total
{
	double total = 0.0;
	
	total += self.bandwidth_byteCount;
	total += self.s3_getCount;
	total += self.s3_putCount;
	total += self.s3_storage_total;
	total += self.s3_multipartStorage_total;
	total += self.sns_mobilePushCount;
	total += self.sns_publishCount;
	total += self.lambda_millisCount;
	total += self.lambda_requestCount;
	
	return total;
}

- (double)s3_storage_total
{
	__block double total = 0.0;
	[self.s3_storage enumerateKeysAndObjectsUsingBlock:^(NSString *storageType, NSNumber *value, BOOL *stop) {
		
		total += [value doubleValue];
	}];
	
	return total;
}

- (double)s3_multipartStorage_total
{
	__block double total = 0.0;
	[self.s3_multipartStorage enumerateKeysAndObjectsUsingBlock:^(NSString *multipartID, NSNumber *value, BOOL *stop) {
		
		total += [value doubleValue];
	}];
	
	return total;
}

- (NSString *)debugDescription
{
	NSDictionary *debugDict = @{
		@"bandwidth": @{
			@"byteCount" : @(self.bandwidth_byteCount)
		},
		@"s3": @{
			@"getCount"  : @(self.s3_getCount),
			@"putCount"  : @(self.s3_putCount),
			@"storage"   : self.s3_storage,
			@"multipart" : self.s3_multipartStorage
		},
		@"sns": @{
			@"mobilePushCount" : @(self.sns_mobilePushCount),
			@"publishCount"    : @(self.sns_publishCount)
		},
		@"lambda": @{
			@"millisCount"  : @(self.lambda_millisCount),
			@"requestCount" : @(self.lambda_requestCount)
		}
	};
	
	return [NSString stringWithFormat:@"<%@:%p>: %@", NSStringFromClass([self class]), self, debugDict];
}

@end
