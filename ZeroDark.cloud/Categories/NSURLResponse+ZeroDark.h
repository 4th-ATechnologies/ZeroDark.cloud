/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURLResponse (ZeroDark)

- (NSInteger)httpStatusCode;

- (nullable NSString *)eTag;
- (nullable NSDate *)lastModified;

@end

NS_ASSUME_NONNULL_END
