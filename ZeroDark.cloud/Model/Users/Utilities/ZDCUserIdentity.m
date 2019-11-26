/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserIdentity.h"

#import "Auth0Constants.h"
#import "Auth0Utilities.h"
#import "ZDCConstants.h"

static NSString *const k_provider    = @"provider";
static NSString *const k_userID      = @"userID";
static NSString *const k_connection  = @"connection";
static NSString *const k_isSocial    = @"isSocial";
static NSString *const k_profileData = @"profileData";

@implementation ZDCUserIdentity

@dynamic identityID;

@synthesize provider = _provider;
@synthesize userID = _userID;
@synthesize connection = _connection;
@synthesize isSocial = _isSocial;
@synthesize profileData = _profileData;

@dynamic displayName;

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	if ((self = [super init]))
	{
		id value;
		
		value = dict[@"provider"];
		if ([value isKindOfClass:[NSString class]]) {
			_provider = [(NSString *)value copy];
		}
		
		value = dict[@"user_id"];
		if ([value isKindOfClass:[NSString class]]) {
			_userID = [(NSString *)value copy];
		}
		
		value = dict[@"connection"];
		if ([value isKindOfClass:[NSString class]]) {
			_connection = [(NSString *)value copy];
		} else {
			_connection = _provider;
		}
		
		value = dict[@"isSocial"];
		if ([value isKindOfClass:[NSNumber class]]) {
			_isSocial = [(NSNumber *)value boolValue];
		} else {
			_isSocial = NO;
		}
		
		value = dict[@"profileData"];
		if ([value isKindOfClass:[NSDictionary class]]) {
			_profileData = [(NSDictionary *)value copy];
		} else {
			_profileData = [[NSDictionary alloc] init];
		}
		
		if (![self isValidIdentity]) {
			return nil;
		}
	}
	return self;
}

- (BOOL)isValidIdentity
{
	if (!_provider   || _provider.length == 0)   return NO;
	if (!_userID     || _userID.length == 0)     return NO;
	if (!_connection || _connection.length == 0) return NO;
	if (!_profileData)                           return NO;
	
	return YES;
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
		_provider    = [decoder decodeObjectOfClass:[NSString class] forKey:k_provider];
		_userID      = [decoder decodeObjectOfClass:[NSString class] forKey:k_userID];
		_connection  = [decoder decodeObjectOfClass:[NSString class] forKey:k_connection];
		_isSocial    = [decoder decodeBoolForKey:k_isSocial];
		_profileData = [decoder decodeObjectOfClass:[NSDictionary class] forKey:k_profileData];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_provider    forKey:k_provider];
	[coder encodeObject:_userID      forKey:k_userID];
	[coder encodeObject:_connection  forKey:k_connection];
	[coder encodeBool:_isSocial      forKey:k_isSocial];
	[coder encodeObject:_profileData forKey:k_profileData];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)identityID
{
	return [NSString stringWithFormat:@"%@|%@", _provider, _userID];
}

- (NSString *)displayName
{
	id value;
	NSString *displayName = nil;

	value = _profileData[@"displayName"];
	if ([value isKindOfClass:[NSString class]]) {
		displayName = (NSString *)value;
	}
	
	if (displayName.length == 0)
	{
		if ([_provider isEqualToString:A0StrategyNameWordpress])
		{
			// wordpress uses the term display_name
	
			value = _profileData[@"display_name"];
			if ([value isKindOfClass:[NSString class]]) {
				displayName = (NSString *)value;
			}
		}
		else if ([_provider isEqualToString:A0StrategyNameEvernote])
		{
			// evernote has a username
	
			value = _profileData[@"username"];
			if ([value isKindOfClass:[NSString class]]) {
				displayName = (NSString *)value;
			}
		}
		else if ([_provider isEqualToString:kAuth0DBConnection_UserAuth])
		{
			// Auth0 database connections use the term "username"
	
			value = _profileData[@"username"];
			if ([value isKindOfClass:[NSString class]]) {
				displayName = (NSString *)value;
			}
		}
		else
		{
			value = _profileData[@"name"];
			if ([value isKindOfClass:[NSString class]]) {
				displayName = (NSString *)value;
			}
		}
	}
	
	if (displayName.length == 0)
	{
		value = _profileData[@"email"];
		if ([value isKindOfClass:[NSString class]])
		{
			NSString *email = (NSString *)value;
			
			if ([Auth0Utilities is4thAEmail:email]) {
				displayName = [Auth0Utilities usernameFrom4thAEmail:email];
			}
			else if ([Auth0Utilities is4thARecoveryEmail:email]) {
				displayName = @"Recovery";
			}
		}
	}
	
	if (displayName.length == 0)
	{
		value = _profileData[@"nickname"];
		if ([value isKindOfClass:[NSString class]]) {
			displayName = (NSString *)value;
		}
	}

	displayName = self.identityID;
	
	if (displayName.length == 0)
	{
		displayName= @"<Unknown>"; // This code-path should (theoretically) be unreachable
	}
	
	return displayName;
}

- (BOOL)isRecoveryAccount
{
	return [_provider isEqualToString:A0StrategyNameAuth0] &&
	       [_connection isEqualToString:kAuth0DBConnection_Recovery];
}

@end
