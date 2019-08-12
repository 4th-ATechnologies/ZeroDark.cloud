/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCCloudDataInfo.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version           = @"version";
static NSString *const k_metadataSize      = @"metadataSize";
static NSString *const k_thumbnailSize     = @"thumbnailSize";
static NSString *const k_dataSize          = @"dataSize";
static NSString *const k_thumbnailxxHash64 = @"thumbnailxxHash64";
static NSString *const k_eTag              = @"eTag";
static NSString *const k_lastModified      = @"lastModified";

@implementation ZDCCloudDataInfo

@synthesize metadataSize = metadataSize;
@synthesize thumbnailSize = thumbnailSize;
@synthesize dataSize = dataSize;
@synthesize thumbnailxxHash64 = thumbnailxxHash64;
@synthesize eTag = eTag;
@synthesize lastModified = lastModified;

- (instancetype)initWithCloudFileHeader:(ZDCCloudFileHeader)header
                                   eTag:(NSString *)inETag
                           lastModified:(NSDate *)inLastModified
{
	if ((self = [super init]))
	{
		metadataSize = header.metadataSize;
		thumbnailSize = header.thumbnailSize;
		dataSize = header.dataSize;
		
		thumbnailxxHash64 = header.thumbnailxxHash64;
		
		self->eTag = [inETag copy];
		self->lastModified = [inLastModified copy];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Version History:
 *
 * < will be documented here >
**/

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
	//	int version = [decoder decodeIntForKey:k_version];
		
		metadataSize  = (uint64_t)[decoder decodeInt64ForKey:k_metadataSize];
		thumbnailSize = (uint64_t)[decoder decodeInt64ForKey:k_thumbnailSize];
		dataSize      = (uint64_t)[decoder decodeInt64ForKey:k_dataSize];
		
		thumbnailxxHash64 = (uint64_t)[decoder decodeInt64ForKey:k_thumbnailxxHash64];
		
		eTag = [decoder decodeObjectForKey:k_eTag];
		lastModified = [decoder decodeObjectForKey:k_lastModified];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeInt64:(int64_t)metadataSize  forKey:k_metadataSize];
	[coder encodeInt64:(int64_t)thumbnailSize forKey:k_thumbnailSize];
	[coder encodeInt64:(int64_t)dataSize      forKey:k_dataSize];
	
	[coder encodeInt64:(int64_t)thumbnailxxHash64 forKey:k_thumbnailxxHash64];
	
	[coder encodeObject:eTag forKey:k_eTag];
	[coder encodeObject:lastModified forKey:k_lastModified];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	return self; // ZDCCloudDataInfo is an immutable class
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (ZDCCloudFileHeader)rawHeader
{
	ZDCCloudFileHeader header;
	bzero(&header, sizeof(header));
	
	header.magic = kZDCCloudFileContextMagic;
	
	header.metadataSize = metadataSize;
	header.thumbnailSize = thumbnailSize;
	header.dataSize = dataSize;
	
	header.thumbnailxxHash64 = thumbnailxxHash64;
	
	return header;
}

@end
