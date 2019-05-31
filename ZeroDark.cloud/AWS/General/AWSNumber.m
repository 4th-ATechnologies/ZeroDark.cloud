#import "AWSNumber.h"


@implementation AWSNumber

+ (BOOL)parseUInt64:(uint64_t *)valuePtr fromString:(NSString *)string
{
	// On both 32-bit and 64-bit machines, unsigned long long = 64 bit
	
	errno = 0;
	uint64_t value = strtoull([string UTF8String], NULL, 10);
	
	// From the manpage:
	//
	// If no conversion could be performed, 0 is returned and the global variable errno is set to EINVAL.
	// If an overflow or underflow occurs, errno is set to ERANGE and the function return value is clamped.
	//
	// Clamped means it will be TYPE_MAX or TYPE_MIN.
	// If overflow/underflow occurs, returning a clamped value is more accurate then returning zero.
	
	if (valuePtr) *valuePtr = value;
	return (errno == 0);
}

@end
