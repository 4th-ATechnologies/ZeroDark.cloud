#import "S3Response.h"
#import "S3ObjectInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface S3Response ()

@property (nonatomic, assign, readwrite) S3ResponseType type;

@property (nonatomic, strong, readwrite) S3Response_ListBucket *listBucket;
@property (nonatomic, strong, readwrite) S3Response_InitiateMultipartUpload *initiateMultipartUpload;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface S3Response_ListBucket ()

@property (nonatomic, readwrite, assign) NSUInteger maxKeys;
@property (nonatomic, readwrite, assign) BOOL isTruncated;

@property (nonatomic, readwrite, copy, nullable) NSString *prefix;

@property (nonatomic, readwrite, copy, nullable) NSString *prevContinuationToken;
@property (nonatomic, readwrite, copy, nullable) NSString *nextContinuationToken;

@property (nonatomic, readwrite, copy, nullable) NSArray<S3ObjectInfo *> *objectList;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface S3Response_InitiateMultipartUpload ()

@property (nonatomic, readwrite, copy, nullable) NSString *bucket;
@property (nonatomic, readwrite, copy, nullable) NSString *key;
@property (nonatomic, readwrite, copy, nullable) NSString *uploadID;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface S3ObjectInfo ()

@property (nonatomic, readwrite, copy, nullable) NSString *key;
@property (nonatomic, readwrite, copy, nullable) NSString *eTag;
@property (nonatomic, readwrite, strong, nullable) NSDate *lastModified;
@property (nonatomic, readwrite, assign) uint64_t size;
@property (nonatomic, readwrite, assign) S3StorageClass storageClass;

@end

NS_ASSUME_NONNULL_END
