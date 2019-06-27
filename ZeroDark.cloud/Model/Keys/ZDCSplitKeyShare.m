
/* ZeroDark.cloud
* 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCSplitKeyShare.h"

#import "ZDCObjectSubclass.h"
#import "NSDate+ZeroDark.h"
#import <S4Crypto/S4Crypto.h>
#import "ZDCConstants.h"


static int const kCurrentVersion = 0;

static NSString *const k_version			= @"version";
static NSString *const k_uuid    		= @"uuid";
static NSString *const k_localUserID 	= @"localUserID";
static NSString *const k_shareData		= @"shareData";

@interface ZDCSplitKeyShare ()
@property (atomic, strong, readwrite) NSDictionary *cachedKeyDict;
@property (atomic, strong, readwrite) NSData	 *shareData;
@end

@implementation ZDCSplitKeyShare

@synthesize uuid = uuid;
@synthesize localUserID = localUserID;
@synthesize shareData = shareData;


@synthesize cachedKeyDict = _cachedKeyDict_atomic_property_must_use_selfDot_syntax;

@dynamic keyDict;
@dynamic ownerID;
@dynamic shareID;
@dynamic shareUserID;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
 								  shareData:(NSData *)inShareData;
{
	NSParameterAssert(inLocalUserID != nil);
	NSParameterAssert(inShareData != nil);
	
	if ((self = [super init]))
	{
		
		// IMPORTANT:
		//
		// The `uuid` MUST be a randomly generated value.
		// It MUST NOT be the keyID value.
		//
		// In other words: (uuid != JSON.keyID) <= REQUIRED
		//
		// Why ?
		// Because there's a simple denial-of-service attack.
		// A user simply needs to upload a fake '.pubKey' file to their account,
		// which has the same keyID as some other user.
		// Now, the user simply needs to communicate with other users which will:
		// - cause them to download the .pubKey for the rogue user
		// - insert it into their database, and thus replacing the pubKey for the target (of the DOS attack)
		// - and now a bunch of users have an invalid pubKey for the target
		//
		// Even worse, the attacker could simply communicate with the target.
		// The same thing would happen, but the target would end up replacing their own private key !
		//
		uuid = [[NSUUID UUID] UUIDString];
		//
		// Do NOT change this code.
		// Read the giant comment block above first.
		
 		localUserID 	= [inLocalUserID copy];
		shareData  		= [inShareData copy];
 	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//MARK: NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Version History:
 *
 * // Goes here ...
 **/

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		//	int version = [decoder decodeIntForKey:k_version];
		
		uuid        	= [decoder decodeObjectForKey:k_uuid];
		localUserID  	= [decoder decodeObjectForKey:k_localUserID];
		shareData		= [decoder decodeObjectForKey:k_shareData];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:uuid        	forKey:k_uuid];
	[coder encodeObject:localUserID 	forKey:k_localUserID];
	[coder encodeObject:shareData 	forKey:k_shareData];
 }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCSplitKeyShare *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->uuid = uuid;
	copy->localUserID = localUserID;
 	copy->shareData 	 = shareData;
 	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//MARK: ZDCObject
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides ZDCObject.
 * Allows us to specify our atomic cachedX properties as ignored (for immutability purposes).
 **/
+ (NSMutableSet<NSString *> *)monitoredProperties
{
	NSMutableSet<NSString *> *result = [super monitoredProperties];
	[result removeObject:NSStringFromSelector(@selector(cachedKeyDict))];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//MARK: KeyDict Values
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)keyDict
{
	// Note: We MUST use atomic getter & setter (to be thread-safe)
	
	NSDictionary *keyDict = self.cachedKeyDict;
	if (keyDict == nil)
	{
		keyDict = [NSJSONSerialization JSONObjectWithData:shareData options:0 error:NULL];
		
		if (keyDict) {
			self.cachedKeyDict = keyDict;
		}
	}
	
	return keyDict;
}

- (NSString *)description
{
	return [self.keyDict description];
}

 - (NSString *)shareID
{
	return self.keyDict[@(kS4KeyProp_ShareID)];
 }

 - (NSString *)ownerID
{
	return self.keyDict[@(kS4KeyProp_ShareOwner)];
}

- (NSString *)shareUserID
{
	return self.keyDict[kZDCCloudRcrd_UserID];
}

@end
