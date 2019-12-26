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

@interface NSArray (S4)

+ (NSArray<NSNumber*> *)arc4RandomArrayWithCount:(NSUInteger)count;

@end
