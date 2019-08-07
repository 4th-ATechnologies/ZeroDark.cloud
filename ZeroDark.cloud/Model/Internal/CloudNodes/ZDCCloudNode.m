#import "ZDCCloudNode.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version                 = @"version_node";
static NSString *const k_uuid                    = @"uuid";
static NSString *const k_localUserID             = @"localUserID";
static NSString *const k_cloudLocator            = @"cloudLocator";
static NSString *const k_eTag_rcrd               = @"aws_eTag_rcrd";
static NSString *const k_eTag_data               = @"aws_eTag_data";
static NSString *const k_isQueuedForDeletion     = @"isDeletion";
//static NSString *const k_orphan_detectionDate    = @"orphan_detectionDate";
//static NSString *const k_orphan_modificationDate = @"orphan_modificationDate";
//static NSString *const k_orphan_verificationDate = @"orphan_verificationDate";


@implementation ZDCCloudNode

@synthesize uuid = uuid;
@synthesize localUserID = localUserID;

@synthesize cloudLocator = cloudLocator;
@synthesize eTag_rcrd = eTag_rcrd;
@synthesize eTag_data = eTag_data;

@synthesize isQueuedForDeletion = isQueuedForDeletion;

//@synthesize orphan_detectionDate = orphan_detectionDate;
//@synthesize orphan_modificationDate = orphan_modificationDate;
//@synthesize orphan_verificationDate = orphan_verificationDate;

