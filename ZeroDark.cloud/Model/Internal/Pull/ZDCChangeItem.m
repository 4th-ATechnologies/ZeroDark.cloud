#import "ZDCChangeItem.h"

static NSString *const k_id        = @"id";
static NSString *const k_timestamp = @"ts";
static NSString *const k_app       = @"app";
static NSString *const k_bucket    = @"bucket";
static NSString *const k_region    = @"region";
static NSString *const k_command   = @"command";
static NSString *const k_path      = @"path";
static NSString *const k_fileID    = @"fileID";
static NSString *const k_eTag      = @"eTag";
static NSString *const k_srcPath   = @"srcPath";
static NSString *const k_dstPath   = @"dstPath";

static NSString *const k_deprecated_uuid = @"uuid";


@implementation ZDCChangeItem {
@protected
	
	NSDictionary *dict;
}

@dynamic uuid;
@dynamic timestamp;
@dynamic app;
@dynamic bucket;
@dynamic region;
@dynamic command;
@dynamic path;
@dynamic fileID;
@dynamic eTag;
@dynamic srcPath;
@dynamic dstPath;

+ (ZDCChangeItem *)parseChangeInfo:(NSDictionary *)dict
{
	ZDCChangeItem *change = [[ZDCChangeItem alloc] initWithDict:dict];
	
	if (change.uuid == nil ||
	    change.command == nil)
	{
		return nil;
	}
	
	return change;
}

- (instancetype)initWithDict:(NSDictionary *)inDict
{
	if ((self = [super init]))
	{
		dict = [inDict copy];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		dict = [decoder decodeObjectForKey:@"dict"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:dict forKey:@"dict"];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCChangeItem *copy = [[ZDCChangeItem alloc] initWithDict:dict];
	return copy;
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
	ZDCMutableChangeItem *copy = [[ZDCMutableChangeItem alloc] initWithDict:dict];
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)uuid
{
	id value;
	
	value = dict[k_id];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	value = dict[k_deprecated_uuid];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSDate *)timestamp
{
	id value = dict[k_timestamp];
	if ([value isKindOfClass:[NSNumber class]])
	{
		NSUInteger millis = [(NSNumber *)value unsignedIntegerValue];
		NSTimeInterval ti = millis / (NSTimeInterval)1000;
		
		return [NSDate dateWithTimeIntervalSince1970:ti];
	}
	
	return nil;
}

- (NSString *)app
{
	id value = dict[k_app];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)bucket
{
	id value = dict[k_bucket];
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	
	return nil;
}

- (NSString *)region
{
	id value = dict[k_region];
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	
	return nil;
}

- (NSString *)command
{
	id value = dict[k_command];
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	
	return nil;
}

- (NSString *)path
{
	id value = dict[k_path];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)fileID
{
	id value = dict[k_fileID];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)eTag
{
	id value = dict[k_eTag];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)srcPath
{
	id value = dict[k_srcPath];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

- (NSString *)dstPath
{
	id value = dict[k_dstPath];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	}
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Description
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [dict description];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCMutableChangeItem

@dynamic eTag;
@dynamic path;
@dynamic dstPath;

- (void)setETag:(NSString *)eTag
{
	NSString *const key = NSStringFromSelector(@selector(eTag));
	
	[self willChangeValueForKey:key];
	{
		NSMutableDictionary *newDict = [dict mutableCopy];
		newDict[k_eTag] = [eTag copy];
		
		dict = [newDict copy];
	}
	[self didChangeValueForKey:key];
}

- (void)setPath:(NSString *)path
{
	NSString *const key = NSStringFromSelector(@selector(path));
	
	[self willChangeValueForKey:key];
	{
		NSMutableDictionary *newDict = [dict mutableCopy];
		newDict[k_path] = [path copy];
		
		dict = [newDict copy];
	}
	[self didChangeValueForKey:key];
}

- (void)setDstPath:(NSString *)dstPath
{
	NSString *const key = NSStringFromSelector(@selector(dstPath));
	
	[self willChangeValueForKey:key];
	{
		NSMutableDictionary *newDict = [dict mutableCopy];
		newDict[k_dstPath] = [dstPath copy];
		
		dict = [newDict copy];
	}
	[self didChangeValueForKey:key];
}

@end
