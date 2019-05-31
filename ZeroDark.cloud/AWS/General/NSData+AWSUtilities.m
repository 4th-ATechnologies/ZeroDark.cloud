#import "NSData+AWSUtilities.h"


@implementation NSData (AWSUtilities)

/**
 * Credit: Stack Overflow User: "Moose"
 * http://stackoverflow.com/a/33501154/43522
**/
- (NSString *)lowercaseHexString
{
	static char _NSData_BytesConversionString_[512] =
	  "000102030405060708090a0b0c0d0e0f"
	  "101112131415161718191a1b1c1d1e1f"
	  "202122232425262728292a2b2c2d2e2f"
	  "303132333435363738393a3b3c3d3e3f"
	  "404142434445464748494a4b4c4d4e4f"
	  "505152535455565758595a5b5c5d5e5f"
	  "606162636465666768696a6b6c6d6e6f"
	  "707172737475767778797a7b7c7d7e7f"
	  "808182838485868788898a8b8c8d8e8f"
	  "909192939495969798999a9b9c9d9e9f"
	  "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf"
	  "b0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
	  "c0c1c2c3c4c5c6c7c8c9cacbcccdcecf"
	  "d0d1d2d3d4d5d6d7d8d9dadbdcdddedf"
	  "e0e1e2e3e4e5e6e7e8e9eaebecedeeef"
	  "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff";
	
	uint16_t* mapping = (uint16_t*)_NSData_BytesConversionString_;
	register uint16_t len = self.length;
	char* hexChars = (char*)malloc( sizeof(char) * (len*2) );
	register uint16_t* dst = ((uint16_t *)hexChars) + len-1;
	register unsigned char* src = (unsigned char *)self.bytes + len-1;
	
	while (len--) *dst-- = mapping[*src--];
	
	NSString *retVal = [[NSString alloc] initWithBytesNoCopy:hexChars
	                                                  length:self.length*2
	                                                encoding:NSASCIIStringEncoding
	                                            freeWhenDone:YES];
	
	return retVal;
}

@end
