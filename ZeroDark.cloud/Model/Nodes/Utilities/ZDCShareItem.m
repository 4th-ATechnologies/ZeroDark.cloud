/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCShareItemPrivate.h"

#import "ZDCObjectSubclass.h"
#import "ZDCDictionary.h"
#import "ZDCConstantsPrivate.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version   = @"version";
static NSString *const k_dict      = @"dict";
static NSString *const k_canAddKey = @"canAddKey";


@implementation ZDCShareItem {
	
	ZDCDictionary<NSString*, id> *dict;
}

@dynamic rawDictionary;
@dynamic permissions;
@dynamic key;
@synthesize canAddKey = canAddKey;

@dynamic pubKeyID; // Defined in ZDCShareItemPrivate.h

- (instancetype)init
{
	return [self initWithDictionary:nil];
}

- (instancetype)initWithDictionary:(nullable NSDictionary *)dictionary
{
	if ((self = [super init]))
	{
		dict = [[ZDCDictionary alloc] init];
		[dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			if ([key isKindOfClass:[NSString class]])
			{
				dict[(NSString *)key] = obj;
			}
			
		#pragma clang diagnostic pop
		}];
		
		canAddKey = NO;
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
		canAddKey = [decoder decodeBoolForKey:k_canAddKey];
		
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
	[coder encodeBool:canAddKey forKey:k_canAddKey];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCShareItem *copy = [[ZDCShareItem alloc] init];
	
	copy->dict = [[ZDCDictionary alloc] initWithDictionary:self.rawDictionary copyItems:YES];
	[self->dict copyChangeTrackingTo:copy->dict];
	
	copy->canAddKey = canAddKey;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)rawDictionary
{
	NSDictionary *raw = dict.rawDictionary;
	
	if (raw[kZDCCloudRcrd_Keys_Perms] == nil &&
	    raw[kZDCCloudRcrd_Keys_Deprecated_Perms] == nil)
	{
		// Ensure the rawDictionary has minimum required set of keys:
		// - perms
		
		NSMutableDictionary *_raw = [raw mutableCopy];
		_raw[kZDCCloudRcrd_Keys_Perms] = @"";
		
		raw = [_raw copy];
	}
	
	return raw;
}

/**
 * See header file for description.
 */
- (NSString *)permissions
{
	id value = dict[kZDCCloudRcrd_Keys_Perms];
	if (value == nil)
		value = dict[kZDCCloudRcrd_Keys_Deprecated_Perms];

	if ([value isKindOfClass:[NSString class]])
		return (NSString *)value;
	else
		return @"";
}

/**
 * See header file for description.
 */
- (void)setPermissions:(NSString *)inPermissions
{
	BOOL old_hasReadPermission = [self hasPermission:ZDCSharePermission_Read];
	{
		NSMutableString *newPermissions = [inPermissions mutableCopy];
	
		for (NSUInteger i = 0; i < inPermissions.length; i++)
		{
			NSString *str = [inPermissions substringWithRange:NSMakeRange(i, 1)];
			if (![newPermissions containsString:str])
			{
				[newPermissions appendString:str];
			}
		}
	
		dict[kZDCCloudRcrd_Keys_Perms] = [newPermissions copy];
	
		if ([dict containsKey:kZDCCloudRcrd_Keys_Deprecated_Perms]) {
			[dict removeObjectForKey:kZDCCloudRcrd_Keys_Deprecated_Perms];
		}
	}
	BOOL new_hasReadPermission = [self hasPermission:ZDCSharePermission_Read];
	
	if (!old_hasReadPermission && new_hasReadPermission)
	{
		// User is granting read permission.
		
		self.canAddKey = YES;
	}
	else if (old_hasReadPermission && !new_hasReadPermission)
	{
		// User is removing read permission.
		
		self.key = nil;
		self.canAddKey = NO;
	}
}

/**
 * See header file for description.
 */
- (NSData *)key
{
	id value = dict[kZDCCloudRcrd_Keys_Key];
	if (value == nil)
		value = dict[kZDCCloudRcrd_Keys_Deprecated_SymKey];
	
	if ([value isKindOfClass:[NSString class]])
		value = [[NSData alloc] initWithBase64EncodedString:(NSString *)value options:0];
	
	if ([value isKindOfClass:[NSData class]])
		return (NSData *)value;
	else
		return [NSData data];
}

/**
 * See header file for description.
 */
- (void)setKey:(NSData *)newKey
{
	dict[kZDCCloudRcrd_Keys_Key] = [newKey base64EncodedStringWithOptions:0];
	
	if ([dict containsKey:kZDCCloudRcrd_Keys_Deprecated_SymKey]) {
		[dict removeObjectForKey:kZDCCloudRcrd_Keys_Deprecated_SymKey];
	}
}

- (nullable NSString *)pubKeyID
{
	NSData *key = self.key;
	id value = nil;
	
	// Replace this code with S4 library function (when ready)
	
	id object = [NSJSONSerialization JSONObjectWithData:key options:0 error:nil];
	if ([object isKindOfClass:[NSDictionary class]])
	{
		value = [(NSDictionary *)object objectForKey:@"keyID"];
		
		if ([value isKindOfClass:[NSString class]])
			return (NSString *)value;
	}
	
	value = dict[kZDCCloudRcrd_Keys_Deprecated_PubKeyID];
	
	if ([value isKindOfClass:[NSString class]])
		return (NSString *)value;
	
	return nil;
}

/**
 * See header file for description.
 */
- (BOOL)hasPermission:(ZDCSharePermission)perm
{
	return [self.permissions containsString:[NSString stringWithFormat:@"%C", perm]];
}

/**
 * See header file for description.
 */
- (void)addPermission:(ZDCSharePermission)perm
{
	NSString *permStr = [NSString stringWithFormat:@"%C", perm];
	self.permissions = [self.permissions stringByAppendingString:permStr];
}

/**
 * See header file for description.
 */
- (void)removePermission:(ZDCSharePermission)perm
{
	NSString *permStr = [NSString stringWithFormat:@"%C", perm];
	
	NSMutableString *newPermissions = [self.permissions mutableCopy];
	BOOL modified = NO;
	
	NSRange range = [newPermissions rangeOfString:permStr];
	while (range.location != NSNotFound)
	{
		[newPermissions deleteCharactersInRange:range];
		
		modified = YES;
		range = [newPermissions rangeOfString:permStr];
	}
	
	if (modified) {
		self.permissions = newPermissions;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject Overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableSet<NSString*> *)monitoredProperties
{
	NSMutableSet<NSString*> *monitoredProperties = [super monitoredProperties];
	
	[monitoredProperties removeObject:NSStringFromSelector(@selector(rawDictionary))];
	[monitoredProperties removeObject:NSStringFromSelector(@selector(permissions))];
	[monitoredProperties removeObject:NSStringFromSelector(@selector(key))];
	
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
	ZDCShareItem *cloudVersion = (ZDCShareItem *)inCloudVersion;
	
	return [dict mergeCloudVersion: cloudVersion->dict
	         withPendingChangesets: pendingChangesets
	                         error: errPtr];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (BOOL)isEqual:(id)another
{
	if ([another isKindOfClass:[ZDCShareItem class]])
		return [self isEqualToShareItem:(ZDCShareItem *)another];
	else
		return NO;
}

/**
 * See header file for description.
 */
- (BOOL)isEqualToShareItem:(ZDCShareItem *)another
{
	return [self->dict isEqualToDictionary:another->dict];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debug
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [self.rawDictionary description];
}

@end
