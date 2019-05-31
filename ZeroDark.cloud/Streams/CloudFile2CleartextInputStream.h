#import <Foundation/Foundation.h>

#import "OSPlatform.h"
#import "ZDCCloudFileHeader.h"
#import "ZDCCryptoFile.h"
#import "ZDCInputStream.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A cloudfile is composed of several sections.
 *
 * When reading from a CloudFile2CleartextInputStream,
 * the stream will perform a "soft break" between each section
 * via the `-read:maxLength:` method. That is, the 'read:maxLength' method
 * will return a 0 (zero) when you reach the end of a section.
 * This ensures you will only ever receive data from a single section at a time.
 */
typedef NS_ENUM(NSInteger, ZDCCloudFileSection) {
	
	/**
	 * Every cloudfile contains a header.
	 * This is always the first section in a cloudfile.
	 */
	ZDCCloudFileSection_Header   = 0,
	
	/** Cloudfiles may optionally contain a metadata section. */
	ZDCCloudFileSection_Metadata,
	
	/** Cloudfiles may optionally contain a thumbnail section. */
	ZDCCloudFileSection_Thumbnail,
	
	/** The file/data section of the cloudfile. */
	ZDCCloudFileSection_Data,
	
	/** Indicates the End Of File has been reached. */
	ZDCCloudFileSection_EOF
};

/**
 * This property allows you to jump to a specific section (via NSInputStream's `setProperty:forKey:` method).
 *
 * @note If you copy a stream, this value gets copied as well.
 *       In other words, the copy will jump to the specific section as well.
 */
extern NSString *const ZDCStreamCloudFileSection;

/**
 * Converts from cloudFile (encrypted) format to cleartext (non-encrypted) format.
 *
 * In other words, the stream takes as input a cloudFile source (via file/stream/data).
 * And as output (what you receive when you invoke `-read:maxLength:`),
 * it gives you the decrypted/cleartext version.
 *
 * Use this for reading encrypted files in ZDCCryptoFileFormat_CloudFile.
 * 
 * How it works:
 * - Create an instance of this class configured to read the raw cloudFile data,
 *   along with the encryption key for decrypting the cloudFile data.
 * - Then continually invoke the `-read:maxLength:` method,
 *   passing in a buffer for the output (the decrypted/cleartext data).
 * - This class will read and decrypt the next chuck of data,
 *   and write the decrypted version to your buffer.
 *
 * @warning A CloudFile contains multiple sections.
 *
 * Recall that a CloudFile is composed of multiple different sections:
 * - header (always present)
 * - metadata (optional, may be present)
 * - thumbnail (optiona, may be present)
 * - data (always present)
 *
 * This class allows you to read every section. Which is a bit different from your average stream.
 * So, to simplify its use, this class will perform a "soft break" between each section
 * via the `-read:maxLength:` method. That is, the 'read:maxLength' method
 * will return a 0 (zero) when you reach the end of a section.
 * This ensures you will only ever receive data from a single section at a time.
 * 
 * Thus, you can simply invoke 'read:maxLength:' until the `-cloudFileSection`
 * reflects the section you're interested in. If you want to jump to a particular section,
 * you can use NSInputStream's `setProperty:forKey:` method, and use the ZDCStreamCloudFileSection key.
 */
@interface CloudFile2CleartextInputStream : ZDCInputStream <NSCopying>

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
 * Creates an instance that will read from the given cloudFileURL,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 *
 * @param cloudFileURL
 *   The location of the encrypted file in "cloud file format".
 *   The instance will open an inputStream with this URL in order to read the file.
 *
 * @param encryptionKey
 *   The key used to decrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCloudFileURL:(NSURL *)cloudFileURL encryptionKey:(NSData *)encryptionKey;

/**
 * Creates an instance that will read from the given cloudFileStream,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 *
 * @param cloudFileStream
 *   A stream that can be used to read the encrypted file in "cloud file format".
 *
 * @param encryptionKey
 *   The key used to decrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCloudFileStream:(NSInputStream *)cloudFileStream encryptionKey:(NSData *)encryptionKey;

/**
 * Creates an instance that will read from the given cloudFileData,
 * decrypt the data, and produce the decrypted data to you via 'read:maxLength:'.
 *
 * @note If your cloudFile data is in a file, don't use this method.
 *       Instead you should be using `initWithCloudFileURL::`.
 *
 * @param cloudFileData
 *   A smallish chunk of data.
 *   If your data is in a file, use `initWithCloudFileURL::` instead.
 *
 * @param encryptionKey
 *   The key used to decrypt the file.
 *   (i.e. node.encryptionKey)
 */
