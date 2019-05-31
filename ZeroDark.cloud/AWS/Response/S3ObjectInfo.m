#import "S3ObjectInfo.h"
#import "S3ResponsePrivate.h" // For readwrite properties


static int const kS3ObjectInfo_CurrentVersion = 0;

static NSString *const k_version       = @"version";
static NSString *const k_key           = @"key";
static NSString *const k_eTag          = @"eTag";
static NSString *const k_lastModified  = @"lastModified";
static NSString *const k_size          = @"size";
static NSString *const k_storageClass  = @"storageClass";



@implementation S3ObjectInfo

@synthesize key = key;
@synthesize eTag = eTag;
@synthesize lastModified = lastModified;
@synthesize size = size;
@synthesize storageClass = storageClass;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		key = [decoder decodeObjectForKey:k_key];
		eTag = [decoder decodeObjectForKey:k_eTag];
		lastModified = [decoder decodeObjectForKey:k_lastModified];
		size = (uint64_t)[decoder decodeInt64ForKey:k_size];
		storageClass = [decoder decodeIntegerForKey:k_storageClass];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kS3ObjectInfo_CurrentVersion != 0) {
		[coder encodeInt:kS3ObjectInfo_CurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:key forKey:k_key];
	[coder encodeObject:eTag forKey:k_eTag];
	[coder encodeObject:lastModified forKey:k_lastModified];
	[coder encodeInt64:(int64_t)size forKey:k_size];
	[coder encodeInteger:storageClass forKey:k_storageClass];
}

- (id)copyWithZone:(NSZone *)zone
{
	S3ObjectInfo *copy = [[[self class] alloc] init];
	
	copy->key = key;
	copy->eTag = eTag;
	copy->lastModified = lastModified;
	copy->size = size;
	copy->storageClass = storageClass;
	
	return copy;
}

@end
