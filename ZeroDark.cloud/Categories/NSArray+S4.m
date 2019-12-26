/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSArray+S4.h"
#import "NSData+S4.h"
#import "NSError+S4.h"
#import "NSString+S4.h"

@implementation NSArray (S4)

+ (NSArray<NSNumber*> *)arc4RandomArrayWithCount:(NSUInteger)count
{
	NSMutableArray *randArray = [NSMutableArray arrayWithCapacity:count];
	
	for (int i = 0; i < count; ) {
		
		NSNumber* num = [NSNumber numberWithInt: arc4random() % count];
		if([randArray containsObject:num]) continue;
		
		[randArray addObject:num];
		i++;
	}
	
	return randArray;
}

@end
