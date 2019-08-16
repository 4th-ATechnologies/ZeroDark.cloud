/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

/**
 * Encapsulates information about a multipart operation.
 *
 * Multipart operations are used when the file/data being uploaded is above a size threshold.
 * When this scenario occurs, the data is split into multiple files during the upload,
 * in order to facilitate resuming long upload operations which may get interrupted.
 *
 * This includes information used by the PushManager while the application is running.
 * It is for use solely by the ZeroDarkCloud framework.
 */
@interface ZDCCloudOperation_MultipartInfo : NSObject <NSCoding, NSCopying>

@property (nonatomic, copy, readwrite) NSString *stagingPath;
@property (nonatomic, copy, readwrite) NSString *sha256Hash;
@property (nonatomic, copy, readwrite) NSString *uploadID;

@property (nonatomic, copy, readwrite) NSData *rawMetadata;
@property (nonatomic, copy, readwrite) NSData *rawThumbnail;

@property (nonatomic, assign, readwrite) uint64_t cloudFileSize;
@property (nonatomic, assign, readwrite) uint64_t chunkSize;

@property (nonatomic, copy, readwrite) NSDictionary<NSNumber*, NSString*> *checksums;

@property (nonatomic, copy, readwrite) NSDictionary<NSNumber*, NSString*> *eTags;

@property (nonatomic, assign, readwrite) BOOL needsAbort;
@property (nonatomic, assign, readwrite) BOOL needsSkip;

@property (nonatomic, readonly) NSUInteger numberOfParts;

- (BOOL)isEqual:(id)another;

@end
