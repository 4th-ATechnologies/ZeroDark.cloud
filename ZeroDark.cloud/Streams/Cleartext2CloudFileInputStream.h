#import <Foundation/Foundation.h>

#import "ZDCCloudFileHeader.h"
#import "ZDCInputStream.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Converts from cleartext (non-encrypted) format to cloudFile (encrypted) format.
 *
 * In other words, the stream takes as input a cleartext source (via file/stream/data).
 * And as output (what you receive when you invoke `-read:maxLength:`),
 * it gives you the cloudFile version.
 *
 * Use this class for creating files in ZDCCryptoFileFormat_CloudFile.
 *
 * The data read from this stream can be:
 * - the input to a network connection (i.e. directly uploading to cloud)
 * - the input for writing the cloud file to disk
 * - the input for another stream
 *
 * Keep in mind that multiple input streams can be piped together.
 * So if you have a file in "cache file format", and you need to convert it to "cloud file format",
 * then you can do the following:
 * 
 * - create a `CacheFile2CleartextInputStream`
 * - then use that as the input for
 *   `-[Cleartext2CloudFileInputStream initWithCleartextFileStream:encryptionKey:]`
 *
 * How to use this class:
 *
 * - Create an instance of this class with an input in "cleartext format".
 * - Optionally assign the rawMetadata & rawThumbnail properties.
 * - If needed, assign the cleartextFileSize property
 *   (needed if this information cannot be extracted from init parameters).
 * - Then continually invoke the `-read:maxLength:` method,
 *   passing in a buffer for the cloud file data (the output) to be copied into.
 * - Continue until you read the end of the input source.
 */
@interface Cleartext2CloudFileInputStream : ZDCInputStream <NSCopying>

/**
 * Creates an instance that will read from the given cleartextFileURL,
 * encrypt the data, and produce the encrypted data to you via 'read:maxLength:'.
 * 
 * The data you read via 'read:maxLength' will be in "cloud file format".
 * 
 * @param cleartextFileURL
 *   A fileURL that can be used to read the file in cleartext format.
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
 * The data you read via 'read:maxLength' will be in "cloud file format".
 *
 * @param cleartextFileStream
 *   A stream that can be used to read the file in cleartext format.
 *   It's common for this parameter to be of type CacheFile2CleartextInputStream.
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
 * The data you read via 'read:maxLength' will be in "cloud file format".
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
 * You can optionally add a metadata section to the cloudFile.
 *
 * @warning You must set this value BEFORE opening the stream.
 */
@property (nonatomic, copy, readwrite, nullable) NSData *rawMetadata;

/**
 * You can optionally add a thumbnail section to the cloudfile.
 *
 * @warning You must set this value BEFORE opening the stream.
 */
@property (nonatomic, copy, readwrite, nullable) NSData *rawThumbnail;

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
 * However, when you use this trick, you MUST go back and re-write the CloudFile header afterwards.
 * If you forget to do so, then attempts to read the CloudFile later will fail.
 *
 * @see `+[Cleartext2CloudFileInputStream updateCloudFileHeader:withCleartextFileSize:encryptionKey:]`
 *
 * The default value is NO.
 */
@property (nonatomic, assign, readwrite) BOOL cleartextFileSizeUnknown;

/**
 * The total size of the cloud file.
 * This value is available anytime after setting `cleartextFileSize`.
 *
 * If you don't manually set `cleartextFileSize`,
 * then the stream will attempt to set it automatically when you open it.
 *
 * Another way to think of it: it will be the output of all read:maxLength: invocations.
 * 
 * @note This property ignores ZDCStreamFileMinOffset & ZDCStreamFileMaxOffset.
 *       If that's what you're looking for, use encryptedRangeSize.
 */
@property (nonatomic, readonly, nullable) NSNumber *encryptedFileSize;

/**
 * The total size of the output (if read in its entirety),
 * taking into account configured ZDCStreamFileMinOffset & ZDCStreamFileMaxOffset properties.
 */
@property (nonatomic, readonly, nullable) NSNumber *encryptedRangeSize;

/**
 * Allows you to update the CloudFile header, and rewrites the cleartext file size.
 * Use this method to fixup the header when setting `cleartextFileSizeUnknown` to YES.
 */
+ (nullable NSError *)updateCloudFileHeader:(NSURL *)cloudFileURL
                      withCleartextFileSize:(uint64_t)cleartextFileSize
                              encryptionKey:(NSData *)encryptionKey;

/**
 * This method can be used to produce an encrypted version of the given header.
 *
 * @param header
 *   The header to encrypt.
 *
 * @param encryptionKey
 *   The symmetric key used to encrypt the cloudFile.
 *
 * @param errorPtr
 *   If an error occurs, this will tell you what went wrong.
 *
 * @return The encrypted data if the decryption process was successful. Nil otherwise.
 */
+ (nullable NSData *)encryptCloudFileHeader:(ZDCCloudFileHeader)header
                          withEncryptionKey:(NSData *)encryptionKey
                                      error:(NSError *_Nullable *_Nullable)errorPtr;

@end

NS_ASSUME_NONNULL_END

