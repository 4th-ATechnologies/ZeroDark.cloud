#import "AWSRegions.h"

static NSUInteger AWSRegionTable_Index_Region        = 0;
static NSUInteger AWSRegionTable_Index_ShortName     = 1;
static NSUInteger AWSRegionTable_Index_DisplayName   = 2;
static NSUInteger AWSRegionTable_Index_IPv4Host      = 3;
static NSUInteger AWSRegionTable_Index_DualStackHost = 4;


@implementation AWSRegions

static NSArray *awsRegionTable;
static NSArray *avalableRegionTable;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        
		awsRegionTable = @[
			@[ @(AWSRegion_US_East_1),          @"us-east-1",      @"US East (N. Virginia)",      @"amazonaws.com",                  @"dualstack.us-east-1.amazonaws.com"        ],
			@[ @(AWSRegion_US_East_2),          @"us-east-2",      @"US East (Ohio)",             @"us-east-2.amazonaws.com",        @"dualstack.us-east-2.amazonaws.com"        ],
			@[ @(AWSRegion_US_West_1),          @"us-west-1",      @"US West (N. California)",    @"us-west-1.amazonaws.com",        @"dualstack.us-west-1.amazonaws.com"        ],
			@[ @(AWSRegion_US_West_2),          @"us-west-2",      @"US West (Oregon)",           @"us-west-2.amazonaws.com",        @"dualstack.us-west-2.amazonaws.com"        ],
			@[ @(AWSRegion_EU_West_1),          @"eu-west-1",      @"Europe (Ireland)",           @"eu-west-1.amazonaws.com",        @"dualstack.eu-west-1.amazonaws.com"        ],
			@[ @(AWSRegion_EU_Central_1),       @"eu-central-1",   @"Europe (Frankfurt)",         @"eu-central-1.amazonaws.com",     @"dualstack.eu-central-1.amazonaws.com"     ],
			@[ @(AWSRegion_AP_NorthEast_1),     @"ap-northeast-1", @"Asia Pacific (Tokyo)",       @"ap-northeast-1.amazonaws.com",   @"dualstack.ap-northeast-1.amazonaws.com"   ],
			@[ @(AWSRegion_AP_NorthEast_2),     @"ap-northeast-2", @"Asia Pacific (Seoul)",       @"ap-northeast-2.amazonaws.com",   @"dualstack.ap-northeast-2.amazonaws.com"   ],
			@[ @(AWSRegion_AP_SouthEast_1),     @"ap-southeast-1", @"Asia Pacific (Singapore)",   @"ap-southeast-1.amazonaws.com",   @"dualstack.ap-southeast-1.amazonaws.com"   ],
			@[ @(AWSRegion_AP_SouthEast_2),     @"ap-southeast-2", @"Asia Pacific (Sydney)",      @"ap-southeast-2.amazonaws.com",   @"dualstack.ap-southeast-2.amazonaws.com"   ],
			@[ @(AWSRegion_SA_East_1),          @"sa-east-1",      @"South America (São Paulo)",  @"sa-east-1.amazonaws.com",        @"dualstack.sa-east-1.amazonaws.com"        ],
			@[ @(AWSRegion_US_GovCloud_West_1), @"us-gov-west-1",  @"AWS GovCloud (US)",          @"s3-us-gov-west-1.amazonaws.com", @"dualstack.s3-us-gov-west-1.amazonaws.com" ],

			@[ @(AWSRegion_EU_West_2),          @"eu-west-2",      @"Europe (London)",            @"eu-west-2.amazonaws.com",        @"dualstack.eu-west-2.amazonaws.com"        ],
			@[ @(AWSRegion_EU_West_3),          @"eu-west-3",      @"Europe (Paris)",             @"eu-west-3.amazonaws.com",        @"dualstack.eu-west-3.amazonaws.com"        ],
//			@[ @(AWSRegion_CN_North_1),         @"cn-north-1",     @"China (Beijing)",            @"cn-north-1.amazonaws.com",       @"dualstack.cn-north-1.amazonaws.com"       ],
			@[ @(AWSRegion_CA_Central_1),       @"ca-central-1",   @"Canada (Central)",           @"ca-central-1.amazonaws.com",     @"dualstack.ca-central-1.amazonaws.com"     ],

		];
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Regions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSArray<NSNumber *> *)allRegions
{
	NSMutableArray<NSNumber *> *regions = [NSMutableArray arrayWithCapacity:awsRegionTable.count];
	
	for (NSArray *entry in awsRegionTable)
	{
		[regions addObject:entry[AWSRegionTable_Index_Region]];
	}
	
	return [regions copy];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSString *)shortNameForRegion:(AWSRegion)region
{
	NSString *shortName = nil;
	
	for (NSArray *entry in awsRegionTable)
	{
		if (region == [entry[AWSRegionTable_Index_Region] integerValue])
		{
			shortName = entry[AWSRegionTable_Index_ShortName];
			break;
		}
	}
	
	return shortName ?: @"invalid";
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSString *)displayNameForRegion:(AWSRegion)region
{
	NSString *displayName = nil;
	
	for (NSArray *entry in awsRegionTable)
	{
		if (region == [entry[AWSRegionTable_Index_Region] integerValue])
		{
			displayName = entry[AWSRegionTable_Index_DisplayName];
			break;
		}
	}
	
	return displayName ?: @"Invalid";
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSString *)IPv4HostForRegion:(AWSRegion)region
{
	return [self IPv4HostForRegion:region service:AWSService_Invalid];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSString *)IPv4HostForRegion:(AWSRegion)region service:(AWSService)service
{
	NSString *host = nil;
	
	for (NSArray *entry in awsRegionTable)
	{
		if (region == [entry[AWSRegionTable_Index_Region] integerValue])
		{
			host = entry[AWSRegionTable_Index_IPv4Host];
			break;
		}
	}
	
	if (service == AWSService_S3)
	{
		if (region == AWSRegion_US_East_1)
			return [NSString stringWithFormat:@"s3.%@", host];
		else
			return [NSString stringWithFormat:@"s3-%@", host];
	}
	else
	{
		NSString *prefix = [AWSServices shortNameForService:service];
		
		if (prefix.length > 0)
			return [NSString stringWithFormat:@"%@.%@", prefix, host];
		else
			return host;
	}
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSString *)dualStackHostForRegion:(AWSRegion)region
{
	return [self dualStackHostForRegion:region service:AWSService_Invalid];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (NSString *)dualStackHostForRegion:(AWSRegion)region service:(AWSService)service
{
	NSString *host = nil;
	
	for (NSArray *entry in awsRegionTable)
	{
		if (region == [entry[AWSRegionTable_Index_Region] integerValue])
		{
			host = entry[AWSRegionTable_Index_DualStackHost];
			break;
		}
	}
	
	NSString *prefix = [AWSServices shortNameForService:service];
	
	if (prefix.length > 0)
		return [NSString stringWithFormat:@"%@.%@", prefix, host];
	else
		return host;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/AWSRegions.html
 */
+ (AWSRegion)regionForName:(NSString *)name
{
	AWSRegion region = AWSRegion_Invalid;
	
	for (NSArray *entry in awsRegionTable)
	{
		if ([name isEqualToString:entry[AWSRegionTable_Index_ShortName]] ||
		    [name isEqualToString:entry[AWSRegionTable_Index_DisplayName]])
		{
			region = (AWSRegion)[entry[AWSRegionTable_Index_Region] integerValue];
			break;
		}
	}
	
	return region;
}

@end
