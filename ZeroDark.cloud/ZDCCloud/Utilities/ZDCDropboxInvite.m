/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCDropboxInvite.h"

@implementation ZDCDropboxInvite

@synthesize treeID = treeID;
@synthesize dirPrefix = dirPrefix;

- (instancetype)initWithTreeID:(NSString *)inTreeID dirPrefix:(NSString *)inDirPrefix
{
	if ((self = [super init]))
	{
		treeID = [inTreeID copy];
		dirPrefix = [inDirPrefix copy];
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	// This class is immutable
	return self;
}

@end
