/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

/** Used for registering your own custom YapDatabse extensions, for various use within your app. */
typedef void (^YapDatabaseExtensionsRegistration)(YapDatabase *database);


/**
 * Container class for configuring the database.
 * And instance of this class is passed to `-[ZeroDarkCloud unlockOrCreateDatabase:]`.
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
 * The default database serializer/deserializer uses NSKeyedArchiver/NSKeyedUnarchiver,
 * and supports any objects that conform to NSCoding.
 *
 * If you wish to use something else, you'll need to provider a custom serializer & deserializer.
 */
@property (nonatomic, readwrite, nullable) YapDatabaseSerializer serializer;

/**
 * The default database serializer/deserializer uses NSKeyedArchiver/NSKeyedUnarchiver,
 * and supports any objects that conform to NSCoding.
 *
 * If you wish to use something else, you'll need to provider a custom serializer & deserializer.
 */
@property (nonatomic, readwrite, nullable) YapDatabaseDeserializer deserializer;

/**
 * The default preSanitizer invokes `-[ZDCObject makeImmutable]`,
 * if the object is of type ZDCObject.
 *
 * You can supply your own custom preSanitizer to override this behavior.
 */
@property (nonatomic, readwrite, nullable) YapDatabasePreSanitizer preSanitizer;

/**
 * The default postSanitizer invokes `-[ZDCObject clearChangeTracking]`,
 * if the object is of type ZDCObject.
 *
 * You can supply your own custom postSanitizer to override this behavior.
 */
@property (nonatomic, readwrite, nullable) YapDatabasePostSanitizer postSanitizer;

/**
 * Allows you to register any custom extensions with the YapDatabase instance.
 * For example, you may want to add custom YapDatabaseView's for sorting your objects in the database.
 *
 * This block is invoked:
 * - before the `-[ZeroDarkCloud unlockOrCreateDatabase]` returns
 * - after ZeroDarkCloud has registered its own extensions
 *
 * @note This block is NOT retained by ZeroDarkCloud, nor is the ZDCDatabaseConfig instance.
 *       So the block is deallocated when the ZDCDatabaseConfig instance is deallocated.
 */
@property (nonatomic, readwrite, nullable) YapDatabaseExtensionsRegistration extensionsRegistration;

@end

NS_ASSUME_NONNULL_END
