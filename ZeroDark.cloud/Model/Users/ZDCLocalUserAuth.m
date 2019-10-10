#import "ZDCLocalUserAuth.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 4;
#pragma unused(kCurrentVersion)

static NSString *const k_version            = @"version";
static NSString *const k_userID             = @"userID";
static NSString *const k_aws_accessKeyID    = @"aws_accessKeyID";
static NSString *const k_aws_secret         = @"aws_secret";
static NSString *const k_aws_session        = @"aws_session";
static NSString *const k_aws_expiration     = @"aws_expiration";

static NSString *const k_auth0_refreshToken = @"auth0_refreshToken";
static NSString *const k_auth0_idToken      = @"auth0_idToken";
 

@implementation ZDCLocalUserAuth

@synthesize userID = userID;

@synthesize aws_accessKeyID = aws_accessKeyID;
@synthesize aws_secret = aws_secret;
@synthesize aws_session = aws_session;
@synthesize aws_expiration = aws_expiration;

@synthesize auth0_refreshToken = auth0_refreshToken;
@synthesize auth0_idToken = auth0_idToken;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
	//	int version = [decoder decodeIntForKey:k_version];
		
		userID = [decoder decodeObjectForKey:k_userID];
		
		aws_accessKeyID = [decoder decodeObjectForKey:k_aws_accessKeyID];
		aws_secret = [decoder decodeObjectForKey:k_aws_secret];
		aws_session = [decoder decodeObjectForKey:k_aws_session];
		aws_expiration = [decoder decodeObjectForKey:k_aws_expiration];

		auth0_refreshToken = [decoder decodeObjectForKey:k_auth0_refreshToken];
		auth0_idToken = [decoder decodeObjectForKey:k_auth0_idToken];
	}
	return self;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:userID forKey:k_userID];
	
	[coder encodeObject:aws_accessKeyID forKey:k_aws_accessKeyID];
	[coder encodeObject:aws_secret forKey:k_aws_secret];
	[coder encodeObject:aws_session forKey:k_aws_session];
	[coder encodeObject:aws_expiration forKey:k_aws_expiration];

	[coder encodeObject:auth0_refreshToken forKey:k_auth0_refreshToken];
	[coder encodeObject:auth0_idToken forKey:k_auth0_idToken];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCLocalUserAuth *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->userID = userID;
	
	copy->aws_accessKeyID = aws_accessKeyID;
	copy->aws_secret = aws_secret;
	copy->aws_session = aws_session;
	copy->aws_expiration = aws_expiration;

	copy->auth0_refreshToken = auth0_refreshToken;
	copy->auth0_idToken = auth0_idToken;
	
	return copy;
}

@end
