/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
