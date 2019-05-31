#import <Foundation/Foundation.h>

#import "ZDCCryptoFile.h"
#import "ZDCInputStream.h"

/**
 * Converts from cacheFile (encrypted) format to cleartext (non-encrypted) format.
 *
 * In other words, the stream takes as input a cacheFile source (via file/stream/data).
 * And as output (what you receive when you invoke `-read:maxLength:`),
 * it gives you the decrypted/cleartext version.
 *
 * Use this for reading encrypted files in ZDCCryptoFileFormat_CacheFile.
 *
 * You can stream the output to an unencrypted file for use with the previewer.
 * Or you can use the output as the input to a different encrypter (e.g. cloud file format).
 * 
 * How it works:
 * - Create an instance of this class with the encryption key,
 *   and an input source for reading the cacheFile.
 * - Then continually invoke the `read:maxLength:` method,
 *   passing in a buffer for the unencrypted data to be copied into.
 * - This class will read and decrypt the next chuck of data from cacheFile source,
 *   and write the decrypted version to your buffer.
 */
@interface CacheFile2CleartextInputStream : ZDCInputStream <NSCopying>

/**
 * Creates an instance that will read from the given cryptoFile,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 *
 * @param cryptoFile
 *   An instance which contains the fileURL & encryptionKey.
 *   Also stream.retainToken is set to cryptoFile.retainToken.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile;

/**
 * Creates an instance that will read from the given cacheFileURL,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 * 
 * @param cacheFileURL
 *   The location of the encrypted file in "cache file format".
 *   The instance will open an inputStream with this URL in order to read the file.
 * 
 * @param encryptionKey
 *   The key used to decrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCacheFileURL:(NSURL *)cacheFileURL encryptionKey:(NSData *)encryptionKey;

/**
 * Creates an instance that will read from the given cacheFileStream,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 * 
 * @param cacheFileStream
 *   A stream that can be used to read the encrypted file in "cache file format".
 *   
 * @param encryptionKey
 *   The key used to decrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCacheFileStream:(NSInputStream *)cacheFileStream encryptionKey:(NSData *)encryptionKey;

/**
 * Creates an instance that will read from the given cacheFileData,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 *
 * @note If your cacheFile data is in a file, don't use this method.
 *       Instead you should be using `initWithCacheFileURL::`.
 *
 * @param cacheFileData
 *   A smallish chunk of data.
 *   If your data is in a file, use `initWithCacheFileURL::` instead.
 *
 * @param encryptionKey
 *   The key used to decrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCacheFileData:(NSData *)cacheFileData
                        encryptionKey:(NSData *)encryptionKey;

/**
 * This value is anytime after the stream has been opened.
 */
@property (nonatomic, readonly) NSNumber *cleartextFileSize;

@end
