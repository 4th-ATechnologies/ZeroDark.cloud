#import "ZDCLocalUserPrivate.h"


double const kS4LocalUser_shelflife = (60 * 60 * 24 * 1);

static int const kS4LocalUser_CurrentVersion = 1;
#pragma unused(kS4LocalUser_CurrentVersion)

static NSString *const k_version_localUser              = @"version_localUser";

static NSString *const k_accessKeyID                    = @"accessKeyID";
static NSString *const k_syncedSalt                     = @"syncedSalt";
static NSString *const k_aws_stage                      = @"aws_stage";

static NSString *const k_syncingPaused                  = @"syncingPaused";
static NSString *const k_accountSuspended               = @"accountSuspended";
static NSString *const k_accountNeedsA0Token            = @"accountNeedsA0Token";
static NSString *const k_isPayingCustomer               = @"isPayingCustomer";
static NSString *const k_hasBackedUpAccessCode          = @"verifiedCloneCode";

static NSString *const k_activationDate                 = @"activationDate";

static NSString *const k_pushToken_debug                   = @"pushToken_debug";
static NSString *const k_pushToken_release                 = @"pushToken_release";
static NSString *const k_lastPushTokenRegistration_debug   = @"lastPushTokenRefresh_debug";
static NSString *const k_lastPushTokenRegistration_release = @"lastPushTokenRefresh_release";

static NSString *const k_needsRegisterPushToken_debug   = @"needsRegisterPushToken_debug";
static NSString *const k_needsRegisterPushToken_release = @"needsRegisterPushToken_release";
static NSString *const k_needsCreateRecoveryConnection  = @"needsCreateRecoveryConnection";
static NSString *const k_needsUserMetadataUpload        = @"needsUserMetadataUpload";
static NSString *const k_needsCheckAccountDeleted       = @"needsCheckAccountDeleted";

static NSString *const k_auth0_primary                  = @"auth0_primary";

static NSString *const k_deprecated_accountDeleted      = @"accountDeleted";


@interface ZDCLocalUser ()

@property (nonatomic, copy, readwrite) NSString *pushToken_debug;
@property (nonatomic, copy, readwrite) NSString *pushToken_release;

@property (nonatomic, strong, readwrite) NSDate *lastPushTokenRegistration_debug;
@property (nonatomic, strong, readwrite) NSDate *lastPushTokenRegistration_release;

@property (nonatomic, assign, readwrite) BOOL needsRegisterPushToken_debug;
@property (nonatomic, assign, readwrite) BOOL needsRegisterPushToken_release;

@end

@implementation ZDCLocalUser

@synthesize accessKeyID = accessKeyID;
@synthesize syncedSalt = syncedSalt;
@synthesize aws_stage = aws_stage;

@synthesize syncingPaused = syncingPaused;
@synthesize accountSuspended = accountSuspended;
@synthesize accountNeedsA0Token = accountNeedsA0Token;
@synthesize isPayingCustomer = isPayingCustomer;
@synthesize hasBackedUpAccessCode = hasBackedUpAccessCode;

@synthesize activationDate = activationDate;

@dynamic    pushToken;
@synthesize pushToken_debug = pushToken_debug;
@synthesize pushToken_release = pushToken_release;
@dynamic    lastPushTokenRegistration;
@synthesize lastPushTokenRegistration_debug   = lastPushTokenRegistration_debug;
@synthesize lastPushTokenRegistration_release = lastPushTokenRegistration_release;

@dynamic    needsRegisterPushToken;
@synthesize needsRegisterPushToken_debug   = needsRegisterPushToken_debug;
@synthesize needsRegisterPushToken_release = needsRegisterPushToken_release;
@synthesize needsCreateRecoveryConnection = needsCreateRecoveryConnection;
@synthesize needsUserMetadataUpload = needsUserMetadataUpload;
@synthesize needsCheckAccountDeleted = needsCheckAccountDeleted;

@synthesize auth0_primary = auth0_primary;

