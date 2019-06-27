/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
