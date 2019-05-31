/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import "OSPlatform.h"
#import "ZDCCloudFileHeader.h"
#import "ZDCCryptoFile.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZDCFileConverstion class contains many utility methods to encrypt & decrypt files.
 */
@interface ZDCFileConversion : NSObject

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encrypt (Cleartext -> Cachefile)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Converts from "unencrypted/cleartext file format" to "cache file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cleartextFileURL
 *   The input file (stored unencrypted).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param completionQueue (optional)
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock (optional)
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the encryption progress.
 */
+ (NSProgress *)encryptCleartextFile:(NSURL *)cleartextFileURL
                  toCacheFileWithKey:(NSData *)encryptionKey
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *_Nullable cryptoFile, NSError *_Nullable error))completionBlock;

/**
 * Converts from "unencrypted/cleartext file format" to "cache file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextFileURL
 *   The input file (stored unencrypted).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param outStream
 *   An output stream that is already open, and ready to be written to.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)cleartextFileURL
          toCacheFileWithKey:(NSData *)encryptionKey
                outputStream:(NSOutputStream *)outStream
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext file format" to "cache file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextFileURL
 *   The input file (stored unencrypted).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)cleartextFileURL
          toCacheFileWithKey:(NSData *)encryptionKey
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext format" to "cachefile format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the encryption progress.
 */
+ (NSProgress *)encryptCleartextData:(NSData *)cleartextData
                  toCacheFileWithKey:(NSData *)encryptionKey
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *_Nullable cryptoFile, NSError *_Nullable error))completionBlock;

/**
 * Converts from "unencrypted/cleartext format" to "cachefile format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCacheFileWithKey:(NSData *)encryptionKey
                outputStream:(NSOutputStream *)outStream
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext format" to "cachefile format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param outputFileURL
 *   The location to write the encrypted file.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCacheFileWithKey:(NSData *)encryptionKey
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext format" to "cachefile format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, the encrypted data is returned.
 * Otherwise returns nil, and sets outError to the error that occurred.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param outError
 *   If something goes wrong, this parameter will tell you why.
 *
 * @return On success, returns the encrypted data. Returns nil if an error occurs.
 */
+ (nullable NSData *)encryptCleartextData:(NSData *)cleartextData
                       toCacheFileWithKey:(NSData *)encryptionKey
                                    error:(NSError *_Nullable *_Nullable)outError;

/**
 * Creates and returns a "pump".
 *
 * This is typically used in conjunction with an API that gives you chunks of data at a time.
 * And your goal is to take the cleartext chunks, and stream them to a cachefile on disk.
 *
 * Here's how it works:
 * - You call this method and get back 2 blocks: dataBlock & completionBlock
 * - When your data provider gives you data, you invoke the databBlock
 * - And when your data provider reports EOF (end-of-file) or error, you invoke the completionBlock
 * - Barring any errors, you now have an encrypted version of the data on disk
 *
 * @param dataBlockOut
 *   Returns the dataBlock that you'll invoke.
 *   The data you pass to this block is the cleartext data that will get encrypted & written to the outputFileURL.
 *
 * @param completionBlockOut
 *   Returns the completionBlock that you'll invoke.
 *   When you invoke this block you're telling the encryption stream there's no more data to encrypt,
 *   and it should finish the encryption process, and flush any remaining data to the disk.
 *   (You cannot invoke the dataBlock again after invoking the completionBlock.)
 *
 * @param outputFileURL
 *   The location to write the encrypted file.
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @return Returns nil on success. Otherwise returns an error that describes what went wrong.
 */
+ (nullable NSError *)encryptCleartextWithDataBlock:(NSError*_Nullable (^_Nonnull*_Nonnull)(NSData*))dataBlockOut
												completionBlock:(NSError*_Nullable (^_Nonnull*_Nonnull)(void))completionBlockOut
                                        toCacheFile:(NSURL *)outputFileURL
                                            withKey:(NSData *)encryptionKey;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encrypt (Cleartext -> Cloudfile)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Converts from "unencrypted/cleartext file format" to "cloud file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cleartextFileURL
 *   The input file (stored unencrypted).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param completionQueue (optional)
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock (optional)
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the encryption progress.
 */
+ (NSProgress *)encryptCleartextFile:(NSURL *)cleartextFileURL
                  toCloudFileWithKey:(NSData *)encryptionKey
                            metadata:(nullable NSData *)metadata
                           thumbnail:(nullable NSData *)thumbnail
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *_Nullable cryptoFile, NSError *_Nullable error))completionBlock;

