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
static NSString *const k_treeID   = @"appID";
static NSString *const k_trunkStr = @"container";


@implementation ZDCTrunkNode

+ (NSString *)uuidForLocalUserID:(NSString *)localUserID
                          treeID:(NSString *)treeID
                           trunk:(ZDCTreesystemTrunk)trunk
{
	NSString *trunkID = NSStringFromTreesystemTrunk(trunk);
	
	return [NSString stringWithFormat:@"%@|%@|%@", localUserID, treeID, trunkID];
}

@synthesize treeID = treeID;
@synthesize trunk = trunk;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             treeID:(NSString *)inTreeID
                              trunk:(ZDCTreesystemTrunk)inTrunk
{
	NSString *_uuid = [ZDCTrunkNode uuidForLocalUserID:inLocalUserID treeID:inTreeID trunk:inTrunk];
	
	if ((self = [super initWithLocalUserID:inLocalUserID uuid:_uuid]))
	{
		treeID = [inTreeID copy];
		trunk = inTrunk;
		
		switch (trunk)
		{
			case ZDCTreesystemTrunk_Home     : self.dirPrefix = kZDCDirPrefix_Home;    break;
			case ZDCTreesystemTrunk_Prefs    : self.dirPrefix = kZDCDirPrefix_Prefs;   break;
			case ZDCTreesystemTrunk_Inbox    : self.dirPrefix = kZDCDirPrefix_MsgsIn;  break;
			case ZDCTreesystemTrunk_Outbox   : self.dirPrefix = kZDCDirPrefix_MsgsOut; break;
			case ZDCTreesystemTrunk_Detached : self.dirPrefix = kZDCDirPrefix_Fake;    break;
		}
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder])) // [ZDCNode initWithCoder:]
	{
		treeID = [decoder decodeObjectForKey:k_treeID];
		trunk = TreesystemTrunkFromString([decoder decodeObjectForKey:k_trunkStr]);
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder]; // [ZDCNode encodeWithCoder:]
	
	[coder encodeObject:treeID forKey:k_treeID];
	[coder encodeObject:NSStringFromTreesystemTrunk(trunk) forKey:k_trunkStr];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCTrunkNode *copy = [super copyWithZone:zone]; // [ZDCNode copyWithZone:]
	
	copy->treeID = treeID;
	copy->trunk = trunk;
	
	return copy;
}

@end
