#import "ZDCCloudRcrd.h"

#import "ZDCConstantsPrivate.h"
#import "NSString+ZeroDark.h"

@implementation ZDCCloudRcrd

@synthesize version;
@synthesize cloudID;
@synthesize sender;

@synthesize encryptionKey;

@synthesize children = children;
@synthesize share;
@synthesize metadata;
@synthesize data;

@synthesize errors = errors;

- (instancetype)init
{
	if ((self = [super init]))
	{
		errors = [NSArray array];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)appendError:(NSError *)error
{
	if (error) {
		errors = [errors arrayByAddingObject:error];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Parsing Children
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma Parsing Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isPointer
{
	return [self getPointerCloudPath:NULL cloudID:NULL ownerID:NULL];
}

- (BOOL)getPointerCloudPath:(ZDCCloudPath **)outPath cloudID:(NSString **)outCloudID ownerID:(NSString **)outOwnerID
{
	BOOL result = NO;
	
	ZDCCloudPath *cloudPath = nil;
	NSString *cloudID = nil;
	NSString *ownerID = nil;
	
	if (self.data)
	{
		NSDictionary *pointer = self.data[kZDCCloudRcrd_Data_Pointer];
		if ([pointer isKindOfClass:[NSDictionary class]])
		{
			NSString *p_owner   = pointer[kZDCCloudRcrd_Data_Pointer_Owner];
			NSString *p_path    = pointer[kZDCCloudRcrd_Data_Pointer_Path];
			NSString *p_cloudID = pointer[kZDCCloudRcrd_Data_Pointer_CloudID];
			
			if ([p_owner   isKindOfClass:[NSString class]] &&
			    [p_path    isKindOfClass:[NSString class]] &&
			    [p_cloudID isKindOfClass:[NSString class]]  )
			{
				if ([p_owner isValidUserID]) {
					ownerID = p_owner;
				}
				
				cloudID = p_cloudID;
				cloudPath = [[ZDCCloudPath alloc] initWithPath:p_path];
				
				result = (ownerID != nil) && (cloudID != nil) && (cloudPath != nil);
			}
		}
	}
	
	if (outPath) *outPath = cloudPath;
	if (outCloudID) *outCloudID = cloudID;
	if (outOwnerID) *outOwnerID = ownerID;
	
	return result;
}

@end
