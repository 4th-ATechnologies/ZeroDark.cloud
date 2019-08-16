/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

@interface NSError (S4)

extern NSString *const S4FrameworkErrorDomain;

+ (NSError *)errorWithS4Error:(S4Err)err;

@end
