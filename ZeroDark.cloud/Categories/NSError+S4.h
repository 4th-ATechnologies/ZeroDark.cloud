/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

@interface NSError (S4)

extern NSString *const S4FrameworkErrorDomain;

+ (NSError *)errorWithS4Error:(S4Err)err;

@end
