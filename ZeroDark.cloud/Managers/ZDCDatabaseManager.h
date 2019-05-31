/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseActionManager.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseCloudCore.h>
#import <YapDatabase/YapDatabaseConnectionProxy.h>
#import <YapDatabase/YapDatabaseConnectionPool.h>
#import <YapDatabase/YapDatabaseFullTextSearch.h>
#import <YapDatabase/YapDatabaseFilteredView.h>
#import <YapDatabase/YapDatabaseHooks.h>
#import <YapDatabase/YapDatabaseRelationship.h>
#import <YapDatabase/YapDatabaseSearchResultsView.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>
#import <YapDatabase/YapDatabaseView.h>

#import "ZDCCloud.h"
#import "ZDCCloudNode.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The following notifications are automatically posted for the uiDatabaseConnection:
 *
 * - UIDatabaseConnectionWillUpdateNotification
 * - UIDatabaseConnectionDidUpdateNotification
 *
 * The notifications correspond with the longLivedReadTransaction of the uiDatabaseConnection.
 * The DatabaseManager class listens for YapDatabaseModifiedNotification's.
 *
 * The UIDatabaseConnectionWillUpdateNotification is posted immediately before the uiDatabaseConnection
 * is moved to the latest commit. And the UIDatabaseConnectionDidUpdateNotification is posted immediately after
 * the uiDatabaseConnection was moved to the latest commit.
 *
 * These notifications are always posted to the main thread.
 */
extern NSString *const UIDatabaseConnectionWillUpdateNotification;

/**
 * The following notifications are automatically posted for the uiDatabaseConnection:
 *
 * - UIDatabaseConnectionWillUpdateNotification
 * - UIDatabaseConnectionDidUpdateNotification
 *
 * The notifications correspond with the longLivedReadTransaction of the uiDatabaseConnection.
 * The DatabaseManager class listens for YapDatabaseModifiedNotification's.
 *
 * The UIDatabaseConnectionWillUpdateNotification is posted immediately before the uiDatabaseConnection
 * is moved to the latest commit. And the UIDatabaseConnectionDidUpdateNotification is posted immediately after
 * the uiDatabaseConnection was moved to the latest commit.
 *
 * These notifications are always posted to the main thread.
 *
 * The UIDatabaseConnectionDidUpdateNotification will always contain a userInfo dictionary with:
 *
 * - kNotificationsKey
 *     Contains the NSArray returned by [uiDatabaseConnection beginLongLivedReadTransaction].
 *     That is, the array of commit info from each commit the connection jumped.
 *     This is the information that is fed into the various YapDatabase API's to figure out what changed.
 */
extern NSString *const UIDatabaseConnectionDidUpdateNotification;

/**
 * Used by UIDatabaseConnectionDidUpdateNotification.userInfo.
 * Contains the NSArray returned by [uiDatabaseConnection beginLongLivedReadTransaction]
 */
extern NSString *const kNotificationsKey;

/**
 * YapDatabase extension of type: YapDatabaseRelationship <br/>
 * Access via: [transaction ext:Ext_Relationship]
 *
 * Used by the framework to link various objects together such that
 * deleting object A will automatically delete object B.
 */
extern NSString *const Ext_Relationship;

/**
 * YapDatabase extension of type: YapDatabaseSecondaryIndex <br/>
 * Access via: [transaction ext:Ext_Index_Nodes]
 *
 * Indexes ZDCNode's by properties 'cloudID' & 'dirPrefix' for quick lookup.
 */
extern NSString *const Ext_Index_Nodes;

/**
 * YapDatabase extension of type: YapDatabaseSecondaryIndex <br/>
 * Access via: [transaction ext:Ext_Index_Nodes]
 *
 * Indexes ZDCUser's by property 'random_uuid' for quick lookup.
 */
extern NSString *const Ext_Index_Users;


/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_SplitKeys]
 *
 * Organizes ZDCSplitKey for convenience & quick enumeration.
 *
  */
extern NSString *const Ext_View_SplitKeys;
extern NSString *const Ext_View_SplitKeys_Date;

/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_LocalUsers]
 *
 * Organizes ZDCLocalUser's for convenience & quick enumeration.
 *
 * @note There are related tools available via the `ZDCLocalUserManager` class.
 */
extern NSString *const Ext_View_LocalUsers;

/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_Filesystem_Name]
 *
 * Organizes ZDCNode's into a hierarchial view, grouped by parentID & sorted by name.
 */
extern NSString *const Ext_View_Filesystem_Name;

/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_Filesystem_CloudName]
 *
 * Organizes ZDCNode's into a hierarchial view, grouped by parentID & sorted by cloudName.
 */
extern NSString *const Ext_View_Filesystem_CloudName;

/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_Flat]
 *
 * Organizes ZDCNode's into a "flat" view, grouped by {localUserID/zAppID} tuple & sorted by uuid.
 */
extern NSString *const Ext_View_Flat;

/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_Cloud_DirPrefix]
 *
 * Organizes ZDCCloudNode's into a hierarchial view, grouped by dirPrefix & sorted by cloudName.
 */
extern NSString *const Ext_View_Cloud_DirPrefix;

/**
 * YapDatabase extension of type: YapDatabaseAutoView <br/>
 * Access via: [transaction ext:Ext_View_Cloud_Flat]
 *
 * Organizes ZDCCloudNode's into a flat view, grouped by {localUserID/zAppID} tuple & sorted by uuid.
 */
extern NSString *const Ext_View_Cloud_Flat;

/**
 * The prefix used to register YapDatabase extensions of type: ZDCCloud
 */
extern NSString *const Ext_CloudCore_Prefix;

/** Secondary Index column name for: `Ext_Index_Nodes` */
extern NSString *const Index_Nodes_Column_CloudID;

