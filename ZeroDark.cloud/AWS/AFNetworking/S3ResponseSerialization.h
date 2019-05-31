#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>


NS_ASSUME_NONNULL_BEGIN


@interface S3ResponseSerialization : NSObject

/**
 * S3 returns 3 different types of reponses:
 * - XML responses, which should be serialized via S3XMLResponseSerialization
 * - JSON responses, which should be serialized via AFJSONResponseSerializer
 * - Binary responses, which should be kept as NSData
 *
 * This method returns a compound serializer that supports all 3.
**/
+ (AFCompoundResponseSerializer *)serializer;

@end

#pragma mark -

@interface S3XMLResponseSerialization : AFHTTPResponseSerializer

- (instancetype)init;

@end

#pragma mark -

@interface S3BinaryResponseSerialization : AFHTTPResponseSerializer

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
