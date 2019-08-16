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
static NSString *const k_zAppID    = @"zAppID";
static NSString *const k_dirPrefix = @"dirPrefix";


@implementation ZDCNodeAnchor

@synthesize userID = userID;
@synthesize zAppID = zAppID;
@synthesize dirPrefix = dirPrefix;

- (instancetype)initWithUserID:(NSString *)inUserID zAppID:(NSString *)inZAppID dirPrefix:(NSString *)inDirPrefix
{
	if ((self = [super init]))
	{
		userID = [inUserID copy];
		zAppID = [inZAppID copy];
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
		zAppID = [decoder decodeObjectForKey:k_zAppID];
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
	[coder encodeObject:zAppID forKey:k_zAppID];
	[coder encodeObject:dirPrefix forKey:k_dirPrefix];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	return self; // immutable class
}

@end
