/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import "ZDCConstants.h"

/**
 * ZeroDarkCloud supports 2 types of encrypted files.
 */
typedef NS_ENUM(NSInteger, ZDCCryptoFileFormat) {
	/** An unkown file format. Generally used for errors. */
	ZDCCryptoFileFormat_Unknown   = 0,
	
	/**
	 * The CacheFile format is used for caching files to the local disk.
	 * It includes only the file itself, and excludes the metadata & thumbnail (which can be stored elsewhere).
	 */
	ZDCCryptoFileFormat_CacheFile = 1,
	
	/**
	 * The CloudFile format is the format used when storing files in the cloud.
	 * It includes the file itself, along with optional sections for metadata & thumbnail.
	 *
	 * The CloudFile format allows all file information to be encoded in a single format,
	 * which allows for atomic operations in the cloud.
	 */
	ZDCCryptoFileFormat_CloudFile = 2,
};

NS_ASSUME_NONNULL_BEGIN

/**
 * A CryptoFile instance encapsulates all the information you need to read an encrypted file.
 *
 * The ZeroDark.cloud framework provides a plethora of tools to read crypto files:
 *
 * - To decrypt a small cryptoFile into memory, you can use `+[ZDCFileConversion decryptCryptoFileIntoMemory:completionQueue:completionBlock:]`.
 * - To decrypt a larger cryptoFile, use `+[ZDCFileConversion decryptCryptoFile:completionQueue:completionBlock:]`.
 * - To read a cryptoFile as a stream, you can use either `CloudFile2CleartextInputStream` or `CacheFile2CleartextInputStream` depending on the fileFormat.
 * - To randomly access data within a cryptoFile, use the `ZDCFileReader` class.
 *
 * @see `ZDCFileConversion`
 * @see `ZDCFileReader`
 * @see `CloudFile2CleartextInputStream`
 * @see `CacheFile2CleartextInputStream`
 */
@interface ZDCCryptoFile : NSObject

/** Designated initializer */
- (instancetype)initWithFileURL:(NSURL *)fileURL
                     fileFormat:(ZDCCryptoFileFormat)fileFormat
                  encryptionKey:(NSData *)encryptionKey
                    retainToken:(nullable id)retainToken;

/**
 * The location of the file on disk.
 */
@property (nonatomic, strong, readonly) NSURL *fileURL;

/**
 * The encryption format being used to store the file.
 */
@property (nonatomic, assign, readonly) ZDCCryptoFileFormat fileFormat;

/**
 * The encryption key used to encrypt/decrypt the file.
 * This is a symmetric key, typically 512 bits for use with Threefish-512.
 */
@property (nonatomic, copy, readonly) NSData *encryptionKey;

/**
 * If the file is being managed by the DiskManager, the retainToken may be non-nil.
 *
 * As long as the retainToken remains in memory (isn't deallocated),
 * the DiskManager considers the file to still be in use, and won't delete the file from disk.
 */
@property (nonatomic, strong, readonly, nullable) id retainToken;

@end

NS_ASSUME_NONNULL_END
