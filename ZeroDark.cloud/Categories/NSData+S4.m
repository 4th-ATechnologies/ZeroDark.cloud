/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSData+S4.h"
#import "NSError+S4.h"

@implementation NSData (S4)

/**
 * See header file for description.
 */
+ (instancetype)secureDataWithLength:(NSUInteger)length
{
	NSData *data = nil;

	void *buffer = XMALLOC(length);
	if (buffer)
	{
		void (^deallocator)(void*, NSUInteger) = ^(void *bytes, NSUInteger length){
			
			ZERO(bytes, length);
			XFREE(bytes);
		};
		
		data = [[NSData alloc] initWithBytesNoCopy:buffer length:length deallocator:deallocator];
	}
	
	return data;
}

/**
 * See header file for description.
 */
+ (nullable NSData *)s4RandomBytes:(NSUInteger)lengthInBytes
{
	NSData *data = nil;
	
	uint8_t *buffer = XMALLOC(lengthInBytes);
	if (buffer)
	{
		if (IsntS4Err(RNG_GetBytes(buffer, lengthInBytes))) // Uses Apple's Common Crypto
		{
			data = [NSData dataWithBytesNoCopy:buffer length:lengthInBytes freeWhenDone:YES];
		}
	}
	
	return data;
}

/**
 * See header file for description.
 */
- (NSString *)zBase32String
{
	const uint8_t *bytes = (const uint8_t *)[self bytes];
	NSUInteger bytesLen = self.length;
	
	size_t x = bytesLen * 8;
	size_t y = 5;
	
	size_t zRad32Len = (x / y + (x % y > 0));
	uint8_t *zRad32Buffer = XMALLOC(zRad32Len);
	
	zbase32_encode(zRad32Buffer, bytes, (unsigned int)(bytesLen * 8));
	
	return [[NSString alloc] initWithBytesNoCopy: zRad32Buffer
	                                      length: zRad32Len
	                                    encoding: NSASCIIStringEncoding
	                                freeWhenDone: YES];
}

/**
 * See header file for description.
 */
+ (nullable NSData *)dataFromZBase32String:(NSString *)string
{
	const uint8_t *bytes = (const uint8_t *)[string UTF8String];
	NSUInteger dataLen = ([string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 7) / 8 * 5;
	
	uint8_t *outBytes = XMALLOC(dataLen);
	int actualLen = zbase32_decode(outBytes, bytes, (unsigned int)dataLen*8);
	
	if (actualLen < 0)
	{
		// String wasn't in zBase32 format
		XFREE(outBytes);
		return nil;
	}
	else
	{
		return [[NSData alloc] initWithBytesNoCopy: outBytes
		                                    length: actualLen
		                              freeWhenDone: YES];
	}
}

/**
 * See header file for description.
 */
- (uint32_t)xxHash32
{
	uint32_t checksum = 0;
	HASH_DO(kHASH_Algorithm_xxHash32,
	        self.bytes, self.length,
	(void *)&checksum, sizeof(checksum));
	
	return checksum;
}

/**
 * See header file for description.
 */
- (uint64_t)xxHash64
{
	uint64_t checksum = 0;
	HASH_DO(kHASH_Algorithm_xxHash64,
	        self.bytes, self.length,
	(void *)&checksum, sizeof(checksum));
	
	return checksum;
}

/**
 * See header file for description.
 */
- (nullable NSData *)hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut
{
	NSError* error = nil;
	NSData *hashData = nil;

	S4Err           err = kS4Err_NoErr;
	uint8_t         hashBuf [512/8];
	HASH_ContextRef hashCtx = kInvalidHASH_ContextRef;
	size_t          hashSize = 0;

	err = HASH_Init(hashAlgor, &hashCtx); CKERR;
	err = HASH_GetSize(hashCtx, &hashSize);CKERR;
	err = HASH_Update(hashCtx, self.bytes, self.length); CKERR;
	err = HASH_Final(hashCtx, hashBuf); CKERR;
	hashData = [NSData dataWithBytes:hashBuf length:hashSize];

done:

	if (hashCtx) {
		HASH_Free(hashCtx);
	}

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if(errorOut) *errorOut = error;
	return hashData;
}

@end
