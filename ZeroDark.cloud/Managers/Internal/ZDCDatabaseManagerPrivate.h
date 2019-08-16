/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCDatabaseManager.h"
#import "ZeroDarkCloud.h"

@interface ZDCDatabaseManager (Private)

/**
 * Standard init method for framework.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Attempts to create the YapDatabase instance using the given encrytionKey.
 * Returns NO if it fails.
 */
- (BOOL)setupDatabase:(ZDCDatabaseConfig *)config;

/**
 * Some internal API's need to perform a synchronous database read.
 * However, it's dangerous to do this using a database connection that might be in use by the user,
 * because it could lead to a deadlock situation.
 * Thus we have an internal databaseConnection that we can confidently use.
 */
- (YapDatabaseConnection *)internal_roConnection;

/**
 * The PushManager & PullManager have the potential to queue up a LOT of readWrite transactions.
 * If these classes use the same rwConnection that the user is using,
 * it can cause the database to appear slow.
 *
 * By queueing our own (internal) read-write transactions into a separate connection,
 * we ensure we aren't starving the user's own transactions.
 */
- (YapDatabaseConnection *)internal_rwConnection;

/**
 * The PushManager & PullManager need to perform various decryption routines within a transaction.
 * But the decryption routines are (comparatively) slow.
 * So we use a dedicated connection to ensure they don't slow down the rest of the system.
 */
- (YapDatabaseConnection *)internal_decryptConnection;

/**
 * The list of {localUserID, zAppID} tuples that currently have a ZDCCloud extension registered.
 */
- (NSArray<YapCollectionKey *> *)currentlyRegisteredTuples;

/**
 * The list of zAppIDs (for the given user) that currently have a ZDCCloud extension.
 */
- (NSArray<NSString *> *)currentlyRegisteredAppIDsForUser:(NSString *)localUserID;

/**
 * The list of {localUserID, zAppID} tuples that had a ZDCCloud extension re-registered during database setup.
 */
- (NSArray<YapCollectionKey *> *)previouslyRegisteredTuples;

/**
 * The list of localUserIDs that had a ZDCCloud extension re-registered during database setup.
 */
- (NSSet<NSString *> *)previouslyRegisteredLocalUserIDs;

/**
 * The list of appIDs (for the given user) that had a ZDCCloud extension re-registered during database setup.
 */
- (NSArray<NSString *> *)previouslyRegisteredAppIDsForUser:(NSString *)localUserID;

@end
