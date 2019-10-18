/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/
#import "ZDCGraftInvite.h"

@implementation ZDCGraftInvite

@synthesize cloudID = cloudID;
@synthesize cloudPath = cloudPath;

- (instancetype)initWithCloudID:(NSString *)inCloudID cloudPath:(ZDCCloudPath *)inCloudPath
{
	if ((self = [super init]))
	{
		cloudID = [inCloudID copy];
		cloudPath = [inCloudPath copy];
	}
	return self;
}

@end
