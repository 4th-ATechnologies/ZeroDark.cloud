/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSError (ZeroDark)

+ (NSString *)domainForClass:(Class)cls;

+ (NSError *)errorWithClass:(Class)cls code:(NSInteger)code;
+ (NSError *)errorWithClass:(Class)cls code:(NSInteger)code description:(nullable NSString *)description;

@end

NS_ASSUME_NONNULL_END
