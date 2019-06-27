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

@synthesize rcrdPath;
@synthesize rcrdETag;
@synthesize rcrdLastModified;

@synthesize dataPath;
@synthesize dataETag;
@synthesize dataLastModified;

@synthesize bucket;
@synthesize region;

@synthesize parents;

@synthesize rcrdCompletionBlock;
@synthesize dirCompletionBlock;

@end
