/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCCloudLocator.h"

// Encoding/Decoding keys
static NSString *const k_regionStr = @"regionStr";
static NSString *const k_bucket    = @"bucket";
static NSString *const k_cloudPath = @"cloudPath";


@implementation ZDCCloudLocator

@synthesize region;
@synthesize bucket;
@synthesize cloudPath;

- (instancetype)initWithRegion:(AWSRegion)inRegion bucket:(NSString *)inBucket cloudPath:(ZDCCloudPath *)inCloudPath
{
	NSAssert(inRegion != AWSRegion_Invalid, @"ZDCCloudLocator.init: invalid region");
	NSAssert(inBucket != nil,               @"ZDCCloudLocator.init: invalid bucket");
	NSAssert(inCloudPath != nil,            @"ZDCCloudLocator.init: invalid cloudPath");
	
	if ((self = [super init]))
	{
		region = inRegion;
		bucket = [inBucket copy];
		cloudPath = [inCloudPath copy];
	}
	return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Note: Do NOT depend on the region values remaining constant.
		// This is why we encode/decode the value as a string.
		
		NSString *regionName = [decoder decodeObjectForKey:k_regionStr];
		region = [AWSRegions regionForName:regionName];
		
		bucket = [decoder decodeObjectForKey:k_bucket];
		cloudPath = [decoder decodeObjectForKey:k_cloudPath];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	NSString *regionName = [AWSRegions shortNameForRegion:region];
	
	[coder encodeObject:regionName forKey:k_regionStr];
	[coder encodeObject:bucket forKey:k_bucket];
	[coder encodeObject:cloudPath forKey:k_cloudPath];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
	return self; // ZDCCloudLocator is immutable
}

- (instancetype)copyWithCloudPath:(ZDCCloudPath *)newCloudPath
{
	ZDCCloudLocator *copy = [[ZDCCloudLocator alloc] init];
	copy->region = region;
	copy->bucket = bucket;
	copy->cloudPath = [newCloudPath copy];
	
	return copy;
}

- (instancetype)copyWithFileNameExt:(NSString *)newFileNameExt
{
	ZDCCloudLocator *copy = [[ZDCCloudLocator alloc] init];
	copy->region = region;
	copy->bucket = bucket;
	copy->cloudPath = [cloudPath copyWithFileNameExt:newFileNameExt];
	
	return copy;
}

- (BOOL)isEqual:(id)another
{
	if (![another isKindOfClass:[ZDCCloudLocator class]])
		return NO;
	else
		return [self isEqualToCloudLocator:(ZDCCloudLocator *)another];
}

- (BOOL)isEqualToCloudLocator:(ZDCCloudLocator *)another
{
	return [self isEqualToCloudLocator:another components:ZDCCloudPathComponents_All_WithExt];
}

- (BOOL)isEqualToCloudLocatorIgnoringExt:(ZDCCloudLocator *)another
{
	return [self isEqualToCloudLocator:another components:ZDCCloudPathComponents_All_WithoutExt];
}

- (BOOL)isEqualToCloudLocator:(ZDCCloudLocator *)another components:(ZDCCloudPathComponents)components
{
	if (another == nil) return NO;
	
	if (region != another->region) return NO;
	if (![bucket isEqualToString:another->bucket]) return NO;
	if (![cloudPath isEqualToCloudPath:another->cloudPath components:components]) return NO;
	
	return YES;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<ZDCCloudLocator: region:%@, bucket:%@, cloudPath:%@>",
	          [AWSRegions shortNameForRegion:region],
	          bucket,
	          [cloudPath description]];
}

@end
