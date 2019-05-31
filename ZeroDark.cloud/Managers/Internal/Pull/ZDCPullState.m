#import "ZDCPullState.h"
#import "ZDCNode.h"

#import "NSDate+ZeroDark.h"
#import "NSString+ZeroDark.h"


@implementation ZDCPullState
{
	dispatch_queue_t queue;
	
	NSMutableDictionary<NSString*, NSMutableArray<S3ObjectInfo*>*> *lists;
	NSMutableArray<ZDCPullItem*> *items;
	NSMutableArray<NSURLSessionTask*>* tasks;
	
	NSMutableSet<NSString*> *unprocessedNodeIDs;
	NSMutableSet<NSString*> *unprocessedAvatarFilenames;
	NSMutableSet<NSString*> *unknownUserIDs;
	
	BOOL changeDetected;
	BOOL authFailed;
}

@synthesize localUserID = localUserID;
@synthesize zAppID = zAppID;
@synthesize pullID = pullID;

@synthesize hasProcessedChanges;
@synthesize needsFetchMoreChanges;
@synthesize isFullPull;

@dynamic tasks;
@dynamic tasksCount;
@dynamic unprocessedNodeIDs;
@dynamic unprocessedAvatarFilenames;
@dynamic unknownUserIDs;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID zAppID:(NSString *)inZAppID
{
	if ((self = [super init]))
	{
		queue = dispatch_queue_create("ZDCPullState", DISPATCH_QUEUE_SERIAL);
		
		localUserID = [inLocalUserID copy];
		zAppID = [inZAppID copy];
		
		pullID = [NSString zdcUUIDString];
		
		lists = [[NSMutableDictionary alloc] init];
		items = [[NSMutableArray alloc] init];
		tasks = [[NSMutableArray alloc] init];
		
		unprocessedNodeIDs         = [[NSMutableSet alloc] init];
		unprocessedAvatarFilenames = [[NSMutableSet alloc] init];
		unknownUserIDs             = [[NSMutableSet alloc] init];
		
		authFailed = NO;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark List Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)pushList:(NSArray<S3ObjectInfo *> *)objectList withRootNodeID:(NSString *)rootNodeID
{
	if (rootNodeID == nil) return;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray<S3ObjectInfo*> *list = lists[rootNodeID];
		if (list == nil) {
			list = lists[rootNodeID] = [[NSMutableArray alloc] init];
		}
		
		[list addObjectsFromArray:objectList];
		
	#pragma clang diagnostic pop
	}});
}

- (NSArray<S3ObjectInfo *> *)popListWithPrefix:(NSString *)prefix rootNodeID:(NSString *)rootNodeID
{
	if (rootNodeID == nil) return nil;
	
	__block NSMutableArray<S3ObjectInfo *> *results = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray<S3ObjectInfo*> *list = lists[rootNodeID];
		if (list)
		{
			NSUInteger i = 0;
			while (i < list.count)
			{
				S3ObjectInfo *info = list[i];
		
				if ([info.key hasPrefix:prefix])
				{
					if (results == nil) {
						results = [NSMutableArray arrayWithCapacity:16];
					}
					[results addObject:info];
					[list removeObjectAtIndex:i];
				}
				else
				{
					i++;
				}
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return results;
}

- (S3ObjectInfo *)popItemWithPath:(NSString *)path rootNodeID:(NSString *)rootNodeID
{
	if (rootNodeID == nil) return nil;
	
	__block S3ObjectInfo *result = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray<S3ObjectInfo*> *list = lists[rootNodeID];
		if (list)
		{
			NSUInteger i = 0;
			while (i < list.count)
			{
				S3ObjectInfo *info = list[i];
				
				if ([info.key isEqualToString:path])
				{
					result = info;
					[list removeObjectAtIndex:i];
				}
				else
				{
					i++;
				}
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Queue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)pushItem:(ZDCPullItem *)item
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[items addObject:item];
		
	#pragma clang diagnostic pop
	}});
}

