/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

@interface NSString (JWT)

+(NSString*) subFromJWTString:(NSString*)token withError:(NSError**)errorOut;
+(NSDate*)  expireDateFromJWTString:(NSString*)token withError:(NSError**)errorOut;


@end
