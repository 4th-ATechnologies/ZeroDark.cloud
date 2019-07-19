/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "A0UserProfile.h"

#import "A0UserIdentity.h"
#import "Auth0API.h"

@implementation A0UserProfile

NSDate *dateFromISO8601String(NSString *string) {
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	[dateFormatter setLocale:enUSPOSIXLocale];
	[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
	return [dateFormatter dateFromString:string];
}

+(instancetype) profileFromFilteredProfileDict:(NSDictionary*)info
{
	A0UserProfile* profile = nil;

	profile = [[A0UserProfile alloc] initWithFilteredProfileDictionary:info];

 	return profile;
}

- (instancetype)initWithFilteredProfileDictionary:(NSDictionary *)dict {

//	if( !dict[@"user_id"]  ) return nil;

	if (self = [self init]) {

		NSMutableDictionary	*extraInfo = NSMutableDictionary.dictionary;

		NSArray *identitiesJSON = dict[@"identities"];
		NSMutableArray *identities = [[NSMutableArray alloc] initWithCapacity:identitiesJSON.count];
		for (NSDictionary *identityJSON in identitiesJSON) {
			[identities addObject:[A0UserIdentity identityFromDictionary:identityJSON]];
		}


		NSDictionary	*user_metadata = [NSDictionary dictionaryWithDictionary:dict[@"user_metadata"]];
		NSDictionary	*app_metadata = [NSDictionary dictionaryWithDictionary:dict[@"app_metadata"]];

		id updated_at = dict[@"updated_at"];

		if(user_metadata.count)
			extraInfo[@"user_metadata"] = user_metadata;

		if(app_metadata.count)
			extraInfo[@"app_metadata"] = app_metadata;

		if(updated_at)
			extraInfo[@"updated_at"] = updated_at;


		_extraInfo = extraInfo;
		_identities = identities;

	}
	return self;


}


+ (instancetype)profileFromDictionary:(NSDictionary *)dict {

	A0UserProfile* profile = nil;

	profile = [[A0UserProfile alloc] initWithDictionary:dict];

	return profile;
}


- (instancetype)initWithDictionary:(NSDictionary *)dictionary {

	if( !dictionary[@"user_id"]  ) return nil;
	
	self = [self initWithUserId:dictionary[@"user_id"]
						   name:dictionary[@"name"]
					   nickname:dictionary[@"nickname"]
						  email:dictionary[@"email"]
						picture:[NSURL URLWithString:dictionary[@"picture"]]
					  createdAt:dateFromISO8601String(dictionary[@"created_at"])];
	if (self) {
		NSArray *identitiesJSON = dictionary[@"identities"];
		NSMutableDictionary *extraInfo = [dictionary mutableCopy];
		[extraInfo removeObjectsForKeys:@[@"user_id", @"name", @"nickname", @"email", @"picture", @"created_at", @"identities"]];
		NSMutableArray *identities = [[NSMutableArray alloc] initWithCapacity:identitiesJSON.count];
		for (NSDictionary *identityJSON in identitiesJSON) {
			[identities addObject:[A0UserIdentity identityFromDictionary:identityJSON]];
		}
		_identities = [NSArray arrayWithArray:identities];
		_extraInfo = extraInfo;
	}
	return self;
}

- (NSDictionary *)userMetadata {
	return self.extraInfo[@"user_metadata"] ?: @{};
}

- (NSDictionary *)appMetadata {
	return self.extraInfo[@"app_metadata"] ?: @{};
}

- initWithUserId:(NSString *)userId
			name:(NSString *)name
		nickname:(NSString *)nickname
		   email:(NSString *)email
		 picture:(NSURL *)picture
	   createdAt:(NSDate *)createdAt {
	self = [super init];
	if (self) {
		NSAssert(userId.length > 0, @"Should have a non empty user id");
		_userId = [userId copy];
		_name = [name copy];
		_nickname = [nickname copy];
		_email = [email copy];
		_picture = picture;
		_createdAt = createdAt;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	self = [self initWithUserId:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(userId))]
						   name:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(name))]
					   nickname:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(nickname))]
						  email:[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(email))]
						picture:[aDecoder decodeObjectOfClass:NSURL.class forKey:NSStringFromSelector(@selector(picture))]
					  createdAt:[aDecoder decodeObjectOfClass:NSDate.class forKey:NSStringFromSelector(@selector(createdAt))]];
	if (self) {
		_extraInfo = [aDecoder decodeObjectOfClass:NSDictionary.class forKey:NSStringFromSelector(@selector(extraInfo))];
		_identities = [aDecoder decodeObjectOfClass:NSArray.class forKey:NSStringFromSelector(@selector(identities))];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
	[aCoder encodeObject:self.userId forKey:NSStringFromSelector(@selector(userId))];
	if (self.name) {
		[aCoder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
	}
	if (self.nickname) {
		[aCoder encodeObject:self.nickname forKey:NSStringFromSelector(@selector(nickname))];
	}
	if (self.email) {
		[aCoder encodeObject:self.email forKey:NSStringFromSelector(@selector(email))];
	}
	if (self.picture) {
		[aCoder encodeObject:self.picture forKey:NSStringFromSelector(@selector(picture))];
	}
	if (self.createdAt) {
		[aCoder encodeObject:self.createdAt forKey:NSStringFromSelector(@selector(createdAt))];
	}
	if (self.extraInfo) {
		[aCoder encodeObject:self.extraInfo forKey:NSStringFromSelector(@selector(extraInfo))];
	}
	if (self.identities) {
		[aCoder encodeObject:self.identities forKey:NSStringFromSelector(@selector(identities))];
	}
}

+ (BOOL)supportsSecureCoding {
	return YES;
}


-(NSString *) description
{
	NSString *description = [NSString stringWithFormat:@"<%@: %#x (\nuserId: %@ \nname: %@ \nidentities: %@ \nextraInfo: %@\n)>",
							 NSStringFromClass([self class]), (unsigned int) self,
							 _userId,_name,_identities,_extraInfo
							 ];
	return description;
}


- (BOOL)isUserBucketSetup
{
	BOOL isSetup = NO;

	if (self.extraInfo)
	{
		NSDictionary *info = (NSDictionary *)self.extraInfo;

		NSDictionary * app_metadata = info[@"app_metadata" ];
		NSString     * aws_bucket = app_metadata[@"bucket"];
		NSString     * regionName = app_metadata[@"region"];

		if(aws_bucket.length && regionName.length)
		{
			isSetup = YES;
		}
	}

	return isSetup;
}

@end
