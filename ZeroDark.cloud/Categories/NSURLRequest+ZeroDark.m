/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
