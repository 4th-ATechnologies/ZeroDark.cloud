/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCNodeManager.h"

#import "ZDCCloudNodeManager.h"
#import "ZDCCloudPathManager.h"
#import "ZDCDatabaseManager.h"
#import "ZDCLocalUser.h"
#import "ZDCLogging.h"
#import "ZDCNodePrivate.h"
#import "ZDCPublicKey.h"
#import "ZDCTreesystemPath.h"
#import "ZDCTrunkNode.h"

// Categories
#import "NSData+S4.h"
#import "NSData+ZeroDark.h"
#import "NSDate+ZeroDark.h"
#import "NSError+ZeroDark.h"
#import "NSMutableDictionary+ZeroDark.h"
#import "NSString+ZeroDark.h"

// Libraries
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif
#import <YapDatabase/YapDatabaseView.h>
#import <YapDatabase/YapDatabaseAutoView.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@implementation ZDCNodeManager

static ZDCNodeManager *sharedInstance = nil;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		sharedInstance = [[ZDCNodeManager alloc] init];
	}});
}

+ (instancetype)sharedInstance
{
	return sharedInstance;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Containers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCTrunkNode *)trunkNodeForLocalUserID:(NSString *)localUserID
                                            zAppID:(NSString *)zAppID
                                             trunk:(ZDCTreesystemTrunk)trunk
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	NSString *nodeID =
	  [ZDCTrunkNode uuidForLocalUserID: localUserID
	                            zAppID: zAppID
	                             trunk: trunk];
	
	return [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCTrunkNode *)trunkNodeForNode:(ZDCNode *)node
                                transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCTrunkNode *trunkNode = nil;
	do {
		
		if ([node isKindOfClass:[ZDCTrunkNode class]])
		{
			trunkNode = (ZDCTrunkNode *)node;
			break;
		}
		else
		{
			if ([node.parentID hasSuffix:@"|graft"])
			{
				NSString *localUserID = nil;
				NSString *zAppID = nil;
				[ZDCNode getLocalUserID:&localUserID zAppID:&zAppID fromParentID:node.parentID];
				
				node = [self findNodeWithPointeeID: node.uuid
				                       localUserID: localUserID
				                            zAppID: zAppID
				                       transaction: transaction];
			}
			else
			{
				node = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
			}
		}
		
	} while (node);
	
	return trunkNode;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)anchorNodeForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCNode *anchorNode = node;

	ZDCNode *currentNode = node;
	while (currentNode)
	{
		if (currentNode.anchor || currentNode.parentID == nil)
		{
			anchorNode = currentNode;
			break;
		}
		
		currentNode = [transaction objectForKey:currentNode.parentID inCollection:kZDCCollection_Nodes];
	}
	
	return anchorNode;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Owners
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSString *)ownerIDForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCNode *anchorNode = [self anchorNodeForNode:node transaction:transaction];
	
	if (anchorNode.anchor)
		return anchorNode.anchor.userID;
	else
		return node.localUserID;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCUser *)ownerForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	NSString *ownerID = [self ownerIDForNode:node transaction:transaction];
	
	return [transaction objectForKey:ownerID inCollection:kZDCCollection_Users];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pointers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)targetNodeForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (!node.isPointer) return node;
	
	ZDCNode *target = node;
	do {
		target = [transaction objectForKey:target.pointeeID inCollection:kZDCCollection_Nodes];
		
	} while (target.isPointer);
	
	return target;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Paths
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCTreesystemPath *)pathForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (node == nil) {
		return nil;
	}
	
	ZDCTrunkNode *trunkNode = nil;
	NSMutableArray<NSString *> *pathComponents = [NSMutableArray arrayWithCapacity:8];
	
	while (YES)
	{
		if ([node isKindOfClass:[ZDCTrunkNode class]])
		{
			trunkNode = (ZDCTrunkNode *)node;
			break;
		}
		else if (node)
		{
			if (![node.parentID hasSuffix:@"|graft"])
			{
				[pathComponents insertObject:(node.name ?: @"") atIndex:0];
			}
		}
		else
		{
			break;
		}
		
		if ([node.parentID hasSuffix:@"|graft"])
		{
			NSString *localUserID = nil;
			NSString *zAppID = nil;
			[ZDCNode getLocalUserID:&localUserID zAppID:&zAppID fromParentID:node.parentID];
			
			node = [self findNodeWithPointeeID: node.uuid
			                       localUserID: localUserID
			                            zAppID: zAppID
			                       transaction: transaction];
		}
		else
		{
			node = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
		}
	}
	
	ZDCTreesystemTrunk trunk = (trunkNode ? trunkNode.trunk : ZDCTreesystemTrunk_Invalid);
	
	ZDCTreesystemPath *path =
	  [[ZDCTreesystemPath alloc] initWithPathComponents: pathComponents
	                                              trunk: trunk];
	return path;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSArray<NSString *> *)parentNodeIDsForNode:(ZDCNode *)node
                                  transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	NSMutableArray *parents = [NSMutableArray arrayWithCapacity:8];
	
	NSString *parentID = node.parentID;
	ZDCNode *parent = nil;
	
	do
	{
		if ([parentID hasSuffix:@"|graft"])
		{
			NSString *localUserID = nil;
			NSString *zAppID = nil;
			[ZDCNode getLocalUserID:&localUserID zAppID:&zAppID fromParentID:node.parentID];
			
			parent = [self findNodeWithPointeeID: node.uuid
			                         localUserID: localUserID
			                              zAppID: zAppID
			                         transaction: transaction];
		}
		else
		{
			parent = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
		}
		
		parentID = parent.parentID;
		if (parentID && ![parentID hasSuffix:@"|graft"])
		{
			[parents insertObject:parentID atIndex:0];
		}
	
	} while (parent && parentID);
	
	return parents;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (BOOL)isNode:(NSString *)inNodeID
 aDescendantOf:(NSString *)potentialParentID
   transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	NSString *nodeID = inNodeID;
	while (nodeID)
	{
		ZDCNode *node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		if (node)
		{
			if ([node.parentID isEqualToString:potentialParentID])
				return YES;
		}
		
		nodeID = node.parentID;
		if ([nodeID hasSuffix:@"|graft"])
		{
			NSString *localUserID = nil;
			NSString *zAppID = nil;
			[ZDCNode getLocalUserID:&localUserID zAppID:&zAppID fromParentID:nodeID];
			
			node = [self findNodeWithPointeeID: nodeID
										  localUserID: localUserID
												 zAppID: zAppID
										  transaction: transaction];
			nodeID = node.uuid;
		}
	}
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate Nodes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)enumerateNodeIDsWithParentID:(NSString *)parentID
                         transaction:(YapDatabaseReadTransaction *)transaction
                          usingBlock:(void (^)(NSString *nodeID, BOOL *stop))enumBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	NSParameterAssert(enumBlock != nil);
	
	ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
	if (parentNode) {
		parentNode = [self targetNodeForNode:parentNode transaction:transaction]; // follow pointer(s)
		parentID = parentNode.uuid;
	}
	
	if (parentID == nil) return; // this check must come after following pointer(s)
	
	YapDatabaseViewTransaction *treesystemViewTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((treesystemViewTransaction = [transaction ext:Ext_View_Treesystem_Name]))
	{
		// Use Treesystem View for best performance.
		//
		// This allows us to directly access only those nodes we're interested in.
		
		[treesystemViewTransaction enumerateKeysInGroup:parentID usingBlock:
		    ^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
		{
			enumBlock(key, stop);
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Treesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCTrunkNode *trunkNode = [self trunkNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: trunkNode.localUserID
		                                   zAppID: trunkNode.zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup:group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				enumBlock(key, stop);
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				enumBlock(key, stop);
			}
		}];
	}
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)recursiveEnumerateNodeIDsWithParentID:(NSString *)parentID
                                  transaction:(YapDatabaseReadTransaction *)transaction
                                   usingBlock:(void (^)(NSString *nodeID,
                                                        NSArray<NSString*> *pathFromParent,
                                                        BOOL *recurseInto,
                                                        BOOL *stop))enumBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	NSParameterAssert(enumBlock != nil);
	
	NSMutableArray<NSString*> *pathFromParent = [NSMutableArray array];
	[self _recursiveEnumerateNodeIDsWithParentID: parentID
	                              pathFromParent: pathFromParent
	                                 transaction: transaction
	                                  usingBlock: enumBlock];
}