@dynamic hasCompletedActivation;
@dynamic hasCompletedSetup;
@dynamic canPerformSync;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


// NSCoding version history:
//
// v1:
// - moved accountDeleted from S4LocalUser to ZDCUser

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder])) // [ZDCUser initWithCoder:]
	{
		int version = [decoder decodeIntForKey:k_version_localUser];
		
		accessKeyID = [decoder decodeObjectForKey:k_accessKeyID];
		syncedSalt = [decoder decodeObjectForKey:k_syncedSalt];
		aws_stage  = [decoder decodeObjectForKey:k_aws_stage];
		
		syncingPaused        = [decoder decodeBoolForKey:k_syncingPaused];
		accountSuspended     = [decoder decodeBoolForKey:k_accountSuspended];
		accountNeedsA0Token  = [decoder decodeBoolForKey:k_accountNeedsA0Token];
		isPayingCustomer     = [decoder decodeBoolForKey:k_isPayingCustomer];
		hasBackedUpAccessCode = [decoder decodeBoolForKey:k_hasBackedUpAccessCode];
		
		if (version == 0) {
			self.accountDeleted = [decoder decodeBoolForKey:k_deprecated_accountDeleted]; // moved to ZDCUser
		}
		
		activationDate = [decoder decodeObjectForKey:k_activationDate];

		pushToken_debug              = [decoder decodeObjectForKey:k_pushToken_debug];
		pushToken_release            = [decoder decodeObjectForKey:k_pushToken_release];
		lastPushTokenRegistration_debug   = [decoder decodeObjectForKey:k_lastPushTokenRegistration_debug];
		lastPushTokenRegistration_release = [decoder decodeObjectForKey:k_lastPushTokenRegistration_release];
		
		needsRegisterPushToken_debug   = [decoder decodeBoolForKey:k_needsRegisterPushToken_debug];
		needsRegisterPushToken_release = [decoder decodeBoolForKey:k_needsRegisterPushToken_release];
		needsCreateRecoveryConnection  = [decoder decodeBoolForKey:k_needsCreateRecoveryConnection];
		needsUserMetadataUpload        = [decoder decodeBoolForKey:k_needsUserMetadataUpload];
		needsCheckAccountDeleted       = [decoder decodeBoolForKey:k_needsCheckAccountDeleted];

		auth0_primary = [decoder decodeObjectForKey:k_auth0_primary];
		
	//	waitListInfo = [decoder decodeObjectForKey:k_waitListInfo];
	}
    
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder]; // [ZDCUser encodeWithCoder:]

	if (kS4LocalUser_CurrentVersion != 0) {
		[coder encodeInt:kS4LocalUser_CurrentVersion forKey:k_version_localUser];
	}
	
	[coder encodeObject:accessKeyID forKey:k_accessKeyID];
	[coder encodeObject:syncedSalt forKey:k_syncedSalt];
	[coder encodeObject:aws_stage  forKey:k_aws_stage];
	
	[coder encodeBool:syncingPaused        forKey:k_syncingPaused];
	[coder encodeBool:accountSuspended     forKey:k_accountSuspended];
	[coder encodeBool:accountNeedsA0Token  forKey:k_accountNeedsA0Token];
	[coder encodeBool:isPayingCustomer     forKey:k_isPayingCustomer];
	[coder encodeBool:hasBackedUpAccessCode forKey:k_hasBackedUpAccessCode];
	
	[coder encodeObject:activationDate forKey:k_activationDate];

	[coder encodeObject:pushToken_debug              forKey:k_pushToken_debug];
	[coder encodeObject:pushToken_release            forKey:k_pushToken_release];
	[coder encodeObject:lastPushTokenRegistration_debug   forKey:k_lastPushTokenRegistration_debug];
	[coder encodeObject:lastPushTokenRegistration_release forKey:k_lastPushTokenRegistration_release];

	[coder encodeBool:needsRegisterPushToken_debug   forKey:k_needsRegisterPushToken_debug];
	[coder encodeBool:needsRegisterPushToken_release forKey:k_needsRegisterPushToken_release];
	[coder encodeBool:needsCreateRecoveryConnection  forKey:k_needsCreateRecoveryConnection];
	[coder encodeBool:needsUserMetadataUpload        forKey:k_needsUserMetadataUpload];
	[coder encodeBool:needsCheckAccountDeleted       forKey:k_needsCheckAccountDeleted];

	[coder encodeObject:auth0_primary forKey:k_auth0_primary];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCLocalUser *copy = [super copyWithZone:zone]; // [ZDCUser copyWithZone:]
	
	copy->accessKeyID = accessKeyID;
	copy->syncedSalt = syncedSalt;
	copy->aws_stage = aws_stage;
	
	copy->syncingPaused = syncingPaused;
	copy->accountSuspended = accountSuspended;
	copy->accountNeedsA0Token = accountNeedsA0Token;
	copy->isPayingCustomer = isPayingCustomer;
	copy->hasBackedUpAccessCode = hasBackedUpAccessCode;

	copy->activationDate = activationDate;
	
	copy->pushToken_debug              = pushToken_debug;
	copy->pushToken_release            = pushToken_release;
	copy->lastPushTokenRegistration_debug   = lastPushTokenRegistration_debug;
	copy->lastPushTokenRegistration_release = lastPushTokenRegistration_release;
	
	copy->needsRegisterPushToken_debug   = needsRegisterPushToken_debug;
	copy->needsRegisterPushToken_release = needsRegisterPushToken_release;
	copy->needsCreateRecoveryConnection  = needsCreateRecoveryConnection;
	copy->needsUserMetadataUpload        = needsUserMetadataUpload;
	copy->needsCheckAccountDeleted       = needsCheckAccountDeleted;

	copy->auth0_primary = auth0_primary;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Build Dependent
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)pushToken
{
#if DEBUG
	return pushToken_debug;
#else
	return pushToken_release;
#endif
}

