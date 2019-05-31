#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, S3StorageClass) {
	S3StorageClass_Standard = 0,
	S3StorageClass_InfrequentAccess,
	S3StorageClass_ReducedRedundancy,
	S3StorageClass_Glacier
};


@interface S3ObjectInfo : NSObject <NSCoding, NSCopying>

@property (nonatomic, copy, readonly, nullable) NSString *key;

@property (nonatomic, copy, readonly, nullable) NSString *eTag;

@property (nonatomic, strong, readonly, nullable) NSDate *lastModified;

@property (nonatomic, assign, readonly) uint64_t size;

@property (nonatomic, assign, readonly) S3StorageClass storageClass;

@end

NS_ASSUME_NONNULL_END
