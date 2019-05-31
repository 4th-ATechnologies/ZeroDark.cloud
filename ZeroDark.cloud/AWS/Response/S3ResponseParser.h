#import <Foundation/Foundation.h>
#import "S3Response.h"

@interface S3ResponseParser : NSObject

/**
 * Parses the given XML response from Amazon S3 (as raw NSData).
**/
+ (S3Response *)parseXMLData:(NSData *)data;

/**
 * Parses the given response if already in JSON format (either raw, or pre-parsed).
**/
+ (S3Response *)parseJSONData:(NSData *)data withType:(S3ResponseType)type;
+ (S3Response *)parseJSONDict:(NSDictionary *)dict withType:(S3ResponseType)type;

@end
