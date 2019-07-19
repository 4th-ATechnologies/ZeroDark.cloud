#import "ZDCCloudNodeManager.h"

#import "ZDCDatabaseManager.h"
#import "ZDCCloudNode.h"
#import "ZDCLogging.h"
#import "ZDCNodeManager.h"

// Categories
#import "NSString+S4.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif


@implementation ZDCCloudNodeManager

static ZDCCloudNodeManager *sharedInstance = nil;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		sharedInstance = [[ZDCCloudNodeManager alloc] init];
	}});
}

+ (instancetype)sharedInstance
{
	return sharedInstance;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Find Cloud Node
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (ZDCCloudNode *)findCloudNodeWithCloudPath:(ZDCCloudPath *)cloudPath
                                      bucket:(NSString *)bucket
                                      region:(AWSRegion)region
                                 localUserID:(NSString *)localUserID
                                 transaction:(YapDatabaseReadTransaction *)transaction
{
	// Verify parameters:
	// - DEBUG: Throw assertion
	// - RELEASE: Ignore & return nil
	
	if (cloudPath == nil
	 || bucket == nil
	 || region == AWSRegion_Invalid
	 || localUserID == nil
	 || transaction == nil)
	{
		NSParameterAssert(cloudPath != nil);
		NSParameterAssert(bucket != nil);
		NSParameterAssert(region != AWSRegion_Invalid);
		NSParameterAssert(localUserID != nil);
		NSParameterAssert(transaction != nil);
		
		DDLogWarn(@"Method invoked with invalid parameter(s): %@", THIS_METHOD);
		return nil;
	}
	
	__block ZDCCloudNode *matchingCloudNode = nil;
	
	YapDatabaseAutoViewTransaction *viewTransaction_cloud_dirPrefix = nil;
	
	if ((viewTransaction_cloud_dirPrefix = [transaction ext:Ext_View_CloudNode_DirPrefix]))
	{
		// Optimal Plan
		//
		// The Ext_View_CloudNode_DirPrefix is already grouped by dirPrefix & sorted by cloudName.
		// Which means we can use a binary search algorithm to find it in O(log n).
		//
		// Where `n` = Number of S4ClodeNodes for which (due to pre-grouping):
		//   - cloudNode.dirPrefix == cloudPath.dirPrefix
		
		NSString *inFileName  = [cloudPath fileNameWithExt:nil];
		
		YapDatabaseViewFind *find = [YapDatabaseViewFind withObjectBlock:
		  ^NSComparisonResult (NSString *collection, NSString *key, id object)
		{
			__unsafe_unretained ZDCCloudNode *cloudNode = (ZDCCloudNode *)object;
			
			// IMPORTANT: YapDatabaseViewFind must match the sortingBlock such that:
			//
			// myView = @[ A, B, C, D, E, F, G ]
			//                ^^^^^^^
			//   sortingBlock(A, B) => NSOrderedAscending
			//   findBlock(A)       => NSOrderedAscending
			//
			//   sortingBlock(E, D) => NSOrderedDescending
			//   findBlock(E)       => NSOrderedDescending
			//
			//   findBlock(B) => NSOrderedSame
			//   findBlock(C) => NSOrderedSame
			//   findBlock(D) => NSOrderedSame
			
			NSString *fileName = [cloudNode.cloudLocator.cloudPath fileNameWithExt:nil];
			if (fileName == nil) fileName = @"";
			
			return [fileName compare:inFileName];
		}];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: localUserID
		                                   region: region
		                                   bucket: bucket
		                                   zAppID: cloudPath.zAppID
		                                dirPrefix: cloudPath.dirPrefix];
		
		// Binary search performance !!!
		NSUInteger index = [viewTransaction_cloud_dirPrefix findFirstMatchInGroup:group using:find];
		if (index != NSNotFound)
		{
			matchingCloudNode = [viewTransaction_cloud_dirPrefix objectAtIndex:index inGroup:group];
		}
	}
	else
	{
		// Backup Plan (defensive programming)
		//
		// View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all ZDCCloudNode's and look for matches (slow but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_CloudNodes usingBlock:
		  ^(NSString *key, ZDCCloudNode *cloudNode, BOOL *stop)
		{
			__unsafe_unretained ZDCCloudLocator *cloudLocator = cloudNode.cloudLocator;
			
			if ([cloudLocator.cloudPath isEqualToCloudPathIgnoringExt:cloudPath]
			 && [cloudLocator.bucket isEqualToString:bucket]
			 && cloudLocator.region == region
			 && [cloudNode.localUserID isEqualToString:localUserID])
			{
				matchingCloudNode = cloudNode;
				*stop = YES;
			}
		}];
	}
	
	return matchingCloudNode;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate CloudNodes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)enumerateCloudNodesWithParent:(ZDCCloudNode *)parent
                          transaction:(YapDatabaseReadTransaction *)transaction
                           usingBlock:(void (^)(ZDCCloudNode *cloudNode, BOOL *stop))enumBlock
{
	if (parent.dirPrefix == nil) return;
	
	YapDatabaseAutoViewTransaction *viewTransaction_cloud_dirPrefix = nil;
	
	if ((viewTransaction_cloud_dirPrefix = [transaction ext:Ext_View_CloudNode_DirPrefix]))
	{
		// Optimal Plan
		//
		// The Ext_View_CloudNode_DirPrefix is already grouped by dirPrefix.
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: parent.localUserID
		                                   region: parent.cloudLocator.region
		                                   bucket: parent.cloudLocator.bucket
		                                   zAppID: parent.cloudLocator.cloudPath.zAppID
		                                dirPrefix: parent.dirPrefix];
		
		[viewTransaction_cloud_dirPrefix enumerateKeysAndObjectsInGroup: group
		                                                     usingBlock:
			^(NSString *collection, NSString *key, ZDCCloudNode *cloudNode, NSUInteger index, BOOL *stop)
		{
			enumBlock(cloudNode, stop);
		}];
	}
	else
	{
		// Backup Plan (defensive programming)
		//
		// View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all ZDCCloudNode's and look for matches (slow but functional).
		
		[transaction enumerateKeysAndObjectsInCollection: kZDCCollection_CloudNodes
		                                      usingBlock:
			^(NSString *key, ZDCCloudNode *cloudNode, BOOL *stop)
		{
			if ([cloudNode.localUserID isEqualToString:parent.localUserID] &&
			    cloudNode.cloudLocator.region == parent.cloudLocator.region &&
			    [cloudNode.cloudLocator.bucket isEqualToString:parent.cloudLocator.bucket] &&
			    [cloudNode.cloudLocator.cloudPath.zAppID isEqualToString:parent.cloudLocator.cloudPath.zAppID] &&
			    [cloudNode.cloudLocator.cloudPath.dirPrefix isEqualToString:parent.dirPrefix])
			{
				enumBlock(cloudNode, stop);
			}
		}];
	}
}

