/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCNodePrivate.h"
#import "ZDCConstants.h"

#import "NSData+S4.h"
#import "NSDate+ZeroDark.h"
#import "NSString+ZeroDark.h"

// Encoding/Decoding Keys

static int const kS4Node_CurrentVersion = 0;
#pragma unused(kS4Node_CurrentVersion)

static NSString *const k_version_node          = @"version_node";
static NSString *const k_uuid                  = @"uuid";
static NSString *const k_localUserID           = @"localUserID";
static NSString *const k_parentID              = @"parentID";
static NSString *const k_name                  = @"name";
static NSString *const k_shareList             = @"shareList";
static NSString *const k_burnDate              = @"burnDate";
static NSString *const k_senderID              = @"senderID";
static NSString *const k_pendingRecipients     = @"pendingRecipients";
static NSString *const k_encryptionKey         = @"encryptionKey";
static NSString *const k_dirSalt               = @"dirSalt";
static NSString *const k_dirPrefix             = @"dirPrefix";
static NSString *const k_cloudID               = @"cloudID";
static NSString *const k_eTag_rcrd             = @"eTag_rcrd";
static NSString *const k_eTag_data             = @"eTag_data";
static NSString *const k_lastModified_rcrd     = @"lastModified_rcrd";
static NSString *const k_lastModified_data     = @"lastModified_data";
static NSString *const k_cloudDataInfo         = @"cloudDataInfo";
static NSString *const k_explicitCloudName     = @"explicitCloudName";
static NSString *const k_anchor                = @"anchor";
static NSString *const k_pointeeID             = @"pointeeID";


@implementation ZDCNode

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize uuid = uuid;
@synthesize localUserID = localUserID;
@synthesize parentID = parentID;
@synthesize name = name;
@synthesize shareList = shareList;
@synthesize burnDate = burnDate;

@synthesize senderID = senderID;
@synthesize pendingRecipients = pendingRecipients;

@synthesize encryptionKey = encryptionKey;
@synthesize dirSalt = dirSalt;
@synthesize dirPrefix = dirPrefix;

@synthesize cloudID = cloudID;
@synthesize eTag_rcrd = eTag_rcrd;
@synthesize eTag_data = eTag_data;
@dynamic lastModified;
@synthesize lastModified_rcrd = lastModified_rcrd;
@synthesize lastModified_data = lastModified_data;
@synthesize cloudDataInfo = cloudDataInfo;
@synthesize explicitCloudName = explicitCloudName;
@synthesize anchor = anchor;
@synthesize pointeeID = pointeeID;
@dynamic isPointer;
@dynamic isSignal;

