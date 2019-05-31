#import <Foundation/Foundation.h>


@interface S3Response_InitiateMultipartUpload : NSObject <NSCoding, NSCopying>

@property (nonatomic, readonly, copy, nullable) NSString *bucket;
@property (nonatomic, readonly, copy, nullable) NSString *key;
@property (nonatomic, readonly, copy, nullable) NSString *uploadID;

@end
