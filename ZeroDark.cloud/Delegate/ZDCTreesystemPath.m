/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCTreesystemPath.h"

// NSCoding constants

static NSString *const k_trunk          = @"container";
static NSString *const k_pathComponents = @"pathComponents";

// Standardized strings

static NSString *const k_home   = @"home";
static NSString *const k_prefs  = @"prefs";
static NSString *const k_inbox  = @"inbox";
static NSString *const k_outbox = @"outbox";


NSString* NSStringFromTreesystemTrunk(ZDCTreesystemTrunk trunk)
{
	switch (trunk)
	{
		case ZDCTreesystemTrunk_Home   : return k_home;
		case ZDCTreesystemTrunk_Prefs  : return k_prefs;
		case ZDCTreesystemTrunk_Inbox  : return k_inbox;
		case ZDCTreesystemTrunk_Outbox : return k_outbox;
		default                        : return @"invalid";
	}
}

ZDCTreesystemTrunk TreesystemTrunkFromString(NSString *str)
{
	if ([str isEqualToString:k_home])   return ZDCTreesystemTrunk_Home;
	if ([str isEqualToString:k_prefs])  return ZDCTreesystemTrunk_Prefs;
	if ([str isEqualToString:k_inbox])  return ZDCTreesystemTrunk_Inbox;
	if ([str isEqualToString:k_outbox]) return ZDCTreesystemTrunk_Outbox;
	
	return ZDCTreesystemTrunk_Invalid;
}
	

@implementation ZDCTreesystemPath

@synthesize trunk = _trunk;
@synthesize pathComponents = _pathComponents;

@dynamic nodeName;
@dynamic isTrunk;

- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents
{
	return [self initWithPathComponents: pathComponents
	                              trunk: ZDCTreesystemTrunk_Home];
}

- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents
                                 trunk:(ZDCTreesystemTrunk)trunk
{
	if ((self = [super init]))
	{
		_trunk = trunk;
		
		if (pathComponents == nil)
			_pathComponents = @[];
		else
			_pathComponents = [[NSArray alloc] initWithArray:pathComponents copyItems:YES];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		NSString *trunkStr = [decoder decodeObjectForKey:k_trunk];
		_trunk = TreesystemTrunkFromString(trunkStr);
		
		_pathComponents = [decoder decodeObjectForKey:k_pathComponents];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	NSString *trunkStr = NSStringFromTreesystemTrunk(_trunk);
	
	[coder encodeObject:trunkStr forKey:k_trunk];
	[coder encodeObject:_pathComponents forKey:k_pathComponents];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	return self; // This class is immutable
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Dynamic Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)nodeName
{
	if (_pathComponents.count == 0) {
		return @"/";
	}
	else {
		return [_pathComponents lastObject];
	}
}

- (BOOL)isTrunk
{
	return (_pathComponents.count == 0);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 *
 * IMPORTANT: This method is intended primarily for debugging.
 *            You are discouraged from treating paths as strings.
 */
- (NSString *)relativePath
{
	return [@"/" stringByAppendingString:[_pathComponents componentsJoinedByString:@"/"]];
}

/**
 * See header file for description.
 *
 * IMPORTANT: This method is intended primarily for debugging.
 *            You are discouraged from treating paths as strings.
 */
- (NSString *)fullPath
{
	return [NSString stringWithFormat:@"%@:%@",
	  NSStringFromTreesystemTrunk(_trunk),
	  [self relativePath]];
}

/**
 * See header file for description.
 */
- (nullable ZDCTreesystemPath *)parentPath
{
	if (_pathComponents.count == 0) return nil;
	
	NSRange range = NSMakeRange(0, _pathComponents.count-1);
	NSArray<NSString *> *parentPathComponents = [_pathComponents subarrayWithRange:range];
	
	return [[ZDCTreesystemPath alloc] initWithPathComponents:parentPathComponents trunk:_trunk];
}

/**
 * See header file for description.
 */
- (ZDCTreesystemPath *)pathByAppendingComponent:(NSString *)pathComponent
{
	if (pathComponent == nil) return self;
	
	NSArray<NSString*> *childPathComponents = [_pathComponents arrayByAddingObject:pathComponent];
	
	return [[ZDCTreesystemPath alloc] initWithPathComponents:childPathComponents trunk:_trunk];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [self fullPath];
}

@end
