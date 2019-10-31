/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCAudit.h"

@implementation ZDCAudit

@synthesize localUserID = _localUserID;
@synthesize aws_region = _aws_region;
@synthesize aws_bucket = _aws_bucket;
@synthesize aws_accessKeyID = _aws_accessKeyID;
@synthesize aws_secret = _aws_secret;
@synthesize aws_session = _aws_session;
@synthesize aws_expiration = _aws_expiration;

- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             region:(NSString *)region
                             bucket:(NSString *)bucket
                        accessKeyID:(NSString *)accessKeyID
                             secret:(NSString *)secret
                            session:(NSString *)session
                         expiration:(NSDate *)expiration
{
	if ((self = [super init]))
	{
		_localUserID = [localUserID copy];
		_aws_region = [region copy];
		_aws_bucket = [bucket copy];
		_aws_accessKeyID = [accessKeyID copy];
		_aws_secret = [secret copy];
		_aws_session = [session copy];
		_aws_expiration = [expiration copy];
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:
		@" - localUserID     : %@\n"
		@" - aws_region      : %@\n"
		@" - aws_bucket      : %@\n"
		@" - aws_accessKeyID : %@\n"
		@" - aws_secret      : %@\n"
		@" - aws_session     : %@\n"
		@" - aws_expiration  : %@",
		_localUserID,
		_aws_region,
		_aws_bucket,
		_aws_accessKeyID,
		_aws_secret,
		_aws_session,
		[_aws_expiration descriptionWithLocale:[NSLocale currentLocale]]];
}

@end
