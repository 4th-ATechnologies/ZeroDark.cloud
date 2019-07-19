/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseConnectionProxy.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This notification is posted (to the main thread) whenever a preference is changed.
 * The notification.userInfo["key"] will give you the key/name of the changed pref.
 */
extern NSString *const ZDCLocalPreferencesChangedNotification;

/**
 * Used in ZDCLocalPreferencesChangedNotification.userInfo. E.g.:
 * ```
 * NSString *changedKey = notification.userInfo[ZDCLocalPreferencesChanged_UserInfo_Key];
 * ```
 */
extern NSString *const ZDCLocalPreferencesChanged_UserInfo_Key;

/**
 * ZDCLocalPreferences is an optional drop-in replacement for NSUserDefaults.
 * You're welcome to use it if you find it useful.
 *
 * @note Local preferences implies preferences meant for this device only.
 *       This class isn't designed for sync.
 *
 * This class has several benefits over NSUserDefaults.
 *
 * The most obvious benefit is that the data is stored into the encrypted database.
 * This allows you to protect sensitive information.
 *
 * Another benefit is performance. NSUserDefaults writes ALL values to disk everytime
 * because it uses a plist to store the values on disk. In contrast, this system uses
 * a database, so only changed values need to be re-written.
 * Thus it has the potential to be faster and involve less disk IO.
 *
 * Implementation Notes:
 *   This class uses a YapDatabaseConnectionProxy to read/write from the database.
 *   See the YapDatabaseConnectionProxy header file for more information.
 *
 * Subclassing Notes:
 *   It's easy to subclass this class for your application.
 *   That allows you to register proper defaults for your app,
 *   as well as add functions that return values of the proper type.
 */
@interface ZDCLocalPreferences : NSObject

/**
 * Creates an instance that will read/write from the given (database) collection.
 *
 * @param collection
 *   All preference items will be stored into the database using this collection.
 *   That is, all items in the database are stored using a {collection, key} tuple.
 *   This instance will use the given collection for all values.
 *
 * @param proxy
 *   The connection proxy used to read & write from the database.
 *   You can get a proxy instance from ZeroDarkCloud.databaseManager.
 */
- (instancetype)initWithCollection:(NSString *)collection
                             proxy:(YapDatabaseConnectionProxy *)proxy;

/** The database collection used by the instance. */
@property (nonatomic, copy, readonly) NSString *collection;

/** The databse proxy used by the instance. */
@property (nonatomic, strong, readonly) YapDatabaseConnectionProxy *proxy;

/**
 * Returns the default value, which is not necessarily the effective value.
 */
- (nullable id)defaultObjectForKey:(NSString *)key;

/**
 * Fetches the effective value for the given key.
 * This will either be a previously set value, or will fallback to the default value.
 */
- (nullable id)objectForKey:(NSString *)key;

/**
 * Fetches the effective value for the given key.
 * This will either be a previously set value, or will fallback to the default value.
 *
 * If fallback to default value, the isDefault parameter will be set to YES.
 */
- (nullable id)objectForKey:(NSString *)key isDefault:(BOOL *_Nullable)isDefaultPtr;

/**
 * Allows you to change the value for the given key.
 * If the value doesn't effectively change, then nothing is written to disk.
 */
- (void)setObject:(nullable id)object forKey:(NSString *)key;

#pragma mark Convenience (Getters)

/** Returns the value as a bool. Returns NO if value doesn't exist, or isn't convertible. */
- (BOOL)boolForKey:(NSString *)key;

/** Returns the value as a float. Returns zero if value doesn't exist, or isn't convertiable */
- (float)floatForKey:(NSString *)key;

/** Returns the value as a double. Returns zero if value doesn't exist, or isnt't convertible. */
- (double)doubleForKey:(NSString *)key;

/** Returns the value as an NSInteger. Returns zero if value doesn't exist, or isnt't convertible. */
- (NSInteger)integerForKey:(NSString *)key;

/** Returns the value as an NSUInteger. Returns zero if value doesn't exist, or isnt't convertible. */
- (NSUInteger)unsignedIntegerForKey:(NSString *)key;

/** Returns the value as a string. Returns nil if value doesn't exist, or isnt't convertible. */
- (nullable NSString *)stringForKey:(NSString *)key;

/** Returns the value as a number. Returns nil if value doesn't exist, or isnt't convertible. */
- (nullable NSNumber *)numberForKey:(NSString *)key;

/** Returns the value as data. Returns nil if value doesn't exist, or isnt't convertible. */
- (nullable NSData *)dataForKey:(NSString *)key;

#pragma mark Convenience (Setters)

/** Type-specific settter */
- (void)setBool:(BOOL)value forKey:(NSString *)key;

/** Type-specific settter */
- (void)setFloat:(float)value forKey:(NSString *)key;

/** Type-specific settter */
- (void)setDouble:(double)value forKey:(NSString *)key;

/** Type-specific settter */
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;

/** Type-specific settter */
- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key;

#pragma mark Convenience (Defaults)

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns NO if the default value doesn't exist, or isn't convertiable.
 */
- (BOOL)defaultBoolForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns zero if the default value doesn't exist, or isn't convertiable.
 */
- (float)defaultFloatForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns zero if the default value doesn't exist, or isn't convertiable.
 */
- (double)defaultDoubleForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns zero if the default value doesn't exist, or isn't convertiable.
 */
- (NSInteger)defaultIntegerForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns zero if the default value doesn't exist, or isn't convertiable.
 */
- (NSUInteger)defaultUnsignedIntegerForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns nil if the default value doesn't exist, or isn't convertiable to a string.
 */
- (nullable NSString *)defaultStringForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns nil if the default value doesn't exist, or isn't convertiable to a number.
 */
- (nullable NSNumber *)defaultNumberForKey:(NSString *)key;

/**
 * Returns the default value, which is not necessarily the effective value.
 * Returns nil if the default value doesn't exist, or isn't of type NSData.
 */
- (nullable NSData *)defaultDataForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
