/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSError+POSIX.h"

@implementation NSError (POSIX)

+ (NSError *)errorWithPOSIXCode:(int) code
{
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

@end