- (void)setCloudLocator:(ZDCCloudLocator *)newCloudLocator
{
	NSString *const key = NSStringFromSelector(@selector(cloudLocator));
	
	[self willChangeValueForKey:key];
	{
		cloudLocator = [newCloudLocator copyWithFileNameExt:nil];
	}
	[self didChangeValueForKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID cloudLocator:(ZDCCloudLocator *)inCloudLocator
{
	if ((self = [super init]))
	{
		uuid = [[NSUUID UUID] UUIDString];
		localUserID = [inLocalUserID copy];
		cloudLocator = [inCloudLocator copyWithFileNameExt:nil];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		uuid        = [decoder decodeObjectForKey:k_uuid];
		localUserID = [decoder decodeObjectForKey:k_localUserID];
		
		cloudLocator = [decoder decodeObjectForKey:k_cloudLocator];
		eTag_rcrd    = [decoder decodeObjectForKey:k_eTag_rcrd];
		eTag_data    = [decoder decodeObjectForKey:k_eTag_data];
		
		isQueuedForDeletion = [decoder decodeBoolForKey:k_isQueuedForDeletion];
		
	//	orphan_detectionDate    = [decoder decodeObjectForKey:k_orphan_detectionDate];
	//	orphan_modificationDate = [decoder decodeObjectForKey:k_orphan_modificationDate];
	//	orphan_verificationDate = [decoder decodeObjectForKey:k_orphan_verificationDate];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:uuid forKey:k_uuid];
	[coder encodeObject:localUserID forKey:k_localUserID];
	
	[coder encodeObject:cloudLocator forKey:k_cloudLocator];
	[coder encodeObject:eTag_rcrd    forKey:k_eTag_rcrd];
	[coder encodeObject:eTag_data    forKey:k_eTag_data];
	
	[coder encodeBool:isQueuedForDeletion forKey:k_isQueuedForDeletion];
	
//	[coder encodeObject:orphan_detectionDate    forKey:k_orphan_detectionDate];
//	[coder encodeObject:orphan_modificationDate forKey:k_orphan_modificationDate];
//	[coder encodeObject:orphan_verificationDate forKey:k_orphan_verificationDate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCCloudNode *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->uuid = uuid;
	copy->localUserID = localUserID;
	
	copy->cloudLocator = cloudLocator;
	copy->eTag_rcrd = eTag_rcrd;
	copy->eTag_data = eTag_data;
	
	copy->isQueuedForDeletion = isQueuedForDeletion;
	
//	copy->orphan_detectionDate = orphan_detectionDate;
//	copy->orphan_modificationDate = orphan_modificationDate;
//	copy->orphan_verificationDate = orphan_verificationDate;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapActionable protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#ifndef TARGET_ACTION_EXTENSION

/**
 * Returns an array of YapActionItem instances.
 * Or nil if there are none.
**/
/*
- (NSArray<YapActionItem*> *)yapActionItems
{
	NSArray *actions = nil;
	
	YapActionItem *removeOrphanAction = nil;
	
	if (self.orphan_modificationDate)
	{
		YapActionItemBlock block = ^(NSString *collection, NSString *key, ZDCCloudNode *cloudNode, id metadata){
			
			[cloudNode action_removeOrphan];
		};
		
	#if 1
		// There may be multiple devices that are all scheduled to delete this file from the server.
		// So instead of using the same value for every device, we introduce some randomness per device.
		//
		// Of course, this is a little bit challenging,
		// because we want to do so in a deterministic fashion (per device).
		// So we use the uuid value to derive our randomness.
		
		uint32_t tenMinutes = (60 * 10);
		uint32_t randomDelay = [self.uuid hash] % tenMinutes;
	
		NSTimeInterval threeDays = (60 * 60 * 24 * 3);
		NSTimeInterval offsetFromModification = threeDays + randomDelay;
		
		// We're also careful to not immediately delete the file.
		// Here's why:
		//
		// Our device has been off for several days.
		// We turn it back on, and we start processing the items in the queue.
		// Of course, we're going to encounter RCRD files that were uploaded several days ago.
		// The corresponding DATA files are also in the queue, but we haven't processed them yet.
		//
		// If we react immedately, based solely on the cloud modificationDate,
		// we would immediately schedule a delete-node:if-orphan operation (right at that moment).
		//
		// This obviously isn't what we want.
		// So we introduce this delay to allow for time for us to process the queue, and get caught up.
		
		NSTimeInterval offsetFromDetection = (60 * 60 * 24 * 1);
		
		// With these 2 offsets, we pick the later of the 2
		
		NSDate *minA = [self.orphan_modificationDate dateByAddingTimeInterval:offsetFromModification];
		NSDate *minB = [self.orphan_detectionDate dateByAddingTimeInterval:offsetFromDetection];
		
		NSDate *removeDate = [minA laterDate:minB];
		
	#else
		// TESTING
	//	NSDate *removeDate = [self.orphan_detectionDate dateByAddingTimeInterval:60];
	#endif
		
		removeOrphanAction =
		  [[YapActionItem alloc] initWithIdentifier:@"removeOrphan"
		                                       date:removeDate
		                               retryTimeout:0
		                           requiresInternet:NO // we're just adding operation to queue
		                                      block:block];
	}
	
	if (removeOrphanAction)
		actions = @[ removeOrphanAction ];
	
	return actions;
}
*/

/**
 * Triggered via YapActionItem block (scheduled with YapActionManager).
**/
/*
- (void)action_removeOrphan
{
	NSLog(@"action_removeOrphan");
	
	[ZDCDatabaseManager_si.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		S4Node *node =
		  [ZDCNodeManager findNodeWithCloudID: self.cloudID
		                         localUserID: self.localUserID
		                         transaction: transaction];

		if (node)
		{
			ZDCCloudNode *cloudNode = [transaction objectForKey:self.uuid inCollection:kZDCCollection_CloudNodes];
			cloudNode = [cloudNode copy];

			cloudNode.orphan_detectionDate = nil;
			cloudNode.orphan_modificationDate = nil;
			cloudNode.orphan_verificationDate = nil;

			[transaction setObject:cloudNode forKey:cloudNode.uuid inCollection:kZDCCollection_CloudNodes];
		}
		else
		{
			[ZDCNodeManager createDeleteOperationForOrphanedCloudNode:self transaction:transaction];
		}
	}];
}
*/

#endif
@end
