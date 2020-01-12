/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCShareList.h"

#import "ZDCObjectSubclass.h"
#import "ZDCDictionary.h"
#import "ZDCConstantsPrivate.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 2;
#pragma unused(kCurrentVersion)

static NSString *const k_version = @"version";
static NSString *const k_dict    = @"dict";

// Extern Constants

/* extern */ NSString *const ZDCShareKeyType_User       = @"UID";
/* extern */ NSString *const ZDCShareKeyType_Server     = @"SRV";
/* extern */ NSString *const ZDCShareKeyType_Passphrase = @"PASS";


@implementation ZDCShareList {
	
	ZDCDictionary<NSString*, ZDCShareItem*> *dict;
}

@dynamic rawDictionary;
@dynamic count;

/**
 * See header file for description.
 */
- (id)init
{
	return [self initWithDictionary:nil];
}

/**
 * See header file for description.
 */
- (id)initWithDictionary:(nullable NSDictionary *)dictionary
{
	if ((self = [super init]))
	{
		dict = [[ZDCDictionary alloc] init];
		
		[dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]])
			{
				ZDCShareItem *item = [[ZDCShareItem alloc] initWithDictionary:(NSDictionary *)obj];
				
				dict[(NSString *)key] = item;
			}
			
		#pragma clang diagnostic pop
		}];
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
		dict = [decoder decodeObjectForKey:k_dict];
		
		// Sanity check:
		if (!dict) {
			dict = [[ZDCDictionary alloc] init];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:dict forKey:k_dict];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCShareList *copy = [[ZDCShareList alloc] init];
	
	ZDCDictionary *deepCopy = [[ZDCDictionary alloc] init];
	[dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, ZDCShareItem *shareItem, BOOL *stop) {
		
		deepCopy[key] = [shareItem copy];
	}];
	
	copy->dict = deepCopy;
	[self->dict copyChangeTrackingTo:deepCopy];
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)rawDictionary
{
	NSMutableDictionary *rawList = [NSMutableDictionary dictionaryWithCapacity:dict.count];
	
	[dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, ZDCShareItem *shareItem, BOOL *stop) {
		
		rawList[key] = shareItem.rawDictionary;
	}];
	
	return rawList;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Counts
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)count
{
	return dict.count;
}

- (NSUInteger)countOfUserIDs
{
	return [self countOfUserIDsExcluding:nil];
}

