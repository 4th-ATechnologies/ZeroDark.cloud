/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCPullTaskResult.h"

@implementation ZDCPullTaskResult

@synthesize pullResult = pullResult;
@synthesize pullErrorReason = pullErrorReason;
@synthesize httpStatusCode = httpStatusCode;
@synthesize underlyingError = underlyingError;

+ (ZDCPullTaskResult *)success
{
	ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
	result.pullResult = ZDCPullResult_Success;
	
	return result;
}

/**
 * For logging & debugging.
 */
- (NSString *)description
{
	if (pullResult == ZDCPullResult_Success) {
		return @"Success";
	}
	if (pullResult == ZDCPullResult_ManuallyAborted) {
		return @"ManuallyAborted";
	}
	
	NSMutableString *description = [NSMutableString stringWithCapacity:100];
	
	switch (pullResult)
	{
		case ZDCPullResult_Fail_Auth         : [description appendString:@"Fail_Auth"];         break;
		case ZDCPullResult_Fail_CloudChanged : [description appendString:@"Fail_CloudChanged"]; break;
		case ZDCPullResult_Fail_Other        : [description appendString:@"Fail_Other"];        break;
		default                              : [description appendString:@"Fail_Unknown"];      break;
	}
	
	[description appendString:@": "];
	
	switch (pullErrorReason)
	{
		case ZDCPullErrorReason_Auth0Error:
			[description appendString:@"Auth0"]; break;
			
		case ZDCPullErrorReason_AwsAuthError:
			[description appendString:@"AwsAuth"]; break;
			
		case ZDCPullErrorReason_ExceededMaxRetries:
			[description appendString:@"ExceededMaxRetries"]; break;
			
		case ZDCPullErrorReason_BadData:
			[description appendString:@"BadData"]; break;
			
		case ZDCPullErrorReason_HttpStatusCode:
			[description appendString:@"HttpStatusCode"]; break;
			
		case ZDCPullErrorReason_LocalTreesystemChanged:
			[description appendString:@"LocalTreesystemChanged"]; break;
			
		default:
			[description appendString:@"?"]; break;
	}
	
	if (httpStatusCode != 0) {
		[description appendFormat:@": %ld", (long)httpStatusCode];
	}
	
	if (underlyingError) {
		[description appendFormat:@": %@", underlyingError];
	}
	
	return description;
}

@end
