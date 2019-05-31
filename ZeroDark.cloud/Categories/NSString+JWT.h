/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

@interface NSString (JWT)

+(NSString*) subFromJWTString:(NSString*)token withError:(NSError**)errorOut;
+(NSDate*)  expireDateFromJWTString:(NSString*)token withError:(NSError**)errorOut;


@end
