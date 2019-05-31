/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCDatabaseConfig.h"

@implementation ZDCDatabaseConfig

@synthesize encryptionKey = encryptionKey;
@synthesize serializer;
@synthesize deserializer;
@synthesize preSanitizer;
@synthesize postSanitizer;
@synthesize extensionsRegistration;

- (instancetype)initWithEncryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		encryptionKey = [inEncryptionKey copy];
	}
	return self;
}

@end
