/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "YapDatabaseCloudCorePipelineDelegate.h"
@class ZDCCloudOperation;

/**
 * The PushManager handles pushing changes up to the cloud.
 *
 * The sync process can be broken down into 2 components: Push & Pull.
 * If you've used git before, you're already familiar with the process.
 * You push changes (made locally) to the cloud. And you pull changes (made on remote devices) from the cloud.
 *
 * This class handles the PUSH side of things.
 */
@interface ZDCPushManager : NSObject <YapDatabaseCloudCorePipelineDelegate>

/**
 * Stops all in-flight uploads for the given {localUserID, zAppID} tuple.
 *
 * The active uploads are cancelled, but they're not removed from the push queue.
 * That is, the active network tasks that are pushing data up to the cloud are stopped.
 * But the corresponding ZDCCloudOperation's are still stored in the database,
 * so they will be restarted the next time the PushManager starts executing operations.
 *
 * To be useful, this method is usually paired with a corresponding call to pause the push queue.
 *
 * You're encouraged to use the SyncManager instead of calling this method directly.
 * @see `[ZDCSyncManager pausePushForLocalUserID:andAbortUploads:]`
 */
- (void)abortOperationsForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;

/**
 * Stops in-flight uploads for the given list of operations.
 *
 * The active uploads are cancelled, but they're not removed from the push queue.
 * That is, the active network tasks that are pushing data up to the cloud are stopped.
 * But the corresponding ZDCCloudOperation's are still stored in the database,
 * so they will be restarted the next time the PushManager starts executing operations.
 */
- (void)abortOperations:(NSArray<ZDCCloudOperation *> *)operations;

@end
