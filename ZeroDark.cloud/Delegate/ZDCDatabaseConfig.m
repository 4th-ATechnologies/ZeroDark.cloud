/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCDatabaseConfig.h"

@implementation ZDCDatabaseConfig

@synthesize encryptionKey = encryptionKey;
@synthesize configHook;

- (instancetype)initWithEncryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		encryptionKey = [inEncryptionKey copy];
	}
	return self;
}

@end
