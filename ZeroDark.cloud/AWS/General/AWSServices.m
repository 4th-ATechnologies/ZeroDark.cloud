#import "AWSServices.h"


@implementation AWSServices

/**
 * Returns the short name of the service.
 * This is the value typically used internally by amazon (e.g. in authentication steps).
**/
+ (NSString *)shortNameForService:(AWSService)service
{
	switch (service)
	{
		case AWSService_S3         : return @"s3";
		case AWSService_APIGateway : return @"execute-api";
		default                    : return @"";
	}
}

@end
