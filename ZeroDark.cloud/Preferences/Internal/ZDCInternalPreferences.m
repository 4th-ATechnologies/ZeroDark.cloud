/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCInternalPreferences.h"

@implementation ZDCInternalPreferences
{
@private

	__weak ZeroDarkCloud *zdc;
}

NSString *const ZDCprefs_activityMonitor_lastActivityType  = @"lastActivityType";
NSString *const ZDCprefs_lastProviderTableUpdate  = @"lastProviderTableUpdate";
NSString *const ZDCprefs_recentRecipients         = @"recentRecipients";
NSString *const ZDCprefs_preferedAuth0IDs         = @"preferedAuth0IDs";


- (instancetype)init
{
	return nil; // To access this class use: owner.networkTools (This class is internal)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super initWithCollection:kZDCCollection_Prefs
									proxy:inOwner.databaseManager.databaseConnectionProxy]))
	{
		zdc = inOwner;
 	}
	return self;
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Defaults
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides abstract method in S4PreferencesBase
 **/
- (id)defaultObjectForKey:(NSString *)key
{
	// If you want a preference to have a default value,
	// then put it into the dictionary below.

	NSDictionary *defaults = @{


#if TARGET_OS_IPHONE
							   // iOS specific

#else
							   // macOS specific

#endif
							   };

	return defaults[key];
}


#pragma mark activityMonitor_lastActivityType

- (NSInteger)activityMonitor_lastActivityType
{
	return [self integerForKey:ZDCprefs_activityMonitor_lastActivityType];
}
- (void)setActivityMonitor_lastActivityType:(NSInteger)value
{
	[self setInteger:value forKey:ZDCprefs_activityMonitor_lastActivityType];
}


#pragma mark lastProviderTableUpdate
@dynamic lastProviderTableUpdate;

- (NSDate *)lastProviderTableUpdate;
{
	return [self objectForKey:ZDCprefs_lastProviderTableUpdate];
}
- (void)setLastProviderTableUpdate:(NSDate *)date
{
	[self setObject:date forKey:ZDCprefs_lastProviderTableUpdate];
}

#pragma mark recentRecipients
@dynamic recentRecipients;


// this keeps N of the most recent recipients

- (NSArray<NSArray *> *)recentRecipients
{
    return [self objectForKey:ZDCprefs_recentRecipients];
}
- (void)setRecentRecipients:(NSArray<NSString *> *)recents
{
    [self setObject:recents forKey:ZDCprefs_recentRecipients];
}
- (void)setRecentRecipient:(NSString *)recipientID auth0ID:(NSString *__nullable)auth0ID
{
    const NSUInteger kMaxRecentRecipients = 4;
    
    NSArray<NSArray *> *recents = [self recentRecipients];
    NSArray*  entry =  nil;
    
    if(recipientID)
    {
        entry = auth0ID?@[recipientID,auth0ID]:@[recipientID];
    }
    
    if(entry)
    {
        if (recents.count == 0)
        {
            recents = @[entry];
        }
        else
        {
            // Insert at index 0
            NSMutableArray *newRecents = [NSMutableArray arrayWithArray:recents];
            NSPredicate* predicate = [NSPredicate predicateWithBlock:^BOOL(NSArray* item, NSDictionary* bindings) {
                return (![item[0] isEqualToString:recipientID]);
            }];
            
            [newRecents filterUsingPredicate:predicate];
            [newRecents insertObject:entry atIndex:0];
            
            while (newRecents.count> kMaxRecentRecipients) {
                [newRecents removeLastObject];
            }
            
            recents = [newRecents copy];
        }
        
        [self setObject:recents forKey:ZDCprefs_recentRecipients];
        
    }
}

- (void)removeRecentRecipient:(NSString *)recipientID
{
    // filter out the deleted ids from the prefs/
    __block NSMutableArray  <NSArray *>* _recentRecipients
                = [NSMutableArray arrayWithArray:[self objectForKey:ZDCprefs_recentRecipients]];
    
    NSPredicate* predicate = [NSPredicate predicateWithBlock:^BOOL(NSArray* item, NSDictionary* bindings)
                              {
                                  return (! [recipientID isEqualToString:item[0]]);
                                }];

    [_recentRecipients filterUsingPredicate:predicate];
    
    [self setObject:_recentRecipients forKey:ZDCprefs_recentRecipients];
}

// this keeps a map of prefered Auth0/SocialIDs for userIDS


// this keeps N of the most recent recipients

- (NSDictionary<NSString *,NSString *> * )preferedAuth0IDs
{
     return [self objectForKey:ZDCprefs_preferedAuth0IDs];
}

- (void)setPreferedAuth0ID:(NSString *__nullable )auth0ID userID:(NSString *)userID;
{
    NSMutableDictionary<NSString *,NSString *> *
        _preferedAuth0IDs = [NSMutableDictionary dictionaryWithDictionary:[self preferedAuth0IDs]];
    
    if(auth0ID)
    {
        [_preferedAuth0IDs setObject:auth0ID forKey:userID];
    }
    else
    {
        [_preferedAuth0IDs removeObjectForKey:userID];
    }
  
    [self setObject:_preferedAuth0IDs forKey:ZDCprefs_preferedAuth0IDs];
}


@end