- (void)setPushToken:(NSString *)value
{
	NSString *key = NSStringFromSelector(@selector(pushToken));
	
	[self willChangeValueForKey:key];
	{
	#if DEBUG
		pushToken_debug = [value copy];
	#else
		pushToken_release = [value copy];
	#endif
	}
	[self didChangeValueForKey:key];
}

- (NSDate *)lastPushTokenRegistration
{
#if DEBUG
	return lastPushTokenRegistration_debug;
#else
	return lastPushTokenRegistration_release;
#endif
}

- (void)setLastPushTokenRegistration:(NSDate *)value
{
	NSString *key = NSStringFromSelector(@selector(lastPushTokenRegistration));
	
	[self willChangeValueForKey:key];
	{
	#if DEBUG
		lastPushTokenRegistration_debug = value;   // NSDate is immutable
	#else
		lastPushTokenRegistration_release = value; // NSDate is immutable
	#endif
	}
	[self didChangeValueForKey:key];
}

- (BOOL)needsRegisterPushToken
{
#if DEBUG
	return needsRegisterPushToken_debug;
#else
	return needsRegisterPushToken_release;
#endif
}

- (void)setNeedsRegisterPushToken:(BOOL)value
{
	NSString *key = NSStringFromSelector(@selector(needsRegisterPushToken));
	
	[self willChangeValueForKey:key];
	{
	#if DEBUG
		needsRegisterPushToken_debug = value;
	#else
		needsRegisterPushToken_release = value;
	#endif
	}
	[self didChangeValueForKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isLocal
{
	// Overrides method in S4USer
	return YES;
}

- (NSString *)rootDirectoryID
{
	return self.uuid;
}

- (BOOL)hasCompletedActivation
{
	return (self.aws_region != AWSRegion_Invalid) && (self.aws_bucket.length > 0);
}

- (BOOL)hasCompletedSetup
{
	return (self.aws_bucket.length > 0)
	    && (self.aws_region != AWSRegion_Invalid)
	    && (self.accessKeyID.length > 0)
	    && (self.publicKeyID > 0);
}

- (BOOL)canPerformSync
{
	return (self.hasCompletedSetup
	     && !self.syncingPaused
	     && !self.accountDeleted
	     && !self.accountSuspended
	     && !self.accountNeedsA0Token);
}

- (BOOL)hasRecoveryConnection
{
	BOOL result = NO;
	
	for (ZDCUserIdentity *ident in self.identities)
	{
		if (ident.isRecoveryAccount) {
			result = YES;
			break;
		}
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark user metdata updater
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setPreferredIdentityID:(NSString *)newPreferredIdentityID
{
	BOOL isChange = NO;
	
	if (self.preferredIdentityID) {
		isChange = ![self.preferredIdentityID isEqual:newPreferredIdentityID];
	}
	else {
		isChange = (newPreferredIdentityID != nil);
	}
	
	if (isChange)
	{
		[super setPreferredIdentityID:newPreferredIdentityID];
		needsUserMetadataUpload = YES;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseRelationshipNode protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<YapDatabaseRelationshipEdge *> *)yapDatabaseRelationshipEdges
{
	NSArray<YapDatabaseRelationshipEdge *> *super_edges = nil;
	NSArray<YapDatabaseRelationshipEdge *> *self_edges = nil;
	
	if ([super respondsToSelector: @selector(yapDatabaseRelationshipEdges)]) {
		super_edges = [super yapDatabaseRelationshipEdges];
	}
    
	if (accessKeyID)
	{
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName: @"accessKeyID"
		                             destinationKey: accessKeyID
		                                 collection: kZDCCollection_SymmetricKeys
		                            nodeDeleteRules: YDB_DeleteDestinationIfSourceDeleted];
		
		self_edges = @[ edge ];
	}
	
	if (super_edges.count > 0)
	{
		if (self_edges)
			return [super_edges arrayByAddingObjectsFromArray:self_edges];
		else
			return super_edges;
	}
	else
	{
		return self_edges;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseActionManager
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#ifndef TARGET_ACTION_EXTENSION

/**
 * Triggered via YapActionItem block (scheduled with YapActionManager).
**/
- (void)action_updateAuth0Info
{
/*
	NSString *localUserID = self.uuid;
	NSString *snapshot_preferredAuth0ID = self.preferredAuth0ID;
	
	NSMutableDictionary* user_metadata = [NSMutableDictionary dictionaryWithCapacity:1];
	if (self.preferredAuth0ID) {
		user_metadata[kZDCUser_metadata_preferredAuth0ID] = self.preferredAuth0ID;
	}

	NSDictionary *info = @{
		@"user_metadata" : user_metadata
	};

	[ZDCUserManager updateAuth0InfoForLocalUser: self
	                                      info: info
	                           completionBlock:^(NSError *error)
	{
		if (error)
		{
			// YapActionManager will automatically retry again later
			return;
		}
		
		YapDatabaseConnection *rwDatabaseConnection = ZDCDatabaseManager.rwDatabaseConnection;
		[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			S4LocalUser *updatedUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
			
			if ((!updatedUser.preferredAuth0ID && !snapshot_preferredAuth0ID)
			 || [updatedUser.preferredAuth0ID isEqualToString:snapshot_preferredAuth0ID])
			{
				updatedUser = [updatedUser copy];
				updatedUser.needsUserMetadataUpload = NO;
				
				[transaction setObject: updatedUser
				                forKey: updatedUser.uuid
				          inCollection: kZDCCollection_Users];
			}
			else
			{
				// The preferredAuth0ID value has changed since we started the upload.
				// Thus, we need to perform another upload.
				//
				// So don't unset the `needsUserMetadataUpload` value.
				// Instead, do nothing, which will cause YapActionManager to automatically retry.
			}
		}];
	}];
*/
}

#endif

@end
