#import "ZDCNodeManager.h"

#import "ZDCCloudPathManager.h"
#import "ZDCContainerNode.h"
#import "ZDCDatabaseManager.h"
#import "ZDCTreesystemPath.h"
#import "ZDCLocalUser.h"
#import "ZDCLogging.h"
#import "ZDCPublicKey.h"

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
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

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
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Containers & Anchors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (nullable ZDCContainerNode *)containerNodeForLocalUserID:(NSString *)localUserID
                                                    zAppID:(NSString *)zAppID
                                                 container:(ZDCTreesystemContainer)container
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	NSString *nodeID =
	  [ZDCContainerNode uuidForLocalUserID: localUserID
	                                zAppID: zAppID
	                             container: container];
	
	return [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
}

/**
 * See header file for description.
 */
- (nullable ZDCContainerNode *)containerNodeForNode:(ZDCNode *)node
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	ZDCContainerNode *containerNode = nil;
	do {
		
		if ([node isKindOfClass:[ZDCContainerNode class]])
		{
			containerNode = (ZDCContainerNode *)node;
			break;
		}
		else
		{
			node = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
		}
		
	} while (node);
	
	return containerNode;
}

/**
 * See header file for description.
 */
- (ZDCNode *)anchorNodeForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCNode *anchorNode = node;

	ZDCNode *currentNode = node;
	while (currentNode)
	{
		if (currentNode.ownerID || currentNode.parentID == nil)
		{
			anchorNode = currentNode;
			break;
		}
		
		currentNode = [transaction objectForKey:currentNode.parentID inCollection:kZDCCollection_Nodes];
	}
	
	return anchorNode;
}

/**
 * Returns the owner of a given node.
 *
 * This is done by traversing the node hierarchy, up to the root,
 * searching for a node with an explicit ownerID property. If not found, the localUserID is returned.
**/
- (NSString *)ownerIDForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCNode *anchorNode = [self anchorNodeForNode:node transaction:transaction];
	
	if (anchorNode.ownerID)
		return anchorNode.ownerID;
	else
		return anchorNode.localUserID;
}

/**
 * See header file for description.
 */
- (nullable ZDCUser *)ownerForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	NSString *ownerID = [self ownerIDForNode:node transaction:transaction];
	
	return [transaction objectForKey:ownerID inCollection:kZDCCollection_Users];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Local Path
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns an array of all parent nodeID's of the given node, up to the containerNode.
 *
 * The containerNode will be at index 0,
 * and the immediate parentNodeID will be the last item in the array.
 *
 * @note The term nodeID is short for ZDCNode.uuid.
 **/
- (NSArray<NSString *> *)parentNodeIDsForNode:(ZDCNode *)node
                                  transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	NSMutableArray *parents = [NSMutableArray arrayWithCapacity:8];
	
	NSString *parentID = node.parentID;
	ZDCNode *parent = nil;
	
	do
	{
		parent = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
		if (parent)
		{
			[parents insertObject:parentID atIndex:0];
			parentID = parent.parentID;
		}
	
	} while (parent && parentID);
	
	return parents;
}

/**
 * Returns the path to the given node.
 * The returned path information is encompassed in a ZDCTreesystemPath,
 * which includes both the cleartext path, as well as ordered list of nodeID's.
**/
- (nullable ZDCTreesystemPath *)pathForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (node == nil) {
		return nil;
	}
	
	ZDCContainerNode *containerNode = nil;
	
	if ([node isKindOfClass:[ZDCContainerNode class]])
	{
		containerNode = (ZDCContainerNode *)node;
		
		return [[ZDCTreesystemPath alloc] initWithPathComponents:@[] container:containerNode.container];
	}
	
	NSMutableArray<NSString *> *pathComponents = [NSMutableArray arrayWithCapacity:8];
	[pathComponents addObject:(node.name ?: @"")];
	
	while (YES)
	{
		node = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
		if ([node isKindOfClass:[ZDCContainerNode class]])
		{
			containerNode = (ZDCContainerNode *)node;
			break;
		}
		else if (node)
		{
			[pathComponents insertObject:(node.name ?: @"") atIndex:0];
		}
		else
		{
			break;
		}
	}
	
	ZDCTreesystemContainer container = (containerNode ? containerNode.container : ZDCTreesystemContainer_Home);
	
	ZDCTreesystemPath *path =
	  [[ZDCTreesystemPath alloc] initWithPathComponents: pathComponents
	                                         container: container];
	return path;
}

/**
 * See header file for description.
 */
