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

static int const kZDCUser_CurrentVersion = 1;
#pragma unused(kZDCUser_CurrentVersion)

static NSString *const k_version_user          = @"version_user";
static NSString *const k_uuid                  = @"uuid";
static NSString *const k_publicKeyID           = @"publicKeyID";
static NSString *const k_blockchainTransaction = @"blockchainTransaction";
static NSString *const k_random_uuid           = @"random_uuid";
static NSString *const k_random_encryptionKey  = @"random_encryptionKey";
static NSString *const k_aws_regionStr         = @"aws_regionStr";
static NSString *const k_aws_bucket            = @"aws_bucket";
static NSString *const k_accountDeleted        = @"accountDeleted";
static NSString *const k_lastUpdated           = @"lastUpdated";
static NSString *const k_auth0_profiles        = @"auth0_profiles";
static NSString *const k_auth0_preferredID     = @"preferedAuth0ID";  // historical spelling
static NSString *const k_auth0_lastUpdated     = @"auth0_updated_at"; // historical spelling - matches auth0 property

// Extern constants

/* extern */ NSString *const kZDCAnonymousUserID = @"anonymoususerid1"; // must 16 characters & zBase32
/* extern */ NSString *const kZDCUser_metadataKey =  @"user_metadata";
/* extern */ NSString *const kZDCUser_metadata_preferedAuth0ID =  @"preferredAuth0ID";


@implementation ZDCUser

@synthesize uuid = uuid;

@synthesize publicKeyID = publicKeyID;
@synthesize blockchainTransaction = blockchainTransaction;

@synthesize random_uuid = random_uuid;
@synthesize random_encryptionKey = random_encryptionKey;

@synthesize aws_region = aws_region;
@synthesize aws_bucket = aws_bucket;

@synthesize accountDeleted = accountDeleted;
@synthesize lastUpdated = lastUpdated;

@synthesize auth0_profiles = auth0_profiles;
@synthesize auth0_preferredID = auth0_preferredID;
@synthesize auth0_lastUpdated = auth0_lastUpdated;

@dynamic preferredProfile;
@dynamic displayName;

@dynamic isLocal;
@dynamic isRemote;
@dynamic hasRegionAndBucket;

- (instancetype)init
{
	return [self initWithUUID:nil];
}

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
		
		lastUpdated = [NSDate date];
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

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Uncomment me when version handling is needed
	//	int version = [decoder decodeIntForKey:k_version_user];
		
		uuid = [decoder decodeObjectForKey:k_uuid];
		
		publicKeyID = [decoder decodeObjectForKey:k_publicKeyID];
		blockchainTransaction = [decoder decodeObjectForKey:k_blockchainTransaction];
		
		random_uuid = [decoder decodeObjectForKey:k_random_uuid];
		random_encryptionKey = [decoder decodeObjectForKey:k_random_encryptionKey];

		aws_region = [AWSRegions regionForName:[decoder decodeObjectForKey:k_aws_regionStr]];
		aws_bucket = [decoder decodeObjectForKey:k_aws_bucket];
		
		accountDeleted = [decoder decodeBoolForKey:k_accountDeleted];
		lastUpdated = [decoder decodeObjectForKey:k_lastUpdated];
		
		auth0_profiles = [decoder decodeObjectForKey:k_auth0_profiles];
		auth0_preferredID = [decoder decodeObjectForKey:k_auth0_preferredID];
		auth0_lastUpdated = [decoder decodeObjectForKey:k_auth0_lastUpdated];
		
		if (!auth0_preferredID)
		{
			auth0_preferredID = [Auth0Utilities firstAvailableAuth0IDFromProfiles:auth0_profiles];
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
	[coder encodeObject:blockchainTransaction forKey:k_blockchainTransaction];
	
	[coder encodeObject:random_uuid          forKey:k_random_uuid];
	[coder encodeObject:random_encryptionKey forKey:k_random_encryptionKey];

	[coder encodeObject:[AWSRegions shortNameForRegion:aws_region] forKey:k_aws_regionStr];
	[coder encodeObject:aws_bucket forKey:k_aws_bucket];
	
	[coder encodeBool:accountDeleted forKey:k_accountDeleted];
	[coder encodeObject:lastUpdated forKey:k_lastUpdated];
	
	[coder encodeObject:auth0_profiles    forKey:k_auth0_profiles];
	[coder encodeObject:auth0_preferredID forKey:k_auth0_preferredID];
	[coder encodeObject:auth0_lastUpdated forKey:k_auth0_lastUpdated];
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
	copy->blockchainTransaction = blockchainTransaction;
	
	copy->random_uuid = random_uuid;
	copy->random_encryptionKey = random_encryptionKey;
	
	copy->aws_region = aws_region;
	copy->aws_bucket = aws_bucket;
	
	copy->accountDeleted = accountDeleted;
	copy->lastUpdated = lastUpdated;
	
	copy->auth0_profiles = auth0_profiles;
	copy->auth0_preferredID = auth0_preferredID;
	copy->auth0_lastUpdated = auth0_lastUpdated;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth0
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)preferredProfile
{
	return auth0_profiles[auth0_preferredID];
}

