/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCCloudTransaction.h"
#import "ZDCCloudPrivate.h"

#import "ZDCConstantsPrivate.h"
#import "ZDCCloudPathManager.h"
#import "ZDCDatabaseManager.h"
#import "ZDCLogging.h"
#import "ZDCNodeManager.h"
#import "ZDCNodePrivate.h"
#import "ZDCPushManager.h"

#import "NSError+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int ddLogLevel = DDLogLevelVerbose;
#elif DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

@interface YapDatabaseReadTransaction ()
- (id)objectForCollectionKey:(YapCollectionKey *)cacheKey withRowid:(int64_t)rowid;
- (id)metadataForCollectionKey:(YapCollectionKey *)cacheKey withRowid:(int64_t)rowid;
@end


@implementation ZDCCloudTransaction

- (NSString *)localUserID
{
	ZDCCloud *ext = (ZDCCloud *)parentConnection->parent;
	return ext.localUserID;
}

- (NSString *)zAppID
{
	ZDCCloud *ext = (ZDCCloud *)parentConnection->parent;
	return ext.zAppID;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)nodeWithPath:(ZDCTreesystemPath *)path
{
	NSString *localUserID = [self localUserID];
	NSString *zAppID = [self zAppID];
	
	ZDCNode *node =
	  [[ZDCNodeManager sharedInstance] findNodeWithPath: path
	                                        localUserID: localUserID
	                                             zAppID: zAppID
	                                        transaction: databaseTransaction];
	return node;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)createNodeWithPath:(ZDCTreesystemPath *)path
                                   error:(NSError *_Nullable *_Nullable)outError
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	if (path.pathComponents.count == 0)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: the given path is invalid";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCNode *parentNode = [self nodeWithPath:[path parentPath]];
	if (parentNode == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_MissingParent;
		NSString *desc = @"One or more parents leading up to the given path do not exist.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSString *nodeName = [path.pathComponents lastObject];
	ZDCNode *existingNode =
	  [[ZDCNodeManager sharedInstance] findNodeWithName: nodeName
	                                           parentID: parentNode.uuid
	                                        transaction: databaseTransaction];
	
	if (existingNode)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_Conflict;
		NSString *desc = @"There is already an existing node at the given path.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:[self localUserID]];
	node.parentID = parentNode.uuid;
	node.name = nodeName;
	
	[[ZDCNodeManager sharedInstance] resetPermissionsForNode:node transaction:rwTransaction];
	
	[rwTransaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
	
	[self queuePutOpsForNode:node];
	
	if (outError) *outError = nil;
	return node;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)createNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	if (node.name == nil || node.parentID == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: node isn't configured properly: requires name and/or parentID.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	if ([databaseTransaction hasObjectForKey:node.uuid inCollection:kZDCCollection_Nodes])
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_Conflict;
		NSString *desc =
		  @"The given node is already in the database."
		  @" Did you mean to modify the existing node? If so, you must use the `modifyNode:` method.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	ZDCNode *conflictingNode =
	  [[ZDCNodeManager sharedInstance] findNodeWithName: node.name
	                                           parentID: node.parentID
	                                        transaction: databaseTransaction];
	
	if (conflictingNode)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_Conflict;
		NSString *desc =
		  @"There is already a node with the same name & parentID."
		  @" (Reminder: the treesystem is case-insensitive.)";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	if (node.shareList.count == 0)
	{
		if (node.isImmutable) {
			node = [node copy];
		}
		[[ZDCNodeManager sharedInstance] resetPermissionsForNode:node transaction:rwTransaction];
	}
	
	[rwTransaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
	
	[self queuePutOpsForNode:node];
	
	return YES;
}

/**
 * Helper method.
 * Creates & queues the operations to PUT the node in the cloud.
 */
- (void)queuePutOpsForNode:(ZDCNode *)node
{
	NSString *localUserID = [self localUserID];
	NSString *zAppID = [self zAppID];
	
	ZDCCloudLocator *cloudLocatorRcrd =
	  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
	                                              fileExtension: kZDCCloudFileExtension_Rcrd
	                                                transaction: databaseTransaction];
	
	ZDCCloudOperation *opRcrd =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          zAppID: zAppID
	                                         putType: ZDCCloudOperationPutType_Node_Rcrd];
	
	opRcrd.nodeID = node.uuid;
	opRcrd.cloudLocator = cloudLocatorRcrd;
	
	ZDCCloudOperation *opData =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          zAppID: zAppID
	                                         putType: ZDCCloudOperationPutType_Node_Data];
	
	opData.nodeID = node.uuid;
	opData.cloudLocator = [cloudLocatorRcrd copyWithFileNameExt:kZDCCloudFileExtension_Data];
	
	[opData addDependency:opRcrd.uuid];
	
	[self addOperation:opRcrd];
	[self addOperation:opData];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)modifyNode:(ZDCNode *)newNode error:(NSError *_Nullable *_Nullable)outError
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	if (newNode.name == nil || newNode.parentID == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: node isn't configured properly: requires name and/or parentID.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	ZDCNode *oldNode = [databaseTransaction objectForKey:newNode.uuid inCollection:kZDCCollection_Nodes];
	
	if (oldNode == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_Conflict;
		NSString *desc =
		  @"The given node doesn't already exist in the database."
		  @" Did you mean to create the node? If so, you must use the `createNode:` method.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	ZDCCloudLocator *cloudLocator =
	  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: newNode
	                                              fileExtension: kZDCCloudFileExtension_Rcrd
	                                                transaction: databaseTransaction];
	
	if (cloudLocator == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Unknown path for node.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	NSDictionary *changeset_permissions = newNode.shareList.changeset;
	
	[rwTransaction setObject:newNode forKey:newNode.uuid inCollection:kZDCCollection_Nodes];
	
	NSString *localUserID = [self localUserID];
	NSString *zAppID = [self zAppID];
	
	ZDCCloudOperation *op = nil;
	
	BOOL didMoveNode = ![newNode.name isEqual:oldNode.name] || ![newNode.parentID isEqual:oldNode.parentID];
	if (didMoveNode)
	{
		ZDCCloudLocator *srcCloudLocator =
		  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: oldNode
		                                              fileExtension: kZDCCloudFileExtension_Rcrd
		                                                transaction: databaseTransaction];
		
		op = [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                             zAppID: zAppID
		                                               type: ZDCCloudOperationType_Move];
		
		op.cloudLocator = srcCloudLocator;
		op.dstCloudLocator = cloudLocator;
	}
	else
	{
		op = [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                             zAppID: zAppID
		                                            putType: ZDCCloudOperationPutType_Node_Rcrd];
		op.cloudLocator = cloudLocator;
	}
	
	op.nodeID = newNode.uuid;
	op.changeset_permissions = changeset_permissions;
	
	[self addOperation:op];
	
	if (outError) *outError = nil;
	return YES;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCCloudOperation *)queueDataUploadForNodeID:(NSString *)nodeID
                                           withChangeset:(nullable NSDictionary *)changeset
{
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	
	NSString *const localUserID = [self localUserID];
	NSString *const zAppID = [self zAppID];
	
	ZDCNode *node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
	if (node == nil) {
		return nil;
	}
	
	if (![node.localUserID isEqualToString:localUserID]) {
		return nil;
	}
	
	ZDCCloudLocator *cloudLocator =
	  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
	                                              fileExtension: kZDCCloudFileExtension_Data
	                                                transaction: databaseTransaction];
	
	if (cloudLocator == nil) {
		return nil;
	}
	
	ZDCCloudOperation *operation =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          zAppID: zAppID
	                                         putType: ZDCCloudOperationPutType_Node_Data];
	
	operation.nodeID = node.uuid;
	operation.cloudLocator = cloudLocator;
	operation.eTag = node.eTag_data;
	
	[self addOperation:operation];
	
	return operation;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)deleteNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError
{
	ZDCDeleteNodeOptions defaultOptions = ZDCDeleteOutdatedNodes | ZDCDeleteUnknownNodes;
	
	return [self deleteNode: node
	            withOptions: defaultOptions
	                  error: outError];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)deleteNode:(ZDCNode *)rootNode
       withOptions:(ZDCDeleteNodeOptions)opts
             error:(NSError *_Nullable *_Nullable)outError
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	
	if ([rootNode isKindOfClass:[ZDCContainerNode class]])
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"You cannot delete a container node.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	NSString *localUserID = [self localUserID];
	NSString *zAppID = [self zAppID];
	
	ZDCNodeManager *nodeManager = [ZDCNodeManager sharedInstance];
	ZDCCloudPathManager *cloudPathManager = [ZDCCloudPathManager sharedInstance];
	
	// Create JSON structure for delete-node command.
	// For example:
	//
	// {
	//   "version":1,
	//   "root":{
	//     "000/abc123":["eTag","cloudID"],
	//   },
	//   "children":{
	//     "": "11"
	//     "dirPrefix1":{
	//       "":"11",
	//       "cloudID1":"eTag1",
	//       "cloudID2":"eTag2",
	//     }
	//   }
	// }
	
	NSString *strOpts = [NSString stringWithFormat:@"%d%d",
		((opts & ZDCDeleteOutdatedNodes) ? 1 : 0),
		((opts & ZDCDeleteUnknownNodes)  ? 1 : 0)
	];
	
	NSMutableDictionary *json = [NSMutableDictionary dictionary];
	json[@"version"] = @(1);
	
	ZDCCloudLocator *root_cloudLocator =
	  [cloudPathManager cloudLocatorForNode: rootNode
	                            transaction: databaseTransaction];
	
	if (root_cloudLocator == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Unknown cloudPath for node.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	NSString *root_cloudPath =
	  [root_cloudLocator.cloudPath pathWithComponents:(ZDCCloudPathComponents_DirPrefix |
	                                                   ZDCCloudPathComponents_FileName_WithoutExt)];
	
	NSString *root_eTag    = rootNode.eTag_rcrd ?: @"";
	NSString *root_cloudID = rootNode.cloudID   ?: @"";
	
	json[@"root"] = @{
		root_cloudPath: @[root_eTag, root_cloudID]
	};
	
	NSMutableDictionary *children = [NSMutableDictionary dictionary];
	json[@"children"] = children;
	
	children[@""] = strOpts;
	
	// Now enumerate all the children, and fill out the "children" section of the JSON.
	
	NSMutableSet<NSString*> *cloudIDs = [NSMutableSet set];
	NSMutableArray<NSString*> *nodeIDs = [NSMutableArray array];
	
	[nodeManager recursiveEnumerateNodesWithParentID: rootNode.uuid
	                                     transaction: databaseTransaction
	                                      usingBlock:
	^(ZDCNode *childNode, NSArray<ZDCNode*> *pathFromParent, BOOL *recurseInto, BOOL *stop) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[nodeIDs addObject:childNode.uuid];
		
		ZDCCloudLocator *cloudLocator =
		  [cloudPathManager cloudLocatorForNode: childNode
		                            transaction: databaseTransaction];
		
		if (cloudLocator)
		{
			// Fill out the JSON info for this child node
			
			NSString *cloudID = childNode.cloudID;
			if (cloudID)
			{
				NSString *dirPrefix = cloudLocator.cloudPath.dirPrefix;
			
				NSMutableDictionary *dir = children[dirPrefix];
				if (dir == nil)
				{
					dir = [NSMutableDictionary dictionary];
					children[dirPrefix] = dir;
			
					dir[@""] = strOpts;
				}
			
				dir[cloudID] = (childNode.eTag_rcrd ?: @"");
				[cloudIDs addObject:cloudID];
			}
			
			// Create corresponding ZDCCloudNode
			
			ZDCCloudNode *cloudNode =
			  [[ZDCCloudNode alloc] initWithLocalUserID: childNode.localUserID
			                               cloudLocator: cloudLocator];
			
			[rwTransaction setObject: cloudNode
			                  forKey: cloudNode.uuid
			            inCollection: kZDCCollection_CloudNodes];
		}
		
		// Unlink the childNode (if linked)
		
		NSString *linkedKey = nil;
		NSString *linkedCollection = nil;
		
		if ([self getLinkedKey:&linkedKey collection:&linkedCollection forNodeID:childNode.uuid])
		{
			[self detachCloudURI: childNode.uuid
			              forKey: linkedKey
			        inCollection: linkedCollection];
		}
		
	#pragma clang diagnostic pop
	}];
	
	ZDCCloudOperation *operation = nil;
	
	if (NO /* reserved for future optimization */)
	{
		// Delete-Leaf operation
		
	//	operation =
	//	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	//	                                          zAppID: zAppID
	//	                                            type: ZDCCloudOperationType_DeleteLeaf];
	}
	else
	{
		operation =
		  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                          zAppID: zAppID
		                                            type: ZDCCloudOperationType_DeleteNode];
		
		NSError *jsonError = nil;
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&jsonError];
		
		if (jsonError)
		{
			if (outError) *outError = jsonError;
			return NO;
		}
		
		operation.deleteNodeJSON = jsonData;
	}
	
	operation.cloudLocator = root_cloudLocator;
	
	if (rootNode.cloudID) {
		[cloudIDs addObject:rootNode.cloudID];
	}
	operation.deletedCloudIDs = cloudIDs;
	
	// Create corresponding ZDCCloudNode
	if (root_cloudLocator)
	{
		ZDCCloudNode *cloudNode =
		  [[ZDCCloudNode alloc] initWithLocalUserID: rootNode.localUserID
		                               cloudLocator: root_cloudLocator];
		
		[rwTransaction setObject: cloudNode
		                  forKey: cloudNode.uuid
		            inCollection: kZDCCollection_CloudNodes];
		
		operation.cloudNodeID = cloudNode.uuid;
	}
	
	// Unlink the rootNode (if linked)
	{
		NSString *linkedKey = nil;
		NSString *linkedCollection = nil;
		
		if ([self getLinkedKey:&linkedKey collection:&linkedCollection forNodeID:rootNode.uuid])
		{
			[self detachCloudURI: rootNode.uuid
			              forKey: linkedKey
			        inCollection: linkedCollection];
		}
	}
	
	// We're also going to set operation.nodeID,
	// even though we're going to delete the node from the database.
	//
	// Why are we doing this ?
	// It makes it easier to find the queued operation afterwards.
	// For example, via the `addedOperationsForNodeID:` method.
	//
	operation.nodeID = rootNode.uuid;
	
	// Queue the operation
	
	[self addOperation:operation]; // Must come AFTER setting `operation.cloudNodeID`
	
	// Delete all the ZDCNode's from the treesystem
	
	[nodeIDs addObject:rootNode.uuid];
	[rwTransaction removeObjectsForKeys:nodeIDs inCollection:kZDCCollection_Nodes];
	
	// Skip put-data operations for any node we're deleting.
	//
	// Note that we're not skipping put:rcrd or move operations.
	// That's an optimization that requires a MUCH more complicated solution.
	
	NSMutableSet<NSUUID *> *opUUIDs = [NSMutableSet set];
	
	[self enumerateOperationsUsingBlock:
		^(YapDatabaseCloudCorePipeline *pipeline,
	     YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			
			if (op.isPutNodeDataOperation && op.nodeID && [nodeIDs containsObject:op.nodeID])
			{
				[opUUIDs addObject:op.uuid];
			}
		}
	}];
	
	[self skipPutOperations:opUUIDs];
	
	// Done
	
	if (outError) *outError = nil;
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Linking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)linkNodeID:(NSString *)nodeID
             toKey:(NSString *)key
      inCollection:(nullable NSString *)collection
             error:(NSError *_Nullable *_Nullable)outError
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	
	if (collection == nil) collection = @"";
	
	if (nodeID == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: the given nodeID is nil.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	if (key.length == 0)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: the given key is invalid";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	if (![databaseTransaction hasObjectForKey:nodeID inCollection:kZDCCollection_Nodes])
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"A node with the given nodeID doesn't exist in the database.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return NO;
	}
	
	// Is the <collection,key> tuple already linked to a node ?
	
	NSString *linkedNodeID = [self linkedNodeIDForKey:key inCollection:collection];
	if (linkedNodeID)
	{
		if ([linkedNodeID isEqualToString:nodeID])
		{
			// Already linked to target node - nothing to do (success)
			if (outError) *outError = nil;
			return YES;
		}
		else
		{
			ZDCCloudErrorCode code = ZDCCloudErrorCode_Conflict;
			NSString *desc =
			  @"The given <collection, key> tuple is already linked to a different node."
			  @" You must unlink it before the tuple can linked again.";
			NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
			
			if (outError) *outError = error;
			return NO;
		}
	}
	
	// Is the node already linked to a different <collection, key> tuple ?
	
	NSString *linkedKey = nil;
	NSString *linkedCollection = nil;
	
	BOOL isNodeLinked = [self getLinkedKey:&linkedKey collection:&linkedCollection forNodeID:nodeID];
	if (isNodeLinked)
	{
		if ([linkedKey isEqualToString:key] && [linkedCollection isEqualToString:collection])
		{
			// Already linked to target node - nothing to do (success)
			if (outError) *outError = nil;
			return YES;
		}
		else
		{
			ZDCCloudErrorCode code = ZDCCloudErrorCode_Conflict;
			NSString *desc =
			  @"The given node is already linked to a different <collection, key> tuple."
			  @" You must unlink it before the node can linked again.";
			NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
			
			if (outError) *outError = error;
			return NO;
		}
	}
	
	[self attachCloudURI:nodeID forKey:key inCollection:collection];
	
	if (outError) *outError = nil;
	return YES;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable NSString *)unlinkKey:(NSString *)key inCollection:(nullable NSString *)collection
{
	NSString *nodeID = [self linkedNodeIDForKey:key inCollection:collection];
	if (nodeID)
	{
		[self detachCloudURI:nodeID forKey:key inCollection:collection];
	}
	
	return nodeID;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Linked Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable NSString *)linkedNodeIDForKey:(NSString *)key inCollection:(nullable NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	__block NSString *nodeID = nil;
	[self enumerateAttachedForKey: key
	                   collection: collection
	                   usingBlock:^(NSString *cloudURI, BOOL *stop)
	{
		nodeID = cloudURI;
		*stop = YES;
	}];
	
	return nodeID;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)linkedNodeForKey:(NSString *)key inCollection:(nullable NSString *)collection
{
	ZDCNode *node = nil;
	
	NSString *nodeID = [self linkedNodeIDForKey:key inCollection:collection];
	if (nodeID) {
		node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
	}
	
	return node;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)isNodeLinked:(NSString *)nodeID
{
	__block BOOL isLinked = NO;
	
	[self enumerateAttachedForCloudURI: nodeID
	                        usingBlock:
	^(NSString *key, NSString *collection, BOOL pending, BOOL *stop) {
		
		isLinked = YES;
	}];
	
	return isLinked;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)getLinkedKey:(NSString **)outKey
          collection:(NSString **)outCollection
           forNodeID:(NSString *)nodeID
{
	__block NSString *key = nil;
	__block NSString *collection = nil;
	
	[self enumerateAttachedForCloudURI: nodeID
	                        usingBlock:^(NSString *_key, NSString *_collection, BOOL pending, BOOL *stop)
	{
		key = _key;
		collection = _collection;
		*stop = YES;
	}];
	
	if (outKey) *outKey = key;
	if (outCollection) *outCollection = collection;
	
	return (key != nil);
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable id)linkedObjectForNodeID:(NSString *)nodeID
{
	NSString *collection = nil;
	NSString *key = nil;
	if ([self getLinkedKey:&key collection:&collection forNodeID:nodeID])
	{
		return [databaseTransaction objectForKey:key inCollection:collection];
	}
	
	return nil;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable id)linkedObjectForPath:(ZDCTreesystemPath *)path
{
	NSString *localUserID = [self localUserID];
	NSString *zAppID = [self zAppID];
	
	ZDCNode *node =
	  [[ZDCNodeManager sharedInstance] findNodeWithPath: path
	                                        localUserID: localUserID
	                                             zAppID: zAppID
	                                        transaction: databaseTransaction];
	
	if (node) {
		return [self linkedObjectForNodeID:node.uuid];
	}
	else {
		return nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Download Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)markNodeAsNeedsDownload:(NSString *)nodeID
{
	[self setTag:@(YES) forKey:nodeID withIdentifier:nil];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)unmarkNodeAsNeedsDownload:(NSString *)nodeID ifETagMatches:(nullable NSString *)eTag
{
	if (eTag)
	{
		ZDCNode *node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		if (node)
		{
			if (node.eTag_data && ![node.eTag_data isEqualToString:eTag]) {
				return;
			}
		}
	}
	
	[self removeTagForKey:nodeID withIdentifier:nil];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)nodeIsMarkedAsNeedsDownload:(NSString *)nodeID
{
	id tag = [self tagForKey:nodeID withIdentifier:nil];
	
	return (tag && [tag isKindOfClass:[NSNumber class]] && [(NSNumber *)tag boolValue]);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (NSArray<ZDCCloudOperation*> *)addedOperationsForNodeID:(NSString *)nodeID
{
	NSMutableArray<ZDCCloudOperation*> *results = [NSMutableArray arrayWithCapacity:2];
	
	if (nodeID == nil) {
		return results;
	}
	
	[self enumerateAddedOperationsUsingBlock:
	^(YapDatabaseCloudCorePipeline *pipeline,
	  YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			if ([op.nodeID isEqualToString:nodeID])
			{
				[results addObject:op];
			}
		}
	}];
	
	return results;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (NSArray<NSDictionary*> *)pendingChangesetsForNodeID:(NSString *)nodeID
{
	NSMutableArray<NSDictionary*> *changesets = [NSMutableArray array];
	
	[self _enumerateOperationsUsingBlock:^(YapDatabaseCloudCorePipeline *pipeline,
														YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			if ([op.nodeID isEqualToString:nodeID])
			{
				if (op.changeset_obj) {
					[changesets addObject:op.changeset_obj];
				}
			}
		}
	}];
	
	return changesets;
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)didMergeDataWithETag:(NSString *)eTag forNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return;
	
	[self _enumerateAndModifyOperations:YDBCloudCore_EnumOps_All
	                         usingBlock:
	  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCorePipeline *pipeline,
	                                   YapDatabaseCloudCoreOperation *operation,
	                                   NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			ZDCCloudOperation *modifiedOp = nil;
			
			if ([op.nodeID isEqualToString:nodeID])
			{
				if (!YDB_IsEqualOrBothNil(op.eTag, eTag))
				{
					modifiedOp = [op copy];
					modifiedOp.eTag = eTag;
					
					return modifiedOp;
				}
			}
		}
		
		return nil;
	}];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)skipDataUploadsForNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return;
	
	[self skipOperationsPassingTest:
	  ^BOOL(YapDatabaseCloudCorePipeline *pipeline,
	        YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			
			if (op.isPutNodeDataOperation && [op.nodeID isEqualToString:nodeID])
			{
				return YES;
			}
		}
		
		return NO;
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Checks the queue to see if there's a queued delete operation for this fileID.
**/
- (BOOL)isCloudIDPendingDeletion:(NSString *)cloudID
{
	if (cloudID == nil) return NO;

	__block BOOL hasPendingDeletion = NO;

	[self _enumerateOperationsUsingBlock:^(YapDatabaseCloudCorePipeline *pipeline,
	                                       YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;

			if ((op.type == ZDCCloudOperationType_DeleteLeaf ||
			     op.type == ZDCCloudOperationType_DeleteNode ) &&
			     [op.deletedCloudIDs containsObject:cloudID])
			{
				hasPendingDeletion = YES;
				*stop = YES;
			}
		}
	}];

	return hasPendingDeletion;
}