/**
 * Converts from "unencrypted/cleartext file format" to "cloud file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextFileURL
 *   The input file (stored unencrypted).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param outStream
 *   An output stream to write to.
 *   This method will open the stream if it's not already open.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)cleartextFileURL
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                outputStream:(NSOutputStream *)outStream
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext file format" to "cloud file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextFileURL
 *   The input file (stored unencrypted).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param outputFileURL
 *   The location to write the encrypted file.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)cleartextFileURL
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext format" to "cloudfile format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the encryption progress.
 */
+ (NSProgress *)encryptCleartextData:(NSData *)cleartextData
                  toCloudFileWithKey:(NSData *)encryptionKey
                            metadata:(nullable NSData *)metadata
                           thumbnail:(nullable NSData *)thumbnail
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *_Nullable cryptoFile, NSError *_Nullable error))completionBlock;

/**
 * Converts from "unencrypted/cleartext format" to "cloud file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param outStream
 *   An output stream to write to.
 *   This method will open the stream if it's not already open.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                outputStream:(NSOutputStream *)outStream
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext format" to "cloudfile format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param outputFileURL
 *   The location to write the encrypted file.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "unencrypted/cleartext format" to "cloudfile format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, the encrypted data will be returned.
 * Otherwise returns nil, and sets outError to the error that occurred.
 *
 * @param cleartextData
 *   The input data (unencrypted file in memory).
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @param outError
 *   If something goes wrong, this parameter will tell you why.
 *
 * @return On success, returns the encrypted data. Returns nil if an error occurs.
 */
+ (nullable NSData *)encryptCleartextData:(NSData *)cleartextData
                       toCloudFileWithKey:(NSData *)encryptionKey
                                 metadata:(nullable NSData *)metadata
                                thumbnail:(nullable NSData *)thumbnail
                                    error:(NSError *_Nullable *_Nullable)outError;

/**
 * Creates and returns a "pump".
 *
 * This is typically used in conjunction with an API that gives you chunks of data at a time.
 * And your goal is to take the cleartext chunks, and stream them to a cloudfile on disk.
 *
 * Here's how it works:
 * - You call this method and get back 2 blocks: dataBlock & completionBlock
 * - When your data provider gives you data, you invoke the databBlock
 * - And when your data provider reports EOF (end-of-file) or error, you invoke the completionBlock
 * - Barring any errors, you now have an encrypted version of the data on disk
 *
 * @param dataBlockOut
 *   Returns the dataBlock that you'll invoke.
 *   The data you pass to this block is the cleartext data that will get encrypted & written to the outputFileURL.
 *
 * @param completionBlockOut
 *   Returns the completionBlock that you'll invoke.
 *   When you invoke this block you're telling the encryption stream there's no more data to encrypt,
 *   and it should finish the encryption process, and flush any remaining data to the disk.
 *   (You cannot invoke the dataBlock again after invoking the completionBlock.)
 *
 * @param outputFileURL
 *   The location to write the encrypted file.
 *
 * @param encryptionKey
 *   A proper key for the encryption.
 *   If encrypting data that corresponds to a ZDCNode, then use `-[ZDCNode encryptionKey]`.
 *   Otherwise you can generate a key using `+[ZDCNode randomEncryptionKey]`.
 *
 * @param metadata
 *   Optional metadata section to be included in the cloudfile.
 *
 * @param thumbnail
 *   Optional thumbnail section to be included in the cloudfile.
 *
 * @return Returns nil on success. Otherwise returns an error that describes what went wrong.
 */
+ (nullable NSError *)encryptCleartextWithDataBlock:(NSError*_Nullable (^_Nonnull*_Nonnull)(NSData*))dataBlockOut
												completionBlock:(NSError*_Nullable (^_Nonnull*_Nonnull)(void))completionBlockOut
                                        toCloudFile:(NSURL *)outputFileURL
                                            withKey:(NSData *)encryptionKey
                                           metadata:(nullable NSData *)metadata
                                          thumbnail:(nullable NSData *)thumbnail;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Decrypt (Crypto -> Cleartext)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Converts a file from an encrypted format to an unencrypted/cleartext format.
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cryptoFile
 *   Encapsulated information about the encrypted file.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the decryption progress.
 */
+ (NSProgress *)decryptCryptoFile:(ZDCCryptoFile *)cryptoFile
                  completionQueue:(nullable dispatch_queue_t)completionQueue
                  completionBlock:(void (^)(NSURL *_Nullable cleartextFileURL,
                                            NSError *_Nullable error))completionBlock;