/**
 * Recursion helper method.
 *
 * @return YES if enumBlock.stop was set to true. I.e. YES if recursion should be aborted.
 */
- (BOOL)_recursiveEnumerateNodeIDsWithParentID:(NSString *)parentID
                                pathFromParent:(NSMutableArray<NSString*> *)pathFromParent
                                   transaction:(YapDatabaseReadTransaction *)transaction
                                    usingBlock:(void (^)(NSString *nodeID,
                                                         NSArray<NSString*> *pathFromParent,
                                                         BOOL *recurseInto,
                                                         BOOL *stop))enumBlock
{
	__block BOOL stopped = NO;
	
	[self enumerateNodeIDsWithParentID: parentID
	                       transaction: transaction
	                        usingBlock:^(NSString *nodeID, BOOL *stop)
	{
		BOOL recurseInto = YES;
		enumBlock(nodeID, pathFromParent, &recurseInto, stop);
		if (*stop)
		{
			stopped = YES;
		}
		else if (recurseInto)
		{
			[pathFromParent addObject:nodeID];
			stopped = [self _recursiveEnumerateNodeIDsWithParentID: nodeID
			                                        pathFromParent: pathFromParent
			                                           transaction: transaction
			                                            usingBlock: enumBlock];
			
			[pathFromParent removeLastObject];
			if (stopped) {
				*stop = YES;
			}
		}
	}];
	
	return stopped;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)enumerateNodesWithParentID:(NSString *)parentID
                       transaction:(YapDatabaseReadTransaction *)transaction
                        usingBlock:(void (^)(ZDCNode *node, BOOL *stop))enumBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	NSParameterAssert(enumBlock != nil);
	
	ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
	if (parentNode) {
		parentNode = [self targetNodeForNode:parentNode transaction:transaction]; // follow pointer(s)
		parentID = parentNode.uuid;
	}
	
	if (parentID == nil) return; // this check must come after following pointer(s)
	
	YapDatabaseViewTransaction *treesystemViewTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((treesystemViewTransaction = [transaction ext:Ext_View_Treesystem_Name]))
	{
		// Use Treesystem View for best performance.
		//
		// This allows us to directly access only those nodes we're interested in.
		
		[treesystemViewTransaction enumerateKeysAndObjectsInGroup:parentID usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			enumBlock((ZDCNode *)object, stop);
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Treesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCTrunkNode *trunkNode = [self trunkNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: trunkNode.localUserID
		                                   zAppID: trunkNode.zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup:group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				enumBlock(node, stop);
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				enumBlock(node, stop);
			}
		}];
	}
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (void)recursiveEnumerateNodesWithParentID:(NSString *)parentID
                                transaction:(YapDatabaseReadTransaction *)transaction
                                 usingBlock:(void (^)(ZDCNode *node,
                                                      NSArray<ZDCNode*> *pathFromParent,
                                                      BOOL *recurseInto,
                                                      BOOL *stop))enumBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	NSParameterAssert(enumBlock != nil);
	
	NSMutableArray<ZDCNode*> *pathFromParent = [NSMutableArray array];
	[self _recursiveEnumerateNodesWithParentID: parentID
	                            pathFromParent: pathFromParent
	                               transaction: transaction
	                                usingBlock: enumBlock];
}

