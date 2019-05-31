/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCContainerNode.h"

#import "ZDCConstants.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCContainerNodePrivate.h"
#import "ZDCNodePrivate.h"

// Encoding/Decoding Keys
//
static NSString *const k_zAppID       = @"appID";
static NSString *const k_containerStr = @"container";


@implementation ZDCContainerNode

+ (NSString *)uuidForLocalUserID:(NSString *)localUserID
                          zAppID:(NSString *)zAppID
                       container:(ZDCTreesystemContainer)container
{
	NSString *containerID = NSStringFromTreesystemContainer(container);
	
	return [NSString stringWithFormat:@"%@|%@|%@", localUserID, zAppID, containerID];
}

@synthesize zAppID = zAppID;
@synthesize container = container;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             zAppID:(NSString *)inZAppID
                          container:(ZDCTreesystemContainer)inContainer
{
	NSString *_uuid = [ZDCContainerNode uuidForLocalUserID:inLocalUserID zAppID:inZAppID container:inContainer];
	
	if ((self = [super initWithLocalUserID:inLocalUserID uuid:_uuid]))
	{
		zAppID = [inZAppID copy];
		container = inContainer;
		
		switch (container)
		{
			case ZDCTreesystemContainer_Home    : self.dirPrefix = kZDCDirPrefix_Home;   break;
			case ZDCTreesystemContainer_Msgs    : self.dirPrefix = kZDCDirPrefix_Msgs;   break;
			case ZDCTreesystemContainer_Inbox   : self.dirPrefix = kZDCDirPrefix_Inbox;  break;
			case ZDCTreesystemContainer_Outbox  : self.dirPrefix = kZDCDirPrefix_Outbox; break;
			case ZDCTreesystemContainer_Prefs   : self.dirPrefix = kZDCDirPrefix_Prefs;  break;
			case ZDCTreesystemContainer_Invalid : self.dirPrefix = kZDCDirPrefix_Fake;   break;
		}
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder])) // [ZDCNode initWithCoder:]
	{
		zAppID = [decoder decodeObjectForKey:k_zAppID];
		container = TreesystemContainerFromString([decoder decodeObjectForKey:k_containerStr]);
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder]; // [ZDCNode encodeWithCoder:]
	
	[coder encodeObject:zAppID forKey:k_zAppID];
	[coder encodeObject:NSStringFromTreesystemContainer(container) forKey:k_containerStr];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCContainerNode *copy = [super copyWithZone:zone]; // [ZDCNode copyWithZone:]
	
	copy->zAppID = zAppID;
	copy->container = container;
	
	return copy;
}

@end
