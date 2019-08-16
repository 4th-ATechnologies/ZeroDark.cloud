/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCPullItem.h"

@implementation ZDCPullItem

@synthesize region = region;
@synthesize bucket = bucket;

@synthesize parents = parents;

@synthesize rcrdCloudPath = rcrdCloudPath;
@synthesize rcrdETag = rcrdETag;
@synthesize rcrdLastModified = rcrdLastModified;

@synthesize dataCloudPath = dataCloudPath;
@synthesize dataETag = dataETag;
@synthesize dataLastModified = dataLastModified;

@synthesize rcrdCompletionBlock = rcrdCompletionBlock;
@synthesize ptrCompletionBlock = ptrCompletionBlock;
@synthesize dirCompletionBlock = dirCompletionBlock;

- (id)copyWithZone:(NSZone *)zone
{
	ZDCPullItem *copy = [[ZDCPullItem alloc] init];
	
	copy->region = region;
	copy->bucket = bucket;
	
	copy->parents = parents;
	
	copy->rcrdCloudPath = rcrdCloudPath;
	copy->rcrdETag = rcrdETag;
	copy->rcrdLastModified = rcrdLastModified;
	
	copy->dataCloudPath = dataCloudPath;
	copy->dataETag = dataETag;
	copy->dataLastModified = dataLastModified;
	
	copy->rcrdCompletionBlock = rcrdCompletionBlock;
	copy->ptrCompletionBlock = ptrCompletionBlock;
	copy->dirCompletionBlock = dirCompletionBlock;
	
	return copy;
}

@end
