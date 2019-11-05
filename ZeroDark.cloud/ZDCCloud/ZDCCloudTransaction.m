/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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

#import "NSData+S4.h"
#import "NSError+ZeroDark.h"
#import "NSString+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

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

- (NSString *)treeID
{
	ZDCCloud *ext = (ZDCCloud *)parentConnection->parent;
	return ext.treeID;
}

- (YapDatabaseCloudCorePipeline *)defaultPipeline
{
	return [parentConnection->parent defaultPipeline];
}

- (NSString *)signalParentID
{
	return [ZDCNode signalParentIDForLocalUserID:[self localUserID] treeID:[self treeID]];
}

- (NSString *)graftParentID
{
	return [ZDCNode graftParentIDForLocalUserID:[self localUserID] treeID:[self treeID]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Messaging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)sendMessageToRecipients:(NSArray<ZDCUser*> *)recipients
                                        error:(NSError *_Nullable *_Nullable)outError
{
	return [self sendMessageToRecipients:recipients withDependencies:nil error:outError];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)sendMessageToRecipients:(NSArray<ZDCUser*> *)recipients
                             withDependencies:(nullable NSArray<ZDCCloudOperation*> *)dependencies
                                        error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	// Create message node
	
	NSString *localUserID = [self localUserID];
	NSString *treeID = [self treeID];
	
	ZDCNode *message = [[ZDCNode alloc] initWithLocalUserID:localUserID];
	
	ZDCTrunkNode *outbox = [self trunkNode:ZDCTreesystemTrunk_Outbox];
	message.parentID = outbox.uuid;
	
	NSString *cloudName = [ZDCNode randomCloudName];
	message.name = cloudName;
	message.explicitCloudName = cloudName;
	
	if (recipients.count > 0)
	{
		NSMutableSet *userIDs = [NSMutableSet setWithCapacity:recipients.count];
		for (ZDCUser *user in recipients)
		{
			[userIDs addObject:user.uuid];
		}
		
		message.pendingRecipients = userIDs;
	}
	
	{ // Add sender permissions
		
		ZDCShareItem *item = [[ZDCShareItem alloc] init];
		[item addPermission:ZDCSharePermission_Read];
		[item addPermission:ZDCSharePermission_Write];
		[item addPermission:ZDCSharePermission_Share];
		[item addPermission:ZDCSharePermission_LeafsOnly];
		
		[message.shareList addShareItem:item forUserID:localUserID];
	}
	
	[rwTransaction setObject:message forKey:message.uuid inCollection:kZDCCollection_Nodes];
	
	// Create & queue operations (put:[rcrd, data] -> local:outbox)
	
	ZDCCloudLocator *cloudLocator =
	  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: message
	                                                transaction: databaseTransaction];
	
	ZDCCloudOperation *op_rcrd =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Rcrd];
	
	ZDCCloudOperation *op_data =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Data];
	
	op_rcrd.nodeID = message.uuid;
	op_data.nodeID = message.uuid;
	
	op_rcrd.cloudLocator = [cloudLocator copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
	op_data.cloudLocator = [cloudLocator copyWithFileNameExt:kZDCCloudFileExtension_Data];
	
	if (dependencies) {
		[op_rcrd addDependencies:dependencies];
	}
	[op_data addDependency:op_rcrd];
	
	[self addOperation:op_rcrd];
	[self addOperation:op_data];
	
	// Create and queue operations (copy-leaf -> remote:inbox)
	
	for (ZDCUser *recipient in recipients)
	{
		ZDCNode *dstNode = [[ZDCNode alloc] initWithLocalUserID:localUserID];
		dstNode.parentID = [self signalParentID];
		dstNode.encryptionKey = message.encryptionKey;
		
		NSString *cloudName = [ZDCNode randomCloudName];
		dstNode.name = cloudName;
		dstNode.explicitCloudName = cloudName;
		
		dstNode.pendingRecipients = [NSSet setWithObject:recipient.uuid];
		
		dstNode.anchor =
		  [[ZDCNodeAnchor alloc] initWithUserID: recipient.uuid
		                                 treeID: treeID
		                              dirPrefix: kZDCDirPrefix_MsgsIn];
		
		{ // Add recipient permissions
			
			ZDCShareItem *item = [[ZDCShareItem alloc] init];
			[item addPermission:ZDCSharePermission_Read];
			[item addPermission:ZDCSharePermission_Write];
			[item addPermission:ZDCSharePermission_Share];
			[item addPermission:ZDCSharePermission_LeafsOnly];
			
			[dstNode.shareList addShareItem:item forUserID:recipient.uuid];
		}
		
		if (![dstNode.shareList hasShareItemForUserID:localUserID])
		{
			// Add sender permissions
			
			ZDCShareItem *item = [[ZDCShareItem alloc] init];
			[item addPermission:ZDCSharePermission_LeafsOnly];
			[item addPermission:ZDCSharePermission_WriteOnce];
			[item addPermission:ZDCSharePermission_BurnIfSender];
			
			[dstNode.shareList addShareItem:item forUserID:localUserID];
		}
		
		[rwTransaction setObject:dstNode forKey:dstNode.uuid inCollection:kZDCCollection_Nodes];
		
		ZDCCloudOperation *op_copy =
		  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                          treeID: treeID
		                                            type: ZDCCloudOperationType_CopyLeaf];
		
		ZDCCloudPath *dstCloudPath =
		  [[ZDCCloudPath alloc] initWithTreeID: treeID
		                             dirPrefix: kZDCDirPrefix_MsgsIn
		                              fileName: cloudName];
		
		ZDCCloudLocator *dstCloudLocator =
		  [[ZDCCloudLocator alloc] initWithRegion: recipient.aws_region
		                                   bucket: recipient.aws_bucket
		                                cloudPath: dstCloudPath];
		
		op_copy.nodeID = message.uuid;
		op_copy.dstNodeID = dstNode.uuid;
		op_copy.cloudLocator = cloudLocator;
		op_copy.dstCloudLocator = dstCloudLocator;
		
		[self addOperation:op_copy];
	}
	
	return message;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)sendSignalToRecipient:(ZDCUser *)recipient
                                      error:(NSError *_Nullable *_Nullable)outError
{
	return [self sendSignalToRecipient:recipient withDependencies:nil error:outError];
}