/**
 * If there are queued move operations for the given nodeID,
 * then the current cloudPath on the server may differ from our local value.
 *
 * This method analyzes queued move operations, to see if perhaps the server's value differs because
 * our queued move operations haven't been executed yet.
**/
- (NSArray<ZDCCloudPath *> *)potentialCloudPathsForNodeID:(NSString *)nodeID
{
	__block NSMutableArray *cloudPaths = [NSMutableArray arrayWithCapacity:2];

	[self _enumerateOperationsUsingBlock:^(YapDatabaseCloudCorePipeline *pipeline,
	                                       YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			
			if ([op.nodeID isEqualToString:nodeID] && (op.type == ZDCCloudOperationType_Move))
			{
				[cloudPaths addObject:op.cloudLocator.cloudPath];
				[cloudPaths addObject:op.dstCloudLocator.cloudPath];
				
				*stop = YES;
			}
		}
	}];
	
	return cloudPaths;
}

/**
 * Use this method when:
 * - a file/directory is moved/renamed during a pull
 * 
 * In this case, any queued local moves conflict with the remote move,
 * and the remote move wins. Thus we should skip our local operation(s).
**/
- (void)skipMoveOperationsForNodeID:(NSString *)nodeID excluding:(NSUUID *)operationUUID
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	[self skipOperationsPassingTest:^BOOL(YapDatabaseCloudCorePipeline *pipeline,
	                                      YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			
			if (op.type == ZDCCloudOperationType_Move
			 && [op.nodeID isEqualToString:nodeID]
			 && ![op.uuid isEqual:operationUUID])
			{
				return YES;
			}
		}
		
		return NO;
	}];
}