- (void)setDirSalt:(NSData *)newDirSalt
{
	// Sanity check !
	// In the past we had bugs where this value was getting stored as a string.
	//
	NSParameterAssert([newDirSalt isKindOfClass:[NSData class]]);
	
	NSString *const key = NSStringFromSelector(@selector(dirSalt));
	[self willChangeValueForKey:key];
	{
		dirSalt = [newDirSalt copy];
	}
	[self didChangeValueForKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
{
	return [self initWithLocalUserID:inLocalUserID uuid:nil];
}

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID uuid:(nullable NSString *)inUUID
{
	NSParameterAssert(inLocalUserID != nil);
	
	if ((self = [super init]))
	{
		uuid = inUUID ? [inUUID copy] : [[NSUUID UUID] UUIDString];
		localUserID = [inLocalUserID copy];
		
		shareList = [[ZDCShareList alloc] init];
		
		encryptionKey = [ZDCNode randomEncryptionKey];
		dirSalt = [ZDCNode randomDirSalt];
		dirPrefix = [ZDCNode randomDirPrefix];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Version History:
 * 
 * < will be documented here >
**/

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
	//	int version = [decoder decodeIntForKey:k_version_node];
		
		uuid          = [decoder decodeObjectForKey:k_uuid];
		localUserID   = [decoder decodeObjectForKey:k_localUserID];
		parentID      = [decoder decodeObjectForKey:k_parentID];
		name          = [decoder decodeObjectForKey:k_name];
		shareList     = [decoder decodeObjectForKey:k_shareList];
		burnDate      = [decoder decodeObjectForKey:k_burnDate];
		
		senderID = [decoder decodeObjectForKey:k_senderID];
		pendingRecipients = [decoder decodeObjectForKey:k_pendingRecipients];
		
		encryptionKey = [decoder decodeObjectForKey:k_encryptionKey];
		dirSalt       = [decoder decodeObjectForKey:k_dirSalt];
		dirPrefix     = [decoder decodeObjectForKey:k_dirPrefix];
		
		cloudID           = [decoder decodeObjectForKey:k_cloudID];
		eTag_rcrd         = [decoder decodeObjectForKey:k_eTag_rcrd];
		eTag_data         = [decoder decodeObjectForKey:k_eTag_data];
		lastModified_rcrd = [decoder decodeObjectForKey:k_lastModified_rcrd];
		lastModified_data = [decoder decodeObjectForKey:k_lastModified_data];
		cloudDataInfo     = [decoder decodeObjectForKey:k_cloudDataInfo];
		explicitCloudName = [decoder decodeObjectForKey:k_explicitCloudName];
		anchor            = [decoder decodeObjectForKey:k_anchor];
		pointeeID         = [decoder decodeObjectForKey:k_pointeeID];
		
		if (shareList == nil) {
			shareList = [[ZDCShareList alloc] init];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kS4Node_CurrentVersion != 0) {
		[coder encodeInt:kS4Node_CurrentVersion forKey:k_version_node];
	}
	
	[coder encodeObject:uuid        forKey:k_uuid];
	[coder encodeObject:localUserID forKey:k_localUserID];
	[coder encodeObject:parentID    forKey:k_parentID];
	[coder encodeObject:name        forKey:k_name];
	[coder encodeObject:shareList   forKey:k_shareList];
	[coder encodeObject:burnDate    forKey:k_burnDate];
	
	[coder encodeObject:senderID forKey:k_senderID];
	[coder encodeObject:pendingRecipients forKey:k_pendingRecipients];
	
	[coder encodeObject:encryptionKey forKey:k_encryptionKey];
	[coder encodeObject:dirSalt       forKey:k_dirSalt];
	[coder encodeObject:dirPrefix     forKey:k_dirPrefix];
	
	[coder encodeObject:cloudID           forKey:k_cloudID];
	[coder encodeObject:eTag_rcrd         forKey:k_eTag_rcrd];
	[coder encodeObject:eTag_data         forKey:k_eTag_data];
	[coder encodeObject:lastModified_rcrd forKey:k_lastModified_rcrd];
	[coder encodeObject:lastModified_data forKey:k_lastModified_data];
	[coder encodeObject:cloudDataInfo     forKey:k_cloudDataInfo];
	[coder encodeObject:explicitCloudName forKey:k_explicitCloudName];
	[coder encodeObject:anchor            forKey:k_anchor];
	[coder encodeObject:pointeeID         forKey:k_pointeeID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCNode *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->uuid        = uuid;
	copy->localUserID = localUserID;
	copy->parentID    = parentID;
	copy->name        = name;
	copy->shareList   = [shareList copy];
	copy->burnDate    = burnDate;
	
	copy->senderID = senderID;
	copy->pendingRecipients = pendingRecipients;
	
	copy->encryptionKey = encryptionKey;
	copy->dirSalt       = dirSalt;
	copy->dirPrefix     = dirPrefix;
	
	copy->cloudID           = cloudID;
	copy->eTag_rcrd         = eTag_rcrd;
	copy->eTag_data         = eTag_data;
	copy->lastModified_rcrd = lastModified_rcrd;
	copy->lastModified_data = lastModified_data;
	copy->cloudDataInfo     = [cloudDataInfo copy];
	copy->explicitCloudName = explicitCloudName;
	copy->anchor            = [anchor copy];
	copy->pointeeID         = pointeeID;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject Overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)makeImmutable
{
	[shareList makeImmutable];
	[cloudDataInfo makeImmutable];
	
	[super makeImmutable];
}

- (BOOL)hasChanges
{
	if ([shareList hasChanges]) return YES;
	if ([cloudDataInfo hasChanges]) return YES;
	
	return [super hasChanges];
}

- (void)clearChangeTracking
{
	[shareList clearChangeTracking];
	[cloudDataInfo clearChangeTracking];
	
	[super clearChangeTracking];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable NSDate *)lastModifed
{
	return ZDCLaterDate(lastModified_rcrd, lastModified_data);
}

- (BOOL)isPointer
{
	return (pointeeID != nil);
}

- (BOOL)isSignal
{
	return [parentID hasSuffix:@"|signal"];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Random
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSData *)randomEncryptionKey
{
	return [NSData s4RandomBytes:kZDCNode_EncryptionKeySizeInBytes];
}

+ (NSData *)randomDirSalt
{
	return [NSData s4RandomBytes:kZDCNode_DirSaltKeySizeInBytes];
}

+ (NSString *)randomDirPrefix
{
	return [NSString zdcUUIDString];
}

+ (NSString *)randomCloudName
{
	return [[NSData s4RandomBytes:20] zBase32String];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Special ParentID's
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSString *)signalParentIDForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	return [NSString stringWithFormat:@"%@|%@|signal", localUserID, treeID];
}

+ (NSString *)graftParentIDForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	return [NSString stringWithFormat:@"%@|%@|graft", localUserID, treeID];
}

+ (BOOL)getLocalUserID:(NSString **)outLocalUserID
                treeID:(NSString **)outTreeID
          fromParentID:(NSString *)parentID
{
	NSArray<NSString *> *components = [parentID componentsSeparatedByString:@"|"];
	if (components.count != 3)
	{
		if (outLocalUserID) *outLocalUserID = nil;
		if (outTreeID) *outTreeID = nil;
		return NO;
	}
	
	NSString *localUserID = components[0];
	NSString *treeID = components[1];
	
	if (outLocalUserID) *outLocalUserID = localUserID;
	if (outTreeID) *outTreeID = treeID;
	return YES;
}

@end
