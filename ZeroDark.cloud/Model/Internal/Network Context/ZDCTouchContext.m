#import "ZDCTouchContext.h"

static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version     = @"version";
static NSString *const k_pollContext = @"pollContext";


@implementation ZDCTouchContext

@synthesize pollContext = pollContext;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		pollContext = [decoder decodeObjectForKey:k_pollContext];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:pollContext forKey:k_pollContext];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCTouchContext *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->pollContext = [pollContext copy];
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)makeImmutable
{
	[super makeImmutable];
	[pollContext makeImmutable];
}

@end
