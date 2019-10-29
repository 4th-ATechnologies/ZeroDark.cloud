/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Used for configuring the database and registering your own custom YapDatabse extensions.
 *
 * For example:
 * - register a serializer/deserializer for your custom collections
 * - register a YapDatabaseExtension, such as a view, for sorting & displaying information in a collectionView
 */
typedef void (^YapDatabaseConfigHook)(YapDatabase *database);


/**
 * Container class for configuring the database.
 * An instance of this class is passed to `-[ZeroDarkCloud unlockOrCreateDatabase:]`.
 */
@interface ZDCDatabaseConfig : NSObject

/**
 * Creates an instance using the single required property.
 */
- (instancetype)initWithEncryptionKey:(NSData *)encryptionKey;

/**
 * The encryptionKey is used for encrypting & decrypting the underlying data of the database.
 * This is used by SQLCipher.
 */
@property (nonatomic, readonly) NSData *encryptionKey;

/**
 * Allows you to configure the database for your app.
 *
 * For example:
 * - register a serializer/deserializer for your custom collections
 * - register a YapDatabaseExtension, such as a view, for sorting & displaying information in a collectionView
 *
 * This block is invoked:
 * - before the `-[ZeroDarkCloud unlockOrCreateDatabase]` returns
 * - after ZeroDarkCloud has registered its own extensions
 *
 * @note This block is NOT retained by ZeroDarkCloud, nor is the ZDCDatabaseConfig instance.
 *       So the block is deallocated when the ZDCDatabaseConfig instance is deallocated.
 */
@property (nonatomic, readwrite, nullable) YapDatabaseConfigHook configHook;

@end

NS_ASSUME_NONNULL_END
