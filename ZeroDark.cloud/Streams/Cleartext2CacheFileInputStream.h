#import <Foundation/Foundation.h>
#import "ZDCInputStream.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Converts from cleartext (non-encrypted) format to cacheFile (encrypted) format.
 *
 * In other words, the stream takes as input a cleartext source (via file/stream/data).
 * And as output (what you receive when you invoke `-read:maxLength:`),
 * it gives you the cacheFile version.
 *
 * Use this class for creating files in ZDCCryptoFileFormat_CacheFile.
 * 
 * How it works:
 * - Create an instance of this class with the encryption key,
 *   and the cleartext input source.
 * - Then continually invoke the [stream read:maxLength:] method,
 *   passing in the your buffer.
 * - This class will then encrypt read and encrypt the underlying cleartext data,
 *   and place the encrypted version in your buffer.
 */
@interface Cleartext2CacheFileInputStream : ZDCInputStream <NSCopying>

/**
 * Creates an instance that will read from the given cleartextFileURL,
 * encrypt the data, and produce the encrypted data to you via 'read:maxLength:'.
 *
 * @param cleartextFileURL
 *   The location of the unencrypted file (in "cleartext") you wish to read from.
 *   The instance will open an inputStream with this URL in order to read the file.
 *
 * @param encryptionKey
 *   The key used to encrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCleartextFileURL:(NSURL *)cleartextFileURL
                           encryptionKey:(NSData *)encryptionKey;

/**
 * Creates an instance that will read from the given cleartextFileStream,
 * encrypt the data, and produce the encrypted data to you via 'read:maxLength:'.
 *
 * @param cleartextFileStream
 *   A stream that can be used to read the unencrypted file (in "cleartext").
 *
 * @param encryptionKey
 *   The key used to encrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCleartextFileStream:(NSInputStream *)cleartextFileStream
                              encryptionKey:(NSData *)encryptionKey;

/**
 * Creates an instance that will read from the given cleartextData,
 * encrypt the data, and produce the encrypted data to you via 'read:maxLength:'.
 *
 * @note If your cleartext data is in a file, don't use this method.
 *       Instead you should be using `initWithCleartextFileURL::`.
 *
 * @param cleartextData
 *   A smallish chunk of data.
 *   If your data is in a file, use `initWithCleartextFileURL::` instead.
 *
 * @param encryptionKey
 *   The key used to encrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCleartextData:(NSData *)cleartextData
                        encryptionKey:(NSData *)encryptionKey;

/**
 * If the instance was initialized using a cleartextFileURL, returns the reference.
 */
@property (nonatomic, strong, readonly, nullable) NSURL *cleartextFileURL;

/**
 * If the instance was initialized using cleartextData, returns the reference.
 */
@property (nonatomic, strong, readonly, nullable) NSData *cleartextData;

/**
 * This property MUST be set before you can invoke 'read:maxLength'.
 *
 * Under most circumstances, the value is set for you by extracting it from the parameters
 * given in the init method. However, this is not always possible, as outlined below.
 * 
 * If you init with a cleartextFileURL (via initWithCleartextFileURL::),
 * then this property will be set for you when opening the stream (by reading NSURLFileSizeKey).
 *
 * If you init with a CacheFile2CleartextInputStream instance (via initWithCleartextFileStream::),
 * then this property will be set for you when opening the stream (by reading cacheFileStream.cleartextFileSize).
 *
 * If you init with data (via initWithCleartextData::),
 * this this property will be set for you (by reading data.length).
 * 
 * In other circumstances (i.e. when using a custom NSInputStream),
 * you must manually set the value yourself.
 */
@property (nonatomic, strong, readwrite, nullable) NSNumber *cleartextFileSize;

/**
 * If you don't know the cleartextFileSize in advance, you can set this property to YES.
 * However, when you use this trick, you MUST go back and re-write the CacheFile header afterwards.
 * If you forget to do so, then attempts to read the CacheFile later will fail.
 *
 * @see `updateCacheFileHeader:withCleartextFileSize:encryptionKey:`
 * @see `[Cleartext2CacheFileInputStream updateCacheFileHeader:withCleartextFileSize:encryptionKey:]`
 * @see `+updateCacheFileHeader:withCleartextFileSize:encryptionKey:`
 * @see `+[Cleartext2CacheFileInputStream updateCacheFileHeader:withCleartextFileSize:encryptionKey:]`
 *
 * The default value is NO.
 */
@property (nonatomic, assign, readwrite) BOOL cleartextFileSizeUnknown;

/**
 * The total size of the resulting cache file.
 * This value is available anytime after setting `cleartextFileSize`.
 *
 * If you don't manually set `cleartextFileSize`,
 * then the stream will attempt to set it automatically when you open it.
 *
 * Another way to think of it: it will be the output of all read:maxLength: invocations.
 */
@property (nonatomic, strong, readonly, nullable) NSNumber *encryptedFileSize;

/**
 * Allows you to update the CacheFile header, and rewrites the cleartext file size.
 * Use this method to fixup the header when setting `cleartextFileSizeUnknown` to YES.
 */
+ (nullable NSError *)updateCacheFileHeader:(NSURL *)cacheFileURL
                      withCleartextFileSize:(uint64_t)cleartextFileSize
                              encryptionKey:(NSData *)encryptionKey;

@end

NS_ASSUME_NONNULL_END
