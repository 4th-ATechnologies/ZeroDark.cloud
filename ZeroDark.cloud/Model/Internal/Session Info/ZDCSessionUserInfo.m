#import "ZDCSessionUserInfo.h"
#import "ZDCSessionUserInfoPrivate.h"


@implementation ZDCSessionUserInfo

@synthesize region = region;
@synthesize bucket = bucket;
@synthesize stage  = stage;

- (instancetype)copyWithZone:(NSZone *)zone
{
	ZDCSessionUserInfo *copy = [[[self class] alloc] init];
	
	copy->region = region;
	copy->bucket = bucket;
	copy->stage  = stage;
	
	return copy;
}

@end
