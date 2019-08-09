/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPullStateManager.h"

#import <YapDatabase/YapCollectionKey.h>

@interface ZDCPullState ()
- (instancetype)initWithLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;
@end


@implementation ZDCPullStateManager {
	
	dispatch_queue_t queue;
	NSMutableDictionary<YapCollectionKey *, ZDCPullState *> *pullStates;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		queue = dispatch_queue_create("ZDCPullStateManager", DISPATCH_QUEUE_SERIAL);
		
		pullStates = [[NSMutableDictionary alloc] init];
	}
	return self;
}

#pragma mark Creating & Deleting SyncState

/**
 * If a syncState already exists for this userID, return nil.
 * Otherwise, a new syncState is created and returned.
**/
- (ZDCPullState *)maybeCreatePullStateForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(zAppID != nil);
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	__block ZDCPullState *newPullState = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		ZDCPullState *existingPullState = pullStates[tuple];
		if (existingPullState == nil)
		{
			newPullState = [[ZDCPullState alloc] initWithLocalUserID:localUserID zAppID:zAppID];
			pullStates[tuple] = newPullState;
		}
		
	#pragma clang diagnostic pop
	}});
	
	return newPullState;
}

/**
 * Deletes the associated pull state, if it exists.
**/
- (void)deletePullState:(ZDCPullState *)pullStateToDelete
{
	NSString *localUserID = pullStateToDelete.localUserID;
	NSString *zAppID = pullStateToDelete.zAppID;
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		ZDCPullState *existingPullState = pullStates[tuple];
		
		if (existingPullState == pullStateToDelete)
		{
			[pullStates removeObjectForKey:tuple];
		}
		
	#pragma clang diagnostic pop
	}});
}

- (ZDCPullState *)deletePullStateForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(zAppID != nil);
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	__block ZDCPullState *deletedPullState = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		deletedPullState = pullStates[tuple];
		if (deletedPullState)
		{
			[pullStates removeObjectForKey:tuple];
		}
		
	#pragma clang diagnostic pop
	}});
	
	return deletedPullState;
}

#pragma mark Checking SyncState

/**
 * Returns whether or not the pull has been cancelled.
 * The methods within the pull logic below should check this method regularly.
**/
- (BOOL)isPullCancelled:(ZDCPullState *)pullState
{
	NSString *localUserID = pullState.localUserID;
	NSString *zAppID = pullState.zAppID;
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	__block BOOL cancelled = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		ZDCPullState *existingPullState = pullStates[tuple];
		
		if (!existingPullState || (existingPullState != pullState)) {
			cancelled = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	return cancelled;
}

@end
