/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import "ZDCCryptoFile.h"

@class ZDCDataPromise;

NS_ASSUME_NONNULL_BEGIN

/**
 * ZDData is used to upload data (of any size).
 *
 * It's used by the ZeroDarkCloudDelegate protocol.
 * Whenever the framework is ready to upload a node or message, it asks the delegate for the data.
 * Since the framework supports everything from small objects to multi-gigabyte files,
 * the ZDCData class is used to encapsulate the response.
 *
 * For small items, you can create a ZDCData container with the raw in-memory data.
 * For example, if you're uploading a serialized object, you can simply serialize the object,
 * and then wrap the serialized bytes within a ZDCData container.
 *
 * For larger items, the data is typically stored in a file somwehere.
 * In this case, you can create a ZDCData container that points to the file.
 *
 * @note For file uploads, the framework will automatically monitor the file during upload.
 *       If the file is modified, the framework will abort the upload & restart it.
 *       This ensures the file doesn't get corrupted during upload.
 *       (Monitoring is done via ZDCDiskMonitor, and uses both hashing & filesystem notifications
 *       to detect changes.)
 */
@interface ZDCData : NSObject

/**
 * Creates an instance with the given data.
 * Use this when the data you're uploading is small, and can easily fit in memory.
 */
- (instancetype)initWithData:(NSData *)data;

/**
 * Creates an instance with the given cleartext (non-encrypted) file.
 * Use this when the file you're uploading already exists on the disk.
 *
 * @note For file uploads, the framework will automatically monitor the file during upload.
 *       If the file is modified, the framework will abort the upload & restart it.
 */
- (instancetype)initWithCleartextFileURL:(NSURL *)cleartextFileURL;

/**
 * Creates an instance with the given encrypted file.
 * Use this when the file you're uploading already exists on disk.
 *
 * @note For file uploads, the framework will automatically monitor the file during upload.
 *       If the file is modified, the framework will abort the upload & restart it.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile;

/**
 * Creates an instance designed to deliver the data in an asynchronous fashion.
 * The PushManager will wait for you to either fullfill or reject the promise.
 */
- (instancetype)initWithPromise:(ZDCDataPromise *)promise;


/** Returns non-nil if the `initWithData:` constructor was used. */
@property (nullable, nonatomic, copy, readonly) NSData *data;

/** Returns non-nil if the `initWithCleartextFileURL:` constructor was used. */
@property (nullable, nonatomic, strong, readonly) NSURL *cleartextFileURL;

/** Returns non-nil if the `initWithCryptoFile:` constructor was used. */
@property (nullable, nonatomic, strong, readonly) ZDCCryptoFile *cryptoFile;

/** Returns non-nil if the `initAsPromise` constructor was used. */
@property (nullable, nonatomic, strong, readonly) ZDCDataPromise *promise;

/**
 * ZeroDark uses a persistent queue to track which nodes need to be uploaded.
 * Sometimes this means that the same node gets enqueued multiple times.
 * However, this doesn't mean the upload needs to occur multiple times.
 * If you're uploading the latest version of the data,
 * then a single upload will suffice, and the framework can skip the duplicate queued operations.
 *
 * This flag acts as a signal to the framework.
 * When set to true, the framework will automatically skip duplicated queued operations.
 * In other words, it will automatically consolidate upload requests for you.
 *
 * However, there are some apps which require server-side version logging,
 * and need to upload each individual version of a node.
 * In this case, set this value to false to ensure the framework won't consolidate requests,
 * but rather execute each queued upload operation in turn.
 *
 * The default value is YES / true.
 */
@property (nonatomic, readwrite) BOOL isLatestVersion;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A simple promise-like inteface for returning NodeData in an asynchronous fashion.
 */
@interface ZDCDataPromise: NSObject

/**
 * Successfully completes the promise by delivering the data.
 */
- (void)fulfill:(ZDCData *)result;

/**
 * Rejects the promise due to an error.
 * If this happens, the PushManager will treat this as an empty data result.
 */
- (void)reject;

@end

NS_ASSUME_NONNULL_END
