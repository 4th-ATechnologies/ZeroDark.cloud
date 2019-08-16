/**
* ZeroDark.cloud
* 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCSplitKey.h"

#import "ZDCObjectSubclass.h"
#import "NSDate+ZeroDark.h"

static int const kCurrentVersion = 0;

static NSString *const k_version			= @"version";
static NSString *const k_uuid    		= @"uuid";
static NSString *const k_localUserID 	= @"localUserID";
static NSString *const k_splitData		= @"splitData";
static NSString *const k_splitNum 		= @"splitNum";
static NSString *const k_sentShares 	= @"sentShares";
static NSString *const k_comment 		= @"comment";

@interface ZDCSplitKey ()
@property (atomic, strong, readwrite) NSDictionary *cachedKeyDict;
@property (atomic, strong, readwrite) NSData	 *splitData;
@end

@implementation ZDCSplitKey

@synthesize uuid = uuid;
@synthesize splitNum = splitNum;
@synthesize localUserID = localUserID;
@synthesize splitData = splitData;
@synthesize sentShares = sentShares;
@synthesize comment = comment;


@synthesize cachedKeyDict = _cachedKeyDict_atomic_property_must_use_selfDot_syntax;

@dynamic keyDict;
@dynamic ownerID;
@dynamic threshold;
@dynamic totalShares;


- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
								splitNum:(NSUInteger)inSplitNum
								splitData:(NSData *)inSplitData;
{
	NSParameterAssert(inLocalUserID != nil);
	NSParameterAssert(inSplitData != nil);
	
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

		splitNum 		= inSplitNum;
		localUserID 	= [inLocalUserID copy];
		splitData  		= [inSplitData copy];
		sentShares		= NULL;
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
		splitData		= [decoder decodeObjectForKey:k_splitData];
		splitNum 		= [decoder decodeIntegerForKey:k_splitNum];
		sentShares		= [decoder decodeObjectForKey:k_sentShares];
		comment			= [decoder decodeObjectForKey:k_comment];
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
	[coder encodeObject:splitData 	forKey:k_splitData];
	[coder encodeInteger:splitNum 	forKey:k_splitNum];
	[coder encodeObject:sentShares 	forKey:k_sentShares];
	[coder encodeObject:comment 		forKey:k_comment];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCSplitKey *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->uuid = uuid;
	copy->localUserID = localUserID;
	copy->splitNum	 	= splitNum;
	copy->splitData 	 = splitData;
	copy->sentShares	 = sentShares;
	copy->comment	 	 = comment;
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
 		keyDict = [NSJSONSerialization JSONObjectWithData:splitData options:0 error:NULL];
		
		if (keyDict) {
			self.cachedKeyDict = keyDict;
		}
	}
	
	return keyDict;
}

- (NSString *)ownerID
{
	return self.keyDict[@(kS4KeyProp_ShareOwner)];
}

- (NSUInteger) threshold
{
	return [self.keyDict[@(kS4KeyProp_ShareThreshold)] integerValue];
}

- (NSUInteger) totalShares
{
	return [self.keyDict[@(kS4KeyProp_ShareTotal)] integerValue];
}

- (NSString *)description
{
	return [self.keyDict description];
}

-(NSDate*)creationDate
{
	
	NSDate* date = self.keyDict[@(kS4KeyProp_StartDate)]
	?[NSDate dateFromRfc3339String:self.keyDict[@(kS4KeyProp_StartDate)]]:nil;

 	return date;
}

- (NSArray <NSString*> *) shareIDs
{
	return  self.keyDict[@"shareIDs"];
}

-(NSDictionary <NSString*, NSNumber*>*) shareNums
{
	return  self.keyDict[@"shareNum"];
}
 
@end
