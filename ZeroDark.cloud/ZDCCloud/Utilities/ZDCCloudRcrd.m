#import "ZDCCloudRcrd.h"
#import "ZDCConstants.h"


@implementation ZDCCloudRcrd

@synthesize version;
@synthesize cloudID;
@synthesize sender;

@synthesize encryptionKey;

@synthesize children = children;
@synthesize share;
@synthesize metadata;
@synthesize data;

- (BOOL)usingAdvancedChildrenContainer
{
	__block BOOL isAdvanced = NO;
	[self enumerateChildrenWithBlock:^(NSString *name, NSString *dirPrefix, BOOL *stop) {
		
		if (name.length > 0) {
			isAdvanced = YES;
			*stop = YES;
		}
	}];
	
	return isAdvanced;
}

- (void)enumerateChildrenWithBlock:(void (^)(NSString *name, NSString *dirPrefix, BOOL *stop))block
{
	if (![children isKindOfClass:[NSDictionary class]]) return;
	
	BOOL stop = NO;
	for (NSString *name in children)
	{
		if (![name isKindOfClass:[NSString class]]) continue;
		
		NSDictionary *child = children[name];
		if (![child isKindOfClass:[NSDictionary class]]) continue;
		
		NSString *prefix = child[kZDCCloudRcrd_Children_Prefix];
		if ([prefix isKindOfClass:[NSString class]])
		{
			block(name, prefix, &stop);
			if (stop) break;
		}
	}
}

- (nullable NSString *)dirPrefix
{
	NSString *dirPrefix = nil;
	if (children)
	{
		NSDictionary *child = children[@""];
		if ([child isKindOfClass:[NSDictionary class]])
		{
			NSString *prefix = child[kZDCCloudRcrd_Children_Prefix];
			if ([prefix isKindOfClass:[NSString class]])
			{
				dirPrefix = prefix;
			}
		}
	}
	
	return dirPrefix;
}

@end

