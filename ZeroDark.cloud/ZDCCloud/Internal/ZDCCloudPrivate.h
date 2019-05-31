/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseExtensionPrivate.h>
#import <YapDatabase/YapDatabaseCloudCorePrivate.h>

#import "ZDCCloud.h"
#import "ZDCCloudConnection.h"
#import "ZDCCloudTypes.h"
#import "ZDCCloudTransaction.h"

#import "ZDCCloudOperation.h"
#import "ZDCCloudOperationPrivate.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCCloudHandler () {
@public
	
	ZDCCloudHandlerBlock   block;
	YapDatabaseBlockType   blockType;
	YapDatabaseBlockInvoke blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCCloud () {
@public
	
	ZDCCloudHandler *handler;
}

/**
 * ZDCCloud instances are automatically created for you by the framework.
 *
 * @param localUserID
 *   The localUserID that will be used as the sender by all stored push operations.
 *
 * @param zAppID
 *   The zAppID from which the stored push operations were created.
 *   Cross application operations are allowed.
 *
 * @param handler
 *   A block that gets plugged into the database,
 *   and executed in response to database events (such as objects being added, modified, deleted, etc).
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             zAppID:(NSString *)zAppID
                            handler:(ZDCCloudHandler *)handler;

/** The handler provided during init */
@property (nonatomic, strong, readonly) ZDCCloudHandler *handler;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCCloudConnection () {
@public
	
	NSMutableArray *operations_block;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCCloudTransaction ()

/**
 * Checks the queue to see if there's a queued delete operation for this cloudID.
 */
- (BOOL)isCloudIDPendingDeletion:(NSString *)cloudID;

/**
 * If there are queued move operations for the given nodeID,
 * then the current cloudPath on the server may differ from our local value.
 *
 * This method analyzes queued move operations, to see if perhaps the server's value differs because
 * our queued move operations haven't been executed yet.
 */
- (NSArray<ZDCCloudPath *> *)potentialCloudPathsForNodeID:(NSString *)nodeID;

/**
 * Use this method when:
 * - a file/directory is moved/renamed during a pull
 *
 * In this case, any queued local moves conflict with the remote move,
 * and the remote move wins. Thus we should skip our local operation(s).
 */
- (void)skipMoveOperationsForNodeID:(NSString *)nodeID excluding:(NSUUID *)operationUUID;

/**
 * Handles all the following:
 *
 * - Skipping queued put operations
 * - Aborting multipart put operations
 * - Cancelling in-progress put tasks
 */
- (void)skipPutOperations:(NSSet<NSUUID *> *)opUUIDs;

/**
 * Use this method when:
 * - a file/directory is renamed during a push
 * - a file/directory is moved/renamed during a pull
 *
 * This method migrates all matching queued operations to the new cloudLocator.
 *
 * if ([operation.cloudLocator isEqualToCloudLocator:oldCloudLocator]) => change to newCloudLocator
 */
- (void)moveCloudLocator:(ZDCCloudLocator *)oldCloudLocator
			 toCloudLocator:(ZDCCloudLocator *)newCloudLocator;

/* Todo ?

- (void)changeCleartextName:(NSString *)oldCleartextName
                         to:(NSString *)newCleartextName
                  forNodeID:(NSString *)nodeID;

- (void)migrateOperationsForNodeID:(NSString *)nodeID
                  fromCloudLocator:(ZDCCloudLocator *)oldCloudLocator
                 cleartextNodeName:(NSString *)oldCleartextNodeName
                    toCloudLocator:(ZDCCloudLocator *)newCloudLocator
                 cleartextNodeName:(NSString *)newCleartextNodeName;
*/

@end
