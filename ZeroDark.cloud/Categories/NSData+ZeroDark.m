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

static uint32_t xor32 (uint32_t in32, void *keydata)
{
	uint8_t* p = keydata;
	uint32_t result = S4_Load32(&p);
	
	result ^= in32;
	
	return result;
}

- (NSData *)encryptedDataWithSymmetricKey:(NSData *)key error:(NSError **)errorOut
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

- (NSData *)decryptedDataWithSymmetricKey:(NSData *)key error:(NSError **)errorOut
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

@end
