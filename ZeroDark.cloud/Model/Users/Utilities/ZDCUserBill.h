/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

@class ZDCUserBillMetadata;
@class ZDCAppBill;
@class ZDCStorageBill;
@class ZDCAppCost;
@class ZDCAppCostDetails;

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a user's bill, which is their tally of cloud costs such as:
 * - s3 storage consumption
 * - sns push notification count
 * - lambda cpu usage (in milliseconds)
 * - bandwidth usage (in bytes)
 *
 * Converting a "bill" to actual user costs is highly app dependent.
 * But this class has tools to provide the tallies & raw cloud costs.
 */
@interface ZDCUserBill : NSObject

/**
 * The bill metadata gives us information such as the year & month this bill represents.
 */
@property (nonatomic, readonly) ZDCUserBillMetadata *metadata;

/**
 * Returns the raw rates dictionary.
 */
@property (nonatomic, readonly) NSDictionary *rates;

/**
 * Returns a dictionary, with bills for specific apps (including the totals for all apps).
 *
 * The keys in the returned dictionary are treeIDs.
 * For example: "com.myCompany.myApp", "com.4th-a.ZeroDarkTodo".
 *
 * If you want to know the totals (for all apps), use the key "*".
 */
@property (nonatomic, readonly) NSDictionary<NSString*, ZDCAppBill*> *apps;

/**
 * Calculates the raw cloud costs for a given app, or the totals for all apps.
 *
 * If you want to know the totals (for all apps), you can pass "*".
 *
 * @param treeID
 *   A ZeroDark.cloud treeID, as registered in the dashboard.
 *   For example: "com.myCompany.myApp", "com.4th-a.ZeroDarkTodo".
 *   If you want to know the totals (for all apps), you can pass "*".
 */
- (nullable ZDCAppCost *)calculateCost:(NSString *)treeID;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Represents the metadata from a ZDCUserBill.
 */
@interface ZDCUserBillMetadata : NSObject

/**
 * The month of the bill.
 *
 * Months are 1-based to match NSCalendar. (i.e. january=1, december=12)
 */
@property (nonatomic, readonly) NSInteger month;

/**
 * The year of the bill.
 */
@property (nonatomic, readonly) NSInteger year;

/**
 * The last time this bill was updated by the server.
 */
@property (nonatomic, readonly) NSDate *timestamp;

/**
 * If the `final` flag is TRUE, it means the bill is for a previous month/year and is finalized.
 * Otherwise, the bill is for the current month, and may be updated as the user continues using the cloud.
 */
@property (nonatomic, readonly) BOOL isFinal;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Represents the raw tallies for a specific app, or for the user's totals (all apps).
 * Instances of this class are created via ZDCUserBill.
 */
@interface ZDCAppBill : NSObject

@property (nonatomic, readonly) uint64_t bandwidth_byteCount;

@property (nonatomic, readonly) uint64_t s3_getCount;
@property (nonatomic, readonly) uint64_t s3_putCount;

@property (nonatomic, readonly) NSDictionary<NSString*, ZDCStorageBill*> *s3_storage;
@property (nonatomic, readonly) NSDictionary<NSString*, ZDCStorageBill*> *s3_multipartStorage;

@property (nonatomic, readonly) ZDCStorageBill *s3_storage_total;
@property (nonatomic, readonly) ZDCStorageBill *s3_multipartStorage_total;

@property (nonatomic, readonly) uint64_t sns_mobilePushCount;
@property (nonatomic, readonly) uint64_t sns_publishCount;

@property (nonatomic, readonly) uint64_t lambda_millisCount;
@property (nonatomic, readonly) uint64_t lambda_requestCount;

/**
 * The last time these tallies were updated by the server.
 */
@property (nonatomic, readonly) NSDate *timestamp;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Represents the storage tally for a specific {app, storageType} tuple.
 * Instances of this class are created via ZDCAppBill.
 */
@interface ZDCStorageBill : NSObject

/**
 * The number of bytes that are currently being stored on the server (as of the ZDCAppBill timestamp).
 */
@property (nonatomic, readonly) uint64_t byteCount;

/**
 * Representes the "byte hours" used so far (as of the ZDCAppBill timestamp).
 *
 * A "byte hour" is analogous to a "kilowatt hour".
 * It means: 1 byte stored for 1 hour.
 * It represents the basic unit of measurement for cloud storage.
 *
 * Since storage is so cheap, you will often see billing rates expressed in "gigabyte month".
 * For example: "$0.023 per GiB/m", which means "2.3 cents per gigabyte month".
 *
 * The conversion from "byte/hour" to "GiB/month" is as you would expect:
 *
 * ```
 * byte_month = byte_hour / hours_in_month
 * GiB_month = byte_month / GiB_in_bytes
 * ```
 */
@property (nonatomic, readonly) double byteHours;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCAppCost : NSObject

@property (nonatomic, readonly) NSDate *monthStart;
@property (nonatomic, readonly) NSDate *monthEnd;

@property (nonatomic, readonly) NSTimeInterval elapsed;
@property (nonatomic, readonly) NSTimeInterval remaining;

@property (nonatomic, readonly, nullable) ZDCAppCostDetails *finalCost;

@property (nonatomic, readonly, nullable) ZDCAppCostDetails *accumulatedCost;

@property (nonatomic, readonly, nullable) ZDCAppCostDetails *estimatedCost;

@property (nonatomic, readonly, nullable) ZDCAppBill *estimatedBill;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCAppCostDetails : NSObject

@property (nonatomic, readonly) double total;

@property (nonatomic, readonly) double bandwidth_byteCount;

@property (nonatomic, readonly) double s3_getCount;
@property (nonatomic, readonly) double s3_putCount;

@property (nonatomic, readonly) NSDictionary<NSString*, NSNumber*> *s3_storage;
@property (nonatomic, readonly) NSDictionary<NSString*, NSNumber*> *s3_multipartStorage;

@property (nonatomic, readonly) double s3_storage_total;
@property (nonatomic, readonly) double s3_multipartStorage_total;

@property (nonatomic, readonly) double sns_mobilePushCount;
@property (nonatomic, readonly) double sns_publishCount;

@property (nonatomic, readonly) double lambda_millisCount;
@property (nonatomic, readonly) double lambda_requestCount;

@end

NS_ASSUME_NONNULL_END
