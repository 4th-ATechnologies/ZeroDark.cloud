/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCNodeAnchor.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version   = @"version";
static NSString *const k_userID    = @"userID";
static NSString *const k_treeID    = @"treeID";
static NSString *const k_dirPrefix = @"dirPrefix";


@implementation ZDCNodeAnchor

@synthesize userID = userID;
@synthesize treeID = treeID;
@synthesize dirPrefix = dirPrefix;

- (instancetype)initWithUserID:(NSString *)inUserID treeID:(NSString *)inTreeID dirPrefix:(NSString *)inDirPrefix
{
	if ((self = [super init]))
	{
		userID = [inUserID copy];
		treeID = [inTreeID copy];
		dirPrefix = [inDirPrefix copy];
	}
	return self;
}

#pragma mark NSCoding

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		userID = [decoder decodeObjectForKey:k_userID];
		treeID = [decoder decodeObjectForKey:k_treeID];
		dirPrefix = [decoder decodeObjectForKey:k_dirPrefix];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:userID forKey:k_userID];
	[coder encodeObject:treeID forKey:k_treeID];
	[coder encodeObject:dirPrefix forKey:k_dirPrefix];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	return self; // immutable class
}

@end