/**
 * Recursion helper method.
 *
 * @return YES if enumBlock.stop was set to true. I.e. YES if recursion should be aborted.
 */
- (BOOL)_recursiveEnumerateNodesWithParentID:(NSString *)parentID
                              pathFromParent:(NSMutableArray<ZDCNode*> *)pathFromParent
                                 transaction:(YapDatabaseReadTransaction *)transaction
                                  usingBlock:(void (^)(ZDCNode *node,
                                                       NSArray<ZDCNode*> *pathFromParent,
                                                       BOOL *recurseInto,
                                                       BOOL *stop))enumBlock
{
	__block BOOL stopped = NO;
	
	[self enumerateNodesWithParentID: parentID
	                     transaction: transaction
	                      usingBlock:^(ZDCNode *node, BOOL *stop)
	{
		BOOL recurseInto = YES;
		enumBlock(node, pathFromParent, &recurseInto, stop);
		if (*stop)
		{
			stopped = YES;
		}
		else if (recurseInto)
		{
			[pathFromParent addObject:node];
			stopped = [self _recursiveEnumerateNodesWithParentID: node.uuid
			                                      pathFromParent: pathFromParent
			                                         transaction: transaction
			                                          usingBlock: enumBlock];
			
			[pathFromParent removeLastObject];
			if (stopped) {
				*stop = YES;
			}
		}
	}];
	
	return stopped;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (BOOL)isEmptyNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	__block BOOL isEmpty = YES;
	
	[self enumerateNodeIDsWithParentID: node.uuid
	                       transaction: transaction
	                        usingBlock:^(NSString *nodeID, BOOL *stop)
	{
		isEmpty = NO;
		*stop = YES;
	}];
	
	return isEmpty;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Find Node
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)findNodeWithName:(NSString *)nodeName
                              parentID:(NSString *)parentID
                           transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
	if (parentNode) {
		parentNode = [self targetNodeForNode:parentNode transaction:transaction]; // follow pointer(s)
		parentID = parentNode.uuid;
	}
	
	if (nodeName == nil) return nil;
	if (parentID == nil) return nil; // this check must come after following pointer(s)
    
	__block ZDCNode *matchingNode = nil;
    
	YapDatabaseAutoViewTransaction *treesystemViewTransaction = nil;
	YapDatabaseAutoViewTransaction *flatViewTransaction = nil;
    
	if ((treesystemViewTransaction = [transaction ext:Ext_View_Treesystem_Name]))
	{
		// Use Treesystem View for best performance.
		//
		// The Ext_View_Treesystem already has the nodes sorted by name (for each parentID).
		// Which means we can use a binary search algorithm to find it in O(log n).
		//
		// Where `n` = Number of ZDCNode's for which (due to pre-grouping):
		//   - node.parentID == parentID
		//
		// Translation from computer science lingo:
		// "This lookup is very fast because it only requires fetching a few objects from the database."
		
		YapDatabaseViewFind *find = [YapDatabaseViewFind withObjectBlock:
		  ^(NSString *collection, NSString *key, id object)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
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
			
			return [node.name localizedCaseInsensitiveCompare:nodeName];
		}];
		
		// binary search performance !!!
		NSUInteger index = [treesystemViewTransaction findFirstMatchInGroup:parentID using:find];
		
		if (index != NSNotFound)
		{
			matchingNode = [treesystemViewTransaction objectAtIndex:index inGroup:parentID];
		}
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Treesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCTrunkNode *trunkNode = [self trunkNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: trunkNode.localUserID
		                                   zAppID: trunkNode.zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup:group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				// Remember:
				// - [nil localizedCaseInsensitiveCompare:nodeName] == 0
				// - NSOrderedSame == 0
				
				if (node.name && ([node.name localizedCaseInsensitiveCompare:nodeName] == NSOrderedSame))
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				// Remember:
				// - [nil localizedCaseInsensitiveCompare:nodeName] == 0
				// - NSOrderedSame == 0
				
				if (node.name && ([node.name localizedCaseInsensitiveCompare:nodeName] == NSOrderedSame))
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	
	return matchingNode;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)findNodeWithPath:(ZDCTreesystemPath *)path
                           localUserID:(NSString *)localUserID
                                zAppID:(NSString *)zAppID
                           transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCNode *node = nil;
	NSString *containerID =
	  [ZDCTrunkNode uuidForLocalUserID: localUserID
	                            zAppID: zAppID
	                             trunk: path.trunk];
	
	if (path.isTrunk)
	{
		node = [transaction objectForKey:containerID inCollection:kZDCCollection_Nodes];
	}
	else
	{
		NSString *parentID = containerID;
		
		for (NSString *filename in path.pathComponents)
		{
			node = [self findNodeWithName:filename parentID:parentID transaction:transaction];
			// Do not follow pointer here.
			// If path ends in pointer, then the pointer node must be returned.
			
			if (node == nil) break;
			parentID = node.uuid;
		}
	}

	return node;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (ZDCNode *)findNodeWithCloudName:(NSString *)cloudName
                          parentID:(NSString *)parentID
                       transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
	if (parentNode) {
		parentNode = [self targetNodeForNode:parentNode transaction:transaction]; // follow pointer(s)
		parentID = parentNode.uuid;
	}
	
	if (cloudName == nil) return nil;
	if (parentID == nil) return nil; // this check must come after following pointer(s)
	
	// The given `cloudName` should NOT have a file extension.
	// If it does, let's fix that.
	//
	NSRange dotRange = [cloudName rangeOfString:@"."];
	if (dotRange.location != NSNotFound)
	{
		cloudName = [cloudName substringToIndex:dotRange.location];
	}
	
	ZDCCloudPathManager *cloudPathManager = [ZDCCloudPathManager sharedInstance];
	
	__block ZDCNode *matchingNode = nil;
	
	YapDatabaseAutoViewTransaction *treesystemViewTransaction = nil;
	YapDatabaseAutoViewTransaction *flatViewTransaction = nil;
	
	if ((treesystemViewTransaction = [transaction ext:Ext_View_Treesystem_CloudName]))
	{
		// Use Treesystem View for best performance.
		//
		// The view already has the nodes sorted by cloudName (for each parentID).
		// Which means we can use a binary search algorithm to find it in O(log n).
		//
		// Where `n` = Number of ZDCNode's for which (due to pre-grouping):
		//   - node.parentID == parentID
		
		YapDatabaseViewFind *find = [YapDatabaseViewFind withObjectBlock:
		  ^(NSString *collection, NSString *key, id object)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
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
			
			NSString *nodeCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
			return [nodeCloudName compare:cloudName];
		}];
		
		// binary search performance !!!
		NSUInteger index = [treesystemViewTransaction findFirstMatchInGroup:parentID using:find];
		
		if (index != NSNotFound)
		{
			matchingNode = [treesystemViewTransaction objectAtIndex:index inGroup:parentID];
		}
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Treesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCTrunkNode *trunkNode = [self trunkNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: trunkNode.localUserID
		                                   zAppID: trunkNode.zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup: group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				// Remember:
				// - [nil localizedCaseInsensitiveCompare:anything] == 0
				// - NSOrderedSame == 0
				
				NSString *nodeCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
				if (nodeCloudName && ([nodeCloudName compare:cloudName] == NSOrderedSame))
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.parentID isEqualToString:parentID])
			{
				// Remember:
				// - [nil localizedCaseInsensitiveCompare:anything] == 0
				// - NSOrderedSame == 0
				
				NSString *nodeCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
				if (nodeCloudName && ([nodeCloudName compare:cloudName] == NSOrderedSame))
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	
	return matchingNode;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (ZDCNode *)findNodeWithCloudID:(NSString *)cloudID
                     localUserID:(NSString *)localUserID
                          zAppID:(NSString *)zAppID
                     transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (cloudID == nil) return nil;
	if (localUserID == nil) return nil;
	if (zAppID == nil) return nil;
	
	__block ZDCNode *matchingNode = nil;
	
	YapDatabaseSecondaryIndexTransaction *secondaryIndexTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((secondaryIndexTransaction = [transaction ext:Ext_Index_Nodes]))
	{
		// Use secondary index for best performance (uses sqlite indexes)
		//
		// WHERE fileID = ?
		
		NSString *queryString = [NSString stringWithFormat:@"WHERE %@ = ?", Index_Nodes_Column_CloudID];
		YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryString, cloudID];
		
		[secondaryIndexTransaction enumerateKeysAndObjectsMatchingQuery:query usingBlock:
		    ^(NSString *collection, NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.localUserID isEqualToString:localUserID])
			{
				ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
				
				if ([trunkNode.zAppID isEqualToString:zAppID])
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Secondary Index extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup: group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.cloudID isEqualToString:cloudID])
			{
				ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
				
				if ([trunkNode.zAppID isEqualToString:zAppID])
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.'
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.cloudID isEqualToString:cloudID])
			{
				if ([node.localUserID isEqualToString:localUserID])
				{
					ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
					
					if ([trunkNode.zAppID isEqualToString:zAppID])
					{
						matchingNode = node;
						*stop = YES;
					}
				}
			}
		}];
	}
	
	return matchingNode;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)findNodeWithCloudPath:(ZDCCloudPath *)cloudPath
                                     bucket:(NSString *)bucket
                                     region:(AWSRegion)region
                                localUserID:(NSString *)localUserID
                                     zAppID:(NSString *)zAppID
                                transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (cloudPath == nil) return nil;
	if (bucket == nil) return nil;
	if (region == AWSRegion_Invalid) return nil;
	if (localUserID ==  nil) return nil;
	
	ZDCNode *parentNode =
	  [self findNodeWithDirPrefix: cloudPath.dirPrefix
	                       bucket: bucket
	                       region: region
	                  localUserID: localUserID
	                       zAppID: zAppID
	                  transaction: transaction];
	
	if (parentNode == nil) {
		return nil;
	}
	
	return [self findNodeWithCloudName: [cloudPath fileNameWithExt:nil]
	                          parentID: parentNode.uuid
	                       transaction: transaction];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)findNodeWithDirPrefix:(NSString *)prefix
                                    bucket:(NSString *)bucket
                                    region:(AWSRegion)region
                               localUserID:(NSString *)localUserID
                                    zAppID:(NSString *)zAppID
                               transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (prefix == nil) return nil;
	if (bucket == nil) return nil;
	if (region == AWSRegion_Invalid) return nil;
	if (localUserID == nil) return nil;
	if (zAppID == nil) return nil;
	
	__block ZDCNode *matchingNode = nil;
	
	YapDatabaseSecondaryIndexTransaction *secondaryIndexTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((secondaryIndexTransaction = [transaction ext:Ext_Index_Nodes]))
	{
		// Use secondary index for best performance (uses sqlite indexes)
		//
		// WHERE dirPrefix = ?
		
		NSString *queryString = [NSString stringWithFormat:@"WHERE %@ = ?", Index_Nodes_Column_DirPrefix];
		
		YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryString, prefix, prefix, prefix];
		
		[secondaryIndexTransaction enumerateKeysAndObjectsMatchingQuery:query usingBlock:
		    ^(NSString *collection, NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.localUserID isEqualToString:localUserID])
			{
				ZDCUser *owner = [self ownerForNode:node transaction:transaction];
				
				if ([owner.aws_bucket isEqualToString:bucket] && owner.aws_region == region)
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Secondary Index extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup: group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.dirPrefix isEqualToString:prefix])
			{
				ZDCUser *owner = [self ownerForNode:node transaction:transaction];
				
				if ([owner.aws_bucket isEqualToString:bucket] && owner.aws_region == region)
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.dirPrefix isEqualToString:prefix])
			{
				if ([node.localUserID isEqualToString:localUserID])
				{
					ZDCUser *owner = [self ownerForNode:node transaction:transaction];
					
					if ([owner.aws_bucket isEqualToString:bucket] && owner.aws_region == region)
					{
						matchingNode = node;
						*stop = YES;
					}
				}
			}
		}];
	}
	
	return matchingNode;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (nullable ZDCNode *)findNodeWithPointeeID:(NSString *)pointeeID
                                localUserID:(NSString *)localUserID
                                     zAppID:(NSString *)zAppID
                                transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (pointeeID == nil) return nil;
	if (localUserID == nil) return nil;
	if (zAppID == nil) return nil;
	
	__block ZDCNode *matchingNode = nil;
	
	YapDatabaseSecondaryIndexTransaction *secondaryIndexTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((secondaryIndexTransaction = [transaction ext:Ext_Index_Nodes]))
	{
		// Use secondary index for best performance (uses sqlite indexes)
		//
		// WHERE pointeeID = ?
		
		NSString *queryString = [NSString stringWithFormat:@"WHERE %@ = ?", Index_Nodes_Column_PointeeID];
		
		YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryString, pointeeID];
		
		[secondaryIndexTransaction enumerateKeysAndObjectsMatchingQuery:query usingBlock:
		    ^(NSString *collection, NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.localUserID isEqualToString:localUserID])
			{
				ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
				
				if ([trunkNode.zAppID isEqualToString:zAppID])
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Secondary Index extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup: group
		                                         usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.pointeeID isEqualToString:pointeeID])
			{
				ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
				
				if ([trunkNode.zAppID isEqualToString:zAppID])
				{
					matchingNode = node;
					*stop = YES;
				}
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.pointeeID isEqualToString:pointeeID])
			{
				if ([node.localUserID isEqualToString:localUserID])
				{
					ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
					
					if ([trunkNode.zAppID isEqualToString:zAppID])
					{
						matchingNode = node;
						*stop = YES;
					}
				}
			}
		}];
	}
	
	return matchingNode;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Lists
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSArray<NSString *> *)allNodeIDsWithLocalUserID:(NSString *)localUserID
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (localUserID == nil) return [NSArray array];
	
	NSMutableArray *result = [NSMutableArray array];
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Use Flat View for best performance.
		
		NSMutableArray<NSString*> *zAppIDs = [NSMutableArray array];
		NSString *prefix = [localUserID stringByAppendingString:@"|"];
		
		[flatViewTransaction enumerateGroupsUsingBlock:^(NSString *group, BOOL *stop) {
			
			if ([group hasPrefix:prefix]) {
				NSString *zAppID = [group substringFromIndex:prefix.length];
				[zAppIDs addObject:zAppID];
			}
		}];
		
		for (NSString *zAppID in zAppIDs)
		{
			NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
			[flatViewTransaction enumerateKeysInGroup: group
			                               usingBlock:
			    ^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
			{
				[result addObject:key];
			}];
		}
	}
	else
	{
		// Backup Plan (defensive programming)
		//
		// Scan all nodes and look for matches (slow but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.localUserID isEqualToString:localUserID])
			{
				[result addObject:key];
			}
		}];
	}
	
	return result;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSArray<NSString *> *)allNodeIDsWithLocalUserID:(NSString *)localUserID
                                            zAppID:(NSString *)zAppID
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (localUserID == nil) return [NSArray array];
	if (zAppID == nil) return [NSArray array];
	
	NSMutableArray *result = [NSMutableArray array];
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Use Flat View for best performance.
		
		NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
		[flatViewTransaction enumerateKeysInGroup: group
		                               usingBlock:
		    ^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
		{
			[result addObject:key];
		}];
	}
	else
	{
		// Backup Plan (defensive programming)
		//
		// Scan all nodes and look for matches (slow but functional).
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.localUserID isEqualToString:localUserID])
			{
				ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
				if ([trunkNode.zAppID isEqualToString:zAppID])
				{
					[result addObject:key];
				}
			}
		}];
	}
	
	return result;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
