/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCTask_UnregisterPushToken.h"
#import "NSURLResponse+ZeroDark.h"

static NSString *const k_userID    = @"userID";
static NSString *const k_regionStr = @"regionStr";

@implementation ZDCTask_UnregisterPushToken

@synthesize userID = userID;
@synthesize region = region;

/**
 * If you don't know the region, just pass AWSRegion_Invalid.
 */
- (instancetype)initWithUserID:(NSString *)inUserID region:(AWSRegion)inRegion
{
	NSParameterAssert(inUserID != nil);
	
	if ((self = [super init]))
	{
		userID = [inUserID copy];
		region = inRegion;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder])) // [ZDCTask initWithCoder:]
	{
		userID = [decoder decodeObjectForKey:k_userID];
		region = [AWSRegions regionForName:[decoder decodeObjectForKey:k_regionStr]];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder]; // [ZDCTask encodeWithCoder:]
	
	[coder encodeObject:userID forKey:k_userID];
	[coder encodeObject:[AWSRegions shortNameForRegion:region] forKey:k_regionStr];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCTask_UnregisterPushToken *copy = [super copyWithZone:zone]; // [ZDCTask copyWithZone:]
	
	copy->userID = userID;
	copy->region = region;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapActionItem *)actionItem:(YapActionItemBlock)block
{
	return [[YapActionItem alloc] initWithIdentifier: @"unregister"
	                                            date: nil       // asap
	                                    retryTimeout: (60 * 15) // 15 minutes
	                                requiresInternet: YES
	                                           block: block];
}

- (void)performTask:(ZeroDarkCloud *)owner
{
	NSString *pushToken = owner.pushToken;
	if (pushToken == nil)
	{
		// YapActionManager will retry us again later
		return;
	}
	
	NSString *task_uuid = self.uuid;         // avoid retaining self
	__weak ZeroDarkCloud *weakOwner = owner; // avoid retaining owner
	
	[owner.webManager unregisterPushToken: pushToken
	                            forUserID: self.userID
	                               region: self.region
	                      completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                      completionBlock:^(NSURLResponse *response, NSError *error)
	{
		NSUInteger statusCode = 0;
		if (response) {
			statusCode = response.httpStatusCode;
		}
		
		// Success (for our puposes) means:
		//
		// 200 - unsubscribe was successful
		// 404 - user not found (so we don't have to worry about it anymore)
		
		if ((statusCode >= 200 && statusCode <= 299) || (statusCode == 404))
		{
			YapDatabaseConnection *rwConnection = weakOwner.databaseManager.rwDatabaseConnection;
			[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction removeObjectForKey:task_uuid inCollection:kZDCCollection_Tasks];
			}];
		}
		else
		{
			// YapActionManager will retry us again later
		}
	}];
}

@end
