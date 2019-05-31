#import <Foundation/Foundation.h>
#import "S3ObjectInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface S3Response_ListBucket : NSObject <NSCoding, NSCopying>

@property (nonatomic, readonly) NSUInteger maxKeys;
@property (nonatomic, readonly) BOOL isTruncated;

@property (nonatomic, readonly, copy, nullable) NSString *prefix;

@property (nonatomic, readonly, copy, nullable) NSString *prevContinuationToken;
@property (nonatomic, readonly, copy, nullable) NSString *nextContinuationToken;

@property (nonatomic, readonly, copy, nullable) NSArray<S3ObjectInfo *> *objectList;

@end

NS_ASSUME_NONNULL_END

