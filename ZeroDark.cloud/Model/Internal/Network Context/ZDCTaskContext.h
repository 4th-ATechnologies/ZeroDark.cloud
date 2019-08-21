/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

#import "ZDCCloudOperation.h"
#import "ZDCCloudLocator.h"
#import "ZDCCryptoFile.h"     // ZDCCryptoFileFormat

/**
 * Utility class used by the PullManager.
 */
@interface ZDCTaskContext : ZDCObject <NSCoding, NSCopying>

- (instancetype)initWithOperation:(ZDCCloudOperation *)operation;

// Operation info

@property (nonatomic, copy, readonly) NSUUID   * operationUUID;
@property (nonatomic, copy, readonly) NSString * pipeline;
@property (nonatomic, copy, readonly) NSString * localUserID;
@property (nonatomic, copy, readonly) NSString * zAppID;

// Context properties

@property (nonatomic, copy, readwrite) NSString *eTag;

@property (nonatomic, assign, readwrite) BOOL multipart_initiate;
@property (nonatomic, assign, readwrite) BOOL multipart_complete;
@property (nonatomic, assign, readwrite) BOOL multipart_abort;
@property (nonatomic, assign, readwrite) NSUInteger multipart_index;

@property (nonatomic, strong, readwrite) NSURL * uploadFileURL;

#if TARGET_OS_IPHONE

@property (nonatomic, assign, readwrite) BOOL deleteUploadFileURL;

#else // macOS

@property (nonatomic, strong, readwrite) NSData *uploadData;
@property (nonatomic, strong, readwrite) NSInputStream *uploadStream;

#endif

@property (nonatomic, copy, readwrite) NSSet<NSUUID *> *duplicateOpUUIDs;
@property (nonatomic, copy, readwrite) NSString *sha256Hash;

// Ephemeral properties

@property (nonatomic, strong, readwrite) NSProgress *progress;

@end
