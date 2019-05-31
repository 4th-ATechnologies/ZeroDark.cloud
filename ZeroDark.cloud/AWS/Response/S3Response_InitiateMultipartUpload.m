#import "S3Response_InitiateMultipartUpload.h"
#import "S3ResponsePrivate.h" // For readwrite properties


static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version  = @"version";
static NSString *const k_bucket   = @"bucket";
static NSString *const k_key      = @"key";
static NSString *const k_uploadID = @"uploadID";


@implementation S3Response_InitiateMultipartUpload

@synthesize bucket = bucket;
@synthesize key = key;
@synthesize uploadID = uploadID;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		bucket   = [decoder decodeObjectForKey:k_bucket];
		key      = [decoder decodeObjectForKey:k_key];
		uploadID = [decoder decodeObjectForKey:k_uploadID];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:@"version"];
	}
	
	[coder encodeObject:bucket   forKey:k_bucket];
	[coder encodeObject:key      forKey:k_key];
	[coder encodeObject:uploadID forKey:k_uploadID];
}

- (id)copyWithZone:(NSZone *)zone
{
	S3Response_InitiateMultipartUpload *copy = [[[self class] alloc] init];
	
	copy->bucket   = bucket;
	copy->key      = key;
	copy->uploadID = uploadID;
	
	return copy;
}

@end
