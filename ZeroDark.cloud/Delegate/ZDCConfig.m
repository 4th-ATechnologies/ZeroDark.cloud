/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCConfig.h"

@implementation ZDCConfig {
	NSString *primaryTreeID;
}

@synthesize databaseName = databaseName;
@dynamic primaryTreeID;

- (instancetype)initWithPrimaryTreeID:(NSString *)inTreeID
{
	if (inTreeID == nil) return nil;
	
	if ((self = [super init]))
	{
		databaseName = @"zdcDatabase";
		primaryTreeID = [inTreeID copy];
	}
	return self;
}

- (NSString *)primaryTreeID
{
	return primaryTreeID;
}

- (void)addTreeID:(NSString *)treeID
{
	// Todo...
}

@end