- (nullable ZDCNode *)sendSignalToRecipient:(ZDCUser *)recipient
                           withDependencies:(nullable NSArray<ZDCCloudOperation*> *)dependencies
                                      error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	// Sanity checks
	
	if (recipient == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: the given recipient is nil";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	// Create signal node
	
	NSString *localUserID = [self localUserID];
	NSString *treeID = [self treeID];
	
	ZDCNode *signal = [[ZDCNode alloc] initWithLocalUserID:localUserID];
	signal.parentID = [self signalParentID];
	
	NSString *cloudName = [ZDCNode randomCloudName];
	signal.name = cloudName;
	signal.explicitCloudName = cloudName;
	
	signal.pendingRecipients = [NSSet setWithObject:recipient.uuid];
	
	signal.anchor =
	  [[ZDCNodeAnchor alloc] initWithUserID: recipient.uuid
	                                 treeID: treeID
	                              dirPrefix: kZDCDirPrefix_MsgsIn];
	
	{ // Add recipient permissions
		
		ZDCShareItem *item = [[ZDCShareItem alloc] init];
		[item addPermission:ZDCSharePermission_Read];
		[item addPermission:ZDCSharePermission_Write];
		[item addPermission:ZDCSharePermission_Share];
		[item addPermission:ZDCSharePermission_LeafsOnly];
		
		[signal.shareList addShareItem:item forUserID:recipient.uuid];
	}
	
	if (![signal.shareList hasShareItemForUserID:localUserID])
	{
		// Add sender permissions
		
		ZDCShareItem *item = [[ZDCShareItem alloc] init];
		[item addPermission:ZDCSharePermission_LeafsOnly];
		[item addPermission:ZDCSharePermission_WriteOnce];
		[item addPermission:ZDCSharePermission_BurnIfSender];
		
		[signal.shareList addShareItem:item forUserID:localUserID];
	}
	
	[rwTransaction setObject:signal forKey:signal.uuid inCollection:kZDCCollection_Nodes];
	
	// Create & queue operation
	
	ZDCCloudPath *cloudPath =
	  [[ZDCCloudPath alloc] initWithTreeID: treeID
	                             dirPrefix: kZDCDirPrefix_MsgsIn
	                              fileName: cloudName];
	
	ZDCCloudLocator *cloudLocator =
	  [[ZDCCloudLocator alloc] initWithRegion: recipient.aws_region
	                                   bucket: recipient.aws_bucket
	                                cloudPath: cloudPath];
	
	ZDCCloudOperation *op_rcrd =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Rcrd];
	
	ZDCCloudOperation *op_data =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Data];
	
	op_rcrd.nodeID = signal.uuid;
	op_data.nodeID = signal.uuid;
	
	op_rcrd.cloudLocator = [cloudLocator copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
	op_data.cloudLocator = [cloudLocator copyWithFileNameExt:kZDCCloudFileExtension_Data];
	
	if (dependencies) {
		[op_rcrd addDependencies:dependencies];
	}
	[op_data addDependency:op_rcrd];
	
	[self addOperation:op_rcrd];
	[self addOperation:op_data];
	
	return signal;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)nodeWithID:(NSString *)nodeID
{
	return [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)nodeWithPath:(ZDCTreesystemPath *)path
{
	NSString *const localUserID = [self localUserID];
	NSString *const treeID = [self treeID];
	
	ZDCNode *node =
	  [[ZDCNodeManager sharedInstance] findNodeWithPath: path
	                                        localUserID: localUserID
	                                             treeID: treeID
	                                        transaction: databaseTransaction];
	return node;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)parentNode:(ZDCNode *)node
{
	NSString *parentID = node.parentID;
	if (parentID == nil) {
		return nil;
	}
	
	ZDCNode *parentNode = nil;
	if ([parentID hasSuffix:@"|graft"])
	{
		parentNode =
		  [[ZDCNodeManager sharedInstance] findNodeWithPointeeID: parentID
		                                             localUserID: [self localUserID]
		                                                  treeID: [self treeID]
		                                             transaction: databaseTransaction];
	}
	else
	{
		parentNode = [databaseTransaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
	}
	
	if ([parentNode.parentID hasSuffix:@"|graft"])
	{
		parentNode =
		  [[ZDCNodeManager sharedInstance] findNodeWithPointeeID: parentNode.uuid
		                                             localUserID: [self localUserID]
		                                                  treeID: [self treeID]
		                                             transaction: databaseTransaction];
	}
	
	return parentNode;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)targetNode:(ZDCNode *)node
{
	return [[ZDCNodeManager sharedInstance] targetNodeForNode:node transaction:databaseTransaction];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCTrunkNode *)trunkNode:(ZDCTreesystemTrunk)trunk
{
	return [[ZDCNodeManager sharedInstance] trunkNodeForLocalUserID: [self localUserID]
	                                                         treeID: [self treeID]
	                                                          trunk: trunk
	                                                    transaction: databaseTransaction];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (ZDCTreesystemPath *)conflictFreePath:(ZDCTreesystemPath *)path
{
	if (path.isTrunk) return path;
	
	ZDCNode *conflictNode = [self nodeWithPath:path];
	if (conflictNode == nil) {
		return path;
	}
	
	NSString *newName =
	  [[ZDCNodeManager sharedInstance] resolveNamingConflict: conflictNode
	                                             transaction: databaseTransaction];
	
	return [[path parentPath] pathByAppendingComponent:newName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)createNodeWithPath:(ZDCTreesystemPath *)path
                                   error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
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
	
	NSString *localUserID = [self localUserID];
	
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:localUserID];
	node.parentID = parentNode.uuid;
	node.name = nodeName;
	
	[[ZDCNodeManager sharedInstance] resetPermissionsForNode:node transaction:rwTransaction];
	
	[rwTransaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
	
	[self queuePutOperationForNodeRcrd:node];
	[self queuePutOperationForNodeData:node];
	
	if (outError) *outError = nil;
	return node;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)insertNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
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
	
	NSString *localUserID = [self localUserID];
	
	if (![node.localUserID isEqualToString:localUserID])
	{
		// You're adding the node to the wrong ZDCCloud extension.
		// ZDCNode.localUserID MUST match ZDCCloud.localUserID.
		
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: node.localUserID != ZDCCloud.localUserID";
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
	
	[self queuePutOperationForNodeRcrd:node];
	[self queuePutOperationForNodeData:node];
	
	return YES;
}

- (nullable ZDCCloudOperation *)queuePutOperationForNodeRcrd:(ZDCNode *)node
{
	NSString *localUserID = [self localUserID];
	NSString *treeID = [self treeID];
	
	ZDCCloudLocator *cloudLocator_rcrd =
	  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
	                                              fileExtension: kZDCCloudFileExtension_Rcrd
	                                                transaction: databaseTransaction];
	
	if (cloudLocator_rcrd == nil) {
		return nil;
	}
	
	ZDCCloudOperation *op_rcrd =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Rcrd];
	
	op_rcrd.nodeID = node.uuid;
	op_rcrd.cloudLocator = cloudLocator_rcrd;
	
	[self addOperation:op_rcrd];
	return op_rcrd;
}

- (nullable ZDCCloudOperation *)queuePutOperationForNodeData:(ZDCNode *)node
{
	NSString *localUserID = [self localUserID];
	NSString *treeID = [self treeID];
	
	if (node.isPointer) {
		return nil;
	}
	
	ZDCCloudLocator *cloudLocator_data =
	  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
	                                              fileExtension: kZDCCloudFileExtension_Data
	                                                transaction: databaseTransaction];
	
	ZDCCloudOperation *op_data =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Data];
	
	op_data.nodeID = node.uuid;
	op_data.cloudLocator = cloudLocator_data;
	op_data.eTag = node.eTag_data;
	
	[self addOperation:op_data];
	return op_data;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCCloudOperation *)modifyNode:(ZDCNode *)newNode error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
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
		return nil;
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
		return nil;
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
		return nil;
	}
	
	NSDictionary *changeset_permissions = newNode.shareList.changeset;
	
	[rwTransaction setObject:newNode forKey:newNode.uuid inCollection:kZDCCollection_Nodes];
	
	NSString *localUserID = [self localUserID];
	NSString *treeID = [self treeID];
	
	ZDCCloudOperation *op = nil;
	
	BOOL didMoveNode = ![newNode.name isEqual:oldNode.name] || ![newNode.parentID isEqual:oldNode.parentID];
	if (didMoveNode)
	{
		ZDCCloudLocator *srcCloudLocator =
		  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: oldNode
		                                              fileExtension: kZDCCloudFileExtension_Rcrd
		                                                transaction: databaseTransaction];
		
		op = [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                             treeID: treeID
		                                               type: ZDCCloudOperationType_Move];
		
		op.cloudLocator = srcCloudLocator;
		op.dstCloudLocator = cloudLocator;
	}
	else
	{
		op = [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                             treeID: treeID
		                                            putType: ZDCCloudOperationPutType_Node_Rcrd];
		op.cloudLocator = cloudLocator;
	}
	
	op.nodeID = newNode.uuid;
	op.changeset_permissions = changeset_permissions;
	
	[self addOperation:op];
	
	if (outError) *outError = nil;
	return op;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
	NSString *const treeID = [self treeID];
	
	ZDCNode *node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
	if (node == nil) {
		return nil;
	}
	
	if (node.isPointer) {
		return nil; // Pointers don't have a DATA fork.
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
	                                          treeID: treeID
	                                         putType: ZDCCloudOperationPutType_Node_Data];
	
	operation.nodeID = node.uuid;
	operation.cloudLocator = cloudLocator;
	operation.eTag = node.eTag_data;
	operation.changeset_obj = changeset;
	
	[self addOperation:operation];
	
	return operation;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCCloudOperation *)deleteNode:(ZDCNode *)node error:(NSError *_Nullable *_Nullable)outError
{
	ZDCDeleteNodeOptions defaultOptions = ZDCDeleteOutdatedNodes | ZDCDeleteUnknownNodes;
	
	return [self deleteNode: node
	            withOptions: defaultOptions
	                  error: outError];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCCloudOperation *)deleteNode:(ZDCNode *)rootNode
                               withOptions:(ZDCDeleteNodeOptions)opts
                                     error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		// Improper database API usage.
		// All other YapDatabase extensions throw an exception when this occurs.
		// Following recommended pattern here.
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
	}
	YapDatabaseReadWriteTransaction *rwTransaction = (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	if ([rootNode isKindOfClass:[ZDCTrunkNode class]])
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"You cannot delete a trunk node.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSString *localUserID = [self localUserID];
	NSString *treeID = [self treeID];
	
	ZDCNodeManager *nodeManager = [ZDCNodeManager sharedInstance];
	ZDCCloudPathManager *cloudPathManager = [ZDCCloudPathManager sharedInstance];
	
	ZDCCloudLocator *root_cloudLocator =
	  [cloudPathManager cloudLocatorForNode: rootNode
	                            transaction: databaseTransaction];
	
	if (root_cloudLocator == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Unknown cloudPath for node.";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	// What kind of node are we dealing with here ?
	
	const BOOL isPointer = rootNode.isPointer;
	
	const BOOL isMessage =
	    [rootNode.parentID hasSuffix:@"|inbox"]
	 || [rootNode.parentID hasSuffix:@"|outbox"]
	 || [rootNode.parentID hasSuffix:@"|signal"];
	
	const BOOL isLeaf = isPointer || isMessage;
	
	NSMutableDictionary *json = nil;
	NSMutableDictionary *children = nil;
	NSString *strOpts = nil;
	
	if (!isLeaf)
	{
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
		
		json = [NSMutableDictionary dictionary];
		json[@"version"] = @(1);
	
		NSString *root_cloudPath =
		  [root_cloudLocator.cloudPath pathWithComponents:(ZDCCloudPathComponents_DirPrefix |
		                                                   ZDCCloudPathComponents_FileName_WithoutExt)];
	
		NSString *root_eTag    = rootNode.eTag_rcrd ?: @"";
		NSString *root_cloudID = rootNode.cloudID   ?: @"";
	
		json[@"root"] = @{
			root_cloudPath: @[root_eTag, root_cloudID]
		};
	
		children = [NSMutableDictionary dictionary];
		json[@"children"] = children;
	
		strOpts = [NSString stringWithFormat:@"%d%d",
			((opts & ZDCDeleteOutdatedNodes) ? 1 : 0),
			((opts & ZDCDeleteUnknownNodes)  ? 1 : 0)
		];
		
		children[@""] = strOpts;
	}
	
	// Enumerate all the child nodes
	
	NSMutableSet<NSString*> *cloudIDs = [NSMutableSet set];
	NSMutableArray<NSString*> *childNodeIDs = [NSMutableArray array];
	
	[nodeManager recursiveEnumerateNodesWithParentID: rootNode.uuid
	                                     transaction: databaseTransaction
	                                      usingBlock:
	^(ZDCNode *childNode, NSArray<ZDCNode*> *pathFromParent, BOOL *recurseInto, BOOL *stop) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[childNodeIDs addObject:childNode.uuid];
		
		if (!isPointer)
		{
			ZDCCloudLocator *cloudLocator =
			  [cloudPathManager cloudLocatorForNode: childNode
			                            transaction: databaseTransaction];
		
			if (cloudLocator)
			{
				// Create corresponding ZDCCloudNode
				
				ZDCCloudNode *cloudNode =
				  [[ZDCCloudNode alloc] initWithLocalUserID: childNode.localUserID
				                               cloudLocator: cloudLocator];
		
				[rwTransaction setObject: cloudNode
				                  forKey: cloudNode.uuid
				            inCollection: kZDCCollection_CloudNodes];
		
				if (!isLeaf)
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
				}
			}
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
	
	if (isLeaf)
	{
		// Delete-Leaf operation
		
		operation =
		  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                          treeID: treeID
		                                            type: ZDCCloudOperationType_DeleteLeaf];
	}
	else
	{
		// Delete-Node operation
		
		operation =
		  [[ZDCCloudOperation alloc] initWithLocalUserID: localUserID
		                                          treeID: treeID
		                                            type: ZDCCloudOperationType_DeleteNode];
		
		NSError *jsonError = nil;
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&jsonError];
		
		if (jsonError)
		{
			if (outError) *outError = jsonError;
			return nil;
		}
		
		operation.deleteNodeJSON = jsonData;
	}
	
	operation.cloudLocator = root_cloudLocator;
	
	if (rootNode.cloudID) {
		[cloudIDs addObject:rootNode.cloudID];
	}
	operation.deletedCloudIDs = cloudIDs;
	
	// Create corresponding ZDCCloudNode
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
	
	BOOL pointeeIsRetained = NO;
	if (isPointer)
	{
		// Delete the pointer itself
		[rwTransaction removeObjectForKey:rootNode.uuid inCollection:kZDCCollection_Nodes];
		
		// Are the other references to the pointee (and children) ?
		
		ZDCNode *pointeeNode = [rwTransaction objectForKey:rootNode.pointeeID inCollection:kZDCCollection_Nodes];
		
		if (![pointeeNode.parentID isEqualToString:[self graftParentID]])
		{
			pointeeIsRetained = YES;
		}
		else
		{
			ZDCNode *retainerNode =
			  [[ZDCNodeManager sharedInstance] findNodeWithPointeeID: rootNode.pointeeID
			                                             localUserID: localUserID
			                                                  treeID: treeID
			                                             transaction: rwTransaction];
			if (retainerNode) {
				pointeeIsRetained = YES;
			}
		}
		
		if (!pointeeIsRetained)
		{
			[rwTransaction removeObjectsForKeys:childNodeIDs inCollection:kZDCCollection_Nodes];
		}
	}
	else // if (!isPointer)
	{
		[rwTransaction removeObjectForKey:rootNode.uuid inCollection:kZDCCollection_Nodes];
		[rwTransaction removeObjectsForKeys:childNodeIDs inCollection:kZDCCollection_Nodes];
	}
	
	// Skip put-data operations for any node we're deleting.
	//
	// Note that we're not skipping put:rcrd or move operations.
	// That's an optimization that requires a MUCH more complicated solution.
	
	NSMutableSet<NSString *> *targetNodeIDs = [NSMutableSet set];
	[targetNodeIDs addObject:rootNode.uuid];
	
	if (!isPointer || !pointeeIsRetained)
	{
		[targetNodeIDs addObjectsFromArray:childNodeIDs];
	}
	
	NSMutableSet<NSUUID *> *opUUIDs = [NSMutableSet set];
	
	[self enumerateOperationsUsingBlock:
		^(YapDatabaseCloudCorePipeline *pipeline,
	     YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			
			if (op.isPutNodeDataOperation && op.nodeID && [targetNodeIDs containsObject:op.nodeID])
			{
				[opUUIDs addObject:op.uuid];
			}
		}
	}];
	
	[self skipPutOperations:opUUIDs];
	
	// Done
	
	if (outError) *outError = nil;
	return operation;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Dropbox
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
* See header file for description.
* Or view the api's online (for both Swift & Objective-C):
* https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
*/
- (nullable ZDCDropboxInvite *)dropboxInviteForNode:(ZDCNode *)node
{
	ZDCLogAutoTrace();
	
	ZDCCloudPath *cloudPath =
	  [[ZDCCloudPathManager sharedInstance] cloudPathForNode:node transaction:databaseTransaction];
	
	if (cloudPath == nil)
	{
		// Did you forget to add the node to the treesystem ?
		//
		return nil;
	}
	
	return [[ZDCDropboxInvite alloc] initWithTreeID:cloudPath.treeID dirPrefix:cloudPath.dirPrefix];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Grafting
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCGraftInvite *)graftInviteForNode:(ZDCNode *)node
{
	ZDCLogAutoTrace();
	
	NSString *cloudID = node.cloudID;
	
	if (cloudID == nil)
	{
		// The node hasn't been uploaded yet.
		//
		// If you're running into this problem, it's probably because you forgot to add dependencies to your message.
		// For example, you may have done something like this:
		//
		// zdc.databaseManager?.rwDatabaseConnection.asyncReadWrite {(transaction) in
		//   {... create node ...}
		//   {... enqueue message ...}
		// }
		//
		// This creates multiple ZDCCloudOperation's to perform those tasks.
		// But you forgot to ensure that:
		// - the "send message" operation must be performed AFTER the "upload node" operations
		//
		// You can get the "upload node" operations via the `addedOperations` method.
		// And you can pass those via:
		// - `sendMesssageToRecipients:withDependencies::`
		// - `sendSignalToRecipient:withDependencies::`
		//
		return nil;
	}
	
	ZDCCloudPath *cloudPath =
	  [[ZDCCloudPathManager sharedInstance] cloudPathForNode:node transaction:databaseTransaction];
	
	if (cloudPath == nil)
	{
		// Did you forget to add the node to the treesystem ?
		//
		return nil;
	}
	
	return [[ZDCGraftInvite alloc] initWithCloudID:cloudID cloudPath:cloudPath];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCNode *)graftNodeWithLocalPath:(ZDCTreesystemPath *)path
                             remoteCloudPath:(ZDCCloudPath *)remotePath
                               remoteCloudID:(NSString *)remoteCloudID
                                  remoteUser:(ZDCUser *)remoteUser
                                       error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
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
	
	if (remotePath == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: remotePath is nil";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	if (remoteUser == nil)
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: remoteUser is nil";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSString *const localUserID = [self localUserID];
	NSString *const treeID = [self treeID];
	
	if ([remoteUser.uuid isEqualToString:localUserID])
	{
		ZDCCloudErrorCode code = ZDCCloudErrorCode_InvalidParameter;
		NSString *desc = @"Invalid parameter: you cannot graft your own treesystem";
		NSError *error = [NSError errorWithClass:[self class] code:code description:desc];
		
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCNode *pointeeNode =
	  [[ZDCNodeManager sharedInstance] findNodeWithCloudPath: remotePath
	                                                  bucket: remoteUser.aws_bucket
	                                                  region: remoteUser.aws_region
	                                             localUserID: localUserID
	                                                  treeID: treeID
	                                             transaction: rwTransaction];
	
	if (pointeeNode == nil)
	{
		pointeeNode = [[ZDCNode alloc] initWithLocalUserID:localUserID];
		pointeeNode.parentID = [self graftParentID];
		pointeeNode.cloudID = remoteCloudID;
		
		NSString *cloudName = [remotePath fileNameWithExt:nil];
		pointeeNode.name = cloudName;
		pointeeNode.explicitCloudName = cloudName;
		
		pointeeNode.anchor =
		  [[ZDCNodeAnchor alloc] initWithUserID: remoteUser.uuid
		                                 treeID: remotePath.treeID
		                              dirPrefix: remotePath.dirPrefix];
		
		[rwTransaction setObject: pointeeNode
		                  forKey: pointeeNode.uuid
		            inCollection: kZDCCollection_Nodes];
	}
	
	ZDCNode *pointerNode = [[ZDCNode alloc] initWithLocalUserID:localUserID];
	pointerNode.parentID = parentNode.uuid;
	pointerNode.name = nodeName;
	pointerNode.pointeeID = pointeeNode.uuid;
	
	[[ZDCNodeManager sharedInstance] resetPermissionsForNode:pointerNode transaction:rwTransaction];
	
	[rwTransaction setObject: pointerNode
	                  forKey: pointerNode.uuid
	            inCollection: kZDCCollection_Nodes];
	
	[self queuePutOperationForNodeRcrd:pointerNode];
	
	if (outError) *outError = nil;
	return pointerNode;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Permissions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (NSArray<ZDCCloudOperation*> *)recursiveAddShareItem:(ZDCShareItem *)shareItem
                                             forUserID:(NSString *)userID
                                                nodeID:(NSString *)rootNodeID
{
	NSMutableArray<NSString*> *nodeIDs = [NSMutableArray array];
	[nodeIDs addObject:rootNodeID];
	
	[[ZDCNodeManager sharedInstance] recursiveEnumerateNodeIDsWithParentID: rootNodeID
	                                                           transaction: databaseTransaction
	                                                            usingBlock:
	^(NSString *descendentNodeID, NSArray<NSString *> *pathFromParent, BOOL *recurseInto, BOOL *stop) {
		
		[nodeIDs addObject:descendentNodeID];
	}];
	
	NSMutableArray<ZDCCloudOperation*> *operations = [NSMutableArray array];
	
	for (NSString *nodeID in nodeIDs)
	{
		ZDCNode *node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		
		if ([node.shareList hasShareItemForUserID:userID])
		{
			// Here's the deal:
			//
			// Since there's already a shareItem for this user, any attempt to ADD the item will fail.
			// The ZDCShareList class operates this way because it's in charge of MERGING changes
			// between multiple devices.
			//
			// In other words, if there's already a shareItem for this user, then you need to MODIFY it:
			//
			// if let shareItem = node.shareList.shareItem(forUserID: userID) {
			//   shareItem.addPermission(ZDCSharePermission.read)
			//   shareItem.addPermission(ZDCSharePermission.write)
			// } else {
			//   let shareItem = ZDCShareItem()
			//   shareItem.addPermission(ZDCSharePermission.read)
			//   shareItem.addPermission(ZDCSharePermission.write)
			//   node.shareList.add(shareItem, forUserID: userID)
			// }
		}
		else
		{
			node = [node copy];
			[node.shareList addShareItem:shareItem forUserID:userID];
			
			ZDCCloudOperation *op = [self modifyNode:node error:nil];
			if (op) {
				[operations addObject:op];
			}
		}
	}
	
	return operations;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (NSArray<ZDCCloudOperation*> *)recursiveRemoveShareItemForUserID:(NSString *)userID
                                                            nodeID:(NSString *)rootNodeID
{
	NSMutableArray<NSString*> *nodeIDs = [NSMutableArray array];
	[nodeIDs addObject:rootNodeID];
	
	[[ZDCNodeManager sharedInstance] recursiveEnumerateNodeIDsWithParentID: rootNodeID
	                                                           transaction: databaseTransaction
	                                                            usingBlock:
	^(NSString *descendentNodeID, NSArray<NSString *> *pathFromParent, BOOL *recurseInto, BOOL *stop) {
		
		[nodeIDs addObject:descendentNodeID];
	}];
	
	NSMutableArray<ZDCCloudOperation*> *operations = [NSMutableArray array];
	
	for (NSString *nodeID in nodeIDs)
	{
		ZDCNode *node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		
		if ([node.shareList hasShareItemForUserID:userID])
		{
			node = [node copy];
			
			[node.shareList removeShareItemForUserID:userID];
			
			ZDCCloudOperation *op = [self modifyNode:node error:nil];
			if (op) {
				[operations addObject:op];
			}
		}
	}
	
	return operations;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Linking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)linkNodeID:(NSString *)nodeID
             toKey:(NSString *)key
      inCollection:(nullable NSString *)collection
             error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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

- (nullable NSString *)_linkedNodeIDForRowid:(int64_t)rowid
{
	__block NSString *nodeID = nil;
	[self _enumerateAttachedForRowid: rowid
								 usingBlock:^(NSString *cloudURI, BOOL *stop)
	{
		nodeID = cloudURI;
		*stop = YES;
	}];
	
	return nodeID;
}

- (nullable ZDCNode *)_linkedNodeForRowid:(int64_t)rowid
{
	ZDCNode *node = nil;
	
	NSString *nodeID = [self _linkedNodeIDForRowid:rowid];
	if (nodeID) {
		node = [databaseTransaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
	}
	
	return node;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable id)linkedObjectForPath:(ZDCTreesystemPath *)path
{
	NSString *const localUserID = [self localUserID];
	NSString *const treeID = [self treeID];
	
	ZDCNode *node =
	  [[ZDCNodeManager sharedInstance] findNodeWithPath: path
	                                        localUserID: localUserID
	                                             treeID: treeID
	                                        transaction: databaseTransaction];
	
	if (node) {
		return [self linkedObjectForNodeID:node.uuid];
	}
	else {
		return nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Tagging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable id)tagForNodeID:(NSString *)nodeID withIdentifier:(NSString *)identifier
{
	return [self tagForKey:nodeID withIdentifier:identifier];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)setTag:(nullable id)tag forNodeID:(NSString *)nodeID withIdentifier:(NSString *)identifier
{
	[self setTag:tag forKey:nodeID withIdentifier:identifier];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)enumerateTagsForNodeID:(NSString *)nodeID
                     withBlock:(void (^NS_NOESCAPE)(NSString *identifier, id tag, BOOL *stop))block
{
	[self enumerateTagsForKey:nodeID withBlock:block];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)removeTagForNodeID:(NSString *)nodeID withIdentifier:(NSString *)identifier
{
	[self removeTagForKey:nodeID withIdentifier:identifier];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)removeAllTagsForNodeID:(NSString *)nodeID
{
	[self removeAllTagsForKey:nodeID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Download Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)internalTaggingKeyForNodeID:(NSString *)nodeID
{
	// There's a public API for tagging nodeID's.
	// We want to use the same tagging system, but don't want to have any conflicts with the public API.
	// So we simply use a different key.
	
	if (nodeID == nil)
		return nil;
	else
		return [NSString stringWithFormat:@"%@|zdc", nodeID];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)markNodeAsNeedsDownload:(NSString *)nodeID components:(ZDCNodeComponents)components
{
	if (nodeID == nil) return;
	
	NSString *key = [self internalTaggingKeyForNodeID:nodeID];
	[self setTag:@(components) forKey:key withIdentifier:nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)unmarkNodeAsNeedsDownload:(NSString *)nodeID
                       components:(ZDCNodeComponents)components
                    ifETagMatches:(nullable NSString *)eTag
{
	if (nodeID == nil) return;
	
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
	
	NSString *key = [self internalTaggingKeyForNodeID:nodeID];
	id tag = [self tagForKey:key withIdentifier:nil];
	
	if (tag && [tag isKindOfClass:[NSNumber class]])
	{
		NSUInteger bitmask = [(NSNumber *)tag unsignedIntegerValue];
		ZDCNodeComponents existingComponents = bitmask & ZDCNodeComponents_All;
		
		// Example:
		//
		//   existingComponents = 01111
		// -         components = 00100
		// ----------------------------
		//   newComponents      = 01011
		//
		// flags &= ~flag
		// ^^^^^^^^^^^^^^
		// Explanation:
		//
		// - If flag == 00100, then ~flag == 11011
		// - & is a bitwise AND operation
		// - &= is assignment after bitwise AND operation
		//
		// Putting it all together:
		// - if flags == 00111
		// - and flag == 00100
		//
		// flags &= ~flag  IS
		// 00111 &= ~00100 IS
		// 00111 &=  11011 IS
		// 00011
		//
		// In other words, it unsets a specific flag.
		
		ZDCNodeComponents newComponents = existingComponents;
		if (components & ZDCNodeComponents_Header) {
			newComponents &= ~ZDCNodeComponents_Header; // see comment above for code explanation
		}
		if (components & ZDCNodeComponents_Metadata) {
			newComponents &= ~ZDCNodeComponents_Metadata; // see comment above for code explanation
		}
		if (components & ZDCNodeComponents_Thumbnail) {
			newComponents &= ~ZDCNodeComponents_Thumbnail; // see comment above for code explanation
		}
		if (components & ZDCNodeComponents_Data) {
			newComponents &= ~ZDCNodeComponents_Data; // see comment above for code explanation
		}
		
		if (newComponents == 0) {
			[self removeTagForKey:key withIdentifier:nil];
		}
		else {
			[self setTag:@(newComponents) forKey:key withIdentifier:nil];
		}
	}
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)nodeIsMarkedAsNeedsDownload:(NSString *)nodeID components:(ZDCNodeComponents)components
{
	BOOL result = NO;
	
	NSString *key = [self internalTaggingKeyForNodeID:nodeID];
	id tag = [self tagForKey:key withIdentifier:nil];
	
	if (tag && [tag isKindOfClass:[NSNumber class]])
	{
		NSUInteger bitmask = [(NSNumber *)tag unsignedIntegerValue];
		ZDCNodeComponents existing = bitmask & ZDCNodeComponents_All;
		
		ZDCNodeComponents passed = components & ZDCNodeComponents_All;
		
		ZDCNodeComponents bitwiseOR = existing | passed;
		if (bitwiseOR != 0) {
			result = YES;
		}
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (nullable ZDCUser *)userWithID:(NSString *)userID
{
	return [databaseTransaction objectForKey:userID inCollection:kZDCCollection_Users];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (NSArray<ZDCCloudOperation*> *)addedOperations
{
	NSMutableArray<ZDCCloudOperation*> *results = [NSMutableArray arrayWithCapacity:2];
	
	[self enumerateAddedOperationsUsingBlock:
	^(YapDatabaseCloudCorePipeline *pipeline,
	  YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			[results addObject:(ZDCCloudOperation *)operation];
		}
	}];
	
	return results;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (BOOL)hasPendingDataUploadsForNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return NO;
	
	__block BOOL result = NO;
	
	[self _enumerateOperationsUsingBlock:^(YapDatabaseCloudCorePipeline *pipeline,
	                                       YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			if ([op.nodeID isEqualToString:nodeID])
			{
				if (op.isPutNodeDataOperation) {
					result = YES;
					*stop = YES;
				}
			}
		}
	}];
	
	return result;
}

/**
 * Method declared in ZDCCloudPrivate.h
 */
- (NSArray<NSDictionary*> *)pendingPermissionsChangesetsForNodeID:(NSString *)nodeID
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
				NSDictionary *changeset = op.changeset_permissions;
				if (changeset) {
					[changesets addObject:changeset];
				}
			}
		}
	}];
	
	return changesets;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
				NSDictionary *changeset = op.changeset_obj;
				if (changeset) {
					[changesets addObject:changeset];
				}
			}
		}
	}];
	
	return changesets;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
 */
