/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSError+S4.h"


@implementation NSError (S4)

NSString *const S4FrameworkErrorDomain   =   @"S4FrameworkErrorDomain";

+ (NSError *)errorWithS4Error:(S4Err)err
{
	char errorBuf[256];
//	S4_GetErrorString(err, sizeof(errorBuf), errorBuf);
	S4_GetErrorString(err, errorBuf);
	
	NSString *errStr = [NSString stringWithUTF8String:errorBuf];
	
	NSDictionary *userInfo = nil;
	if (errStr) {
		userInfo = @{ NSLocalizedDescriptionKey: errStr };
	}
	
	return [NSError errorWithDomain:S4FrameworkErrorDomain code:err userInfo:userInfo];
}

@end
