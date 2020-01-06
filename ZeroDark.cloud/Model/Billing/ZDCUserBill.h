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

/**
 * The number of bytes the user has downloaded from the cloud.
 */
@property (nonatomic, readonly) uint64_t bandwidth_byteCount;

/**
 * The number S3 GET requests issued by the user.
 *
 * This corresponds to the following actions:
 * - Downloads of RCRD files by the PullManager.
 *   This occurs automatically during sync, if a node's metadata has been modified.
 *   For example, if a node was moved/renamed, or its permissions were changed.
 * - Downloads of DATA files by the app, generally issued thru the DownloadManager or ImageManager.
 *   This occurs when your app requests the download of a node's data, metadata or thumbnail.
 */
@property (nonatomic, readonly) uint64_t s3_getCount;

/**
 * The number of S3 PUT and/or LIST requests.
 *
 * This generally corresponds to the number of nodes that have been uploaded.
 */
@property (nonatomic, readonly) uint64_t s3_putCount;

/**
 * Details the storage consumption used by the app, for each storage tier.
 *
 * The tiers consist of:
 * - standard
 * - standard_ia
 * - glacier
 */
@property (nonatomic, readonly) NSDictionary<NSString*, ZDCStorageBill*> *s3_storage;

/**
 * Details temporary storage consumption used by the app, while uploading large nodes.
 *
 * If you create a node that's large (e.g. 50 MiB), then the PushManager will upload the node in parts.
 * This helps the system quickly recover from network disconnections, and other interruptions such as system sleep.
 * For example, user disconnects from WiFi or puts laptop to sleep.
 * By using multipart uploads, the PushManager can restart the last part,
 * as opposed to restarting the upload from the very beginning.
 *
 * While a multipart upload is in progress, the parts will sit in AWS, in a temporary location.
 * This details the costs associated with such temporary storage.
 *
 * @note Unfinished uploads are automatically cancelled after a few days, and their storage is deleted.
 */
@property (nonatomic, readonly) NSDictionary<NSString*, ZDCStorageBill*> *s3_multipartStorage;

/**
 * Convenience function: returns the SUM of all items in the s3_storage dictionary.
 */
@property (nonatomic, readonly) ZDCStorageBill *s3_storage_total;

/**
 * Convenience function: returns the SUM of all items in the s3_multipartStorage dictionary.
 */
@property (nonatomic, readonly) ZDCStorageBill *s3_multipartStorage_total;

/**
 * The number of push notifications actually sent via AWS SNS to devices.
 *
 * For example, if Alice changes a node, that will trigger 1 notification to Alice.
 * The sns_publishCount will be incremented by 1,
 * and the sns_mobilePushCount will be incremented by the number of devices in which Alice is signed in.
 *
 * If Alice changes a node that's shared with Bob, that will trigger 1 notification for Alice & 1 for Bob.
 * The sns_publishCount will be incremented by 2,
 * and the sns_mobilePushCount will be incremented by however many devices Alice & Bob are signed into.
 *
 * @note If a user signs out on a device (or deletes the app),
 *       that device gets pruned from the list of devices.
 */
@property (nonatomic, readonly) uint64_t sns_mobilePushCount;

/**
 * The number of push notifications triggered by the user.
 *
 * For example, if Alice changes a node, that will trigger 1 notification to Alice.
 * The sns_publishCount will be incremented by 1,
 * and the sns_mobilePushCount will be incremented by the number of devices in which Alice is signed in.
 *
 * If Alice changes a node that's shared with Bob, that will trigger 1 notification for Alice & 1 for Bob.
 * The sns_publishCount will be incremented by 2,
 * and the sns_mobilePushCount will be incremented by however many devices Alice & Bob are signed into.
 */
@property (nonatomic, readonly) uint64_t sns_publishCount;

/**
 * The number of milliseconds of CPU time consumed by the user.
 *
 * Whenever the user makes a request from the server (e.g. uploads a new node),
 * the server tracks the amount of time required to process the request, and updates this value server-side.
 */
@property (nonatomic, readonly) uint64_t lambda_millisCount;

/**
 * The number of CPU requests consumed by the user.
 *
 * This value represents the number of requests,
 * as opposed to the amount of time it took the server to process the request.
 */
@property (nonatomic, readonly) uint64_t lambda_requestCount;

/**
 * The last time these tallies were updated by the server.
 *
 * This is specific to the particular app, and may be different from ZDCUserBill.metadata.timestamp.
 * However, this timestamp will always be less-than-or-equal-to that value.
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

/**
 * Provides a calculation of the app's raw cloud costs.
 *
 * Instances of this class are created via `-[ZDCUserBill calculateCost:]`.
 */