/**
 * See header file for description.
 */
- (void)recursiveEnumerateCloudNodesWithParent:(ZDCCloudNode *)parent
                                   transaction:(YapDatabaseReadTransaction *)transaction
                                    usingBlock:(void (^)(ZDCCloudNode *cloudNode, BOOL *stop))enumBlock
{
	if (parent == nil) return;
	if (transaction == nil) return;
	
	[self _recursiveEnumerateCloudNodesWithParent: parent
	                                  transaction: transaction
	                                   usingBlock: enumBlock];
}

/**
 * Helper method for recursion.
 */
- (BOOL)_recursiveEnumerateCloudNodesWithParent:(ZDCCloudNode *)parent
                                    transaction:(YapDatabaseReadTransaction *)transaction
                                     usingBlock:(void (^)(ZDCCloudNode *cloudNode, BOOL *stop))enumBlock
{
	__block BOOL stopped = NO;
	
	[self enumerateCloudNodesWithParent: parent
	                        transaction: transaction
	                         usingBlock:^(ZDCCloudNode *child, BOOL *stop)
	{
		enumBlock(child, stop);
		if (*stop)
		{
			stopped = YES;
		}
		else
		{
			stopped = [self _recursiveEnumerateCloudNodesWithParent: child
			                                            transaction: transaction
			                                             usingBlock: enumBlock];
			if (stopped) {
				*stop = YES;
			}
		}
	}];
	
	return stopped;
}

/**
 * Returns a list of all cloudNodeID's belonging to the given user.
**/
- (NSArray<NSString *> *)allCloudNodeIDsWithLocalUserID:(NSString *)localUserID
                                            transaction:(YapDatabaseReadTransaction *)transaction
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	
	YapDatabaseAutoViewTransaction *viewTransaction_cloud_dirPrefix = nil;
	
	if ((viewTransaction_cloud_dirPrefix = [transaction ext:Ext_View_CloudNode_DirPrefix]))
	{
		// Optimal Plan
		//
		// The Ext_View_CloudNode_DirPrefix is already grouped by localUserID.
		
		NSString *prefix = [localUserID stringByAppendingString:@"|"];
		
		[viewTransaction_cloud_dirPrefix enumerateGroupsUsingBlock:^(NSString *group, BOOL *stop) {
			
			if ([group hasPrefix:prefix])
			{
				[viewTransaction_cloud_dirPrefix enumerateKeysInGroup: group
				                                           usingBlock:
					^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
				{
					[result addObject:key];
				}];
			}
		}];
	}
	else
	{
		// Backup Plan (defensive programming)
		//
		// View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all ZDCCloudNode's and look for matches (slow but functional).
		
		[transaction enumerateKeysAndObjectsInCollection: kZDCCollection_CloudNodes
														  usingBlock:^(NSString *key, ZDCCloudNode *cloudNode, BOOL *stop)
		{
			if ([cloudNode.localUserID isEqualToString:localUserID])
			{
				[result addObject:key];
			}
		}];
	}
	
	return result;
}

@end
