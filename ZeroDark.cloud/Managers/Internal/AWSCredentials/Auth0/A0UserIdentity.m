/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "A0UserIdentity.h"

@implementation A0UserIdentity

+ (instancetype)identityFromDictionary:(NSDictionary *)dict {

	A0UserIdentity* identity = nil;

	identity = [[A0UserIdentity alloc] initWithUserId:dict[@"user_id"]
					   provider:dict[@"provider"]
					 connection:dict[@"connection"]
						 social:dict[@"isSocial"]
					accessToken:dict[@"access_token"]
			  accessTokenSecret:dict[@"access_token_secret"]
					profileData:dict[@"profileData"]];

	return identity;
}

- (instancetype)initWithUserId:(NSString *)userId
					  provider:(NSString *)provider
					connection:(NSString *)connection
						social:(NSNumber *)social
				   accessToken:(NSString *)accessToken
			 accessTokenSecret:(NSString *)accessTokenSecret
				   profileData:(NSDictionary *)profileData {
	self = [super init];
	if (self) {
		_userId = userId;
		_provider = provider;
		_connection = connection;
		_social = social.boolValue;
		_accessToken = accessToken;
		_accessTokenSecret = accessTokenSecret;
		_profileData = profileData;
	}
	return self;
}

- (NSString *)identityId {
	return [NSString stringWithFormat:@"%@|%@", self.provider, self.userId];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	return [self initWithUserId:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(userId))]
					   provider:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(provider))]
					 connection:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(connection))]
						 social:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(isSocial))]
					accessToken:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(accessToken))]
			  accessTokenSecret:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(accessTokenSecret))]
					profileData:[aDecoder decodeObjectForKey:NSStringFromSelector(@selector(profileData))]];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
	if (self.userId) {
		[aCoder encodeObject:self.userId forKey:NSStringFromSelector(@selector(userId))];
	}
	if (self.provider) {
		[aCoder encodeObject:self.provider forKey:NSStringFromSelector(@selector(provider))];
	}
	if (self.connection) {
		[aCoder encodeObject:self.connection forKey:NSStringFromSelector(@selector(connection))];
	}
	if (self.accessToken) {
		[aCoder encodeObject:self.accessToken forKey:NSStringFromSelector(@selector(accessToken))];
	}
	if (self.accessTokenSecret) {
		[aCoder encodeObject:self.accessTokenSecret forKey:NSStringFromSelector(@selector(accessTokenSecret))];
	}
	if (self.profileData) {
		[aCoder encodeObject:self.profileData forKey:NSStringFromSelector(@selector(profileData))];
	}
	[aCoder encodeObject:@(self.isSocial) forKey:NSStringFromSelector(@selector(isSocial))];
}

@end
