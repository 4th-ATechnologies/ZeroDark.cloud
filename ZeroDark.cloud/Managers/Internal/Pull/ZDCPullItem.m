/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPullItem.h"

@implementation ZDCPullItem

@synthesize region;
@synthesize bucket;

@synthesize parents;

@synthesize rcrdCloudPath;
@synthesize rcrdETag;
@synthesize rcrdLastModified;

@synthesize dataCloudPath;
@synthesize dataETag;
@synthesize dataLastModified;

@synthesize rcrdCompletionBlock;
@synthesize ptrCompletionBlock;
@synthesize dirCompletionBlock;

@end
