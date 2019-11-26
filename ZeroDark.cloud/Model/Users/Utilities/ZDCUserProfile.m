/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserProfile.h"
#import "ZDCUserIdentityPrivate.h"

static NSString *const k_userID     = @"userID";
static NSString *const k_name       = @"name";
static NSString *const k_nickname   = @"nickname";
static NSString *const k_email      = @"email";
static NSString *const k_picture    = @"picture";
static NSString *const k_createdAt  = @"createdAt";
static NSString *const k_identities = @"identities";
static NSString *const k_extraInfo  = @"extraInfo";


@implementation ZDCUserProfile

@synthesize userID = _userID;
@synthesize name = _name;
@synthesize nickname = _nickname;
@synthesize email = _email;
@synthesize picture = _picture;
@synthesize createdAt = _createdAt;
@synthesize identities = _identities;
@synthesize extraInfo = _extraInfo;

@dynamic appMetadata;
@dynamic userMetadata;

@dynamic appMetadata_awsID;
@dynamic appMetadata_region;
@dynamic appMetadata_bucket;

@dynamic userMetadata_preferredIdentityID;

@dynamic isUserBucketSetup;


NSDate *DateFromISO8601String(NSString *string) {
	
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	[dateFormatter setLocale:enUSPOSIXLocale];
	[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
	return [dateFormatter dateFromString:string];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
	if ((self = [super init]))
	{
		id value;
		
		value = dictionary[@"user_id"];
		if ([value isKindOfClass:[NSString class]]) {
			_userID = [(NSString *)value copy];
		}
		
		value = dictionary[@"name"];
		if ([value isKindOfClass:[NSString class]]) {
			_name = [(NSString *)value copy];
		}
		
		value = dictionary[@"nickname"];
		if ([value isKindOfClass:[NSString class]]) {
			_nickname = [(NSString *)value copy];
		}
		
		value = dictionary[@"email"];
		if ([value isKindOfClass:[NSString class]]) {
			_email = [(NSString *)value copy];
		}
		
		value = dictionary[@"picture"];
		if ([value isKindOfClass:[NSString class]]) {
			_picture  = [NSURL URLWithString:(NSString *)value];
		}
		
		value = dictionary[@"created_at"];
		if ([value isKindOfClass:[NSString class]]) {
			_createdAt = DateFromISO8601String((NSString *)value);
		}
		
		value = dictionary[@"identities"];
		if ([value isKindOfClass:[NSArray class]])
		{
			NSArray *list_unparsed = (NSArray *)value;
			NSMutableArray<ZDCUserIdentity *> *list_parsed = [NSMutableArray arrayWithCapacity:list_unparsed.count];
			
			for (id json in list_unparsed)
			{
				if ([json isKindOfClass:[NSDictionary class]])
				{
					ZDCUserIdentity *identity = [[ZDCUserIdentity alloc] initWithDictionary:(NSDictionary *)json];
					if (identity) {
						[list_parsed addObject:identity];
					}
				}
			}
			
			_identities = [list_parsed copy];
		}
		else {
			_identities = [[NSArray alloc] init];
		}
		
		NSMutableDictionary *extraInfo = [dictionary mutableCopy];
		[extraInfo removeObjectsForKeys:@[
			@"user_id", @"name", @"nickname", @"email", @"picture", @"created_at", @"identities"
		]];
		
		// Auth0 removes the profileData from the first identity for some reason.
		// So we restore that information.
		
		ZDCUserIdentity *primaryIdentity = [_identities firstObject];
		if (primaryIdentity)
		{
			NSMutableDictionary *profileData = [primaryIdentity.profileData mutableCopy];
			
			if (_name && !profileData[@"name"]) {
				profileData[@"name"] = _name;
			}
			
			if (_nickname && !profileData[@"nickname"]) {
				profileData[@"nickname"] = _nickname;
			}
			
			if (_email && !profileData[@"email"]) {
				profileData[@"email"] = _email;
			}
			
			if (_picture && !profileData[@"picture"]) {
				profileData[@"picture"] = _picture;
			}
			
			primaryIdentity.profileData = profileData;
		}
		
		// Auth0 flattens the app_metadata & user_metadata sections for some reason.
		// So we remove this extra noise.
		
		value = extraInfo[@"app_metadata"];
		if ([value isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *appMetadata = (NSDictionary *)value;
			
			for (id key in appMetadata)
			{
				value = appMetadata[key];
				if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]])
				{
					id meta_value = value;
					id flat_value = extraInfo[key];
					
					if (flat_value && [flat_value isEqual:meta_value])
					{
						extraInfo[key] = nil;
					}
				}
			}
		}
		
		_extraInfo = [extraInfo copy];
	}
	return self;
}

