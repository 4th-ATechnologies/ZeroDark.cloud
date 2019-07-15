/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPollContext.h"

#include <stdatomic.h>

static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version      = @"version";
static NSString *const k_eTag         = @"eTag";
static NSString *const k_taskContext  = @"taskContext";


@implementation ZDCPollContext {

	atomic_flag completed;
}

@synthesize taskContext = taskContext;
@synthesize eTag = eTag;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		taskContext = [decoder decodeObjectForKey:k_taskContext];
		eTag = [decoder decodeObjectForKey:k_eTag];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:taskContext forKey:k_taskContext];
	[coder encodeObject:eTag forKey:k_eTag];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCPollContext *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->taskContext = [taskContext copy];
	copy->eTag = eTag;
	
	return copy;
}

/**
 * Polling could complete via the poll request itself,
 * or via an arriving push notification.
 *
 * If both arrive at the same time, we need a way to ensure it's only processed once.
 *
 * The completed marker is reset if the requestID is changed.
**/
- (BOOL)atomicMarkCompleted
{
	atomic_bool prev = atomic_flag_test_and_set_explicit(&completed, memory_order_relaxed);
	return (prev == false);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)makeImmutable
{
	[super makeImmutable];
	[taskContext makeImmutable];
}

@end
