/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSData+ZeroDark.h"

#import "NSError+S4.h"
#import <S4Crypto/S4Crypto.h>


@implementation NSData (ZeroDark)

static uint32_t xor32(uint32_t in32, void *keydata)
{
	uint8_t* p = keydata;
	uint32_t result = S4_Load32(&p);
	
	result ^= in32;
	
	return result;
}

/**
 * See header file for description.
 */
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
			
			break;
		}
	}
	
	return [[NSData alloc] initWithBytesNoCopy:outBytes length:o freeWhenDone:YES];
}

/**
 * See header file for description.
 */
- (NSData *)encryptedWithSymmetricKey:(NSData *)key error:(NSError **)errorOut
{
	NSMutableData*   encryptedData = nil;
	NSError*         error = nil;
	S4Err            err = kS4Err_NoErr;
	Cipher_Algorithm algo = kCipher_Algorithm_Invalid;
	
	uint8_t*         ciphertext = NULL;
	size_t           ciphertextLength = 0;

	uint32_t         checksum = 0;
	uint8_t          checkSumBytes[4];

	switch (key.length) // numBytes * 8 == numBits
	{
		case 32 : algo = kCipher_Algorithm_AES128; break;
		case 64 : algo = kCipher_Algorithm_2FISH256; break;
		default : RETERR(kS4Err_BadParams);
	}
	
	err = HASH_DO(kHASH_Algorithm_xxHash32,
	              self.bytes, self.length,
	      (void *)&checksum, sizeof(checksum)); CKERR;
	
	checksum = xor32(checksum, (uint8_t *)key.bytes);
	
	uint8_t *p = checkSumBytes;
	S4_Store32(checksum, &p);
	
	err = CBC_EncryptPAD(algo,
	          (uint8_t *)key.bytes,
	          (uint8_t *)key.bytes + key.length/2,
	                     self.bytes, self.length,
	                     &ciphertext, &ciphertextLength); CKERR;
	
	encryptedData = [NSMutableData dataWithCapacity:(sizeof(checkSumBytes) + ciphertextLength)];
	
	[encryptedData appendBytes:checkSumBytes length:sizeof(checkSumBytes)];
	[encryptedData appendBytes:ciphertext length:ciphertextLength];
	
done:
	
	if (ciphertext) {
		XFREE(ciphertext);
	}
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if(errorOut) *errorOut = error;
	return encryptedData;
}

/**
 * See header file for description.
 */