/**
 * Handles all the following:
 *
 * - Skipping queued put operations
 * - Aborting multipart put operations
 * - Cancelling in-progress put tasks
**/
- (void)skipPutOperations:(NSSet<NSUUID *> *)opUUIDs
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	// Note: We can't just skip multipart operations that are in progress.
	// Instead, we need to initiate an abort by setting a flag on the operation.
	
	NSMutableArray<ZDCCloudOperation *> *opsToCancel = [NSMutableArray array];
	NSMutableArray<ZDCCloudOperation *> *multipartOpsToAbort = [NSMutableArray array];
	
	[self skipOperationsPassingTest:
	    ^BOOL (YapDatabaseCloudCorePipeline *pipeline,
	           YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
		
			if ((op.type == ZDCCloudOperationType_Put) && [opUUIDs containsObject:op.uuid])
			{
				[opsToCancel addObject:op];
		
				if (op.multipartInfo.uploadID)
				{
					[multipartOpsToAbort addObject:op];
		
					return NO;
				}
				else
				{
					return YES;
				}
			}
		}
		
		return NO;
	}];
	
	for (ZDCCloudOperation *op in multipartOpsToAbort)
	{
		ZDCCloudOperation *modifiedOp = [op copy];
		
		modifiedOp.multipartInfo.needsAbort = YES;
		modifiedOp.multipartInfo.needsSkip = YES;
		
		[self modifyOperation:modifiedOp];
	}
	
	__unsafe_unretained YapDatabaseReadWriteTransaction *rwTransaction =
	  (YapDatabaseReadWriteTransaction *)databaseTransaction;

	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	[rwTransaction addCompletionQueue:bgQueue completionBlock:^{

		NSDictionary *userInfo = @{
			ZDCSkippedOperationsNotification_UserInfo_Ops: opsToCancel
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCSkippedOperationsNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	}];
}

