/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
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
