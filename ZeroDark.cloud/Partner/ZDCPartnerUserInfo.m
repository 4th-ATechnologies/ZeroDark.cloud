//
//  ZDCPartnerUserInfo.m
//  ZeroDarkCloud
//
//  Created by Robbie Hanson on 4/20/20.
//

#import "ZDCPartnerUserInfo.h"

@implementation ZDCPartnerUserInfo

@synthesize userID = _userID;
@synthesize region = _region;
@synthesize bucket = _bucket;
@synthesize stage  = _stage;
@synthesize salt   = _salt;

- (instancetype)initWithUserID:(NSString *)userID
                        region:(AWSRegion)region
                        bucket:(NSString *)bucket
                         stage:(NSString *)stage
                          salt:(NSString *)salt
{
	if ((self = [super init]))
	{
		_userID = [userID copy];
		_region = region;
		_bucket = [bucket copy];
		_stage = [stage copy];
		_salt = [salt copy];
	}
	return self;
}

@end
