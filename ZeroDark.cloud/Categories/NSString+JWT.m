/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSString+JWT.h"
#import <JWT/JWT.h>

@implementation NSString (JWT)

+(NSString*) subFromJWTString:(NSString*)token withError:(NSError**)errorOut
{
    NSString* result = NULL;
    
    JWTBuilder *builder = [JWTBuilder decodeMessage:token].options(@(YES));
    NSDictionary *decoded = builder.decode;
    NSError* jwtError = builder.jwtError;
    
    if(!jwtError)
    {
        NSDictionary* payload = decoded[@"payload"];
        if (payload)
        {
            result  = payload[@"sub"];
        }
    }
    else
    {
        if(errorOut)
            *errorOut = jwtError;
    }
    return result;
    
}

+ (NSDate *)expireDateFromJWTString:(NSString *)token withError:(NSError **)errorOut
{
    NSDate* result = NULL;
    
    JWTBuilder *builder = [JWTBuilder decodeMessage:token].options(@(YES));
    NSDictionary *decoded = builder.decode;
    NSError* jwtError = builder.jwtError;
    
    if(!jwtError)
    {
        NSDictionary* payload = decoded[@"payload"];
        if (payload)
        {
            NSNumber* timeStamp = payload[@"exp"];
            result =  [NSDate dateWithTimeIntervalSince1970:timeStamp.doubleValue];
        }
    }
    else
    {
        if(errorOut)
            *errorOut = jwtError;
    }
    return result;

}


@end