- (instancetype)initWithCloudFileData:(NSData *)cloudFileData encryptionKey:(NSData *)encryptionKey;

/**
 * This property is available anytime after the stream has been opened.
 */
@property (nonatomic, readonly) NSNumber *cleartextFileSize;

/**
 * This property is available anytime after the cloudFileSection has
 * been set to ZDCCloudFileSection_Metadata (or higher).
 */
@property (nonatomic, readonly) ZDCCloudFileHeader cloudFileHeader;

/**
 * Every invocation of 'read:maxLength:' will only ever give you data from a single section at a time.
 * This property tells you what the next invocation of 'read:maxLength:' will return to you.
 *
 * @note You can jump to a particular section by using the `setProperty:forKey:` method.
 *       For the key you pass `ZDCStreamCloudFileSection`.
 *       And for the value you pass `ZDCCloudFileSection` (wrapped as NSNumber).
 */
@property (nonatomic, readonly) ZDCCloudFileSection cloudFileSection;

/**
 * This method is used to read just the header, metadata & thumbnail sections of a cloud file.
 *
 * Pass nil/NULL for anything you don't need,
 * and this method will skip attempting to read that section.
 *
 * Since this method only attempts to read part of the cloud file,
 * the stream can represent a partial file. (e.g. only the first X bytes)
 */
+ (BOOL)decryptCloudFileStream:(CloudFile2CleartextInputStream *)inputStream
                        header:(ZDCCloudFileHeader *_Nullable)headerPtr
                   rawMetadata:(NSData *_Nullable *_Nullable)metadataPtr
                  rawThumbnail:(NSData *_Nullable *_Nullable)thumbnailPtr
                         error:(NSError *_Nullable *_Nullable)errorPtr;

/**
 * This method is used to read the header, metadata & thumbnail sections of a cloud file.
 * As such, the data you pass can be a partially downloaded cloud file.
 *
 * Pass nil/NULL for anything you don't expect to be in the (partial) data,
 * and this method will skip attempting to read that section.
 *
 * For example, if you only downloaded the header & metadata, simply pass null for the thumbnail,
 * and the code won't bother reading/decrypting that section.
 */
+ (BOOL)decryptCloudFileData:(NSData *)cloudFileData
           withEncryptionKey:(NSData *)encryptionKey
                      header:(ZDCCloudFileHeader *_Nullable)headerPtr
                 rawMetadata:(NSData *_Nullable *_Nullable)metadataPtr
                rawThumbnail:(NSData *_Nullable *_Nullable)thumbnailPtr
                       error:(NSError *_Nullable *_Nullable)errorPtr;

/**
 * This method is used to read the header, metadata & thumbnail sections of a cloud file.
 * As such, the URL you pass can be a partially downloaded cloud file.
 * 
 * Pass nil/NULL for anything you don't expect to be in the (partial) data,
 * and this method will skip attempting to read that section.
 *
 * For example, if you only downloaded the header & metadata, simply pass null for the thumbnail,
 * and the code won't bother reading/decrypting that section.
 */
+ (BOOL)decryptCloudFileURL:(NSURL *)cloudFileURL
          withEncryptionKey:(NSData *)encryptionKey
                     header:(ZDCCloudFileHeader *_Nullable)headerPtr
                rawMetadata:(NSData *_Nullable *_Nullable)metadataPtr
               rawThumbnail:(NSData *_Nullable *_Nullable)thumbnailPtr
                      error:(NSError *_Nullable *_Nullable)errorPtr;

/**
 * This method can be used to decrypt bytes from the middle of a cloud file.
 *
 * @param cloudFileBlocks
 *   Data from the cloud file.
 *   The length of this data must be a perfect multiple of encryptionKey.length.
 *
 * @param byteOffset
 *   The offset (in bytes) of cloudFileBlocks, from the very beginning of the cloud file.
 *   This value must be a perfect multiple of kZDCNode_TweakBlockSizeInBytes.
 *
 * @param encryptionKey
 *   The symmetric key used to encrypt/decrypt the file.
 *
 * @param errorPtr
 *   If an error occurs, this will tell you what went wrong.
 *
 * @return The decrypted cleartext data if the decryption process was successful. Nil otherwise.
 */
+ (nullable NSData *)decryptCloudFileBlocks:(NSData *)cloudFileBlocks
                             withByteOffset:(uint64_t)byteOffset
                              encryptionKey:(NSData *)encryptionKey
                                      error:(NSError *_Nullable *_Nullable)errorPtr;

@end

NS_ASSUME_NONNULL_END
