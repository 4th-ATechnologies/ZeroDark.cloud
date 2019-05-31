#import <Foundation/Foundation.h>

#import "ZDCConstants.h"
#import "ZDCCryptoFile.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The FileReader class provides random access to an encrypted file.
 *
 * That is, it allows you to open an encrypted file on disk,
 * and read from that file (using random access) as if the file were cleartext (not encrypted).
 */
@interface ZDCFileReader : NSObject

/**
 * Initializes a new FileReader with the encapsulated information from the cryptoFile instance.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile;

/**
 * Designated initializer.
 */
- (instancetype)initWithFileURL:(NSURL *)fileURL
                         format:(ZDCCryptoFileFormat)format
                  encryptionKey:(NSData *)encryptionKey
                    retainToken:(nullable id)retainToken;

/**
 * This property is available anytime after the stream has been opened.
 */
@property (nonatomic, strong, readonly, nullable) NSNumber *cleartextFileSize;

/**
 * Attempts to open the underlying file on disk.
 *
 * @param errorOut
 *   Pass a non-nil error pointer to receive the reason for an error.
 *
 * @return
 *   YES if the file was successfully opened. NO otherwise.
 */
- (BOOL)openFileWithError:(NSError *_Nullable *_Nullable)errorOut;

/**
 * @param buffer
 *   An allocated buffer where the read bytes are to be stored.
 *   The buffer must be at least as big as range.length.
 * 
 * @param range
 *   The range of the data to read.
 *   This range is expressed as if the underlying file was cleartext.
 *   That is, you don't have to worry about the encryption stuff - all translation is done for you.
 * 
 * @param errorOut
 *   If the returned value is negative, this will contain the error that occurred.
**/
- (ssize_t)getBytes:(void *)buffer range:(NSRange)range error:(NSError **)errorOut;

/**
 * Optional manual close method.
 * Underlying stream will automatically close if ZDCFileReader is deallocated.
 */
- (void)close;

@end

NS_ASSUME_NONNULL_END