/** Secondary Index column name for: `Ext_Index_Nodes` */
extern NSString *const Index_Nodes_Column_DirPrefix;

/** Secondary Index column name for: `Ext_Index_Users` */
extern NSString *const Index_Users_Column_RandomUUID;

/**
 * ZeroDarkCloud requires a database for atomic operations.
 * YapDatabase is used as it's the most performant and highly-concurrent.
 *
 * If you're curious about YapDatabase, you can find the project page
 * [here](https://github.com/yapstudios/YapDatabase). The extensive documentation
 * is on the [wiki](https://github.com/yapstudios/YapDatabase/wiki).
 *
 * This class provides access to the YapDatabase instance & various
 * connections/extensions being used by the framework.
 * You're encouraged (but not required) to store your objects in the same YapDatabase instance,
 * as doing so allows you to participate in the same atomic transactions being used by the framework.
 */
@interface ZDCDatabaseManager : NSObject

/**
 * The root YapDatabase instance.
 * Most of the time you'll want a database connection instead.
 */
@property (nonatomic, strong, readonly) YapDatabase *database;

/**
 * The UI connection is read-only, and is reserved for use EXCLUSIVELY on the MAIN THREAD.
 *
 * This follows the recommended best-practices for YapDatabase:
 * https://github.com/yapstudios/YapDatabase/wiki/Performance-Pro
 *
 * Only use this connection for performing synchronous reads on the main thread.
 * All other uses violate the recommended best-practices outlined in the wiki,
 * and will throw an exception in DEBUG builds (to help you learn the rules).
 * 
 * @warning Attempting to access this property outside the main thread will throw an exception.
 */
@property (nonatomic, strong, readonly) YapDatabaseConnection *uiDatabaseConnection;

/**
 * A read-only connection pool.
 * Most of the time you'll want the roDatabaseConnection property (which uses this connection pool).
 */
@property (nonatomic, strong, readonly) YapDatabaseConnectionPool *roConnectionPool;

/**
 * Read-only connection(s) are automatically vended from the roConnectionPool.
 * With this connection you can perform a read-only sync/async transaction.
 *
 * @note When performing a synchronous read-only connection on the main-thread,
 *       you're encouraged to use the uiDatabaseConnection.
 */
@property (nonatomic, strong, readonly) YapDatabaseConnection *roDatabaseConnection; // read-only

/**
 * Read-write connection is reserved for write transactions.
 * This may be used from ANY THREAD.
 *
 * Note:
 *   For performance reasons, you'll want to avoid performing a synchronous write from the main thread,
 *   as that would risk stalling your user interface.
 */
@property (nonatomic, strong, readonly) YapDatabaseConnection *rwDatabaseConnection; // read-write

/**
 * Uses the roDatabaseConnection & rwDatabaseConnection.
 */
@property (nonatomic, strong, readonly) YapDatabaseConnectionProxy *databaseConnectionProxy;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For use within:
 * - Ext_View_Flat
 */
+ (NSString *)groupForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;

/**
 * For use within:
 * - Ext_View_Cloud_DirPrefix
 */
+ (NSString *)groupForLocalUserID:(NSString *)localUserID
                           region:(AWSRegion)region
                           bucket:(NSString *)bucket
                        appPrefix:(NSString *)appPrefix
                        dirPrefix:(NSString *)dirPrefix;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the registered name of the ZDCCloud extension for the given localUserID.
 * This is typically used to access the ZDCCloudTransaction.
 * For example:
 *
 * [zdc.rwDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *
 *    NSString *extName = [zdc.databaseManager cloudExtNameForUser:localUserID app:MyAppID];
 *    ZDCCloudTransaction *ext = [transaction ext:extName];
 *
 *    // ... do something with ext ...
 * }];
 */
- (NSString *)cloudExtNameForUser:(NSString *)localUserID;

/**
 * Returns the registered name of the ZDCCloud extension for the given <localUserID, zAppID> tuple.
 * This is typically used to access the ZDCCloudTransaction.
 * For example:
 *
 * [zdc.rwDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *
 *    NSString *extName = [zdc.databaseManager cloudExtNameForUser:localUserID app:MyAppID];
 *    ZDCCloudTransaction *ext = [transaction ext:extName];
 *
 *    // ... do something with ext ...
 * }];
 */
- (NSString *)cloudExtNameForUser:(NSString *)localUserID app:(NSString *)appID;

/**
 * Returns all registered ZDCCloud instances for the given account.
 */
- (NSArray<ZDCCloud *> *)cloudExtsForUser:(NSString *)localUserID;

/**
 * Returns the registered ZDCCloud instance for the given account.
 *
 * This method invokes `-cloudExtForUser:app:` and passes the default zAppID (ZeroDarkCloud.zAppID).
 */
- (nullable ZDCCloud *)cloudExtForUser:(NSString *)localUserID;

/**
 * Returns the registered ZDCCloud instance for the given account.
 */
- (nullable ZDCCloud *)cloudExtForUser:(NSString *)localUserID app:(NSString *)appID;

/**
 * A separate ZDCCloud instance is registered for every account.
 *
 * When the database is unlocked, ZDCCloudCore instances are automatically
 * registered for all pre-existing accounts in the database.
 * During runtime, ZDCCloud instances are created for you when you activate an appID for a localUser.
 */
- (ZDCCloud *)registerCloudExtensionForUser:(NSString *)localUserID app:(NSString *)appID;

/**
 * A separate ZDCCloud instance MUST be registered for every account.
 * If an account is deleted (not suspended) during runtime, then this method MUST be invoked to delete the instance.
 */
- (void)unregisterCloudExtensionForUser:(NSString *)localUserID app:(NSString *)appID;

@end

NS_ASSUME_NONNULL_END
