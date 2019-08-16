/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSData+S4.h"

#import "NSData+AWSUtilities.h"
#import "NSString+ZeroDark.h"
#import "NSError+S4.h"

@implementation NSData (S4)

+ (NSData *)s4RandomBytes:(NSUInteger)length
{
	NSData *data = nil;
	
	uint8_t *randData = XMALLOC(length);
	if (randData)
	{
		if (IsntS4Err(RNG_GetBytes(randData, length)))
		{
			data = [NSData dataWithBytesNoCopy:randData length:length freeWhenDone:YES];
		}
	}
	
	return data;
}

- (NSString *)hexString
{
	// Just use NSData+AWSUtilities code
	//
	return self.lowercaseHexString;
}

+ (NSData *)dataFromHexString:(NSString *)inString
{
    NSMutableString *str = [inString mutableCopy];

    [str replaceOccurrencesOfString:@"<" withString:@"" options:0 range:NSMakeRange(0, str.length)];
    [str replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, str.length)];
    [str replaceOccurrencesOfString:@">" withString:@"" options:0 range:NSMakeRange(0, str.length)];

    NSUInteger inLength = [str length];

    unichar *inCharacters = alloca(sizeof(unichar) * inLength);
    [str getCharacters:inCharacters range:NSMakeRange(0, inLength)];

    UInt8 *outBytes = malloc(sizeof(UInt8) * ((inLength / 2) + 1));

    NSInteger i, o = 0;
    UInt8 outByte = 0;

    for (i = 0; i < inLength; i++) {

        UInt8 c = inCharacters[i];
        SInt8 value = -1;

        if      (c >= '0' && c <= '9') value =      (c - '0');
        else if (c >= 'A' && c <= 'F') value = 10 + (c - 'A');
        else if (c >= 'a' && c <= 'f') value = 10 + (c - 'a');

        if (value >= 0) {

            if (i % 2 == 1) {
                outBytes[o++] = (outByte << 4) | value;
                outByte = 0;

            } else {
                outByte = value;
            }

        } else {

            if (o != 0) break;
        }
    }

    return [[NSData alloc] initWithBytesNoCopy:outBytes length:o freeWhenDone:YES];
}

- (NSString *)zBase32String
{
	const uint8_t *bytes = (const uint8_t *)[self bytes];
	NSUInteger bytesLen = self.length;
	
	size_t x = bytesLen * 8;
	size_t y = 5;
	
	size_t zRad32Len = (x / y + (x % y > 0));
	uint8_t *zRad32Buffer = malloc(zRad32Len);
	
	zbase32_encode(zRad32Buffer, bytes, (unsigned int)(bytesLen * 8));
	
	return [[NSString alloc] initWithBytesNoCopy: zRad32Buffer
	                                      length: zRad32Len
	                                    encoding: NSASCIIStringEncoding
	                                freeWhenDone: YES];
}

+ (NSData *)dataFromZBase32String:(NSString *)string
{
	const uint8_t *bytes = (const uint8_t *)[string UTF8String];
	NSUInteger dataLen = (string.UTF8LengthInBytes + 7) / 8 * 5;
	
	uint8_t *outBytes = malloc(dataLen);
	
	int actualLen = zbase32_decode(outBytes, bytes, (unsigned int)dataLen*8);
	
	return [[NSData alloc] initWithBytesNoCopy: outBytes
	                                    length: actualLen
	                              freeWhenDone: YES];
}

- (uint32_t)xxHash32
{
	uint32_t checksum = 0;
	HASH_DO(kHASH_Algorithm_xxHash32,
	        self.bytes, self.length,
	(void *)&checksum, sizeof(checksum));
	
	return checksum;
}

- (uint64_t)xxHash64
{
	uint64_t checksum = 0;
	HASH_DO(kHASH_Algorithm_xxHash64,
	        self.bytes, self.length,
	(void *)&checksum, sizeof(checksum));
	
	return checksum;
}

+ (instancetype)allocSecureDataWithLength:(NSUInteger)length
{
	NSData* data = NULL;

	void* bytes = XMALLOC(length);
	if(bytes)
	{
		data = [[NSData alloc] initWithBytesNoCopy:bytes
											length:length
									   deallocator:^(void * _Nonnull bytes,
													 NSUInteger length) {
										   ZERO(bytes, length);
										   XFREE(bytes);
									   }];
	}

done:
	return data;
}


- (NSData *)hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut
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