**/
- (NSArray<NSString *> *)allUploadedNodeIDsWithLocalUserID:(NSString *)localUserID
                                                    zAppID:(NSString *)zAppID
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	if (localUserID == nil) return nil;
	if (zAppID == nil) return nil;
	
	NSMutableArray *uploadedNodeIDs = nil;
	
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	YapDatabaseSecondaryIndexTransaction *secondaryIndexTransaction = nil;
	
	if ((flatViewTransaction = [transaction ext:Ext_View_Flat]) &&
	    (secondaryIndexTransaction = [transaction ext:Ext_Index_Nodes]))
	{
		// Combine multiple extensions for best performance (uses sqlite indexes)
		//
		// - The flatViewTransaction can quickly give us a list of nodeIDs for the <localUserID, zAppID>,
		//   but doesn't tell us which are uploaded.
		//
		// - The secondaryIndexTransaction can quickly tell us which nodes are uploaded,
		//   but doesn't tell us which <localUserID, zAppID> they belong to.
		//
		// So we can combine the 2.
		
		NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
		NSUInteger capacity = [flatViewTransaction numberOfItemsInGroup:group];
		NSMutableSet<NSString *> *nodeIDs = [NSMutableSet setWithCapacity:capacity];
		
		[flatViewTransaction enumerateKeysInGroup: group
		                               usingBlock:
		  ^(NSString *collection, NSString *nodeID, NSUInteger index, BOOL *stop)
		{
			[nodeIDs addObject:nodeID];
		}];
		
		NSMutableArray<NSString *> *uploadedNodeIDs = [NSMutableArray arrayWithCapacity:nodeIDs.count];
		
		NSString *queryString = [NSString stringWithFormat:@"WHERE %@ IS NOT NULL", Index_Nodes_Column_CloudID];
		YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryString];
		
		[secondaryIndexTransaction enumerateKeysMatchingQuery:query usingBlock:
		^(NSString *collection, NSString *nodeID, BOOL *stop)
		{
			if ([nodeIDs containsObject:nodeID])
			{
				[uploadedNodeIDs addObject:nodeID];
			}
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Secondary Index extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan the users collection and look for a match (slow but functional).
		
		NSString *group = [ZDCDatabaseManager groupForLocalUserID:localUserID zAppID:zAppID];
		
		NSUInteger capacity = [flatViewTransaction numberOfItemsInGroup:group];
		uploadedNodeIDs = [NSMutableArray arrayWithCapacity:capacity];
		
		[flatViewTransaction enumerateKeysAndObjectsInGroup: group
		                                         usingBlock:
		    ^(NSString *collection, NSString *nodeID, id object, NSUInteger index, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if (node.cloudID)
			{
				[uploadedNodeIDs addObject:nodeID];
			}
		}];
	}
	else
	{
		// Last resort (super defensive programming)
		//
		// None of the extensions we want are ready yet.'
		// It must be still initializing / updating.
		//
		// Scan the entire nodes collection and look for a match (slowest but functional).
		
		uploadedNodeIDs = [NSMutableArray arrayWithCapacity:128];
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Nodes
		                                      usingBlock:^(NSString *nodeID, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
			
			if ([node.localUserID isEqualToString:localUserID] && node.cloudID)
			{
				ZDCTrunkNode *trunkNode = [self trunkNodeForNode:node transaction:transaction];
				
				if ([trunkNode.zAppID isEqualToString:zAppID])
				{
					[uploadedNodeIDs addObject:nodeID];
				}
			}
		}];
	}
	
	return uploadedNodeIDs;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Permissions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (BOOL)resetPermissionsForNode:(ZDCNode *)node transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCLogAutoTrace();
	NSParameterAssert(transaction != nil);
	
	ZDCNode *parent = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
	if (parent == nil) return NO;
	
	[node.shareList removeAllShareItems];
	
	// Goal is to inherit permissions from the parent node.
	//
	[parent.shareList enumerateListWithBlock:^(NSString *key, ZDCShareItem *shareItem, BOOL *stop) {
		
		if (![key isEqualToString:@"UID:*"] &&
		    ![key isEqualToString:@"UID:anonymous"])
		{
			// Careful:
			// Don't copy shareItem.key.
			// That needs to get re-calculated via: wrapSymKey(node.encryptionKey, usingPubKey:someUser.pubKey)
			
			ZDCShareItem *copy = [[ZDCShareItem alloc] init];
			copy.permissions = shareItem.permissions;
			
			[node.shareList addShareItem:copy forKey:key];
		}
	}];
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Conflict Resolution
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCRestManager.html
 */