- (ZDCPullItem *)popItemWithPreferredNodeIDs:(NSSet<NSString *> *)preferredNodeIDs
{
	__block ZDCPullItem *nextItem = nil;
	__block NSInteger nextItemDepth = -1;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		// Algorithm:
		//
		// - First: prefer items with a lower depth (more shallow within the graph)
		// - Second: prefer items that were modified more recently
		
		for (ZDCPullItem *item in items)
		{
			// Determine the depth of the item.
			//
			// If the delegate gave us a list of preferredNodeIDs,
			// this allows us to artificially decrease the depth of the node,
			// which increases its priority within the queue.
			
			NSInteger itemDepth = -1;
			if (preferredNodeIDs)
			{
				for (NSUInteger i = item.parents.count; i > 0; i--)
				{
					NSString *parentNodeID = item.parents[i-1];
					if ([preferredNodeIDs containsObject:parentNodeID])
					{
						itemDepth = item.parents.count - i;
						break;
					}
				}
			}
			if (itemDepth < 0)
			{
				itemDepth = item.parents.count;
			}
			
			if ((nextItem == nil) || (itemDepth < nextItemDepth))
			{
				nextItem = item;
				nextItemDepth = itemDepth;
			}
			else
			{
				NSDate *nlm = ZDCLaterDate(nextItem.rcrdLastModified, nextItem.dataLastModified);
				NSDate *ilm = ZDCLaterDate(item.rcrdLastModified, item.dataLastModified);
				
				BOOL later = NO;
				
				if (ilm)
				{
					if (nlm == nil)
					{
						later = YES;
					}
					else
					{
						later = [ilm isAfter:nlm];
					}
				}
				
				if (later)
				{
					nextItem = item;
					nextItemDepth = itemDepth;
				}
			}
		}
		
		if (nextItem)
		{
			[items removeObjectIdenticalTo:nextItem];
		}
		
	#pragma clang diagnostic pop
	}});
	
	return nextItem;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Task Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<NSURLSessionTask *> *)tasks
{
	__block NSArray<NSURLSessionTask *> *result = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = [tasks copy];
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (NSUInteger)tasksCount
{
	__block NSUInteger result = 0;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = tasks.count;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)addTask:(NSURLSessionTask *)task
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[tasks addObject:task];
		
	#pragma clang diagnostic pop
	}});
}

- (void)removeTask:(NSURLSessionTask *)task
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[tasks removeObject:task];
		
	#pragma clang diagnostic pop
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSSet<NSString *> *)unprocessedNodeIDs
{
	__block NSSet<NSString *>* result = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = [unprocessedNodeIDs copy];
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)addUnprocessedNodeIDs:(NSArray<NSString *>*)nodeIDs
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[unprocessedNodeIDs addObjectsFromArray:nodeIDs];
		
	#pragma clang diagnostic pop
	}});
}

- (void)removeUnprocessedNodeID:(NSString *)nodeID
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[unprocessedNodeIDs removeObject:nodeID];
		
	#pragma clang diagnostic pop
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Avatar Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSSet<NSString *> *)unprocessedAvatarFilenames
{
	__block NSSet<NSString *>* result = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = [unprocessedAvatarFilenames copy];
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)addUnprocessedAvatarFilenames:(NSArray<NSString *> *)avatarFilenames
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[unprocessedAvatarFilenames addObjectsFromArray:avatarFilenames];
		
	#pragma clang diagnostic pop
	}});
}

- (void)removeUnprocessedAvatarFilename:(NSString *)avatarFilename
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[unprocessedAvatarFilenames removeObject:avatarFilename];
		
	#pragma clang diagnostic pop
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSSet<NSString *> *)unknownUserIDs
{
	__block NSSet<NSString *>* result = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = [unknownUserIDs copy];
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)addUnknownUserIDs:(NSSet<NSString *>*)userIDs
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[unknownUserIDs unionSet:userIDs];
		
	#pragma clang diagnostic pop
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth Failure
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isFirstChangeDetected
{
	__block BOOL result = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (changeDetected == NO)
		{
			result = changeDetected = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

/**
 * Returns YES if this is the first time we're processing an auth failure.
**/
- (BOOL)isFirstAuthFailure
{
	__block BOOL result = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (authFailed == NO)
		{
			result = authFailed = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

@end