/**
 * Converts a file from an encrypted format to an unencrypted/cleartext format.
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, a nil value will be returned.
 * Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param cryptoFile
 *   Encapsulated information about the encrypted file.
 *
 * @param outStream
 *   An output stream to write to.
 *   This method will open the stream if it's not already open.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)decryptCryptoFile:(ZDCCryptoFile *)cryptoFile
           toOutputStream:(NSOutputStream *)outStream
                    error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts a file from an encrypted format to an unencrypted/cleartext format.
 *
 * The operation is synchronous, and thus should be called from a background thread.
 * If successful, the cleartext/decrypted data will be returned.
 * Otherwise a relavent error will be returned via the outError parameter that describes the error that occurred.
 *
 * @param cryptoFile
 *   Encapsulated information about the encrypted file.
 *
 * @param outError
 *   If something goes wrong, this parameter will tell you why.
 *
 * @return On success, returns the decrypted data. Returns nil if an error occurs.
 */
+ (nullable NSData *)decryptCryptoFileIntoMemory:(ZDCCryptoFile *)cryptoFile
                                           error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts a file from an encrypted format to an unencrypted/cleartext format.
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * @param cryptoFile
 *   Encapsulated information about the encrypted file.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the decryption progress.
 */
+ (NSProgress *)decryptCryptoFileIntoMemory:(ZDCCryptoFile *)cryptoFile
                            completionQueue:(nullable dispatch_queue_t)completionQueue
                            completionBlock:(void (^)(NSData *_Nullable cleartext,
                                                      NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Decrypt (Cachefile -> Cleartext)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Converts from "cache file format" to "unencrypted/cleartext file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cacheFileURL
 *   The input file (stored in cache file format).
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the decryption progress.
 */
+ (NSProgress *)decryptCacheFile:(NSURL *)cacheFileURL
                   encryptionKey:(NSData *)encryptionKey
                     retainToken:(nullable id)retainToken
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSURL *_Nullable cleartextFileURL,
                                           NSError *_Nullable error))completionBlock;

/**
 * Converts from "cache file format" to "unencrypted/cleartext file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 *
 * @param cacheFileURL
 *   The input file (stored in cache file format).
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param outStream
 *   An output stream to write to.
 *   This method will open the stream if it's not already open.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)decryptCacheFile:(NSURL *)cacheFileURL
           encryptionKey:(NSData *)encryptionKey
             retainToken:(nullable id)retainToken
          toOutputStream:(NSOutputStream *)outStream
                   error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "cache file format" to "unencrypted/cleartext file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * @param cacheFileURL
 *   The input file (stored in cache file format).
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param outError
 *   If something goes wrong, this parameter will tell you why.
 *
 * @return On success, returns the decrypted data. Returns nil if an error occurs.
 */
+ (nullable NSData *)decryptCacheFileIntoMemory:(NSURL *)cacheFileURL
                                  encryptionKey:(NSData *)encryptionKey
                                    retainToken:(nullable id)retainToken
                                          error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "cache file format" to "unencrypted/cleartext file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * @param cacheFileURL
 *   The input file (stored in cache file format).
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the decryption progress.
 */
+ (NSProgress *)decryptCacheFileIntoMemory:(NSURL *)cacheFileURL
                             encryptionKey:(NSData *)encryptionKey
                               retainToken:(nullable id)retainToken
                           completionQueue:(nullable dispatch_queue_t)completionQueue
                           completionBlock:(void (^)(NSData *_Nullable cleartext,
                                                     NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Decrypt (Cloudfile -> Cleartext)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Converts from "cloud file format" to "unencrypted/cleartext file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cloudFileURL
 *   The input file (stored in cloud file format).
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the decryption progress.
 */
+ (NSProgress *)decryptCloudFile:(NSURL *)cloudFileURL
                   encryptionKey:(NSData *)encryptionKey
                     retainToken:(nullable id)retainToken
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCCloudFileHeader header,
                                           NSData *_Nullable metadata,
                                           NSData *_Nullable thumbnail,
                                           NSURL *_Nullable cleartextFileURL,
                                           NSError *_Nullable error))completionBlock;

/**
 * Converts from "cloud file format" to "unencrypted/cleartext file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 *
 * @note A cloudFile is composed of several sections: [header, metadata, thumbnail, data].
 *       The only section written to the outStream by this method is the data section.
 *
 * @param cloudFileURL
 *   The input file (stored in cloud file format).
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param outStream
 *   An output stream that is already open, and ready to be written to.
 *
 * @return
 *   If successful, a nil value will be returned.
 *   Otherwise a relavent error will be returned that should describe the error that occurred.
 *
 * @param outError
 *   If an error occurs, describes what went wrong.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)decryptCloudFile:(NSURL *)cloudFileURL
           encryptionKey:(NSData *)encryptionKey
             retainToken:(nullable id)retainToken
          toOutputStream:(NSOutputStream *)outStream
                   error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "cloud file format" to "unencrypted/cleartext file format".
 *
 * The operation is synchronous, and thus should be called from a background thread.
 *
 * @param cloudFileURL
 *   The input file (stored in cloud file format).
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param outError
 *   If something goes wrong, this parameter will tell you why.
 *
 * @return On success, returns the decrypted data. Returns nil if an error occurs.
 */
