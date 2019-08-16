/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSString+S4.h"
#import "NSData+S4.h"
#import "NSString+ZeroDark.h"
#import <S4Crypto/S4Crypto.h>

@implementation NSString (S4)

#define INT_CEIL(x,y) (x / y + (x % y > 0))

- (NSString *)KDFWithSeedKey:(NSData *)seedKey label:(NSString *)label
{
	S4Err err = kS4Err_NoErr;
	
	NSString *hashString = nil;
	
	size_t zrad32Len = INT_CEIL(seedKey.length * 8, 5);
	uint8_t* zRad32Bufer = malloc(zrad32Len);
	
	uint8_t* hash  = malloc(seedKey.length);
	
	err = MAC_KDF(kMAC_Algorithm_SKEIN,
	              kHASH_Algorithm_SKEIN256,
	              (uint8_t *)seedKey.bytes, seedKey.length,
	              label.UTF8String,
	              (uint8_t *)self.UTF8String , self.UTF8LengthInBytes,
	              (uint32_t)seedKey.length * 8, seedKey.length, hash); CKERR;
	
    zbase32_encode(zRad32Bufer, hash, (unsigned int) seedKey.length * 8);
	
	hashString = [[NSString alloc] initWithBytes:zRad32Bufer length:zrad32Len encoding:NSUTF8StringEncoding];
	
done:
	
	if(hash)  free(hash);
	if(zRad32Bufer) free(zRad32Bufer);
	
	return hashString;
}

/**
 * Convenience method which converts string to UTF-8 data, and then returns hash of it.
 **/
- (NSData *)hashWithAlgorithm:(HASH_Algorithm)hashAlgo error:(NSError **)errorOut
{
    NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
    return [data hashWithAlgorithm:hashAlgo error:errorOut];
}


@end
