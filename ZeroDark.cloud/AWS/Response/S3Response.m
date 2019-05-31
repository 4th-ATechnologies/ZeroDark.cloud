#import "S3Response.h"
#import "S3ResponsePrivate.h" // For readwrite properties


static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version                 = @"version";
static NSString *const k_listBucket              = @"listBucket";
static NSString *const k_initiateMultipartUpload = @"initiateMultipartUpload";


@implementation S3Response

@synthesize listBucket = listBucket;
@synthesize initiateMultipartUpload = initiateMultipartUpload;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		listBucket = [decoder decodeObjectForKey:k_listBucket];
		initiateMultipartUpload = [decoder decodeObjectForKey:k_initiateMultipartUpload];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:@"version"];
	}
	
	[coder encodeObject:listBucket forKey:k_listBucket];
	[coder encodeObject:initiateMultipartUpload forKey:k_initiateMultipartUpload];
}

- (id)copyWithZone:(NSZone *)zone
{
	S3Response *copy = [[[self class] alloc] init];
	
	copy->listBucket = [listBucket copy];
	copy->initiateMultipartUpload = [initiateMultipartUpload copy];
	
	return copy;
}

@end
