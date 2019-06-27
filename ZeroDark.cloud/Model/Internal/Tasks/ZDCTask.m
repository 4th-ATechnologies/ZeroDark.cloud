/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCTask.h"

static NSString *const k_uuid = @"uuid";

@implementation ZDCTask

@synthesize uuid = uuid;

- (instancetype)init
{
	if ((self = [super init]))
	{
		uuid = [[NSUUID UUID] UUIDString];
	}
	return self;
}

#pragma mark NSCoding

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		uuid = [decoder decodeObjectForKey:k_uuid];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:uuid forKey:k_uuid];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	ZDCTask *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	copy->uuid = uuid;
	
	return copy;
}

#pragma mark Subclass Hooks

- (YapActionItem *)actionItem:(YapActionItemBlock)block
{
	NSAssert(NO, @"Subclass forgot to override method: -[ZDCTask actionItem:]");
	return nil;
}

- (void)performTask:(ZeroDarkCloud *)owner
{
	NSAssert(NO, @"Subclass forgot to override method: -[ZDCTask performTask:]");
}

@end
