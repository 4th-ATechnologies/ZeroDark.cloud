/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

@interface NSString (JWT)

+(NSString*) subFromJWTString:(NSString*)token withError:(NSError**)errorOut;
+(NSDate*)  expireDateFromJWTString:(NSString*)token withError:(NSError**)errorOut;


@end
