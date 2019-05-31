#import <Foundation/Foundation.h>

#import "AWSServices.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * List of available AWS regions.
 *
 * Source: http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
**/
typedef NS_ENUM(NSInteger, AWSRegion) {
	
	/** USA (N. Virginia) */
	AWSRegion_US_East_1,
	
	/** USA (Ohio) */
	AWSRegion_US_East_2,
	
	/** USA (N. California) */
	AWSRegion_US_West_1,
	
	/** USA (Oregon) */
	AWSRegion_US_West_2,
	
	/** USA (GovCloud) */
	AWSRegion_US_GovCloud_West_1,
	
	/** Europe (Ireland) */
	AWSRegion_EU_West_1,
	
	/** Europe (London) */
	AWSRegion_EU_West_2,
	
	/** Europe (Paris) */
	AWSRegion_EU_West_3,
	
	/** Europe (Frankfurt) */
	AWSRegion_EU_Central_1,
	
	/** Asia Pacific (Tokyo) */
	AWSRegion_AP_NorthEast_1,
	
	/** Asia Pacific (Seoul) */
	AWSRegion_AP_NorthEast_2,
	
	/** Asia Pacific (Singapore) */
	AWSRegion_AP_SouthEast_1,
	
	/** Asia Pacific (Sydney) */
	AWSRegion_AP_SouthEast_2,
	
	/** South America (São Paulo) */
	AWSRegion_SA_East_1,

	/** China (Beijing) */
	AWSRegion_CN_North_1,
	
	/** Canada (Central) */
	AWSRegion_CA_Central_1,

	/** Represents an invalid region. Kinda like a nil value. */
	AWSRegion_Invalid = NSIntegerMax
};

/**
 * Common utility methods related to AWS regions.
 */
@interface AWSRegions : NSObject

/**
 * Returns all regions.
 */
+ (NSArray<NSNumber *> *)allRegions;

/**
 * Returns the short name of the region.
 * This is the value typically used internally by amazon (e.g. in authentication steps).
 * E.g. "us-west-2"
 * 
 * @note When serializing region information, it's recommended you convert from enum to shortName string.
 *       As Amazon adds more regions throughout the world, the enum values WILL change.
 *       However, the shortName values will remain consistent, and so are more reliable for persistent storage.
 */
+ (NSString *)shortNameForRegion:(AWSRegion)region;

/**
 * Returns a string for the region which is suitable for display to the user.
 * E.g. "USA (Oregon)"
 */
+ (NSString *)displayNameForRegion:(AWSRegion)region;

/**
 * Returns the URL host for the given region.
 * The host will be IPv4 specific.
 *
 * E.g. us-west-2.amazonaws.com
 */
+ (nullable NSString *)IPv4HostForRegion:(AWSRegion)region;

/**
 * Returns the URL host for the given region & service).
 * The host will be IPv4 specific.
 *
 * E.g. us-west-2.amazonaws.com
 */
+ (nullable NSString *)IPv4HostForRegion:(AWSRegion)region service:(AWSService)service;

/**
 * Returns the URL host for the given region.
 * The host will support both IPv4 & IPv6.
 * 
 * @note DualStack may not be supported by all aws services.
 *
 * E.g. dualstack.us-west-2.amazonaws.com
 */
+ (nullable NSString *)dualStackHostForRegion:(AWSRegion)region;

/**
 * Returns the URL host for the given region & service.
 * The host will support both IPv4 & IPv6.
 *
 * @note DualStack may not be supported by all aws services.
 *
 * E.g. s3.dualstack.us-west-2.amazonaws.com
 */
+ (nullable NSString *)dualStackHostForRegion:(AWSRegion)region service:(AWSService)service;

/**
 * Returns the region enum value for the given region's shortName.
 *
 * This method works with either the shortName or displayName.
 */
+ (AWSRegion)regionForName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
