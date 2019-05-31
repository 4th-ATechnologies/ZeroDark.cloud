#import <Foundation/Foundation.h>

#import "S3Response_ListBucket.h"
#import "S3Response_InitiateMultipartUpload.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, S3ResponseType) {
	S3ResponseType_ListBucket,
	S3ResponseType_InitiateMultipartUpload,
	
	S3ResponseType_Unknown = NSIntegerMax
};


@interface S3Response : NSObject <NSCoding, NSCopying>

@property (nonatomic, readonly) S3ResponseType type;

@property (nonatomic, readonly) S3Response_ListBucket *listBucket;
@property (nonatomic, readonly) S3Response_InitiateMultipartUpload *initiateMultipartUpload;

@end

NS_ASSUME_NONNULL_END