/**
 * Use this method when:
 * - a file/directory is renamed during a push
 * - a file/directory is moved/renamed during a pull
 *
 * This method migrates all matching queued operations to the new cloudLocator.
 *
 * if ([operation.cloudLocator isEqualToCloudLocator:oldCloudLocator]) => change to newCloudLocator
**/
- (void)moveCloudLocator:(ZDCCloudLocator *)oldCloudLocator
          toCloudLocator:(ZDCCloudLocator *)newCloudLocator
{
	DDLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	if (oldCloudLocator == nil) {
		DDLogWarn(@"%@ - Ignoring request: oldCloudLocator is nil", THIS_METHOD);
		return;
	}
	if (newCloudLocator == nil) {
		DDLogWarn(@"%@ - Ignoring request: newCloudLocator is nil", THIS_METHOD);
		return;
	}
	
	[self _enumerateAndModifyOperations:YDBCloudCore_EnumOps_All
	                         usingBlock:
	  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCorePipeline *pipeline,
	                                   YapDatabaseCloudCoreOperation *operation,
	                                   NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			ZDCCloudOperation *modifiedOp = nil;
			
			if ([op.cloudLocator isEqualToCloudLocator:oldCloudLocator])
			{
				if (modifiedOp == nil)
					modifiedOp = [op copy];
				
				modifiedOp.cloudLocator = newCloudLocator;
			}
			if ([op.dstCloudLocator isEqualToCloudLocator:oldCloudLocator])
			{
				if (modifiedOp == nil)
					modifiedOp = [op copy];
				
				modifiedOp.dstCloudLocator = newCloudLocator;
			}
			
			return modifiedOp;
		}
		
		return nil;
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Subclass Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclass Hook.
 * 
 * We use this method to properly update ZDCCloudOperations.
**/
- (NSArray<YapDatabaseCloudCoreOperation *> *)processOperations:(NSArray<YapDatabaseCloudCoreOperation *> *)inOperations
                                                     inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
                                                   withGraphIdx:(NSUInteger)operationsGraphIdx
{
	// Step 1 of 3:
	//
	// Filter out all operations except:
	// - those supported by this class (ZDCCloudOperation)
	// - those that aren't marked for deletion
	
	NSUInteger capacity = inOperations.count;
	
	NSMutableArray<ZDCCloudOperation *> *operations = [NSMutableArray arrayWithCapacity:capacity];
	NSMutableDictionary<NSUUID *, ZDCCloudOperation *> *map = [NSMutableDictionary dictionaryWithCapacity:capacity];
	
	for (YapDatabaseCloudCoreOperation *op in inOperations)
	{
		if (!op.pendingStatusIsCompletedOrSkipped)
		{
			if ([op isKindOfClass:[ZDCCloudOperation class]])
			{
				__unsafe_unretained ZDCCloudOperation *s4op = (ZDCCloudOperation *)op;
				
				[operations addObject:s4op];
				map[s4op.uuid] = s4op;
			}
		}
	}
	
	// Step 2 of 3:
	//
	// Add implicit dependencies for operations with the same target.
	// That is, if the user created 2 operations for the same node,
	// then we should make one of them dependent on the other.
	
	for (NSUInteger i = 1; i < operations.count; i++)
	{
		ZDCCloudOperation *laterOp = operations[i];
		
		for (NSUInteger j = i; j > 0; j--)
		{
			ZDCCloudOperation *earlierOp = operations[j-1];
			
			if ([laterOp hasSameTarget:earlierOp])
			{
				[laterOp addDependency:earlierOp];
				break;
			}
		}
	}
	
	// Step 3 of 3:
	//
	// Add implicit dependencies to enable FlatGraph optimizations.
	// That is, we need to inject dependencies for these operations
	// based on the queued operations from earlier commits.
	//
	// The FlatGraph optimiztion allows us to escape the strict per-commit operation ordering.
	// That is, all operations from commit A must complete before starting any operations from commit B.
	// However, to do this we must inject proper dependencies based on the filesystem hierarchy.
	
	[self _enumerateOperations: (YDBCloudCore_EnumOps_Existing | YDBCloudCore_EnumOps_Inserted)
	                inPipeline: pipeline
						 usingBlock: ^void (YapDatabaseCloudCoreOperation *oldOperation, NSUInteger graphIdx, BOOL *stop)
	{
		// Remember: this method is invoked for each graphIdx that had changes.
		//
		// Therefore the graphIdx could be:
		// - the latest graphIdx, with all added operations
		// - an earlier graphIdx, due to an inserted/modified operation
		//
		if (graphIdx >= operationsGraphIdx)
		{
			*stop = YES;
			return;
		}
		
		if ([oldOperation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *oldOp = (ZDCCloudOperation *)oldOperation;
			
			for (ZDCCloudOperation *newOp in operations)
			{
				if ([self newOperation:newOp dependsOnOldOperation:oldOp])
				{
					[newOp addDependency:oldOperation];
				}
			}
		}
	}];
	
	return operations;
}

- (BOOL)newOperation:(ZDCCloudOperation *)newOp dependsOnOldOperation:(ZDCCloudOperation *)oldOp
{
	if ([newOp hasSameTarget:oldOp])
	{
		return YES;
	}
	
	if (![newOp.localUserID isEqualToString:oldOp.localUserID]) return NO;
	
	if (newOp.type == ZDCCloudOperationType_Put)
	{
		if (newOp.putType == ZDCCloudOperationPutType_Node_Rcrd ||
		    newOp.putType == ZDCCloudOperationPutType_Node_Data)
		{
			if (oldOp.type == ZDCCloudOperationType_Put)
			{
				if (oldOp.putType == ZDCCloudOperationPutType_Node_Rcrd ||
				    oldOp.putType == ZDCCloudOperationPutType_Node_Data)
				{
					//   new.put.rcrd || new.put.data
					// + old.put.rcrd || old.put.data
					// ------------------------------
					// => same.node || old.node.in.hierarchy.of.new.node
					
					NSString *newNodeID = newOp.nodeID;
					NSString *oldNodeID = oldOp.nodeID;
					
					if ([newNodeID isEqualToString:oldNodeID]) return YES;
					
					BOOL isDescendant =
					  [[ZDCNodeManager sharedInstance] isNode: newNodeID
					                            aDescendantOf: oldNodeID
					                              transaction: databaseTransaction];
					if (isDescendant) return YES;
					
					return NO;
				}
				else if (oldOp.putType == ZDCCloudOperationPutType_Message_Local ||
				         oldOp.putType == ZDCCloudOperationPutType_Message_Remote )
				{
					//   new.put.rcrd || new.put.data
					// + old.put.messageLocal || old.put.messageRemote
					// ------------------------------
					// => NO
					
					return NO;
				}
			}
			else if (oldOp.type == ZDCCloudOperationType_Move ||
			         oldOp.type == ZDCCloudOperationType_CopyLeaf)
			{
				//   new.put.rcrd || new.put.data
				// + old.move || old.copyLeaf
				// ------------------------------
				// => same.src || same.dst
				
				if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
				                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
				
				if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.dstCloudLocator
				                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
				
				return NO;
			}
			else if (oldOp.type == ZDCCloudOperationType_DeleteLeaf ||
			         oldOp.type == ZDCCloudOperationType_DeleteNode)
			{
				//   new.put.rcrd || new.put.data
				// + old.deleteLeaf || old.deleteNode
				// ------------------------------
				// => same.src
				
				if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
				                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
				
				return NO;
			}
			else if (oldOp.type == ZDCCloudOperationType_Avatar)
			{
				//   new.put.rcrd || new.put.data
				// + old.avatar
				// ------------------------------
				// => NO
				
				return NO;
			}
		}
		else if (newOp.putType == ZDCCloudOperationPutType_Message_Local ||
		         newOp.putType == ZDCCloudOperationPutType_Message_Remote)
		{
			if (oldOp.type == ZDCCloudOperationType_Put)
			{
				if (oldOp.putType == ZDCCloudOperationPutType_Message_Local ||
				    oldOp.putType == ZDCCloudOperationPutType_Message_Remote)
				{
					//   new.put.msgLocal || new.put.msgRemote
					// + old.put.msgLocal || old.put.msgRemote
					// ---------------------------------------
					// => same.src
					
					if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
					                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
					
					return NO;
				}
				else if (oldOp.putType == ZDCCloudOperationPutType_Node_Rcrd ||
				         oldOp.putType == ZDCCloudOperationPutType_Node_Data  )
				{
					//   new.put.msgLocal || new.put.msgRemote
					// + old.put.rcrd || old.put.data
					// ---------------
					// => NO
					
					return NO;
				}
			}
			else if (oldOp.type == ZDCCloudOperationType_Move ||
			         oldOp.type == ZDCCloudOperationType_CopyLeaf)
			{
				//   new.put.msgLocal || new.put.msgRemote
				// + old.move || old.copyLeaf
				// -----------------
				// => same.src || same.dst
				
				if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
				                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
				
				if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.dstCloudLocator
				                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
				
				return NO;
			}
			else if (oldOp.type == ZDCCloudOperationType_DeleteLeaf ||
			         oldOp.type == ZDCCloudOperationType_DeleteNode)
			{
				//   new.put.msgLocal || new.put.msgRemote
				// + old.deleteLeaf || old.deleteNode
				// -----------------
				// => same.src
				
				if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
				                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
				
				return NO;
			}
			else if (oldOp.type == ZDCCloudOperationType_Avatar)
			{
				//   new.put.msgLocal || new.put.msgRemote
				// + old.avatar
				// -----------------
				// => NO
				
				return NO;
			}
		}
	}
	else if (newOp.type == ZDCCloudOperationType_Move ||
	         newOp.type == ZDCCloudOperationType_CopyLeaf)
	{
		if (oldOp.type == ZDCCloudOperationType_Put ||
		    oldOp.type == ZDCCloudOperationType_DeleteLeaf ||
		    oldOp.type == ZDCCloudOperationType_DeleteNode)
		{
			//   new.move || new.copyLeaf
			// + old.put || old.deleteLeaf || old.deleteNode
			// ----------
			// => same.src || same.dst
			
			ZDCCloudLocator *newLocatorSrc = newOp.cloudLocator;
			ZDCCloudLocator *newLocatorDst = newOp.dstCloudLocator;
			
			ZDCCloudLocator *oldLocator = oldOp.cloudLocator;
			
			if ([newLocatorSrc isEqualToCloudLocator: oldLocator
			                              components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			if ([newLocatorDst isEqualToCloudLocator: oldLocator
			                              components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			return NO;
		}
		else if (oldOp.type == ZDCCloudOperationType_Move ||
		         oldOp.type == ZDCCloudOperationType_CopyLeaf)
		{
			//   new.move || new.copyLeaf
			// + old.move || old.copyLeaf
			// --------------------------
			// => same.src || same.dst
			
			ZDCCloudLocator *newLocatorSrc = newOp.cloudLocator;
			ZDCCloudLocator *newLocatorDst = newOp.dstCloudLocator;
			
			ZDCCloudLocator *oldLocatorSrc = oldOp.cloudLocator;
			ZDCCloudLocator *oldLocatorDst = oldOp.cloudLocator;
			
			if ([newLocatorSrc isEqualToCloudLocator: oldLocatorSrc
			                              components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			if ([newLocatorDst isEqualToCloudLocator: oldLocatorSrc
			                              components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			if ([newLocatorSrc isEqualToCloudLocator: oldLocatorDst
			                              components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			if ([newLocatorDst isEqualToCloudLocator: oldLocatorDst
			                              components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			return NO;
		}
		else if (oldOp.type == ZDCCloudOperationType_Avatar)
		{
			//   new.move || new.copyLeaf
			// + old.avatar
			// --------------------------
			// => NO
			
			return NO;
		}
	}
	else if (newOp.type == ZDCCloudOperationType_DeleteLeaf ||
	         newOp.type == ZDCCloudOperationType_DeleteNode)
	{
		if (oldOp.type == ZDCCloudOperationType_Put ||
		    oldOp.type == ZDCCloudOperationType_DeleteLeaf ||
		    oldOp.type == ZDCCloudOperationType_DeleteNode)
		{
			//   new.deleteLeaf || new.deleteNode
			// + old.put || old.deleteLeaf || old.deleteNode
			// ---------------------------------------------
			// => same.src
			
			if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
			                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			return NO;
		}
		else if (oldOp.type == ZDCCloudOperationType_Move ||
		         oldOp.type == ZDCCloudOperationType_CopyLeaf)
		{
			//   new.deleteLeaf || new.deleteNode
			// + old.move || old.copyLeaf
			// -----------------
			// => same.src || same.dst
			
			if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.cloudLocator
			                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			if ([newOp.cloudLocator isEqualToCloudLocator: oldOp.dstCloudLocator
			                                   components: ZDCCloudPathComponents_All_WithoutExt]) return YES;
			
			return NO;
		}
		else if (oldOp.type == ZDCCloudOperationType_Avatar)
		{
			//   new.deleteLeaf || new.deleteNode
			// + old.avatar
			// -----------------
			// => NO
			
			return NO;
		}
	}
	else if (newOp.type == ZDCCloudOperationType_Avatar)
	{
		if (oldOp.type == ZDCCloudOperationType_Avatar)
		{
			//   new.avatar
			// + old.avatar
			// ------------
			// => same.avatar_auth0ID
			
			if ([newOp.avatar_auth0ID isEqual:oldOp.avatar_auth0ID]) return YES;
			
			return NO;
		}
		else if (oldOp.type == ZDCCloudOperationType_Put        ||
		         oldOp.type == ZDCCloudOperationType_Move       ||
					oldOp.type == ZDCCloudOperationType_DeleteLeaf ||
		         oldOp.type == ZDCCloudOperationType_DeleteNode ||
		         oldOp.type == ZDCCloudOperationType_CopyLeaf    )
		{
			//   new.avatar
			// + old.put || old.move || old.delete || old.copy
			// ------------
			// => NO
			
			return NO;
		}
	}
	
	NSAssert(NO, @"You need to add code here to support this type of operation.");
	return NO;
}

- (void)validateOperation:(YapDatabaseCloudCoreOperation *)operation
{
	if (![operation isKindOfClass:[ZDCCloudOperation class]]) {
		NSAssert(NO, @"Invalid operation class !");
	}
	
	__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
	
	if (op.localUserID == nil) {
		NSAssert(NO, @"localUserID is nil !");
	}
	
	switch (op.type)
	{
		case ZDCCloudOperationType_Put:
		{
			switch (op.putType)
			{
				case ZDCCloudOperationPutType_Node_Rcrd:
				case ZDCCloudOperationPutType_Node_Data:
				{
					NSAssert(op.nodeID != nil, @"nodeID is nil !");
					NSAssert(op.cloudLocator != nil, @"cloudLocator is nil !");
					break;
				}
				case ZDCCloudOperationPutType_Pointer:
				{
					NSAssert(NO, @"Implement this section when you start implementing pointers...");
					break;
				}
				case ZDCCloudOperationPutType_Message_Local:
				case ZDCCloudOperationPutType_Message_Remote:
				{
					NSAssert(op.cloudLocator != nil, @"cloudLocator is nil !");
					break;
				}
				default:
				{
					NSAssert(NO, @"Invalid operation putType !");
					break;
				}
			}
			break;
		}
		case ZDCCloudOperationType_Move:
		{
			NSAssert(op.nodeID != nil, @"nodeID is nil !");
			NSAssert(op.cloudLocator != nil, @"cloudLocator is nil !");
			NSAssert(op.dstCloudLocator != nil, @"dstCloudLocator is nil !");
			break;
		}
		case ZDCCloudOperationType_DeleteLeaf:
		{
			NSAssert(op.cloudLocator != nil, @"cloudLocator is nil !");
			NSAssert(op.deletedCloudIDs != nil, @"deletedCloudIDs is nil !");
			break;
		}
		case ZDCCloudOperationType_DeleteNode:
		{
			NSAssert(op.cloudLocator != nil, @"cloudLocator is nil !");
			NSAssert(op.deletedCloudIDs != nil, @"deletedCloudIDs is nil !");
			NSAssert(op.deleteNodeJSON != nil, @"deleteNodeJSON is nil !");
			break;
		}
		case ZDCCloudOperationType_CopyLeaf:
		{
			NSAssert(op.nodeID != nil, @"nodeID is nil !");
			NSAssert(op.cloudLocator != nil, @"cloudLocator is nil !");
			NSAssert(op.dstCloudLocator != nil, @"dstCloudLocator is nil !");
			break;
		}
		case ZDCCloudOperationType_Avatar:
		{
			NSAssert(op.avatar_auth0ID != nil, @"avatar_auth0ID is nil !");
			break;
		}
		default:
		{
			NSAssert(NO, @"Invalid operation type !");
			break;
		}
	}
}

- (BOOL)addOperation:(YapDatabaseCloudCoreOperation *)operation
{
	[self validateOperation:operation];
	return [super addOperation:operation];
}

- (BOOL)modifyOperation:(YapDatabaseCloudCoreOperation *)operation
{
	[self validateOperation:operation];
	return [super modifyOperation:operation];
}

- (BOOL)insertOperation:(YapDatabaseCloudCoreOperation *)operation inGraph:(NSInteger)graphIdx
{
	[self validateOperation:operation];
	return [super insertOperation:operation inGraph:graphIdx];
}

- (void)didCompleteOperation:(YapDatabaseCloudCoreOperation *)operation
{
//	DDLogCookie(@"Did COMPLETE operation: %@", operation.uuid);
}

- (void)didSkipOperation:(YapDatabaseCloudCoreOperation *)operation
{
//	DDLogCookie(@"Did SKIP operation: %@", operation.uuid);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal helper method for other handleX methods.
**/
- (void)_didChangeWithRowid:(int64_t)rowid
              collectionKey:(YapCollectionKey *)ck
                     object:(id)object
                   metadata:(id)metadata
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudConnection *cloudConnection = (ZDCCloudConnection *)parentConnection;
	__unsafe_unretained ZDCCloud *cloud = (ZDCCloud *)parentConnection->parent;
	
	__unsafe_unretained ZDCCloudHandler *handler = cloud->handler;
	
	if (handler->blockType == YapDatabaseBlockTypeWithKey)
	{
		ZDCCloudHandlerWithKeyBlock block = (ZDCCloudHandlerWithKeyBlock)handler->block;
		
		block(databaseTransaction, cloudConnection->operations_block, ck.collection, ck.key);
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithObject)
	{
		ZDCCloudHandlerWithObjectBlock block = (ZDCCloudHandlerWithObjectBlock)handler->block;
		
		block(databaseTransaction, cloudConnection->operations_block, ck.collection, ck.key, object);
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		ZDCCloudHandlerWithMetadataBlock block = (ZDCCloudHandlerWithMetadataBlock)handler->block;
		
		block(databaseTransaction, cloudConnection->operations_block, ck.collection, ck.key, metadata);
	}
	else
	{
		ZDCCloudHandlerWithRowBlock block = (ZDCCloudHandlerWithRowBlock)handler->block;
		
		block(databaseTransaction, cloudConnection->operations_block, ck.collection, ck.key, object, metadata);
	}
	
	if ([cloudConnection->operations_block count] > 0)
	{
		for (YapDatabaseCloudCoreOperation *operation in cloudConnection->operations_block)
		{
			[self addOperation:operation];
		}
		
		[cloudConnection->operations_block removeAllObjects];
	}
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being inserted, meaning there is not currently an entry for the collection/key tuple.
**/
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	[super didInsertObject:object forCollectionKey:collectionKey withMetadata:metadata rowid:rowid];
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being modified, meaning there is already an entry for the collection/key tuple which is being modified.
**/
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudHandler *handler = ((ZDCCloud *)parentConnection->parent)->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceObject:forKey:inCollection:
 * - replaceObject:forKey:inCollection:withSerializedObject:
 *
 * There is already a row for the collection/key tuple, and only the object is being modified (metadata untouched).
**/
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudHandler *handler = ((ZDCCloud *)parentConnection->parent)->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceMetadata:forKey:inCollection:
 * - replaceMetadata:forKey:inCollection:withSerializedMetadata:
 *
 * There is already a row for the collection/key tuple, and only the metadata is being modified (object untouched).
**/
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudHandler *handler = ((ZDCCloud *)parentConnection->parent)->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfMetadataModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudHandler *handler = ((ZDCCloud *)parentConnection->parent)->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudHandler *handler = ((ZDCCloud *)parentConnection->parent)->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	DDLogAutoTrace();
	
	__unsafe_unretained ZDCCloudHandler *handler = ((ZDCCloud *)parentConnection->parent)->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectTouched |
	                                            YapDatabaseBlockInvokeIfMetadataTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	                   object:object
	                 metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction
 * - removeObjectForKey:inCollection:
 */
- (void)willRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	// Why are we usin the pre-op hook instead of the post-op hook here ?
	//
	// If we instead use the `didRemoveObjectForCollectionKey:` then:
	// - when the method is inovked, the database row no longer exists
	// - we call [self linkedNodeForKey:inCollection:]
	// - which in turn calls [self linkedNodeIDForKey:inCollection:]
	// - which in turn calls [self enumerateAttachedForKey:inCollection:]
	// - which in turn calls [databaseTransaction getRowid:&rowid forKey:key inCollection:collection]
	// - which doesn't find the rowid, since it's already been deleted
	//
	// So we have 2 options:
	// - use the pre-op version
	// - add alternative code paths which take {rowid, collectionKey} as opposed to {collection, key}
	//
	// We're taking the easy option for now.
	
	ZDCNode *linkedNode = [self linkedNodeForKey:ck.key inCollection:ck.collection];
	if (linkedNode)
	{
		[self deleteNode:linkedNode error:nil];
	}
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectsForKeys:inCollection:
 * - removeAllObjectsInCollection:
 *
 * IMPORTANT:
 *   The number of items passed to this method has the following guarantee:
 *   count <= (SQLITE_LIMIT_VARIABLE_NUMBER - 1)
 *
 * The YapDatabaseReadWriteTransaction will inspect the list of keys that are to be removed,
 * and then loop over them in "chunks" which are readily processable for extensions.
 */
- (void)willRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	for (NSString *key in keys)
	{
		ZDCNode *linkedNode = [self linkedNodeForKey:key inCollection:collection];
		if (linkedNode)
		{
			[self deleteNode:linkedNode error:nil];
		}
	}
}

@end
