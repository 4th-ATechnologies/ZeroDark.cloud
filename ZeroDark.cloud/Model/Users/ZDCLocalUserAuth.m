#import "ZDCLocalUserAuth.h"
#import "NSString+JWT.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 3;
#pragma unused(kCurrentVersion)

static NSString *const k_version            = @"version";
static NSString *const k_aws_userID         = @"aws_userID";
static NSString *const k_aws_userARN        = @"aws_userARN";
static NSString *const k_aws_accessKeyID    = @"aws_accessKeyID";
static NSString *const k_aws_secret         = @"aws_secret";
static NSString *const k_aws_session        = @"aws_session";
static NSString *const k_aws_expiration     = @"aws_expiration";

static NSString *const k_auth0_refreshToken    = @"auth0_refreshToken";
 
@implementation ZDCLocalUserAuth

@synthesize aws_userID = aws_userID;
@synthesize aws_userARN = aws_userARN;
@synthesize aws_accessKeyID = aws_accessKeyID;
@synthesize aws_secret = aws_secret;
@synthesize aws_session = aws_session;
@synthesize aws_expiration = aws_expiration;

@synthesize auth0_refreshToken = auth0_refreshToken;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		int version = [decoder decodeIntForKey:k_version];
		
		aws_userID = [decoder decodeObjectForKey:k_aws_userID];
		aws_userARN = [decoder decodeObjectForKey:k_aws_userARN];
		aws_accessKeyID = [decoder decodeObjectForKey:k_aws_accessKeyID];
		aws_secret = [decoder decodeObjectForKey:k_aws_secret];
		aws_session = [decoder decodeObjectForKey:k_aws_session];
		aws_expiration = [decoder decodeObjectForKey:k_aws_expiration];

		if(version >= 3)
		{
			auth0_refreshToken = [decoder decodeObjectForKey:k_auth0_refreshToken];
		}
		else if(version == 2)
		{
			auth0_refreshToken = [decoder decodeObjectForKey:k_auth0_refreshToken];
	//		auth0_tokens = [decoder decodeObjectForKey:k_auth0_tokens];
			// we deprecated the auth0_tokens  -- no longer used.
		}
	}
	return self;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:aws_userID forKey:k_aws_userID];
	[coder encodeObject:aws_userARN forKey:k_aws_userARN];
	[coder encodeObject:aws_accessKeyID forKey:k_aws_accessKeyID];
	[coder encodeObject:aws_secret forKey:k_aws_secret];
	[coder encodeObject:aws_session forKey:k_aws_session];
	[coder encodeObject:aws_expiration forKey:k_aws_expiration];

	[coder encodeObject:auth0_refreshToken forKey:k_auth0_refreshToken];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCLocalUserAuth *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->aws_userID = aws_userID;
	copy->aws_userARN = aws_userARN;
	copy->aws_accessKeyID = aws_accessKeyID;
	copy->aws_secret = aws_secret;
	copy->aws_session = aws_session;
	copy->aws_expiration = aws_expiration;

	copy->auth0_refreshToken = auth0_refreshToken;
	
	return copy;
}

@end
