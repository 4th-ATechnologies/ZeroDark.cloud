/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "NSURLRequest+ZeroDark.h"

@implementation NSURLRequest (ZeroDark)

- (NSString *)zdcDescription
{
	NSMutableString *dsc = [NSMutableString string];
	
	[dsc appendFormat:@"%@\n", self.URL];
	[dsc appendFormat:@"%@ %@ HTTP/X.Y\n", self.HTTPMethod, [self.URL path]];
	[dsc appendFormat:@"Host: %@\n", [self.URL host]];
	
	NSDictionary <NSString *,NSString *> *headers = self.allHTTPHeaderFields;
	[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		
		[dsc appendFormat:@"%@: %@\n", key, value];
	}];
	
	return dsc;
}

@end
