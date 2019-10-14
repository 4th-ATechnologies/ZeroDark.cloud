/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseCloudCore.h>

#import "ZDCCloudConnection.h"
#import "ZDCCloudTransaction.h"
#import "ZDCCloudOperation.h"
#import "ZDCCloudLocator.h"
#import "ZDCCloudRcrd.h"

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
 *
 * When using the ZeroDarkCloud framework, you'll often be interacting with `ZDCCloudTransaction`.
 */
@interface ZDCCloud : YapDatabaseCloudCore

/** The localUserID provided during init */
@property (nonatomic, copy, readonly) NSString *localUserID;

/** The treeID provided during init */
@property (nonatomic, copy, readonly) NSString *treeID;

@end