- (NSData *)decryptedWithSymmetricKey:(NSData *)key error:(NSError **)errorOut
{
	NSData*          decryptedData = nil;
	NSError*         error = nil;
	S4Err            err = kS4Err_NoErr;
	Cipher_Algorithm algo = kCipher_Algorithm_Invalid;
	
	uint8_t*         ciphertext = NULL;
	size_t           ciphertextLength = 0;

	uint8_t*         plaintext = NULL;
	size_t           plaintextLength = 0;
	
	uint32_t         checkSumA = 0;
	uint32_t         checkSumB = 0;

	switch (key.length) // numBytes * 8 == numBits
	{
		case 32 : algo = kCipher_Algorithm_AES128; break;
		case 64 : algo = kCipher_Algorithm_2FISH256; break;
		default : RETERR(kS4Err_BadParams);
	}
	
	if (self.length < 5) {
		RETERR(kS4Err_BadParams);
	}
	
	uint8_t *p = (uint8_t *)self.bytes;
	checkSumA = S4_Load32(&p);
	
	ciphertext = p;
	ciphertextLength = self.length - sizeof(uint32_t);
	
	err = CBC_DecryptPAD(algo,
	          (uint8_t *)key.bytes,
	          (uint8_t *)key.bytes + key.length/2,
	                     ciphertext, ciphertextLength,
	                     &plaintext, &plaintextLength); CKERR;
	
	err = HASH_DO(kHASH_Algorithm_xxHash32,
	              plaintext, plaintextLength,
	      (void *)&checkSumB, sizeof(checkSumB)); CKERR;
	checkSumB = xor32(checkSumB, (uint8_t *)key.bytes);
	
	if (checkSumA != checkSumB) {
		RETERR(kS4Err_CorruptData);
	}
	
	decryptedData = [NSData dataWithBytesNoCopy:plaintext length:plaintextLength freeWhenDone:YES];
	
done:
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (errorOut) *errorOut = error;
	return decryptedData;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Base58
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

static const int8_t base58map[] = {
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, -1, -1, -1, -1, -1, -1,
	-1, 9, 10, 11, 12, 13, 14, 15, 16, -1, 17, 18, 19, 20, 21, -1,
	22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, -1, -1, -1, -1, -1,
	-1, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, -1, 44, 45, 46,
	47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, -1, -1, -1, -1, -1
};

static const UniChar base58chars[] = {
	'1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P',
	'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n',
	'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
};

- (NSString *)base58String
{
	NSData *d = self;
	size_t i, z = 0;
	
	while (z < d.length && ((const uint8_t *)d.bytes)[z] == 0) z++; // count leading zeroes
	
	uint8_t buf[(d.length - z)*138/100 + 1]; // log(256)/log(58), rounded up
	memset(buf, 0, sizeof(buf));
	
	for (i = z; i < d.length; i++) {
		uint32_t carry = ((const uint8_t *)d.bytes)[i];
		
		for (ssize_t j = sizeof(buf) - 1; j >= 0; j--) {
			carry += (uint32_t)buf[j] << 8;
			buf[j] = carry % 58;
			carry /= 58;
		}
	}
	
	i = 0;
	while (i < sizeof(buf) && buf[i] == 0) i++; // skip leading zeroes
	
	CFMutableStringRef s = CFStringCreateMutable(kCFAllocatorDefault, z + sizeof(buf) - i);
	while (z-- > 0) CFStringAppendCharacters(s, base58chars, 1);
	while (i < sizeof(buf)) CFStringAppendCharacters(s, &base58chars[buf[i++]], 1);
	ZERO(buf, sizeof(buf));
	return CFBridgingRelease(s);
}

/**
 * See header file for description.
 */
+ (nullable NSData *)dataFromBase58String:(NSString *)string;
{
	// From:
	// https://github.com/voisine/breadwallet
	
	size_t i, z = 0;
	
	// Check all chars are allowed
	BOOL pass;
	for (NSUInteger w = 0; w < string.length; ++w) {
		pass = false;
		for (NSUInteger q = 0; q < 59; ++q)
			if ( [string characterAtIndex:w] == base58chars[q] )
				pass = true;
		if ( !pass )
			return nil;
	}
	
	// Decode
	while (z < string.length && [string characterAtIndex:z] == *base58chars) z++; // count leading zeroes
	
	uint8_t buf[(string.length - z)*733/1000 + 1]; // log(58)/log(256), rounded up
	memset(buf, 0, sizeof(buf));
	
	for (i = z; i < string.length; i++) {
		
		UniChar c = [string characterAtIndex:i];
		
		if (c >= sizeof(base58map)/sizeof(*base58map) || base58map[c] == -1) break; // invalid base58 digit
		
		uint32_t carry = (uint32_t)base58map[c];
		
		for (ssize_t j = (ssize_t)sizeof(buf) - 1; j >= 0; j--) {
			carry += (uint32_t)buf[j]*58;
			buf[j] = carry & 0xff;
			carry >>= 8;
		}
	}
	i = 0;
	
	while (i < sizeof(buf) && buf[i] == 0) i++; // skip leading zeroes
	
	NSMutableData *d = [NSMutableData dataWithCapacity:z + sizeof(buf) - i];
	d.length = z;
	[d appendBytes:&buf[i] length:sizeof(buf) - i];
	ZERO(buf, sizeof(buf));
	return [d copy];
}

@end
