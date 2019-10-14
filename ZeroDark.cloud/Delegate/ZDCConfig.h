/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
	
/**
 * Container class for configuring ZeroDarkCloud.
 * An instance of this class is passed to `-[ZeroDarkCloud initWithConfig:delegate:]`.
*/
@interface ZDCConfig : NSObject

/**
 * A treeID is a unique identifier for the container where your application stores its data.
 *
 * Every user has their own individual bucket in the cloud.
 * And within the user's bucket are various app containers.
 * Every app container has a unique name, which is called the treeID.
 *
 * A treeID generally has the form: com.companyName.appName
 *
 * As a visualization, Alice's bucket might look like this
 * ```
 *       (Alice's bucket)
 *              / \
 * (com.acme.boom) (com.hush.phone)
 * ```
 *
 * You need to first register your treeID on the ZeroDark [dashboard](https://dashboard.zerodark.cloud).
 */
- (instancetype)initWithPrimaryTreeID:(NSString *)treeID;

/**
 * The default treeID, which is the treeID specified during initialization.
 */
@property (nonatomic, copy, readwrite) NSString *primaryTreeID;

/**
 * Typically, you only need a single ZeroDarkCloud instance per app.
 * Once instance is capable of supporting multiple users.
 *
 * If you insist on having separate ZeroDarkCloud instances,
 * then you must use a different databaseName for each instance.
 * Failing to do so will cause an error during init of your ZeroDarkCloud instance.
 *
 * The databaseName is used to create an instance of [YapDatabase](https://github.com/yapstudios/YapDatabase).
 * ZeroDarkCloud needs a database for a ton of different things.
 * You're welcome to use the same YapDatabase instance to store your own objects. (YapDatabase is awesome.)
 * If you do, the `ZDCDatabaseConfig` provides hooks you can use during
 * YapDatabase initialization to register your own app-specific database extensions (views, indexes, etc).
 *
 * The default databaseName is "zdcDatabase".
 */
@property (nonatomic, copy, readwrite) NSString *databaseName;

/**
 * Adds a treeID to the list of application containers you're requesting access to.
 */
- (void)addTreeID:(NSString *)treeID;

@end

NS_ASSUME_NONNULL_END
