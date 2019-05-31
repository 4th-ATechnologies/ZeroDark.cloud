/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
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
