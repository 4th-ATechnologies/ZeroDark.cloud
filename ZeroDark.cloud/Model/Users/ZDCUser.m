/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserPrivate.h"

#import "Auth0Utilities.h"
#import "NSData+S4.h"
#import "NSString+ZeroDark.h"

// NSCoding constants

static int const kZDCUser_CurrentVersion = 2;
#pragma unused(kZDCUser_CurrentVersion)

static NSString *const k_version_user           = @"version_user";
static NSString *const k_uuid                   = @"uuid";
static NSString *const k_publicKeyID            = @"publicKeyID";
static NSString *const k_blockchainProof        = @"blockchainProof";
static NSString *const k_random_uuid            = @"random_uuid";
static NSString *const k_random_encryptionKey   = @"random_encryptionKey";
static NSString *const k_aws_regionStr          = @"aws_regionStr";
static NSString *const k_aws_bucket             = @"aws_bucket";
static NSString *const k_accountBlocked         = @"accountBlocked";
static NSString *const k_accountDeleted         = @"accountDeleted";
static NSString *const k_lastRefresh_profile    = @"lastRefresh_profile";
static NSString *const k_lastRefresh_blockchain = @"lastRefresh_blockchain";
static NSString *const k_identities             = @"identities";
static NSString *const k_preferredIdentityID    = @"preferedAuth0ID";  // historical spelling


static NSString *const kDeprecated_auth0_profiles = @"auth0_profiles";

// Extern constants

/* extern */ NSString *const kZDCAnonymousUserID = @"anonymoususerid1"; // must be 16 characters & zBase32


@implementation ZDCUser

@synthesize uuid = uuid;

@synthesize publicKeyID = publicKeyID;
@synthesize blockchainProof = blockchainProof;

@synthesize random_uuid = random_uuid;
@synthesize random_encryptionKey = random_encryptionKey;

@synthesize aws_region = aws_region;
@synthesize aws_bucket = aws_bucket;

@synthesize accountBlocked = accountBlocked;
@synthesize accountDeleted = accountDeleted;
@synthesize lastRefresh_profile = lastRefresh_profile;
@synthesize lastRefresh_blockchain = lastRefresh_blockchain;

@synthesize identities = identities;
@synthesize preferredIdentityID = preferredIdentityID;

@dynamic displayIdentity;
@dynamic displayName;

@dynamic isLocal;
@dynamic isRemote;
@dynamic hasRegionAndBucket;

