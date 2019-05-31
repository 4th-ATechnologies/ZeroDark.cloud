/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "NSError+Auth0API.h"

/* extern */ NSString *const Auth0APIManagerErrorDataKey = @"com.auth0.authentication.error";
 
@implementation NSError (Auth0API)

- (nullable NSString *)auth0API_error
{
	id result = self.userInfo[Auth0APIManagerErrorDataKey];
	
	if ([result isKindOfClass:[NSString class]]) {
		return (NSString *)result;
	}
	else {
		return nil;
	}
}

@end
