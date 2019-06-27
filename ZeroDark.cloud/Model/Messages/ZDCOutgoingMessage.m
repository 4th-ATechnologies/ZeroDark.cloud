/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCOutgoingMessage.h"

#import "ZDCConstants.h"
#import "ZDCNode.h"

#import "NSDate+ZeroDark.h"

// Encoding/Decoding Keys

static int const kS4OutgoingMessage_CurrentVersion = 0;
#pragma unused(kS4OutgoingMessage_CurrentVersion)

static NSString *const k_version_node          = @"version_node";
static NSString *const k_uuid                  = @"uuid";
static NSString *const k_senderUserID          = @"senderUserID";
static NSString *const k_receiverUserID        = @"receiverUserID";
static NSString *const k_shareList             = @"shareList";
static NSString *const k_burnDate              = @"burnDate";
static NSString *const k_encryptionKey         = @"encryptionKey";
static NSString *const k_cloudID               = @"cloudID";
static NSString *const k_eTag_rcrd             = @"eTag_rcrd";
static NSString *const k_eTag_data             = @"eTag_data";
static NSString *const k_lastModified_rcrd     = @"lastModified_rcrd";
static NSString *const k_lastModified_data     = @"lastModified_data";


@implementation ZDCOutgoingMessage

@synthesize uuid = uuid;
@synthesize senderUserID = senderUserID;
@synthesize receiverUserID = receiverUserID;
@synthesize shareList = shareList;
@synthesize burnDate = burnDate;

@synthesize encryptionKey = encryptionKey;

@synthesize cloudID = cloudID;
@synthesize eTag_rcrd = eTag_rcrd;
@synthesize eTag_data = eTag_data;
@dynamic lastModified;
@synthesize lastModified_rcrd = lastModified_rcrd;
@synthesize lastModified_data = lastModified_data;


- (instancetype)initWithSender:(NSString *)inSenderUserID receiver:(NSString *)inReceiverUserID
{
	NSParameterAssert(inSenderUserID != nil);
	NSParameterAssert(inReceiverUserID != nil);
	
	if ((self = [super init]))
	{
		uuid = [ZDCNode randomCloudName];
		senderUserID = [inSenderUserID copy];
		receiverUserID = [inReceiverUserID copy];
		
		shareList = [[ZDCShareList alloc] init];
		encryptionKey = [ZDCNode randomEncryptionKey];
		
		[self initializeShareList];
	}
	return self;
}

- (void)initializeShareList
{
	// Add sender
	//
	if (receiverUserID)
	{
		ZDCShareItem *item = [[ZDCShareItem alloc] init];
		item.canAddKey = YES;
		
		[item addPermission:ZDCSharePermission_Read];
		[item addPermission:ZDCSharePermission_Write];
		[item addPermission:ZDCSharePermission_Share];
		[item addPermission:ZDCSharePermission_LeafsOnly];
		
		[shareList addShareItem:item forUserID:receiverUserID];
	}
	
	// Add receiver
	//
	if (senderUserID && ![senderUserID isEqual:receiverUserID])
	{
		ZDCShareItem *item = [[ZDCShareItem alloc] init];
		item.canAddKey = YES;
		
		[item addPermission:ZDCSharePermission_LeafsOnly];
		[item addPermission:ZDCSharePermission_WriteOnce];
		[item addPermission:ZDCSharePermission_BurnIfOwner];
		
		[shareList addShareItem:item forUserID:senderUserID];
	}
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
		
		uuid           = [decoder decodeObjectForKey:k_uuid];
		senderUserID   = [decoder decodeObjectForKey:k_senderUserID];
		receiverUserID = [decoder decodeObjectForKey:k_receiverUserID];
		shareList      = [decoder decodeObjectForKey:k_shareList];
		burnDate       = [decoder decodeObjectForKey:k_burnDate];
		
		encryptionKey = [decoder decodeObjectForKey:k_encryptionKey];
		
		cloudID           = [decoder decodeObjectForKey:k_cloudID];
		eTag_rcrd         = [decoder decodeObjectForKey:k_eTag_rcrd];
		eTag_data         = [decoder decodeObjectForKey:k_eTag_data];
		lastModified_rcrd = [decoder decodeObjectForKey:k_lastModified_rcrd];
		lastModified_data = [decoder decodeObjectForKey:k_lastModified_data];
		
		if (shareList == nil) {
			shareList = [[ZDCShareList alloc] init];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kS4OutgoingMessage_CurrentVersion != 0) {
		[coder encodeInt:kS4OutgoingMessage_CurrentVersion forKey:k_version_node];
	}
	
	[coder encodeObject:uuid           forKey:k_uuid];
	[coder encodeObject:senderUserID   forKey:k_senderUserID];
	[coder encodeObject:receiverUserID forKey:k_receiverUserID];
	[coder encodeObject:shareList      forKey:k_shareList];
	[coder encodeObject:burnDate       forKey:k_burnDate];
	
	[coder encodeObject:encryptionKey forKey:k_encryptionKey];
	
	[coder encodeObject:cloudID           forKey:k_cloudID];
	[coder encodeObject:eTag_rcrd         forKey:k_eTag_rcrd];
	[coder encodeObject:eTag_data         forKey:k_eTag_data];
	[coder encodeObject:lastModified_rcrd forKey:k_lastModified_rcrd];
	[coder encodeObject:lastModified_data forKey:k_lastModified_data];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCOutgoingMessage *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->uuid           = uuid;
	copy->senderUserID   = senderUserID;
	copy->receiverUserID = receiverUserID;
	copy->shareList      = [shareList copy];
	copy->burnDate       = burnDate;
	
	copy->encryptionKey = encryptionKey;
	
	copy->cloudID           = cloudID;
	copy->eTag_rcrd         = eTag_rcrd;
	copy->eTag_data         = eTag_data;
	copy->lastModified_rcrd = lastModified_rcrd;
	copy->lastModified_data = lastModified_data;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject Overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)makeImmutable
{
	[shareList makeImmutable];
	[super makeImmutable];
}

- (BOOL)hasChanges
{
	if ([shareList hasChanges]) return YES;
	return [super hasChanges];
}

- (void)clearChangeTracking
{
	[shareList clearChangeTracking];
	[super clearChangeTracking];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable NSDate *)lastModifed
{
	return ZDCLaterDate(lastModified_rcrd, lastModified_data);
}

@end