+ (nullable NSData *)decryptCloudFileIntoMemory:(NSURL *)cloudFileURL
                                  encryptionKey:(NSData *)encryptionKey
                                    retainToken:(nullable id)retainToken
                                          error:(NSError *_Nullable *_Nullable)outError;

/**
 * Converts from "cloud file format" to "unencrypted/cleartext file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 *
 * @param cloudFileURL
 *   The input file (stored in cloud file format).
 *
 * @param encryptionKey
 *   The key that was used to encrypt the file.
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param completionQueue
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the decryption progress.
 */
+ (NSProgress *)decryptCloudFileIntoMemory:(NSURL *)cloudFileURL
                             encryptionKey:(NSData *)encryptionKey
                               retainToken:(nullable id)retainToken
                           completionQueue:(nullable dispatch_queue_t)completionQueue
                            completionBlock:(void (^)(ZDCCloudFileHeader header,
                                                      NSData *_Nullable metadata,
                                                      NSData *_Nullable thumbnail,
                                                      NSData *_Nullable cleartext,
                                                      NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convert (Crypto -> Crypto)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Converts from "cache file format" to "cloud file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cacheFileURL
 *   The input file (stored in cache file format).
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param cacheFileEncryptionKey
 *   If given, the new cacheFile will be encrypted using the given encryptionKey.
 *   It not given, the new cacheFile will be encrypted using file.encryptionKey.
 *
 * @param completionQueue (optional)
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock (optional)
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the conversion progress.
 */
+ (NSProgress *)convertCacheFile:(NSURL *)cacheFileURL
                     retainToken:(nullable id)retainToken
                   encryptionKey:(NSData *)cacheFileEncryptionKey
              toCloudFileWithKey:(NSData *)cloudFileEncryptionKey
                        metadata:(nullable NSData *)metadata
                       thumbnail:(nullable NSData *)thumbnail
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSURL *_Nullable outputFileURL, NSError *_Nullable error))completionBlock;

/**
 * Converts from "cloud file format" to "cache file format".
 *
 * The operation is asynchronous, and the completionBlock should be used to detect when it completes.
 * If successful, the output file will be written to the tempDirectoryURL, using a random fileName.
 * The caller is responsible for moving the temp file into its permanent location, or deleting it.
 *
 * @param cloudFileURL
 *   The input file (stored in cloud file format).
 *
 * @param retainToken
 *   A retainToken from the CacheManager,
 *   than can be used to ensure the file isn't deleted before it can be opened.
 *
 * @param cloudFileEncryptionKey
 *   The encryption key used when encrypting the input/cloudFileURL.
 *
 * @param cacheFileEncryptionKey
 *   The encryption key to use when creating/encrypting the output/cacheFile
 *
 * @param completionQueue (optional)
 *   If not specified, dispatch_get_main_queue() will be used.
 *
 * @param completionBlock (optional)
 *   The completionBlock to be executed when the operation is complete.
 *
 * @return A progress instance you can use to monitor the conversion progress.
 */
+ (NSProgress *)convertCloudFile:(NSURL *)cloudFileURL
                     retainToken:(nullable id)retainToken
                   encryptionKey:(NSData *)cloudFileEncryptionKey
              toCacheFileWithKey:(NSData *)cacheFileEncryptionKey
                 completionQueue:(dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCCloudFileHeader header,
                                           NSData *_Nullable metadata,
                                           NSData *_Nullable thumbnail,
                                           NSURL *_Nullable cacheFileURL,
                                           NSError *_Nullable error))completionBlock;

/**
 * Re-Encrypts an encrypted file (either in CacheFile or CloudFile format),
 * by decrypting each block on the fly, and then re-encrypting them with a different key.
 *
 * @return A progress instance you can use to monitor the conversion progress.
 */
+ (NSProgress *)reEncryptFile:(NSURL *)srcFileURL
                      fromKey:(NSData *)srcEncryptionKey
                        toKey:(NSData *)dstEncryptionKey
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(void (^)(NSURL *_Nullable dstFileURL, NSError *_Nullable error))completionBlock;

/**
 * Re-Encrypts an encrypted file (either in CacheFile or CloudFile format),
 * by decrypting each block on the fly, and then re-encrypting them with a different key.
 *
 * @return Returns YES on success, NO otherwise.
 */
+ (BOOL)reEncryptFile:(NSURL *)srcFileURL
              fromKey:(NSData *)srcEncryptionKey
               toFile:(NSURL *)dstFileURL
                toKey:(NSData *)dstEncryptionKey
                error:(NSError *_Nullable *_Nullable)outError;

@end

NS_ASSUME_NONNULL_END