- (void)didMergeDataWithETag:(NSString *)eTag forNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return;
	
	NSMutableArray<NSUUID*> *operationUUIDs = [NSMutableArray array];
	
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
			
			if ([op.nodeID isEqualToString:nodeID] && op.isPutNodeDataOperation)
			{
				[operationUUIDs addObject:op.uuid];
				
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
	
	YapDatabaseCloudCorePipeline *defaultPipeline = [self defaultPipeline];
	for (NSUUID *operationUUID in operationUUIDs)
	{
		[defaultPipeline setHoldDate: nil
		        forOperationWithUUID: operationUUID
		                     context: kZDCContext_Conflict];
	}
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudTransaction.html
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
	ZDCLogAutoTrace();
	
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
	ZDCLogAutoTrace();
	
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
	ZDCLogAutoTrace();
	
	// Proper API usage check
	if (![databaseTransaction isKindOfClass:[YapDatabaseReadWriteTransaction class]])
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	if (oldCloudLocator == nil) {
		ZDCLogWarn(@"%@ - Ignoring request: oldCloudLocator is nil", THIS_METHOD);
		return;
	}
	if (newCloudLocator == nil) {
		ZDCLogWarn(@"%@ - Ignoring request: newCloudLocator is nil", THIS_METHOD);
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
			NSAssert(op.dstNodeID != nil, @"dstNodeID is nil !");
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

- (void)willAddOperation:(YapDatabaseCloudCoreOperation *)operation
              inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
            withGraphIdx:(NSUInteger)opGraphIdx
{
	// An operation is being ADDED.
	//
	// So the given graphIdx will be the latest.
	//
	// - graphIdx  0 (FIRST)  : represents oldest commit that still has pending operations
	// - graphIdx  1 (MIDDLE) : represents a later commit with pending operations
	// - graphIdx 42 (LAST)   : represents the most recent commit with pending operations
	//
	// We need to add implicit dependencies so we can take advantage of FlatGraph optimizations.
	
	ZDCCloudOperation *newOp = (ZDCCloudOperation *)operation;
	
	[self _enumerateOperations: YDBCloudCore_EnumOps_All
	                inPipeline: pipeline
	                usingBlock: ^void (YapDatabaseCloudCoreOperation *oldOperation, NSUInteger graphIdx, BOOL *stop)
	{
		if (![oldOperation isKindOfClass:[ZDCCloudOperation class]]) {
			return; // from block; i.e. continue;
		}
		__unsafe_unretained ZDCCloudOperation *oldOp = (ZDCCloudOperation *)oldOperation;
			
		if (graphIdx < opGraphIdx)
		{
			// oldOp : from graphA (commit #X)
			// newOp : from graphB (commit #Y)
			//
			// where X < Y
			
			if ([self newOperation:newOp dependsOnOldOperation:oldOp])
			{
				[newOp addDependency:oldOperation];
			}
		}
		else if (graphIdx == opGraphIdx)
		{
			// oldOp : from graphB (commit #Y)
			// newOp : from graphB (commit #Y)
			//
			// We are being extra cautious here, and only injecting dependencies if:
			// - the newOp should depend on the oldOp
			// - the inverse dependency doesn't exist
			
			if ([self newOperation:newOp dependsOnOldOperation:oldOp])
			{
				NSSet<NSUUID*> *oldOpDependencies = [self recursiveDependenciesForOperation:oldOp];
				if (![oldOpDependencies containsObject:newOp.uuid])
				{
					[newOp addDependency:oldOp];
				}
			}
		}
		else
		{
			*stop = YES;
		}
	}];
}

/**
 * Subclass Hook
 */
- (void)willInsertOperation:(YapDatabaseCloudCoreOperation *)operation
                 inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
               withGraphIdx:(NSUInteger)opGraphIdx
{
	// An operation is being INSERTED.
	//
	// That is, an operation is being put into the graph as if it was added in a previous commit.
	// So the given graphIdx is NOT the latest.
	//
	// - graphIdx  0 (FIRST)  : represents oldest commit that still has pending operations
	// - graphIdx  1 (MIDDLE) : represents a later commit with pending operations
	// - graphIdx 42 (LAST)   : represents the most recent commit with pending operations
	//
	// Here's what we want to do:
	// - Enumerate all the operations that were added to the graph in commits BEFORE this modifiedOp's commit
	// - Check to see if the operation has been changed in such a way that it now depends on the oldOp
	// - If so, add the dependency
	
	__unsafe_unretained ZDCCloudOperation *newOp = (ZDCCloudOperation *)operation;
	
	[self _enumerateOperations: YDBCloudCore_EnumOps_All
	                inPipeline: pipeline
	                usingBlock:
	^void (YapDatabaseCloudCoreOperation *oldOperation, NSUInteger graphIdx, BOOL *stop)
	{
		__unsafe_unretained ZDCCloudOperation *oldOp = (ZDCCloudOperation *)oldOperation;
		
		if (graphIdx < opGraphIdx)
		{
			// oldOp : from graphA (commit #X)
			// newOp : from graphB (commit #Y)
			//
			// where X < Y
			
			if ([self newOperation:newOp dependsOnOldOperation:oldOp] &&
			    ![newOp.uuid isEqual:oldOp.uuid])
			{
				// Make sure we don't create a circulate dependency
				
				NSSet<NSUUID*> *oldOpDependencies = [self recursiveDependenciesForOperation:oldOp];
				if (![oldOpDependencies containsObject:newOp.uuid])
				{
					[newOp addDependency:oldOp];
				}
			}
		}
		else
		{
			*stop = YES;
		}
	}];
}

/**
 * Subclass Hook
 */
- (void)didInsertOperation:(YapDatabaseCloudCoreOperation *)operation
                inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
              withGraphIdx:(NSUInteger)opGraphIdx
{
	// An existing operation was INSERTED.
	//
	// Here's what we want to do:
	// - Enumerate all the operations that are in LATER graph index's
	// - Check to see if the later operation should now depend on the modifiedOp
	// - If so, add the dependency
	
	__unsafe_unretained ZDCCloudOperation *oldOp = (ZDCCloudOperation *)operation;
	__block NSMutableArray<ZDCCloudOperation*> *modifiedLaterOps = nil;
	
	[self _enumerateOperations: YDBCloudCore_EnumOps_All
	                inPipeline: pipeline
	                usingBlock:
	^void (YapDatabaseCloudCoreOperation *newOperation, NSUInteger graphIdx, BOOL *stop)
	{
		if (graphIdx > opGraphIdx)
		{
			// oldOp : from graphA (commit #X)
			// newOp : from graphB (commit #Y)
			//
			// where X < Y
			
			__strong ZDCCloudOperation *newOp = (ZDCCloudOperation *)newOperation;
			
			if ([self newOperation:newOp dependsOnOldOperation:oldOp] &&
			    ![newOp.uuid isEqual:oldOp.uuid])
			{
				// Make sure we don't create a circulate dependency
				
				NSSet<NSUUID*> *oldOpDependencies = [self recursiveDependenciesForOperation:oldOp];
				if (![oldOpDependencies containsObject:newOp.uuid])
				{
					newOp = [newOp copy];
					[newOp addDependency:oldOp];
				
					if (modifiedLaterOps == nil) {
						modifiedLaterOps = [NSMutableArray array];
					}
					[modifiedLaterOps addObject:newOp];
				}
			}
		}
	}];
	
	for (ZDCCloudOperation *modifiedOp in modifiedLaterOps)
	{
		[self modifyOperation:modifiedOp];
	}
}

/**
 * Subclass Hook
 */
- (void)willModifyOperation:(YapDatabaseCloudCoreOperation *)operation
                 inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
               withGraphIdx:(NSUInteger)opGraphIdx
{
	// An existing operation is being MODIFIED.
	//
	// That is, an operation that was added in a previous commit is now being modified.
	// So the given graphIdx is NOT the latest.
	//
	// - graphIdx  0 (FIRST)  : represents oldest commit that still has pending operations
	// - graphIdx  1 (MIDDLE) : represents a later commit with pending operations
	// - graphIdx 42 (LAST)   : represents the most recent commit with pending operations
	//
	// Here's what we want to do:
	// - Enumerate all the operations that were added to the graph in commits BEFORE this modifiedOp's commit
	// - Check to see if the operation has been changed in such a way that it now depends on the oldOp
	// - If so, add the dependency
	
	__unsafe_unretained ZDCCloudOperation *newOp = (ZDCCloudOperation *)operation;
	
	[self _enumerateOperations: YDBCloudCore_EnumOps_All
	                inPipeline: pipeline
	                usingBlock:
	^void (YapDatabaseCloudCoreOperation *oldOperation, NSUInteger graphIdx, BOOL *stop)
	{
		__unsafe_unretained ZDCCloudOperation *oldOp = (ZDCCloudOperation *)oldOperation;
		
		if (graphIdx < opGraphIdx)
		{
			// oldOp : from graphA (commit #X)
			// newOp : from graphB (commit #Y)
			//
			// where X < Y
			
			if ([self newOperation:newOp dependsOnOldOperation:oldOp] &&
			    ![newOp.uuid isEqual:oldOp.uuid])
			{
				// Make sure we don't create a circulate dependency
				
				NSSet<NSUUID*> *oldOpDependencies = [self recursiveDependenciesForOperation:oldOp];
				if (![oldOpDependencies containsObject:newOp.uuid])
				{
					[newOp addDependency:oldOp];
				}
			}
		}
		else
		{
			*stop = YES;
		}
	}];
}

/**
 * Subclass Hook
 */
- (void)didModifyOperation:(YapDatabaseCloudCoreOperation *)operation
                 inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
               withGraphIdx:(NSUInteger)opGraphIdx
{
	// An existing operation was MODIFIED.
	//
	// Here's what we want to do:
	// - Enumerate all the operations that are in LATER graph index's
	// - Check to see if the later operation should now depend on the modifiedOp
	// - If so, add the dependency
	
	__unsafe_unretained ZDCCloudOperation *oldOp = (ZDCCloudOperation *)operation;
	__block NSMutableArray<ZDCCloudOperation*> *modifiedLaterOps = nil;
	
	[self _enumerateOperations: YDBCloudCore_EnumOps_All
	                inPipeline: pipeline
	                usingBlock:
	^void (YapDatabaseCloudCoreOperation *newOperation, NSUInteger graphIdx, BOOL *stop)
	{
		if (graphIdx > opGraphIdx)
		{
			// oldOp : from graphA (commit #X)
			// newOp : from graphB (commit #Y)
			//
			// where X < Y
			
			__strong ZDCCloudOperation *newOp = (ZDCCloudOperation *)newOperation;
			
			if ([self newOperation:newOp dependsOnOldOperation:oldOp] &&
			    ![newOp.uuid isEqual:oldOp.uuid])
			{
				// Make sure we don't create a circulate dependency
				
				NSSet<NSUUID*> *oldOpDependencies = [self recursiveDependenciesForOperation:oldOp];
				if (![oldOpDependencies containsObject:newOp.uuid])
				{
					newOp = [newOp copy];
					[newOp addDependency:oldOp];
				
					if (modifiedLaterOps == nil) {
						modifiedLaterOps = [NSMutableArray array];
					}
					[modifiedLaterOps addObject:newOp];
				}
			}
		}
	}];
	
	for (ZDCCloudOperation *modifiedOp in modifiedLaterOps)
	{
		[self modifyOperation:modifiedOp];
	}
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
//	ZDCLogCookie(@"Did COMPLETE operation: %@", operation.uuid);
}

- (void)didSkipOperation:(YapDatabaseCloudCoreOperation *)operation
{
//	ZDCLogCookie(@"Did SKIP operation: %@", operation.uuid);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	ZDCLogAutoTrace();
	
	[super didInsertObject:object forCollectionKey:collectionKey withMetadata:metadata rowid:rowid];
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
	ZDCLogAutoTrace();
	
	[super didUpdateObject:object forCollectionKey:collectionKey withMetadata:metadata rowid:rowid];
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
	ZDCLogAutoTrace();
	
	[super didReplaceObject:object forCollectionKey:collectionKey withRowid:rowid];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction
 * - removeObjectForKey:inCollection:
 */
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	[super didRemoveObjectForCollectionKey:ck withRowid:rowid];
	
	ZDCNode *linkedNode = [self _linkedNodeForRowid:rowid];
	if (linkedNode)
	{
		[self deleteNode:linkedNode error:nil];
	}
	
	if ([ck.collection isEqualToString:kZDCCollection_Nodes])
	{
		NSString *nodeID = ck.key;
		NSString *internalKey = [self internalTaggingKeyForNodeID:nodeID];
		
		[self removeAllTagsForKey:nodeID];
		[self removeAllTagsForKey:internalKey];
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
- (void)didRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	[super didRemoveObjectsForKeys:keys inCollection:collection withRowids:rowids];
	
	for (NSNumber *num in rowids)
	{
		int64_t rowid = [num longLongValue];
		
		ZDCNode *linkedNode = [self _linkedNodeForRowid:rowid];
		if (linkedNode)
		{
			[self deleteNode:linkedNode error:nil];
		}
	}
	
	if ([collection isEqualToString:kZDCCollection_Nodes])
	{
		for (NSString *nodeID in keys)
		{
			NSString *internalKey = [self internalTaggingKeyForNodeID:nodeID];
			
			[self removeAllTagsForKey:nodeID];
			[self removeAllTagsForKey:internalKey];
		}
	}
}

@end