- (instancetype)init
{
	return [self initWithUUID:nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (instancetype)initWithUUID:(nullable NSString *)inUUID
{
	if ((self = [super init]))
	{
		if (inUUID)
			uuid = [inUUID copy];
		else
			uuid = [[NSUUID UUID] UUIDString];
		
		random_uuid = [NSString zdcUUIDString];
		random_encryptionKey = [NSData s4RandomBytes:(512 / 8)]; // 512 bits
		
		aws_region = AWSRegion_Invalid; // <- not zero
		
		lastRefresh_profile = [NSDate date];
		lastRefresh_blockchain = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// NSCoding version history:
//
// v1:
//	- Moved accountDeleted from S4LocalUser to ZDCUser
//
// v2:
// - Moved from `auth0_profiles` to `identities`
// - Renamed auth0_preferredID to preferredIdentityID
// - Changing to lastUpdated_profile & lastUpdated_blockchain
//

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Uncomment me when version handling is needed
		int version = [decoder decodeIntForKey:k_version_user];
		
		uuid = [decoder decodeObjectForKey:k_uuid];
		
		publicKeyID = [decoder decodeObjectForKey:k_publicKeyID];
		blockchainProof = [decoder decodeObjectForKey:k_blockchainProof];
		
		random_uuid = [decoder decodeObjectForKey:k_random_uuid];
		random_encryptionKey = [decoder decodeObjectForKey:k_random_encryptionKey];

		aws_region = [AWSRegions regionForName:[decoder decodeObjectForKey:k_aws_regionStr]];
		aws_bucket = [decoder decodeObjectForKey:k_aws_bucket];
		
		accountBlocked = [decoder decodeBoolForKey:k_accountBlocked];
		accountDeleted = [decoder decodeBoolForKey:k_accountDeleted];
		lastRefresh_profile = [decoder decodeObjectForKey:k_lastRefresh_profile];
		lastRefresh_blockchain = [decoder decodeObjectForKey:k_lastRefresh_blockchain];
		
		if (version >= 2)
		{
			identities = [decoder decodeObjectForKey:k_identities];
		}
		else
		{
			NSDictionary *auth0_profiles = [decoder decodeObjectForKey:kDeprecated_auth0_profiles];
			
			NSMutableArray *_identities = [NSMutableArray arrayWithCapacity:auth0_profiles.count];
			for (NSDictionary *dict in auth0_profiles.objectEnumerator)
			{
				ZDCUserIdentity *ident = [[ZDCUserIdentity alloc] initWithDictionary:dict];
				if (ident) {
					[_identities addObject:ident];
				}
			}
			
			identities = [_identities copy];
		}
		
		preferredIdentityID = [decoder decodeObjectForKey:k_preferredIdentityID];
		
		// Sanitation
		
		if (!lastRefresh_profile) {
			lastRefresh_profile = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
		}
		
		if (!lastRefresh_blockchain) {
			lastRefresh_blockchain = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
		}
 	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kZDCUser_CurrentVersion != 0) {
		[coder encodeInt:kZDCUser_CurrentVersion forKey:k_version_user];
	}
	
	[coder encodeObject:uuid forKey:k_uuid];
	
	[coder encodeObject:publicKeyID forKey:k_publicKeyID];
	[coder encodeObject:blockchainProof forKey:k_blockchainProof];
	
	[coder encodeObject:random_uuid          forKey:k_random_uuid];
	[coder encodeObject:random_encryptionKey forKey:k_random_encryptionKey];

	[coder encodeObject:[AWSRegions shortNameForRegion:aws_region] forKey:k_aws_regionStr];
	[coder encodeObject:aws_bucket forKey:k_aws_bucket];
	
	[coder encodeBool:accountBlocked forKey:k_accountBlocked];
	[coder encodeBool:accountDeleted forKey:k_accountDeleted];
	[coder encodeObject:lastRefresh_profile forKey:k_lastRefresh_profile];
	[coder encodeObject:lastRefresh_blockchain forKey:k_lastRefresh_blockchain];
	
	[coder encodeObject:identities          forKey:k_identities];
	[coder encodeObject:preferredIdentityID forKey:k_preferredIdentityID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCUser *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	[self copyTo:copy];
	return copy;
}

- (void)copyTo:(ZDCUser *)copy
{
	copy->uuid = uuid;
	
	copy->publicKeyID = publicKeyID;
	copy->blockchainProof = blockchainProof;
	
	copy->random_uuid = random_uuid;
	copy->random_encryptionKey = random_encryptionKey;
	
	copy->aws_region = aws_region;
	copy->aws_bucket = aws_bucket;
	
	copy->accountBlocked = accountBlocked;
	copy->accountDeleted = accountDeleted;
	copy->lastRefresh_profile = lastRefresh_profile;
	copy->lastRefresh_blockchain = lastRefresh_blockchain;
	
	copy->identities = [identities copy];
	copy->preferredIdentityID = preferredIdentityID;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth0
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (nullable ZDCUserIdentity *)displayIdentity
{
	if (identities.count == 0) return nil;
	
	if (preferredIdentityID)
	{
		ZDCUserIdentity *result = [self identityWithID:preferredIdentityID];
		if (result) {
			return result;
		}
	}
	
	// Look for `isOwnerPreferredIdentity`
	//
	for (ZDCUserIdentity *identity in identities)
	{
		if (identity.isOwnerPreferredIdentity) {
			return identity;
		}
	}
	
	// Prefer a non-recovery-account identity
	//
	for (ZDCUserIdentity *identity in identities)
	{
		if (!identity.isRecoveryAccount){
			return identity;
		}
	}
	
	return identities[0];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (NSString *)displayName
{
	ZDCUserIdentity *displayIdentity = [self displayIdentity];
	if (displayIdentity) {
		return displayIdentity.displayName;
	}
	else {
		return uuid;
	}
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (nullable ZDCUserIdentity *)identityWithID:(NSString *)identityID
{
	ZDCUserIdentity *match = nil;
	if (identityID)
	{
		for (ZDCUserIdentity *identity in identities)
		{
			if ([identity.identityID isEqualToString:identityID])
			{
				match = identity;
				break;
			}
		}
	}
	
	return match;
}

- (NSUInteger)nonRecoveryProfileCount
{
	NSUInteger count = 0;
	
	for (ZDCUserIdentity *ident in identities)
	{
		if (!ident.isRecoveryAccount) {
			count++;
		}
	}
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (BOOL)isLocal
{
	// This method is overriden in ZDCLocalUser
	return NO;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (BOOL)isRemote
{
	return (self.isLocal == NO);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
- (BOOL)hasRegionAndBucket
{
	return (self.aws_region != AWSRegion_Invalid) && (self.aws_bucket.length > 0);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseRelationshipNode protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<YapDatabaseRelationshipEdge *> *)yapDatabaseRelationshipEdges
{
	YapDatabaseRelationshipEdge *pubKeyEdge = nil;

	if (publicKeyID)
	{
		pubKeyEdge =
		  [YapDatabaseRelationshipEdge edgeWithName: @"pubKey"
		                             destinationKey: publicKeyID
		                                 collection: kZDCCollection_PublicKeys
		                            nodeDeleteRules: YDB_DeleteDestinationIfSourceDeleted];
	}
	
	if (pubKeyEdge)
		return @[pubKeyEdge];
	else
		return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
+ (BOOL)isUserID:(NSString *)str
{
	return ((str.length == 32) && [str isZBase32]);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUser.html
 */
+ (BOOL)isAnonymousID:(NSString *)str
{
	return ((str.length == 16) && [str isZBase32]);
}

@end
