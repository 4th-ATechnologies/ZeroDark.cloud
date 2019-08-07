/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworkReachabilityManager.h>

#import "ZeroDarkCloudUmbrella.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * This class is the primary interface for interacting with the ZeroDark.cloud framework.
 */
@interface ZeroDarkCloud : NSObject

/**
 * Initializes an instance for use within your app.
 *
 * Typically you only need a single instance per app.
 * Once instance is capable of supporting multiple users, and even multiple zAppIDs.
 *
 * The databaseName is used to create an instance of [YapDatabase](https://github.com/yapstudios/YapDatabase).
 * ZeroDarkCloud needs a database for a ton of different things.
 * You're welcome to use the same YapDatabase instance to store your own objects. (YapDatabase is awesome.)
 * If you do, the ZeroDarkCloudDelegate protocol provides hooks you can use during
 * YapDatabase initialization to register your own app-specific database extensions (views, indexes, etc).
 *
 * @param delegate
 *   A delegate is required to support push & pull operations.
 *
 * @param databaseName
 *   The filename to use for the database file. For example: "database.sqlite".
 *   The database will not be touched until you call `unlockOrCreateDatabaseWithKey:`.
 *
 * @param zAppID
 *   The primary ZeroDark.cloud zAppID for this application.
 *   This is the name you registered within the ZeroDark.cloud developer dashboard.
 *   It's usually something along the lines of "com.YourCompany.YourAppName".
 */
- (instancetype)initWithDelegate:(id<ZeroDarkCloudDelegate>)delegate
                    databaseName:(NSString *)databaseName
                          zAppID:(NSString *)zAppID;

/**
 * Initializes an instance for use within your app.
 *
 * Typically, you only need a single instance per app.
 * Once instance is capable of supporting multiple users, and even multiple zAppIDs.
 *
 * The databasePath is used to create an instance of [YapDatabase](https://github.com/yapstudios/YapDatabase).
 * ZeroDarkCloud needs a database for a ton of different things.
 * You're welcome to use the same YapDatabase instance to store your own objects. (YapDatabase is awesome.)
 * If you do, the ZeroDarkCloudDelegate protocol provides hooks you can use during
 * YapDatabase initialization to register your own app-specific database extensions (views, indexes, etc).
 *
 * @note You can only create a single ZeroDarkCloud instance per database filename.
 *
 * @param delegate
 *   A delegate is required to support push & pull operations.
 *
 * @param databasePath
 *   The full path to the database file, including the database name.
 *   The database will not be touched until you call `unlockOrCreateDatabaseWithKey:`.
 *
 * @param zAppID
 *   The primary ZeroDark.cloud zAppID for this application.
 *   This is the name you registered within the ZeroDark.cloud developer dashboard.
 *   It's usually something along the lines of "com.YourCompany.YourAppName".
 */
- (instancetype)initWithDelegate:(id<ZeroDarkCloudDelegate>)delegate
                    databasePath:(NSURL *)databasePath
                          zAppID:(NSString *)zAppID;

/** The delegate specified during initialization */
@property (nonatomic, strong, readwrite) id<ZeroDarkCloudDelegate> delegate;

/**
 * The databasePath specified during initialization.
 * This information was used to create a YapDatabase instance.
 * More information about the database can be found via the `databaseManager` property.
 */
@property (nonatomic, strong, readonly) NSURL *databasePath;

/**
 * The primary ZeroDark.cloud zAppID for this application.
 * This is the name you registered within the ZeroDark.cloud developer dashboard.
 * It's usually something along the lines of "com.YourCompany.YourAppName".
 */
@property (nonatomic, copy, readonly) NSString *zAppID;

/**
 * A reference to AFNetworkReachabilityManager.sharedManager.
 *
 * The framework automatically calls startMonitoring on this instance,
 * as it needs internet reachability & notifications of reachability changes.
 */
@property (nonatomic, strong, readonly) AFNetworkReachabilityManager *reachability;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Framework Unlock
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The ZeroDarkCloud framework stores data on the local device in a database.
 * For security purposes, it requires this database to be encrypted.
 * This is accomplished using a local sqlite database which is encrypted using SQLCipher.
 * In order to start using the framework, this database file must first be unlocked (or created).
 * This property returns whether or not the database file has been unlocked yet (or created).
 *
 * Note:
 *   The framework comes with a suite a tools for securely storing/retrieving a database key.
 *   For example, adding TouchID only takes a few lines of code.
 *
 * @see DatabaseKeyManager
 */
@property (atomic, readonly) BOOL isDatabaseUnlocked;

/**
 * Attempts to unlock the database file using the given key.
 * If the key matches, the unlock will succeed.
 *
 * @see DatabaseKeyManager
 *
 * @return On success, returns nil. Otherwise returns an error that describes what went wrong.
 */