- (NSString *)resolveNamingConflict:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLogAutoTrace();
	
	NSString *name = node.name;
	if (name.length == 0) {
		name = [NSString zdcUUIDString];
	}
	
	NSString *name_base = [name stringByDeletingPathExtension];
	NSString *name_ext  = [name pathExtension];
	
	// Check to see if 'name_base' ends with a (space + number).
	//
	// - "Poems.doc"            -> NO
	// - "Bicycle Manual 3.pdf" -> YES
	// - "42.pdf"               -> NO
	
	NSRange numberRange = NSMakeRange(NSNotFound, 0);
	
	NSRange searchRange = NSMakeRange(0, name_base.length);
	NSRange spaceRange = [name_base rangeOfString:@" " options:0 range:searchRange];
	while (spaceRange.location != NSNotFound)
	{
		numberRange.location = spaceRange.location + 1;
		numberRange.length = name_base.length - numberRange.location;
		
		searchRange = numberRange;
		spaceRange = [name_base rangeOfString:@" " options:0 range:searchRange];
	}
	
	uint64_t numberToAppend = 2;
	
	if ((numberRange.location != NSNotFound) && (numberRange.length > 0))
	{
		NSString *numberString = [name_base substringWithRange:numberRange];
		const char *numStr = [numberString UTF8String];
		
		uint64_t parsedNumber = strtoull(numStr, NULL, 10);
		
		if (parsedNumber != 0)
		{
			name_base = [name_base substringToIndex:(numberRange.location - 1)];
			numberToAppend = parsedNumber;
		}
	}
	
	// Append increasing numbers until we find a name that's not in conflict.
	
	NSString *newName = nil;
	BOOL done = NO;
	
	do
	{
		if (name_ext.length > 0)
			newName = [NSString stringWithFormat:@"%@ %llu.%@", name_base, numberToAppend, name_ext];
		else
			newName = [NSString stringWithFormat:@"%@ %llu", name_base, numberToAppend];
		
		ZDCNode *conflictingNode =
		  [self findNodeWithName: newName
		                parentID: node.parentID
		             transaction: transaction];
		
		if (conflictingNode) {
			numberToAppend++;
		}
		else {
			done = YES;
		}
		
	} while (!done);
	
	return newName;
}

@end
