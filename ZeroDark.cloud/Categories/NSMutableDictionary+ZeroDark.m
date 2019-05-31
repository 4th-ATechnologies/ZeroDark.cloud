#import "NSMutableDictionary+ZeroDark.h"

@implementation NSMutableDictionary (ZeroDark)

static NSString *const kB64Header = @"#B64:";

- (void)normalizeForJSON
{
	for (NSString *key in [self allKeys])
	{
		id obj = self[key];
		if ([obj isKindOfClass:[NSData class]])
		{
			NSString* rad64 = [(NSData*)obj base64EncodedStringWithOptions:0];
			NSString* outStr = [NSString stringWithFormat:@"%@%@", kB64Header, rad64];
			
			self[key] = outStr;
		}
	}
}

- (void)normalizeFromJSON
{
	for (NSString *key in [self allKeys])
	{
		id obj = self[key];
		if ([obj isKindOfClass:[NSString class]])
		{
			NSString* string = (NSString*)obj;
			if ([string hasPrefix:kB64Header])
			{
				NSString *inStr = [string substringFromIndex:kB64Header.length];
				NSData* data = [[NSData alloc] initWithBase64EncodedString:inStr options:0];
				
				self[key] = data;
			}
		}
	}
}

@end
