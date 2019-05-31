#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AWSURL : NSObject

/**
 * Performs percent encoding for the query components of a URL.
**/
+ (NSString *)urlEncodeQueryKeyOrValue:(NSString *)unencodedKeyOrValue;

/**
 * Performs percent encoding for an individual path component of a URL.
**/
+ (NSString *)urlEncodePathComponent:(NSString *)unencodedPathComponent;

@end

NS_ASSUME_NONNULL_END
