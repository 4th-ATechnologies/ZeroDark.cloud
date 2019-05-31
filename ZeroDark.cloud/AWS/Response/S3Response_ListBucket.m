#import "S3Response_ListBucket.h"
#import "S3ResponsePrivate.h" // For readwrite properties


static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version               = @"version";
static NSString *const k_maxKeys               = @"maxKeys";
static NSString *const k_isTruncated           = @"isTruncated";
static NSString *const k_prefix                = @"prefix";
static NSString *const k_prevContinuationToken = @"prevContinuationToken";
static NSString *const k_nextContinuationToken = @"nextContinuationToken";
static NSString *const k_objectList            = @"objectList";


@implementation S3Response_ListBucket

@synthesize maxKeys = maxKeys;
@synthesize isTruncated = isTruncated;
@synthesize prefix = prefix;
@synthesize nextContinuationToken = nextContinuationToken;
@synthesize prevContinuationToken = prevContinuationToken;
@synthesize objectList = objectList;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		maxKeys = (NSUInteger)[decoder decodeIntegerForKey:k_maxKeys];
		isTruncated = [decoder decodeBoolForKey:k_isTruncated];
		
		prefix = [decoder decodeObjectForKey:k_prefix];
		
		prevContinuationToken = [decoder decodeObjectForKey:k_prevContinuationToken];
		nextContinuationToken = [decoder decodeObjectForKey:k_nextContinuationToken];
		
		objectList = [decoder decodeObjectForKey:k_objectList];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:@"version"];
	}
	
	[coder encodeInteger:maxKeys forKey:k_maxKeys];
	[coder encodeBool:isTruncated forKey:k_isTruncated];
	
	[coder encodeObject:prefix forKey:k_prefix];
	
	[coder encodeObject:prevContinuationToken forKey:k_prevContinuationToken];
	[coder encodeObject:nextContinuationToken forKey:k_nextContinuationToken];
	
	[coder encodeObject:objectList forKey:k_objectList];
}

- (id)copyWithZone:(NSZone *)zone
{
	S3Response_ListBucket *copy = [[[self class] alloc] init];
	
	copy->maxKeys = maxKeys;
	copy->isTruncated = isTruncated;
	
	copy->prefix = prefix;
	
	copy->prevContinuationToken = prevContinuationToken;
	copy->nextContinuationToken = nextContinuationToken;
	
	copy->objectList = objectList;
	
	return copy;
}

@end
