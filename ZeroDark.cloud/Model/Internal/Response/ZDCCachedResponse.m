#import "ZDCCachedResponse.h"


static NSString *const k_data         = @"data";
static NSString *const k_uncacheDate  = @"uncacheDate";
static NSString *const k_eTag         = @"eTag";
static NSString *const k_lastModified = @"lastModified";

/**
 * Stores cached NSURLResponses in the (encrypted) database.
 * To be replaced with NSURLCache subclass in the future.
 *
 * Objects are automatically deleted from the cache via ZDCDatabaseManager.actionManager.
**/
@implementation ZDCCachedResponse

@synthesize data = data;
@synthesize uncacheDate = uncacheDate;
@synthesize eTag = eTag;
@synthesize lastModified = lastModified;

- (instancetype)initWithData:(NSData *)inData timeout:(NSTimeInterval)inTimeout
{
	if ((self = [super init]))
	{
		data = [inData copy];
		uncacheDate = [NSDate dateWithTimeIntervalSinceNow:inTimeout];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		data = [decoder decodeObjectForKey:k_data];
		uncacheDate = [decoder decodeObjectForKey:k_uncacheDate];
		eTag = [decoder decodeObjectForKey:k_eTag];
		lastModified = [decoder decodeObjectForKey:k_lastModified];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:data         forKey:k_data];
	[coder encodeObject:uncacheDate  forKey:k_uncacheDate];
	[coder encodeObject:eTag         forKey:k_eTag];
	[coder encodeObject:lastModified forKey:k_lastModified];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCCachedResponse *copy =  [super copyWithZone:zone]; // [S4DatabaseObject copyWithZone:]
	
	copy->data = data;
	copy->uncacheDate = uncacheDate;
	copy->eTag = eTag;
	copy->lastModified = lastModified;
	
	return copy;
}

@end