- (instancetype)initWithFilteredProfileDictionary:(NSDictionary *)dict
{
	if ((self = [self init]))
	{
		id value;
		
		value = dict[@"identities"];
		if ([value isKindOfClass:[NSArray class]])
		{
			NSArray *list_unparsed = (NSArray *)value;
			NSMutableArray<ZDCUserIdentity *> *list_parsed = [NSMutableArray arrayWithCapacity:list_unparsed.count];
			
			for (id json in list_unparsed)
			{
				if ([json isKindOfClass:[NSDictionary class]])
				{
					ZDCUserIdentity *identity = [[ZDCUserIdentity alloc] initWithDictionary:(NSDictionary *)json];
					if (identity) {
						[list_parsed addObject:identity];
					}
				}
			}
			
			_identities = [list_parsed copy];
		}
		else {
			_identities = [[NSArray alloc] init];
		}
		
		NSMutableDictionary *extraInfo = [NSMutableDictionary dictionaryWithCapacity:3];
		
		extraInfo[@"user_metadata"] = [dict[@"user_metadata"] copy];
		extraInfo[@"app_metadata"]  = [dict[@"app_metadata"]  copy];
		extraInfo[@"updated_at"]    = [dict[@"updated_at"]    copy];
		
		_extraInfo = [extraInfo copy];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		_userID     = [decoder decodeObjectOfClass:[NSString class]     forKey:k_userID];
		_name       = [decoder decodeObjectOfClass:[NSString class]     forKey:k_name];
		_nickname   = [decoder decodeObjectOfClass:[NSString class]     forKey:k_nickname];
		_email      = [decoder decodeObjectOfClass:[NSString class]     forKey:k_email];
		_picture    = [decoder decodeObjectOfClass:[NSURL class]        forKey:k_picture];
		_createdAt  = [decoder decodeObjectOfClass:[NSDate class]       forKey:k_createdAt];
		_identities = [decoder decodeObjectOfClass:[NSArray class]      forKey:k_identities];
		_extraInfo  = [decoder decodeObjectOfClass:[NSDictionary class] forKey:k_extraInfo];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_userID     forKey:k_userID];
	[coder encodeObject:_name       forKey:k_name];
	[coder encodeObject:_nickname   forKey:k_nickname];
	[coder encodeObject:_email      forKey:k_email];
	[coder encodeObject:_picture    forKey:k_picture];
	[coder encodeObject:_createdAt  forKey:k_createdAt];
	[coder encodeObject:_extraInfo  forKey:k_extraInfo];
	[coder encodeObject:_identities forKey:k_identities];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)appMetadata
{
	id value = _extraInfo[@"app_metadata"];
	if ([value isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary *)value;
	} else {
		return @{};
	}
}

- (NSDictionary *)userMetadata
{
	id value = _extraInfo[@"user_metadata"];
	if ([value isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary *)value;
	} else {
		return @{};
	}
}

- (nullable NSString *)appMetadata_awsID
{
	id value = self.appMetadata[@"aws_id"];
	
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	} else {
		return nil;
	}
}

- (nullable NSString *)appMetadata_region
{
	id value = self.appMetadata[@"region"];
	
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	} else {
		return nil;
	}
}

- (nullable NSString *)appMetadata_bucket
{
	id value = self.appMetadata[@"bucket"];
	
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	} else {
		return nil;
	}
}

- (nullable NSString *)userMetadata_preferredIdentityID
{
	id value = self.userMetadata[@"preferredAuth0ID"];
	
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	} else {
		return nil;
	}
}

- (BOOL)isUserBucketSetup
{
	NSString *region = self.appMetadata_region;
	if (region.length == 0) {
		return NO;
	}
	
	NSString *bucket = self.appMetadata_bucket;
	if (bucket.length == 0) {
		return NO;
	}
	
	return YES;
}

- (nullable ZDCUserIdentity *)identityWithID:(NSString *)identityID
{
	ZDCUserIdentity *match = nil;
	if (identityID)
	{
		for (ZDCUserIdentity *ident in _identities)
		{
			if ([ident.identityID isEqualToString:identityID])
			{
				match = ident;
				break;
			}
		}
	}
	
	return match;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	NSString *description = [NSString stringWithFormat:
		@"<%@: %p (\nuserId: %@ \nname: %@ \nidentities: %@ \nextraInfo: %@\n)>",
		NSStringFromClass([self class]),
		self,
		_userID,
		_name,
		_identities,
		_extraInfo
	];
	return description;
}

@end
