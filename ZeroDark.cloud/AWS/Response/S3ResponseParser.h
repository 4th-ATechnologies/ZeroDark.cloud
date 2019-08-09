#import <Foundation/Foundation.h>
#import "S3Response.h"

NS_ASSUME_NONNULL_BEGIN

@interface S3ResponseParser : NSObject

/**
 * Parses the given XML response from Amazon S3 (as raw NSData).
 */
+ (nullable S3Response *)parseXMLData:(NSData *)data;

/**
 * Parses the given JSON response (still in raw NSData form).
 */
+ (nullable S3Response *)parseJSONData:(NSData *)data withType:(S3ResponseType)type;

/**
 * Parses the given JSON response.
 */
+ (nullable S3Response *)parseJSONDict:(NSDictionary *)dict withType:(S3ResponseType)type;

/**
 * Attempts to parse an S3 item.
 */
+ (nullable S3ObjectInfo *)parseObjectInfo:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
