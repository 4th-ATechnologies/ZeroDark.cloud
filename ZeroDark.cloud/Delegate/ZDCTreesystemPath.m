/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCTreesystemPath.h"

// NSCoding constants

static NSString *const k_container      = @"container";
static NSString *const k_pathComponents = @"pathComponents";

// Standardized strings

static NSString *const k_home   = @"home";
static NSString *const k_msgs   = @"msgs";
static NSString *const k_inbox  = @"inbox";
static NSString *const k_outbox = @"outbox";
static NSString *const k_prefs  = @"prefs";


NSString* NSStringFromTreesystemContainer(ZDCTreesystemContainer container)
{
	switch (container)
	{
		case ZDCTreesystemContainer_Home   : return k_home;
		case ZDCTreesystemContainer_Msgs   : return k_msgs;
		case ZDCTreesystemContainer_Inbox  : return k_inbox;
		case ZDCTreesystemContainer_Outbox : return k_outbox;
		case ZDCTreesystemContainer_Prefs  : return k_prefs;
		default                            : return @"invalid";
	}
}

ZDCTreesystemContainer TreesystemContainerFromString(NSString *str)
{
	if ([str isEqualToString:k_home])   return ZDCTreesystemContainer_Home;
	if ([str isEqualToString:k_msgs])   return ZDCTreesystemContainer_Msgs;
	if ([str isEqualToString:k_inbox])  return ZDCTreesystemContainer_Inbox;
	if ([str isEqualToString:k_outbox]) return ZDCTreesystemContainer_Outbox;
	if ([str isEqualToString:k_prefs])  return ZDCTreesystemContainer_Prefs;
	
	return ZDCTreesystemContainer_Invalid;
}
	

@implementation ZDCTreesystemPath

@synthesize container = _container;
@synthesize pathComponents = _pathComponents;

@dynamic nodeName;
@dynamic isContainerRoot;

- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents
{
	return [self initWithPathComponents: pathComponents
	                          container: ZDCTreesystemContainer_Home];
}

- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents
                             container:(ZDCTreesystemContainer)container
{
	if ((self = [super init]))
	{
		_container = container;
		
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
		NSString *containerStr = [decoder decodeObjectForKey:k_container];
		_container = TreesystemContainerFromString(containerStr);
		
		_pathComponents = [decoder decodeObjectForKey:k_pathComponents];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	NSString *containerStr = NSStringFromTreesystemContainer(_container);
	
	[coder encodeObject:containerStr forKey:k_container];
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

- (BOOL)isContainerRoot
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
	  NSStringFromTreesystemContainer(_container),
	  [self relativePath]];
}

- (nullable ZDCTreesystemPath *)parentPath
{
	if (_pathComponents.count == 0) return nil;
	
	NSRange range = NSMakeRange(0, _pathComponents.count-1);
	NSArray<NSString *> *parentPathComponents = [_pathComponents subarrayWithRange:range];
	
	return [[ZDCTreesystemPath alloc] initWithPathComponents:parentPathComponents container:_container];
}

- (ZDCTreesystemPath *)pathByAppendingComponent:(NSString *)pathComponent
{
	if (pathComponent == nil) return self;
	
	NSArray<NSString*> *childPathComponents = [_pathComponents arrayByAddingObject:pathComponent];
	
	return [[ZDCTreesystemPath alloc] initWithPathComponents:childPathComponents container:_container];
}

@end