- (nullable NSError *)unlockOrCreateDatabase:(ZDCDatabaseConfig *)config;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Managers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task. */
@property (nonatomic, readonly) ZDCCloudPathManager * cloudPathManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task. */
@property (nonatomic, readonly) ZDCDatabaseKeyManager * databaseKeyManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task. */
@property (nonatomic, readonly) ZDCDirectoryManager * directoryManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task. */
@property (nonatomic, readonly) ZDCNodeManager * nodeManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task. */
@property (nonatomic, readonly) ZDCProgressManager * progressManager;


/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCDatabaseManager * databaseManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCDiskManager * diskManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCDownloadManager * downloadManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCImageManager * imageManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCLocalUserManager * localUserManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCPullManager * pullManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCPushManager * pushManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCRemoteUserManager * remoteUserManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCRestManager * restManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCSearchUserManager * searchManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCSyncManager * syncManager;

/** The functionality of ZeroDarkCloud is split into multiple managers, separated by task.
    Once the database is unlocked, this returns non-nil. */
@property (nonatomic, readonly, nullable) ZDCUITools * uiTools;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Convenient way to get a reference to the ZDCCloudTransaction for the given localUserID.
 *
 * @note localUserID == ZDCLocalUser.uuid
 */
- (nullable ZDCCloudTransaction *)cloudTransaction:(YapDatabaseReadTransaction *)transaction
                                    forLocalUserID:(NSString *)localUserID;

/**
 * Convenient way to get a reference to the ZDCCloudTransaction for the given {localUserID, zAppID} tuple.
 *
 * @note localUserID == ZDCLocalUser.uuid
 */
- (nullable ZDCCloudTransaction *)cloudTransaction:(YapDatabaseReadTransaction *)transaction
                                    forLocalUserID:(NSString *)localUserID
                                            zAppID:(nullable NSString *)zAppID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The (parsed) pushToken that gets registered with the server.
 *
 * @see didRegisterForRemoteNotificationsWithDeviceToken:
 */
@property (atomic, strong, readonly, nullable) NSString *pushToken;

/**
 * The ZeroDark.cloud framework relies on push notifications for real-time updates.
 * After registering for push notifications with the OS,
 * invoke this method to inform the framework of the device's push token.
 *
 * The framework will automatically register the push token with the server
 * for all ZDCLocalUser's in the database.
 */
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

#if TARGET_OS_IOS
/**
 * (iOS Version)
 *
 * When you receive a push notification, forward it to the ZeroDarkCloud framework using this method.
 * If the notification is from the ZeroDark servers,
 * this method will kick off the process of handling the notification, and return YES.
 * When the notification has been fully handled, the framework will invoke the completionHandler automatically.
 *
 * If the notification isn't from the ZeroDark servers, this method returns NO.
 * Which means the notification (and invoking the completionHandler) is your responsibility.
 *
 * @param userInfo
 *   The notification you received via the AppDelegate method.
 *
 * @param completionHandler
 *   The completionHandler you received via the AppDelegate method.
 *
 * @return YES if the ZDC framework will handle the notification & completionHandler.
 *         NO if the notification isn't from the ZeroDark servers.
 */
- (BOOL)didReceiveRemoteNotification:(NSDictionary *)userInfo
              fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;
#else
/**
 * When you receive a push notification, forward it to the ZeroDarkCloud framework using this method.
 *
 * (macOS version)
 *
 * If the notification is from the ZeroDark servers,
 * this method will kick off the process of handling the notification, and then return YES.
 * When the notification has been fully handled, the framework will invoke the completionHandler automatically.
 *
 * If the notification isn't from the ZeroDark servers, this method returns NO.
 * Which means the notification is your responsibility.
 *
 * @param userInfo
 *   The notification you received via the AppDelegate method.
 *
 * @return YES if the ZDC framework will handle the notification & completionHandler.
 *         NO if the notification isn't from the ZeroDark servers.
 */
- (BOOL)didReceiveRemoteNotification:(NSDictionary *)userInfo;
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Background Networking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IOS

/**
 * When your AppDelegate receives this notification, forward it to the ZeroDarkCloud framework using this method.
 *
 * If the session is managed by the ZDC framework,
 * this method will kick off the process of handling the event(s), and then return YES.
 * When the notification has been fully handled, the framework will invoke the completionHandler automatically.
 *
 * If the session isn't managed by the ZDC framework, this method returns NO.
 * Which means the events are your responsibility.
 *
 * @param sessionIdentifier
 *   The session identifier, as delivered to your AppDelegate.
 *
 * @param completionHandler
 *   The completionHandler, as delivered to your AppDelegate.
 *
 * @return YES if the ZDC framework will handle the event(s) & completionHandler.
 *         NO if the session isn't maanaged by the ZDC framework.
 */
- (BOOL)handleEventsForBackgroundURLSession:(NSString *)sessionIdentifier
                          completionHandler:(void (^)(void))completionHandler;
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Utility method to returns the bundle for the ZeroDarkCloud framework.
 */
+ (NSBundle *)frameworkBundle;

@end

NS_ASSUME_NONNULL_END
