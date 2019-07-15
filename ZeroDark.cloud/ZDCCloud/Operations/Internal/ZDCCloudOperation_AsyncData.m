/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCCloudOperation_AsyncData.h"

@implementation ZDCCloudOperation_AsyncData

@synthesize data = data;
@synthesize metadata = metadata;
@synthesize thumbnail = thumbnail;

@synthesize rawMetadata;
@synthesize rawThumbnail;

@synthesize node = node;

- (instancetype)initWithData:(ZDCData *)inData
{
	if ((self = [super init]))
	{
		data = inData;
	}
	return self;
}

@end