@interface ZDCAppCost : NSObject

/**
 * If ZDCUserBill.isFinal is true, then this value will be non-nil.
 * This is the case when the bill is for a previous month.
 */
@property (nonatomic, readonly, nullable) ZDCAppCostDetails *finalCost;

/**
 * If ZDCUserBill.isFinal is false, then this value will be non-nil.
 * This is the case when the bill is for the current month.
 */
@property (nonatomic, readonly, nullable) ZDCAppCostDetails *accumulatedCost;

/**
 * If ZDCUserBill.isFinal is false, then this value will be non-nil.
 * This is the case when the bill is for the current month.
 *
 * The estimatedCost gives us a rough estimate of what the cost may be at the end of the month.
 * For example, if we're half-way thru the current month, then the estimate essentially doubles the current values.
 *
 * A good analogy here is your electric bill.
 * If you look at your electric meter halfway thru the month, it will tell you how much electricity you've used so far.
 * This is the equivalent of the accumulated cost. Assuming your electricity usage so far this month isn't
 * out-of-the-ordinary, you can calculate a decent estimate of your end-of-the-month usage.
 * And this is equivalent of the estimated cost.
 */
@property (nonatomic, readonly, nullable) ZDCAppCostDetails *estimatedCost;

/**
 * If ZDCUserBill.isFinal is false, then this value will be non-nil.
 * This is the case when the bill is for the current month.
 *
 * The estimatedBill gives us a rough estimate of what we guess will be the tallies at the end of the month.
 * For example, if we're half-way thru the current month, then the estimate essentially doubles the current values.
 *
 * A good analogy here is your electric bill.
 * If you look at your electric meter halfway thru the month, it will tell you how much electricity you've used so far.
 * This is the equivalent of the accumulated cost. Assuming your electricity usage so far this month isn't
 * out-of-the-ordinary, you can calculate a decent estimate of your end-of-the-month usage.
 * And this is equivalent of the estimated cost.
 */
@property (nonatomic, readonly, nullable) ZDCAppBill *estimatedBill;

/** Timestamp of when the month started. */
@property (nonatomic, readonly) NSDate *monthStart;

/** Timestamp of when the month ended. */
@property (nonatomic, readonly) NSDate *monthEnd;

/**
 * The number of seconds that have elapsed so far (for the month).
 *
 * This is useful when the bill is for the current month. (i.e. ZDCUserBill.isFinal == false)
 * It gives you an idea of how far thru the month we are, and thus how accurate the estimated costs are.
 */
@property (nonatomic, readonly) NSTimeInterval elapsed;

/**
* The number of seconds that are remaining (for the month).
*
* This is useful when the bill is for the current month. (i.e. ZDCUserBill.isFinal == false)
* It gives you an idea of how far thru the month we are, and thus how accurate the estimated costs are.
*/
@property (nonatomic, readonly) NSTimeInterval remaining;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The calculated raw cost for each service.
 */
@interface ZDCAppCostDetails : NSObject

/** Convenience funtion: returns the total of all costs. */
@property (nonatomic, readonly) double total;

/** The cost for bandwidth. */
@property (nonatomic, readonly) double bandwidth_byteCount;

/** The cost for S3 GET operations. */
@property (nonatomic, readonly) double s3_getCount;

/** The cost for S3 PUT operations. */
@property (nonatomic, readonly) double s3_putCount;

/** The cost for S3 storage. */
@property (nonatomic, readonly) NSDictionary<NSString*, NSNumber*> *s3_storage;

/** The cost for temporary S3 storage, used during mulipart uploads. */
@property (nonatomic, readonly) NSDictionary<NSString*, NSNumber*> *s3_multipartStorage;

/** Convenience function: returns the total of all items in the s3_storage dictionary. */
@property (nonatomic, readonly) double s3_storage_total;

/** Convenience function: returns the total of all items in the s3_multipartStorage dictionary. */
@property (nonatomic, readonly) double s3_multipartStorage_total;

/** The cost for SNS push notification deliveries. */
@property (nonatomic, readonly) double sns_mobilePushCount;

/** The cost for SNS push notification publications. */
@property (nonatomic, readonly) double sns_publishCount;

/** The cost for CPU usage. */
@property (nonatomic, readonly) double lambda_millisCount;

/** The cost for CPU requests. */
@property (nonatomic, readonly) double lambda_requestCount;

@end

NS_ASSUME_NONNULL_END
