/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCInternalPreferences.h"

@implementation ZDCInternalPreferences {

	__weak ZeroDarkCloud *zdc;
}

NSString *const k_activityMonitor_lastActivityType  = @"lastActivityType";
NSString *const k_lastProviderTableUpdate           = @"lastProviderTableUpdate";
NSString *const k_recentRecipients                  = @"recentRecipients_2";

- (instancetype)init
{
	return nil; // To access this class use: owner.networkTools (This class is internal)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	self = [super initWithCollection: kZDCCollection_Prefs
	                           proxy: inOwner.databaseManager.databaseConnectionProxy];
	if (self)
	{
		zdc = inOwner;
 	}
	return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Defaults
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides abstract method in ZDCLocalPreferences
**/
- (id)defaultObjectForKey:(NSString *)key
{
	// If you want a preference to have a default value,
	// then put it into the dictionary below.

	NSDictionary *defaults = @{

	#if TARGET_OS_IPHONE // iOS specific

	#else                // macOS specific

	#endif
	};

	return defaults[key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark activityMonitor_lastActivityType
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@dynamic activityMonitor_lastActivityType;

- (NSInteger)activityMonitor_lastActivityType
{
	return [self integerForKey:k_activityMonitor_lastActivityType];
}
- (void)setActivityMonitor_lastActivityType:(NSInteger)value
{
	[self setInteger:value forKey:k_activityMonitor_lastActivityType];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark lastProviderTableUpdate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@dynamic lastProviderTableUpdate;

- (NSDate *)lastProviderTableUpdate;
{
	return [self objectForKey:k_lastProviderTableUpdate];
}
- (void)setLastProviderTableUpdate:(NSDate *)date
{
	[self setObject:date forKey:k_lastProviderTableUpdate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark recentRecipients
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@dynamic recentRecipients;

- (NSArray<NSString *> *)recentRecipients
{
	return [self objectForKey:k_recentRecipients];
}

- (void)addRecentRecipient:(NSString *)inUserID
{
	NSMutableArray<NSString *> *recents = [[self recentRecipients] mutableCopy];
	if (recents == nil)
	{
		recents = [NSMutableArray arrayWithCapacity:1];
	}
	
	[recents removeObject:inUserID];
	[recents insertObject:inUserID atIndex:0];
	
	while (recents.count > 10) {
		[recents removeLastObject];
	}
	
	[self setObject:[recents copy] forKey:k_recentRecipients];
}

- (void)removeRecentRecipient:(NSString *)userID
{
	NSArray<NSString *> *recents = [self recentRecipients];
	if (recents == nil) {
		return;
	}
	
	NSUInteger idx = [recents indexOfObject:userID];
	if (idx == NSNotFound) {
		return;
	}
	
	NSMutableArray<NSString *> *newRecents = [recents mutableCopy];
	[newRecents removeObjectAtIndex:idx];
	
	[self setObject:[newRecents copy] forKey:k_recentRecipients];
}


@end
