/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
**/

#import "NSMutableURLRequest+ZeroDark.h"

@implementation NSMutableURLRequest (ZeroDark)

- (void)setHTTPRange:(NSRange)byteRange
{
	NSString *rangeString =
	  [NSString stringWithFormat:@"bytes=%llu-%llu",
	    (unsigned long long)(byteRange.location),
	    (unsigned long long)(byteRange.location + byteRange.length - 1)];
	
	[self setValue:rangeString forHTTPHeaderField:@"Range"];
}

@end