- (BOOL)isNode:(NSString *)inNodeID
 aDescendantOf:(NSString *)potentialParentID
   transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
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
	}
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate Nodes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Enumerates all ZDCNode.uuid's whose parentID property matches the given parentID.
 *
 * This method is slightly faster than enumerating the ZDCNode objects,
 * as it can skip fetching the objects from the database.
 *
 * This only includes the direct children of the given parent.
 * Further ancestors (grandchildren, etc) are NOT enumerated.
**/
- (void)enumerateNodeIDsWithParentID:(NSString *)parentID
                         transaction:(YapDatabaseReadTransaction *)transaction
                          usingBlock:(void (^)(NSString *nodeID, BOOL *stop))enumBlock
{
	DDLogAutoTrace();
	
	if (parentID == nil) return;
	
	NSParameterAssert(transaction != nil);
	NSParameterAssert(enumBlock != nil);
	
	YapDatabaseViewTransaction *filesystemViewTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((filesystemViewTransaction = [transaction ext:Ext_View_Filesystem_Name]))
	{
		// Use Filesystem View for best performance.
		//
		// This allows us to directly access only those nodes we're interested in.
		
		[filesystemViewTransaction enumerateKeysInGroup:parentID usingBlock:
		    ^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
		{
			enumBlock(key, stop);
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Filesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
		ZDCContainerNode *containerNode = [self containerNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: containerNode.localUserID
		                                   zAppID: containerNode.zAppID];
		
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
 */
- (void)recursiveEnumerateNodeIDsWithParentID:(NSString *)parentID
                                  transaction:(YapDatabaseReadTransaction *)transaction
                                   usingBlock:(void (^)(NSString *nodeID,
                                                        NSArray<NSString*> *pathFromParent,
                                                        BOOL *recurseInto,
                                                        BOOL *stop))enumBlock
{
	DDLogAutoTrace();
	
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
 * Enumerates all ZDCNode's whose parentID property matches the given parentID.
 *
 * This only includes the direct children of the given parent.
 * Further ancestors (grandchildren, etc) are NOT enumerated.
**/
- (void)enumerateNodesWithParentID:(NSString *)parentID
                       transaction:(YapDatabaseReadTransaction *)transaction
                        usingBlock:(void (^)(ZDCNode *node, BOOL *stop))enumBlock
{
	DDLogAutoTrace();
	
	if (parentID == nil) return;
	
	NSParameterAssert(transaction != nil);
	NSParameterAssert(enumBlock != nil);
	
	YapDatabaseViewTransaction *filesystemViewTransaction = nil;
	YapDatabaseViewTransaction *flatViewTransaction = nil;
	
	if ((filesystemViewTransaction = [transaction ext:Ext_View_Filesystem_Name]))
	{
		// Use Filesystem View for best performance.
		//
		// This allows us to directly access only those nodes we're interested in.
		
		[filesystemViewTransaction enumerateKeysAndObjectsInGroup:parentID usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			enumBlock((ZDCNode *)object, stop);
		}];
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Filesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
		ZDCContainerNode *containerNode = [self containerNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: containerNode.localUserID
		                                   zAppID: containerNode.zAppID];
		
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
 */
- (void)recursiveEnumerateNodesWithParentID:(NSString *)parentID
                                transaction:(YapDatabaseReadTransaction *)transaction
                                 usingBlock:(void (^)(ZDCNode *node,
                                                      NSArray<ZDCNode*> *pathFromParent,
                                                      BOOL *recurseInto,
                                                      BOOL *stop))enumBlock
{
	DDLogAutoTrace();
	
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
	DDLogAutoTrace();
	
	__block BOOL stopped = NO;
	
	[self enumerateNodesWithParentID:parentID
	                     transaction:transaction
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
 * Returns whether or not the directory has any children nodes.
 */
- (BOOL)isEmptyNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	__block BOOL isEmpty = YES;
	
	[self enumerateNodeIDsWithParentID:node.uuid
	                       transaction:transaction
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
 * Finds the node with the given name, if it exists, and returns it.
 *
 * @param nodeName
 *   The ZDCNode.name to find.
 *   The name comparison is both case-insensitive & localized. (So in German: daß == dass)
 *
 * @param parentID
 *   One of the following:
 *   - S4Directory.uuid (if within a parent directory)
 *   - S4LocalUser.uuid (if in the root directory)
 *
 * @return The matching ZDCNode, or nil if it doesn't exist.
**/
- (ZDCNode *)findNodeWithName:(NSString *)nodeName
                     parentID:(NSString *)parentID
                  transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (nodeName == nil) return nil;
	if (parentID == nil) return nil;
    
    __block ZDCNode *matchingNode = nil;
    
    YapDatabaseAutoViewTransaction *filesystemViewTransaction = nil;
    YapDatabaseAutoViewTransaction *flatViewTransaction = nil;
    
	if ((filesystemViewTransaction = [transaction ext:Ext_View_Filesystem_Name]))
	{
		// Use Filesystem View for best performance.
		//
		// The Ext_View_Filesystem already has the nodes sorted by name (for each parentID).
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
		NSUInteger index = [filesystemViewTransaction findFirstMatchInGroup:parentID using:find];
		
		if (index != NSNotFound)
		{
			matchingNode = [filesystemViewTransaction objectAtIndex:index inGroup:parentID];
		}
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Filesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
		ZDCContainerNode *containerNode = [self containerNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: containerNode.localUserID
		                                   zAppID: containerNode.zAppID];
		
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
 * Finds the node with the given path components.
 *
 * @param pathComponents
 *   An array of path components, such as: @[ @"/", @"Documents", @"Inventory.numbers" ]
 *   You can easily produce this parameter using either [NSURL pathComponents] or [NSString pathComponents].
 *
 * @param localUserID
 *   This is the associated user account identifier. (SCLocalUser.uuid)
 *
 * @return The matching ZDCNode, or nil if it doesn't exist.
**/
- (nullable ZDCNode *)findNodeWithPath:(ZDCTreesystemPath *)path
                           localUserID:(NSString *)localUserID
                                zAppID:(NSString *)zAppID
                           transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	ZDCNode *node = nil;
	NSString *containerID =
	  [ZDCContainerNode uuidForLocalUserID: localUserID
	                                zAppID: zAppID
	                             container: path.container];
	
	if (path.isContainerRoot)
	{
		node = [transaction objectForKey:containerID inCollection:kZDCCollection_Nodes];
	}
	else
	{
		NSString *parentID = containerID;
		
		for (NSString *filename in path.pathComponents)
		{
			node = [self findNodeWithName:filename parentID:parentID transaction:transaction];
			
			if (node == nil) break;
			parentID = node.uuid;
		}
	}

	return node;
}

/**
 * See header file for description.
 */
- (ZDCNode *)findNodeWithCloudName:(NSString *)cloudName
                          parentID:(NSString *)parentID
                       transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (cloudName == nil) return nil;
	if (parentID == nil) return nil;
	if (transaction == nil) return nil;
	
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
	
	YapDatabaseAutoViewTransaction *filesystemViewTransaction = nil;
	YapDatabaseAutoViewTransaction *flatViewTransaction = nil;
	
	if ((filesystemViewTransaction = [transaction ext:Ext_View_Filesystem_CloudName]))
	{
		// Use Filesystem View for best performance.
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
		NSUInteger index = [filesystemViewTransaction findFirstMatchInGroup:parentID using:find];
		
		if (index != NSNotFound)
		{
			matchingNode = [filesystemViewTransaction objectAtIndex:index inGroup:parentID];
		}
	}
	else if ((flatViewTransaction = [transaction ext:Ext_View_Flat]))
	{
		// Backup Plan (defensive programming)
		//
		// Filesystem View extension isn't ready yet.
		// It must be still initializing / updating.
		//
		// Scan all nodes belonging to the user and look for a match (slow but functional).
		
		ZDCNode *parentNode = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
		ZDCContainerNode *containerNode = [self containerNodeForNode:parentNode transaction:transaction];
		
		NSString *group =
		  [ZDCDatabaseManager groupForLocalUserID: containerNode.localUserID
		                                   zAppID: containerNode.zAppID];
		
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
 */
- (ZDCNode *)findNodeWithCloudID:(NSString *)cloudID
                     localUserID:(NSString *)localUserID
                          zAppID:(NSString *)zAppID
                     transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (cloudID == nil) return nil;
	if (localUserID == nil) return nil;
	
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
				matchingNode = node;
				*stop = YES;
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
				matchingNode = node;
				*stop = YES;
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
			
			if ([node.localUserID isEqualToString:localUserID])
			{
				if ([node.cloudID isEqualToString:cloudID])
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
 */
- (nullable ZDCNode *)findNodeWithCloudPath:(ZDCCloudPath *)cloudPath
                                     bucket:(NSString *)bucket
                                     region:(AWSRegion)region
                                localUserID:(NSString *)localUserID
                                     zAppID:(NSString *)zAppID
                                transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (cloudPath == nil) return nil;
	if (bucket == nil) return nil;
	if (region == AWSRegion_Invalid) return nil;
	if (localUserID ==  nil) return nil;
	if (transaction == nil) return nil;
	
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
 * Finds the node with a matching dirPrefix.
 *
 * A SecondaryIndex is utilized to make this a very fast lookup.
**/
- (nullable ZDCNode *)findNodeWithDirPrefix:(NSString *)prefix
                                    bucket:(NSString *)bucket
                                    region:(AWSRegion)region
                               localUserID:(NSString *)localUserID
                                    zAppID:(NSString *)zAppID
                               transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (prefix == nil) return nil;
	if (bucket == nil) return nil;
	if (region == AWSRegion_Invalid) return nil;
	if (localUserID == nil) return nil;
	if (zAppID == nil) return nil;
	if (transaction == nil) return nil;
	
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
				ZDCUser *owner = [[ZDCNodeManager sharedInstance] ownerForNode:node transaction:transaction];
				
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
				ZDCUser *owner = [[ZDCNodeManager sharedInstance] ownerForNode:node transaction:transaction];
				
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
					ZDCUser *owner = [[ZDCNodeManager sharedInstance] ownerForNode:node transaction:transaction];
					
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Lists
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (NSArray<NSString *> *)allNodeIDsWithLocalUserID:(NSString *)localUserID
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(transaction != nil);
#else
	if (!localUserID || !transaction) return [NSArray array];
#endif
	
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
 */
- (NSArray<NSString *> *)allNodeIDsWithLocalUserID:(NSString *)localUserID
                                            zAppID:(NSString *)zAppID
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(zAppID != nil);
	NSParameterAssert(transaction != nil);
#else
	if (!localUserID || !zAppID || !transaction) return [NSArray array];
#endif
	
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
				ZDCContainerNode *containerNode = [self containerNodeForNode:node transaction:transaction];
				if ([containerNode.zAppID isEqualToString:zAppID])
				{
					[result addObject:key];
				}
			}
		}];
	}
	
	return result;
}

/**
 * Returns all ZDCNode.uuid's where ZDCNode.cloudID is non-nil.
 * That is, the node has been uploaded at least once.
 *
 * Important: uploaded once != fully synced right at this moment.
 * Rather it means that we expect it to be on the server.
 *
 * Note: This method has been optimized for performance, and is the recommended approach.
**/
- (NSArray<NSString *> *)allUploadedNodeIDsWithLocalUserID:(NSString *)localUserID
                                                    zAppID:(NSString *)zAppID
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	if (localUserID == nil) return nil;
	if (zAppID == nil) return nil;
	if (transaction == nil) return nil;
	
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
				ZDCContainerNode *containerNode = [self containerNodeForNode:node transaction:transaction];
				
				if ([containerNode.zAppID isEqualToString:zAppID])
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
 */
- (BOOL)resetPermissionsForNode:(ZDCNode *)node transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	if (node.isImmutable) return NO;
	if (node.parentID == nil) return NO;
	
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
 */
- (NSString *)resolveNamingConflictForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	DDLogAutoTrace();
	
	NSString *name = node.name;
	if (name.length == 0)
	{
		DDLogWarn(@"%@: node.name.length == 0", THIS_METHOD);
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
	
//	ZDCNode *nodeCopy = nil;
//	ZDCUser *nodeOwner = nil;
	
	do
	{
		if (name_ext)
			newName = [NSString stringWithFormat:@"%@ %llu.%@", name_base, numberToAppend, name_ext];
		else
			newName = [NSString stringWithFormat:@"%@ %llu", name_base, numberToAppend];
		
		BOOL conflicting = NO;
		
		ZDCNode *conflictingNode = [self findNodeWithName:newName parentID:node.parentID transaction:transaction];
		if (conflictingNode)
		{
			conflicting = YES;
		}
//		else if (checkForOrphanedRcrds)
//		{
//			if (nodeCopy == nil)
//				nodeCopy = [node copy];
//
//			if (nodeOwner == nil)
//				nodeOwner = [CloudPathManager ownerForNode:node transaction:transaction];
//
//			nodeCopy.name = newName;
//			nodeCopy.cloudName = [CloudPathManager cloudNameForNode:nodeCopy transaction:transaction];
//
//			ZDCCloudPath *cloudPath =
//			  [CloudPathManager cloudPathForNode:nodeCopy fileExtension:nil transaction:transaction];
//
//			ZDCCloudNode *conflictingCloudNode =
//			  [CloudNodeManager findCloudNodeWithCloudPath: cloudPath
//			                                        bucket: nodeOwner.aws_bucket
//			                                        region: nodeOwner.aws_region
//			                                   localUserID: node.localUserID
//			                                   transaction: transaction];
//
//			if (conflictingCloudNode)
//			{
//				conflicting = YES;
//			}
//		}
		
		if (conflicting) {
			numberToAppend++;
		}
		else {
			done = YES;
		}
		
	} while (!done);
	
	return newName;
}

@end