- (NSString *)displayName
{
	NSString *name = [self displayNameForAuth0ID:nil];
	return name;
}

- (NSString *)displayNameForAuth0ID:(NSString *)profileID
{
	NSString *displayName = nil;
	NSDictionary *profile = nil;
	
	if (profileID.length)
	{
		profile = auth0_profiles[profileID];
	}
	else
	{
		profile = self.preferredProfile;
	}

	if (profile)
	{
		NSString * email      = profile[@"email"];
		NSString * name       = profile[@"name"];
		NSString * username   = profile[@"username"];
		NSString * nickname   = profile[@"nickname"];
		NSString * connection = profile[@"connection"];
		
		// process nsdictionary issues
		if ([username isKindOfClass:[NSNull class]]) {
			username = nil;
		}
		if ([email isKindOfClass:[NSNull class]]) {
			email = nil;
		}
		if ([name isKindOfClass:[NSNull class]]) {
			name = nil;
		}
		if ([nickname isKindOfClass:[NSNull class]]) {
			nickname = nil;
		}

		if (![connection isEqualToString:kAuth0DBConnection_Recovery])
		{
			if ([connection isEqualToString:kAuth0DBConnection_UserAuth])
			{
				if ([Auth0Utilities is4thAEmail:email])
				{
					displayName = [Auth0Utilities usernameFrom4thAEmail:email];
					email = nil;
				}
			}

			// fix for weird providers
			if (!name)
			{
				name = [Auth0Utilities correctUserNameForA0Strategy:connection profile:profile];
			}
			
			if (!displayName && name.length) {
				displayName =  name;
			}
			if (!displayName && username.length) {
				displayName =  username;
			}
			if (!displayName && email.length) {
				displayName =  email;
			}
			if (!displayName && nickname.length) {
				displayName =  nickname;
			}
		}
	}

	if (!displayName) {
		displayName = [NSString stringWithFormat:@"<%@>", uuid];
	}
	
	return displayName;
}

- (NSUInteger)nonRecoveryProfileCount
{
	__block NSUInteger count = 0;
	[auth0_profiles enumerateKeysAndObjectsUsingBlock:^(NSString* auth0ID, NSDictionary* profile, BOOL *stop) {

		if (![Auth0Utilities isRecoveryProfile:profile]) {
			count++;
		}
	}];

	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (BOOL)isLocal
{
	// This method is overriden in ZDCLocalUser
	return NO;
}

/**
 * See header file for description.
 */
- (BOOL)isRemote
{
	return (self.isLocal == NO);
}

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
 */
+ (BOOL)isUserID:(NSString *)str
{
	return ((str.length == 32) && [str isZBase32]);
}

/**
 * See header file for description.
 */
+ (BOOL)isAnonymousID:(NSString *)str
{
	return ((str.length == 16) && [str isZBase32]);
}

@end
