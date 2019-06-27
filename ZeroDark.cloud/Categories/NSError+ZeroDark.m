/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "NSError+ZeroDark.h"

@implementation NSError (ZeroDark)

+ (NSString *)domainForClass:(Class)cls
{
	return NSStringFromClass(cls);
}

+ (NSError *)errorWithClass:(Class)cls code:(NSInteger)code
{
	return [self errorWithClass:cls code:code description:nil];
}

+ (NSError *)errorWithClass:(Class)cls code:(NSInteger)code description:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = [self domainForClass:cls];
	return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

@end
