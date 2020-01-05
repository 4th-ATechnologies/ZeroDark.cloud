/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserBill.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCUserBill ()

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary;

@property (nonatomic, readonly) NSDictionary *rawDictionary;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCUserBillMetadata ()

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary;

@property (nonatomic, readonly) NSDictionary *rawDictionary;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCAppBill ()

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary;

@property (nonatomic, readonly) NSDictionary *rawDictionary;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCStorageBill ()

- (instancetype)initWithDictionary:(NSDictionary *)rawDictionary;

@property (nonatomic, readonly) NSDictionary *rawDictionary;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCAppCost ()

@property (nonatomic, readwrite) NSDate *monthStart;
@property (nonatomic, readwrite) NSDate *monthEnd;

@property (nonatomic, readwrite) NSTimeInterval elapsed;
@property (nonatomic, readwrite) NSTimeInterval remaining;

@property (nonatomic, readwrite, nullable) ZDCAppCostDetails *finalCost;
@property (nonatomic, readwrite, nullable) ZDCAppCostDetails *accumulatedCost;
@property (nonatomic, readwrite, nullable) ZDCAppCostDetails *estimatedCost;
@property (nonatomic, readwrite, nullable) ZDCAppBill *estimatedBill;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCAppCostDetails ()

@property (nonatomic, readwrite) double bandwidth_byteCount;

@property (nonatomic, readwrite) double s3_getCount;
@property (nonatomic, readwrite) double s3_putCount;

@property (nonatomic, readwrite) NSDictionary<NSString*, NSNumber*> *s3_storage;
@property (nonatomic, readwrite) NSDictionary<NSString*, NSNumber*> *s3_multipartStorage;

@property (nonatomic, readwrite) double sns_mobilePushCount;
@property (nonatomic, readwrite) double sns_publishCount;

@property (nonatomic, readwrite) double lambda_millisCount;
@property (nonatomic, readwrite) double lambda_requestCount;

@end

NS_ASSUME_NONNULL_END
