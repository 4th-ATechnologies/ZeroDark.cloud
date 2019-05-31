/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseCloudCoreConnection.h>

@class ZDCCloud;

/**
 * ZDCCloud is a YapDatabase extension.
 *
 * It manages the storage of the upload queue.
 * This allows your application to work offline.
 * Any changes that need to be pushed to the cloud will get stored in the database using
 * a lightweight operation object that encodes the minimum information necessary
 * to execute the operation at a later time.
 * 
 * It extends YapDatabaseCloudCore, which we also developed,
 * and contributed to the open source community.
 */
@interface ZDCCloudConnection : YapDatabaseCloudCoreConnection

/** Returns the parent instance */
@property (nonatomic, strong, readonly) ZDCCloud *cloud;

@end
