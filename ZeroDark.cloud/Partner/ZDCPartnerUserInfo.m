/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import "ZDCPartnerUserInfo.h"

@implementation ZDCPartnerUserInfo

@synthesize userID = _userID;
@synthesize region = _region;
@synthesize bucket = _bucket;
@synthesize stage = _stage;
@synthesize salt = _salt;
@synthesize refreshToken = _refreshToken;
@synthesize accessKey = _accessKey;

- (instancetype)initWithUserID:(NSString *)userID
                        region:(AWSRegion)region
                        bucket:(NSString *)bucket
                         stage:(NSString *)stage
                          salt:(NSString *)salt
                  refreshToken:(NSString *)refreshToken
                     accessKey:(NSData *)accessKey
{
	NSParameterAssert(userID.length != 0);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(bucket.length != 0);
	NSParameterAssert(stage.length != 0);
	NSParameterAssert(salt.length != 0);
	NSParameterAssert(refreshToken.length != 0);
	NSParameterAssert(accessKey.length != 0);
	
	if ((self = [super init]))
	{
		_userID = [userID copy];
		_region = region;
		_bucket = [bucket copy];
		_stage = [stage copy];
		_salt = [salt copy];
		_refreshToken = [refreshToken copy];
		_accessKey = [accessKey copy];
	}
	return self;
}

@end
