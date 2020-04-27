#import "ZDCLocalUserAuth.h"

// Encoding/Decoding Keys

static int const kCurrentVersion = 4;
#pragma unused(kCurrentVersion)

static NSString *const k_version              = @"version";
static NSString *const k_localUserID          = @"userID";
static NSString *const k_aws_accessKeyID      = @"aws_accessKeyID";
static NSString *const k_aws_secret           = @"aws_secret";
static NSString *const k_aws_session          = @"aws_session";
static NSString *const k_aws_expiration       = @"aws_expiration";

static NSString *const k_coop_refreshToken    = @"auth0_refreshToken";
static NSString *const k_coop_jwt             = @"auth0_idToken";

static NSString *const k_partner_refreshToken = @"partner_refreshToken";
static NSString *const k_partner_jwt          = @"partner_jwt";


@implementation ZDCLocalUserAuth

@synthesize localUserID = localUserID;

@synthesize aws_accessKeyID = aws_accessKeyID;
@synthesize aws_secret = aws_secret;
@synthesize aws_session = aws_session;
@synthesize aws_expiration = aws_expiration;

@synthesize coop_refreshToken = coop_refreshToken;
@synthesize coop_jwt = coop_jwt;

@synthesize partner_refreshToken = partner_refreshToken;
@synthesize partner_jwt = partner_jwt;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
	//	int version = [decoder decodeIntForKey:k_version];
		
		localUserID = [decoder decodeObjectForKey:k_localUserID];
		
		aws_accessKeyID = [decoder decodeObjectForKey:k_aws_accessKeyID];
		aws_secret = [decoder decodeObjectForKey:k_aws_secret];
		aws_session = [decoder decodeObjectForKey:k_aws_session];
		aws_expiration = [decoder decodeObjectForKey:k_aws_expiration];

		coop_refreshToken = [decoder decodeObjectForKey:k_coop_refreshToken];
		coop_jwt = [decoder decodeObjectForKey:k_coop_jwt];
		
		partner_refreshToken = [decoder decodeObjectForKey:k_partner_refreshToken];
		partner_jwt = [decoder decodeObjectForKey:k_partner_jwt];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:localUserID forKey:k_localUserID];
	
	[coder encodeObject:aws_accessKeyID forKey:k_aws_accessKeyID];
	[coder encodeObject:aws_secret forKey:k_aws_secret];
	[coder encodeObject:aws_session forKey:k_aws_session];
	[coder encodeObject:aws_expiration forKey:k_aws_expiration];

	[coder encodeObject:coop_refreshToken forKey:k_coop_refreshToken];
	[coder encodeObject:coop_jwt forKey:k_coop_jwt];
	
	[coder encodeObject:partner_refreshToken forKey:k_partner_refreshToken];
	[coder encodeObject:partner_jwt forKey:k_partner_jwt];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCLocalUserAuth *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->localUserID = localUserID;
	
	copy->aws_accessKeyID = aws_accessKeyID;
	copy->aws_secret = aws_secret;
	copy->aws_session = aws_session;
	copy->aws_expiration = aws_expiration;

	copy->coop_refreshToken = coop_refreshToken;
	copy->coop_jwt = coop_jwt;
	
	copy->partner_refreshToken = partner_refreshToken;
	copy->partner_jwt = partner_jwt;
	
	return copy;
}

@end
