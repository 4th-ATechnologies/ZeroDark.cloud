/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCTrunkNode.h"

#import "ZDCConstants.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCNodePrivate.h"
#import "ZDCTrunkNodePrivate.h"

// Encoding/Decoding Keys
//
static NSString *const k_zAppID   = @"appID";
static NSString *const k_trunkStr = @"container";


@implementation ZDCTrunkNode

+ (NSString *)uuidForLocalUserID:(NSString *)localUserID
                          zAppID:(NSString *)zAppID
                           trunk:(ZDCTreesystemTrunk)trunk
{
	NSString *trunkID = NSStringFromTreesystemTrunk(trunk);
	
	return [NSString stringWithFormat:@"%@|%@|%@", localUserID, zAppID, trunkID];
}

@synthesize zAppID = zAppID;
@synthesize trunk = trunk;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             zAppID:(NSString *)inZAppID
                              trunk:(ZDCTreesystemTrunk)inTrunk
{
	NSString *_uuid = [ZDCTrunkNode uuidForLocalUserID:inLocalUserID zAppID:inZAppID trunk:inTrunk];
	
	if ((self = [super initWithLocalUserID:inLocalUserID uuid:_uuid]))
	{
		zAppID = [inZAppID copy];
		trunk = inTrunk;
		
		switch (trunk)
		{
			case ZDCTreesystemTrunk_Home    : self.dirPrefix = kZDCDirPrefix_Home;    break;
			case ZDCTreesystemTrunk_Prefs   : self.dirPrefix = kZDCDirPrefix_Prefs;   break;
			case ZDCTreesystemTrunk_Inbox   : self.dirPrefix = kZDCDirPrefix_MsgsIn;  break;
			case ZDCTreesystemTrunk_Outbox  : self.dirPrefix = kZDCDirPrefix_MsgsOut; break;
			case ZDCTreesystemTrunk_Invalid : self.dirPrefix = kZDCDirPrefix_Fake;    break;
		}
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder])) // [ZDCNode initWithCoder:]
	{
		zAppID = [decoder decodeObjectForKey:k_zAppID];
		trunk = TreesystemTrunkFromString([decoder decodeObjectForKey:k_trunkStr]);
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder]; // [ZDCNode encodeWithCoder:]
	
	[coder encodeObject:zAppID forKey:k_zAppID];
	[coder encodeObject:NSStringFromTreesystemTrunk(trunk) forKey:k_trunkStr];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCTrunkNode *copy = [super copyWithZone:zone]; // [ZDCNode copyWithZone:]
	
	copy->zAppID = zAppID;
	copy->trunk = trunk;
	
	return copy;
}

@end
