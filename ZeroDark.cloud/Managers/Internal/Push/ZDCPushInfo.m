/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPushInfo.h"

@interface ZDCRequestInfo ()
- (instancetype)initWithReq:(NSDictionary *)req info:(NSDictionary *)info;
@end

#pragma mark -

@implementation ZDCPushInfo {
@protected
	
	NSDictionary *dict;
}

@dynamic localUserID;
@dynamic changeID_new;
@dynamic changeID_old;
@dynamic isActivation;

@synthesize changeInfo = changeInfo;
@synthesize requestInfo = requestInfo;

/**
 * Example push notification:
 * {
 *   aps = {
 *     "content-available" = 1;
 *   };
 *   "4th-a" = {
 *     info = {
 *       app = "com.4th-a.storm4";
 *       bucket = "com.4th-a.user.e11wpypyk39re8s3btg11eyuxf778gd3-01930288";
 *       command = "put-if-nonexistent";
 *       eTag = 4d96b12cf10db04dd5cce78223437c47;
 *       fileID = 1F52FC7B52684778805A8CD3BB18C755;
 *       id = C3750CC633564C66B1E70AF796F2551E;
 *       path = "com.4th-a.storm4/msgs/16oedcezkzuwogpbn8q1hb5aeet1y1db.rcrd";
 *       region = "us-west-2";
 *       ts = 1526053567474;
 *       type = data;
 *     };
 *     new = C3750CC633564C66B1E70AF796F2551E;
 *     old = 85019B1D7A9447AAABE443D2B1B593A2;
 *     req = {
 *       id = "891B3A2C-5A8A-4BE1-9774-E19A28E886BE";
 *       uid = e11wpypyk39re8s3btg11eyuxf778gd3;
 *       v = {
 *         "change_id" = C3750CC633564C66B1E70AF796F2551E;
 *         status = 200;
 *       };
 *     };
 *     uid = e11wpypyk39re8s3btg11eyuxf778gd3;
 *   };
 * }
**/

+ (nullable ZDCPushInfo *)parsePushInfo:(NSDictionary *)info
{
	NSDictionary *dict = info[@"4th-a"];
	
	if (![dict isKindOfClass:[NSDictionary class]])
	{
		// Doesn't apply to us
		return nil;
	}
	
	ZDCPushInfo *pushInfo = [[ZDCPushInfo alloc] init];
	pushInfo->dict = dict;
	
	NSDictionary *change_info = [pushInfo info];
	NSDictionary *change_req  = [pushInfo req];
	
	if (change_info && (change_info[@"id"] == nil) && (change_info[@"uuid"] == nil) && (pushInfo.changeID_new != nil))
	{
		// Sanity check:
		//
		// The change_info MUST have an 'id' or 'uuid' property.
		// This should always be the case...
		//
		// But since this value is duplicated throughout the push notification,
		// it becomes a candidate for "future optimizations".
		// That is, I can easily imagine me thinking, "let's delete those duplicates...".
		// Which could end up breaking some brittle code paths.
		//
		// So this is future proofing for our code.
		
		NSMutableDictionary *modification = [change_info mutableCopy];
		modification[@"id"] = pushInfo.changeID_new;
		
		change_info = [modification copy];
	}
	
	if (change_info) {
		pushInfo->changeInfo = [ZDCChangeItem parseChangeInfo:change_info];
	}
	if (change_req) {
		pushInfo->requestInfo = [[ZDCRequestInfo alloc] initWithReq:change_req info:change_info];
	}
	
	return pushInfo;
}

- (NSString *)localUserID
{
	id value = dict[@"uid"];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)changeID_new
{
	id value = dict[@"new"];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)changeID_old
{
	id value = dict[@"old"];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return value;
}

- (NSDictionary *)info
{
	id value = dict[@"info"];
	if ([value isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary *)value;
	}
	
	return nil;
}

- (NSDictionary *)req
{
	id value = dict[@"req"];
	if ([value isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary *)value;
	}
	
	return nil;
}

- (BOOL)isActivation
{
	id value = dict[@"activation"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		return [(NSNumber *)value boolValue];
	}
	
	return NO;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCRequestInfo {
@protected
	
	NSDictionary *dict;
	NSDictionary *changeInfo;
}

- (instancetype)initWithReq:(NSDictionary *)req info:(NSDictionary *)info
{
	if ((self = [super init]))
	{
		if ([req isKindOfClass:[NSDictionary class]]) {
			dict = [req copy];
		}
		else {
			dict = [NSDictionary dictionary];
		}
		
		if ([info isKindOfClass:[NSDictionary class]]) {
			changeInfo = [info copy];
		}
	}
	return self;
}

@dynamic requestID;
@dynamic localUserID;
@dynamic status;
@dynamic statusCode;

- (NSString *)requestID
{
	id value = dict[@"id"];
	if ([value isKindOfClass:[NSString class]])
	{
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)localUserID
{
	id value = dict[@"uid"];
	if ([value isKindOfClass:[NSString class]])
	{
		return (NSString *)value;
	}
	
	return nil;
}

- (NSDictionary *)status
{
	NSDictionary *status = nil;
	
	id value = dict[@"v"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		status = (NSDictionary *)value;
	}
	else // old format (pre extended status codes)
	{
		value = dict[@"status"];
		if ([value isKindOfClass:[NSNumber class]])
		{
			status = @{ @"status": value };
		}
	}
	
	if (status && changeInfo)
	{
		// Inject "info" so it looks the same as a poll-request response
		
		NSMutableDictionary *injection = [status mutableCopy];
		injection[@"info"] = changeInfo;
		
		return [injection copy];
	}
	else
	{
		return status;
	}
}

- (NSInteger)statusCode
{
	id value = self.status[@"status"];
	if ([value isKindOfClass:[NSNumber class]])
	{
		return [value integerValue];
	}
	
	return 0;
}

@end