- (NSUInteger)countOfUserIDsExcluding:(nullable NSString *)excludingUserID
{
	__block NSUInteger count = 0;
	
	[dict enumerateKeysUsingBlock:^(NSString *key, BOOL *stop) {
		
		NSString *userID = [ZDCShareList userIDFromKey:key];
		if (userID)
		{
			if (excludingUserID && [userID isEqualToString:excludingUserID]) {
				// ignore
			}
			else {
				count++;
			}
		}
	}];
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Read
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (BOOL)hasShareItemForKey:(NSString *)key
{
	return [dict containsKey:key];
}

/**
 * See header file for description.
 */
- (BOOL)hasShareItemForUserID:(NSString *)userID
{
	NSString *key = [[self class] keyForUserID:userID];
	return [dict containsKey:key];
}

/**
 * See header file for description.
 */
- (BOOL)hasShareItemForServerID:(NSString *)serverID
{
	NSString *key = [[self class] keyForServerID:serverID];
	return [dict containsKey:key];
}

/**
 * See header file for description.
 */
- (nullable ZDCShareItem *)shareItemForKey:(NSString *)key
{
	return dict[key];
}

/**
 * See header file for description.
 */
- (nullable ZDCShareItem *)shareItemForUserID:(NSString *)userID
{
	NSString *key = [[self class] keyForUserID:userID];
	return dict[key];
}

/**
 * See header file for description.
 */
- (nullable ZDCShareItem *)shareItemForServerID:(NSString *)serverID
{
	NSString *key = [[self class] keyForServerID:serverID];
	return dict[key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Write
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (BOOL)addShareItem:(ZDCShareItem *)item forKey:(NSString *)key
{
	if (!key || ![[self class] isValidKey:key]) {
		NSAssert(NO, @"Invalid key - will be silently ignored in production. Do you have a bug ?");
		return NO;
	}
	if (item && ![item isKindOfClass:[ZDCShareItem class]]) {
		NSAssert(NO, @"Invalid item - will be silently ignored in production. Do you have a bug ?");
		return NO;
		
	}
	
	if ([dict containsKey:key]) {
		return NO; // Did you read the description in the header file ?
	}
	else {
		dict[key] = [item copy];
		return YES;
	}
}

/**
 * See header file for description.
 */
- (BOOL)addShareItem:(ZDCShareItem *)item forUserID:(NSString *)userID
{
	NSString *key = [[self class] keyForUserID:userID];
	return [self addShareItem:item forKey:key];
}

/**
 * See header file for description.
 */
- (BOOL)addShareItem:(ZDCShareItem *)item forServerID:(NSString *)serverID
{
	NSString *key = [[self class] keyForServerID:serverID];
	return [self addShareItem:item forKey:key];
}

/**
 * See header file for description.
 */
- (void)removeShareItemForKey:(NSString *)key
{
	if (key == nil) return;
	
	dict[key] = nil;
}

/**
 * See header file for description.
 */
- (void)removeShareItemForUserID:(NSString *)userID
{
	NSString *key = [[self class] keyForUserID:userID];
	[self removeShareItemForKey:key];
}

/**
 * See header file for description.
 */
- (void)removeShareItemForServerID:(NSString *)serverID
{
	NSString *key = [[self class] keyForServerID:serverID];
	[self removeShareItemForKey:key];
}

/**
 * See header file for description.
 */
- (void)removeAllShareItems
{
	[dict removeAllObjects];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (NSArray<NSString *> *)allKeys
{
	return [dict allKeys];
}

/**
 * See header file for description.
 */
- (NSArray<NSString *> *)allUserIDs
{
	NSMutableArray *userIDs = [NSMutableArray array];
	
	[dict enumerateKeysUsingBlock:^(NSString *key, BOOL *stop) {
		
		NSString *userID = [ZDCShareList userIDFromKey:key];
		if (userID) {
			[userIDs addObject:userID];
		}
	}];
	
	return userIDs;
}

/**
 * Enumerates all items in the list.
 */
- (void)enumerateListWithBlock:(void (^)(NSString *key, ZDCShareItem *shareItem, BOOL *stop))block
{
	[dict enumerateKeysAndObjectsUsingBlock:block];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (BOOL)isEqual:(nullable id)another
{
	if ([another isKindOfClass:[ZDCShareList class]]) {
		return [self isEqualToShareList:(ZDCShareList *)another];
	}
	else {
		return NO;
	}
}

/**
 * See header file for description.
 */
- (BOOL)isEqualToShareList:(ZDCShareList *)another
{
	if (self.count != another.count) return NO;
	
	__block BOOL notEqual = NO;
	[self enumerateListWithBlock:^(NSString *key, ZDCShareItem *shareItem_self, BOOL *stop) {
		
		ZDCShareItem *shareItem_another = another->dict[key];
		
		if (!shareItem_another || ![shareItem_self isEqualToShareItem:shareItem_another])
		{
			notEqual = YES;
			*stop = YES;
		}
	}];
	
	return !notEqual;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject Overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableSet<NSString*> *)monitoredProperties
{
	NSMutableSet<NSString*> *monitoredProperties = [super monitoredProperties];
	
	[monitoredProperties removeObject:NSStringFromSelector(@selector(rawDictionary))];
	[monitoredProperties removeObject:NSStringFromSelector(@selector(count))];
	
	return monitoredProperties;
}

- (void)makeImmutable
{
	[dict makeImmutable];
	[super makeImmutable];
}

- (BOOL)hasChanges
{
	if ([dict hasChanges]) return YES;
	if ([super hasChanges]) return YES;
	
	return NO;
}

- (void)clearChangeTracking
{
	[dict clearChangeTracking];
	[super clearChangeTracking];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCSyncable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable NSDictionary *)changeset
{
	return [dict changeset];
}

- (nullable NSDictionary *)peakChangeset
{
	return [dict peakChangeset];
}

- (nullable NSDictionary *)undo:(NSDictionary *)changeset error:(NSError **)errPtr
{
	return [dict undo:changeset error:errPtr];
}

- (nullable NSError *)performUndo:(NSDictionary *)changeset
{
	return [dict performUndo:changeset];
}

- (void)rollback
{
	[dict rollback];
}

- (nullable NSDictionary *)mergeChangesets:(NSArray<NSDictionary*> *)orderedChangesets
                                     error:(NSError *_Nullable *_Nullable)errPtr
{
	return [dict mergeChangesets:orderedChangesets error:errPtr];
}

- (nullable NSError *)importChangesets:(NSArray<NSDictionary*> *)orderedChangesets
{
	return [dict importChangesets:orderedChangesets];
}

- (nullable NSDictionary *)mergeCloudVersion:(nonnull id)inCloudVersion
                       withPendingChangesets:(nullable NSArray<NSDictionary *> *)pendingChangesets
                                       error:(NSError *__autoreleasing  _Nullable * _Nullable)errPtr
{
	if (![inCloudVersion isKindOfClass:[self class]])
	{
		if (errPtr) *errPtr = [self incorrectObjectClass];
		return nil;
	}
	ZDCShareList *cloudVersion = (ZDCShareList *)inCloudVersion;
	
	return [dict mergeCloudVersion: cloudVersion->dict
	         withPendingChangesets: pendingChangesets
	                         error: errPtr];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debug
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [self.rawDictionary description];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (BOOL)isUserKey:(NSString *)key
{
	return [key hasPrefix:[ZDCShareKeyType_User stringByAppendingString:@":"]];
}

/**
 * See header file for description.
 */
+ (BOOL)isServerKey:(NSString *)key
{
	return [key hasPrefix:[ZDCShareKeyType_Server stringByAppendingString:@":"]];
}

/**
 * See header file for description.
 */
+ (NSString *)keyForUserID:(NSString *)userID
{
	return [NSString stringWithFormat:@"%@:%@", ZDCShareKeyType_User, userID];
}

/**
 * See header file for description.
 */
+ (nullable NSString *)userIDFromKey:(NSString *)key
{
	NSString *prefix = [ZDCShareKeyType_User stringByAppendingString:@":"];
	
	if ([key hasPrefix:prefix]) {
		return [key substringFromIndex:prefix.length];
	} else {
		return nil;
	}
}

/**
 * See header file for description.
 */
+ (NSString *)keyForServerID:(NSString *)serverID
{
	return [NSString stringWithFormat:@"%@:%@", ZDCShareKeyType_Server, serverID];
}

/**
 * See header file for description.
 */
+ (nullable NSString *)serverIDFromKey:(NSString *)key
{
	NSString *prefix = [ZDCShareKeyType_Server stringByAppendingString:@":"];
	
	if ([key hasPrefix:prefix]) {
		return [key substringFromIndex:prefix.length];
	} else {
		return nil;
	}
}

/**
 * All keys have the same format: "<type>:<identifier_for_type>".
 * This method returns whether or not the key has the correct format.
 */
+ (BOOL)isValidKey:(NSString *)key
{
	NSArray<NSString*> *components = [key componentsSeparatedByString:@":"];
	
	// identifiers in our system never contain the ':' character
	return (components.count == 2);
}

/**
 * This method is no longer needed.
 *
 * > This method checks to see if 2 shareLists are equal,
 * > but ignores the salted bits of the encryption key.
 */
+ (BOOL)isShareList:(NSDictionary *)list1 equalTo:(NSDictionary *)list2
{
	if (list1.count != list2.count) return NO;
	
	for (NSString *key in list1)
	{
		id dict1 = list1[key];
		id dict2 = list2[key];
		
		if (![dict1 isKindOfClass:[NSDictionary class]]) return NO;
		if (![dict2 isKindOfClass:[NSDictionary class]]) return NO;
		
		NSMutableDictionary *item1 = [dict1 mutableCopy];
		NSMutableDictionary *item2 = [dict2 mutableCopy];
		
		/**
		 * item1 & item2 should look like this:
		 * {
		 *   "perms": <string>,
		 *   "burn": <optional_date_as_string>,
		 *   "key": "...really big string..." // <-- this has salt
		 * }
		 */
		
		NSString *str1 = item1[kZDCCloudRcrd_Keys_Key];
		NSString *str2 = item2[kZDCCloudRcrd_Keys_Key];
		
		if (str1 == nil) str1 = item1[kZDCCloudRcrd_Keys_Deprecated_SymKey];
		if (str2 == nil) str2 = item2[kZDCCloudRcrd_Keys_Deprecated_SymKey];
		
		item1[kZDCCloudRcrd_Keys_Key] = nil;
		item2[kZDCCloudRcrd_Keys_Key] = nil;
		
		item1[kZDCCloudRcrd_Keys_Deprecated_SymKey] = nil;
		item2[kZDCCloudRcrd_Keys_Deprecated_SymKey] = nil;
		
		if (![item1 isEqualToDictionary:item2]) return NO;
		
		if (![str1 isKindOfClass:[NSString class]]) return NO;
		if (![str2 isKindOfClass:[NSString class]]) return NO;
		
		NSData *data1 = [[NSData alloc] initWithBase64EncodedString:str1 options:0];
		NSData *data2 = [[NSData alloc] initWithBase64EncodedString:str2 options:0];
		
		NSDictionary *key1 = nil;
		NSDictionary *key2 = nil;
		
		if (data1) {
			key1 = [NSJSONSerialization JSONObjectWithData:data1 options:0 error:nil];
		}
		if (data2) {
			key2 = [NSJSONSerialization JSONObjectWithData:data2 options:0 error:nil];
		}
		
		if (![key1 isKindOfClass:[NSDictionary class]]) return NO;
		if (![key2 isKindOfClass:[NSDictionary class]]) return NO;
		
		/**
		 * key1 && key2 should look like this:
		 * {
		 *   "version": 1,
		 *   "encoding": "Curve41417",
		 *   "keyID": "40bceV15G5ZaPTckJ0022Q==",
		 *   "keySuite": "ThreeFish-512",
		 *   "mac": "ed9IY0dk6sk=",
		 *   "encrypted": "...really big string..." // <-- this has salt
		 * }
		 **/
		
		NSMutableDictionary *sKey1 = [key1 mutableCopy];
		NSMutableDictionary *sKey2 = [key2 mutableCopy];
		
		sKey1[@"encrypted"] = nil;
		sKey2[@"encrypted"] = nil;
		
		// The keyID is derived from the key bits.
		// (I'm pretty sure it's a hash, but I'd need to double-check to be sure.)
		//
		// So the idea here is that if all the other stuff is the same (including keyID),
		// then the key is also the same as well.
		//
		// Note: If an attacker tried to fake it by chaning the key, but not changing the keyID,
		//       the key wouldn't pass the "self test" stage, and would be rejected by the system.
		
		if (![sKey1 isEqualToDictionary:sKey2]) return NO;
	}
	
	return YES;
}

/**
 * See header file for description.
 */
+ (ZDCShareList *)defaultShareListForTrunk:(ZDCTreesystemTrunk)trunk
                           withLocalUserID:(NSString *)localUserID
{
	ZDCShareList *shareList = [[ZDCShareList alloc] init];
	
	switch (trunk)
	{
		case ZDCTreesystemTrunk_Home:
		{
			{ // "UID:{localUserID}" : "rws"
				
				ZDCShareItem *shareItem = [[ZDCShareItem alloc] init];
				[shareItem addPermission:ZDCSharePermission_Read];
				[shareItem addPermission:ZDCSharePermission_Write];
				[shareItem addPermission:ZDCSharePermission_Share];
			
				[shareList addShareItem:shareItem forUserID:localUserID];
			}
			break;
		}
		case ZDCTreesystemTrunk_Prefs:
		{
			{ // "UID:{localUserID}" : "rws"
				
				ZDCShareItem *shareItem = [[ZDCShareItem alloc] init];
				[shareItem addPermission:ZDCSharePermission_Read];
				[shareItem addPermission:ZDCSharePermission_Write];
				[shareItem addPermission:ZDCSharePermission_Share];
				
				[shareList addShareItem:shareItem forUserID:localUserID];
			}
			break;
		}
		case ZDCTreesystemTrunk_Inbox:
		{
			{ // "UID:{localUserID}" : "rws"
				
				ZDCShareItem *shareItem = [[ZDCShareItem alloc] init];
				[shareItem addPermission:ZDCSharePermission_Read];
				[shareItem addPermission:ZDCSharePermission_Write];
				[shareItem addPermission:ZDCSharePermission_Share];
				
				[shareList addShareItem:shareItem forUserID:localUserID];
			}
			{ // "UID:*" : "WB"
				
				ZDCShareItem *shareItem = [[ZDCShareItem alloc] init];
				[shareItem addPermission:ZDCSharePermission_WriteOnce];
				[shareItem addPermission:ZDCSharePermission_BurnIfSender];
				
				[shareList addShareItem:shareItem forUserID:@"*"];
			}
			break;
		}
		case ZDCTreesystemTrunk_Outbox:
		{
			{ // "UID:{localUserID}" : "rws"
				
				ZDCShareItem *shareItem = [[ZDCShareItem alloc] init];
				[shareItem addPermission:ZDCSharePermission_Read];
				[shareItem addPermission:ZDCSharePermission_Write];
				[shareItem addPermission:ZDCSharePermission_Share];
				
				[shareList addShareItem:shareItem forUserID:localUserID];
			}
			break;
		}
		default: break;
	}
	
	return shareList;
}

@end
