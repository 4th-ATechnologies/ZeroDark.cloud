/**
 * Storm4
 * https://www.storm4.cloud
**/

#import "S4DeepCopy.h"

@implementation NSDictionary (S4DeepCopy)

- (id)deepCopyWithOptions:(S4DeepCopyOptions)options
{
	NSMutableDictionary *deepCopy = [NSMutableDictionary dictionaryWithCapacity:[self count]];
	
	[self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		// JSON requirement:
		// All objects are instances of NSString, NSNumber, NSArray, NSDictionary, or NSNull.
		
		if ([obj isKindOfClass:[NSString class]])
		{
			// NSString can be immutable or mutable
			
			if (options & S4DeepCopy_MutableLeaves)
				deepCopy[key] = [obj mutableCopy];
			else
				deepCopy[key] = [obj copy];
		}
		else if ([obj isKindOfClass:[NSNumber class]] ||
		         [obj isKindOfClass:[NSNull class]])
		{
			// NSNumber is immutable.
			// NSNull is a singleton (immutable).
			
			deepCopy[key] = obj;
		}
		else if ([obj isKindOfClass:[NSArray class]] ||
		         [obj isKindOfClass:[NSDictionary class]])
		{
			deepCopy[key] = [obj deepCopyWithOptions:options];
		}
		else
		{
			NSAssert(NO, @"Object is not JSON compatible");
		}
	}];
	
	if (options & S4DeepCopy_MutableContainers)
		return deepCopy;
	else
		return [deepCopy copy];
}

@end

@implementation NSArray (S4DeepCopy)

- (id)deepCopyWithOptions:(S4DeepCopyOptions)options
{
	NSMutableArray *deepCopy = [NSMutableArray arrayWithCapacity:[self count]];
	
	for (id obj in self)
	{
		// JSON requirement:
		// All objects are instances of NSString, NSNumber, NSArray, NSDictionary, or NSNull.
		
		if ([obj isKindOfClass:[NSString class]])
		{
			// NSString can be immutable or mutable
			
			if (options & S4DeepCopy_MutableLeaves)
				[deepCopy addObject:[obj mutableCopy]];
			else
				[deepCopy addObject:[obj copy]];
		}
		else if ([obj isKindOfClass:[NSNumber class]] ||
					[obj isKindOfClass:[NSNull class]])
		{
			// NSNumber is immutable.
			// NSNull is a singleton (immutable).
			
			[deepCopy addObject:obj];
		}
		else if ([obj isKindOfClass:[NSArray class]] ||
					[obj isKindOfClass:[NSDictionary class]])
		{
			[deepCopy addObject:[obj deepCopyWithOptions:options]];
		}
		else
		{
			NSAssert(NO, @"Object is not JSON compatible");
		}
	}
	
	if (options & S4DeepCopy_MutableContainers)
		return deepCopy;
	else
		return [deepCopy copy];
}

@end
