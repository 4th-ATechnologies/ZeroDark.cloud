/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCLocalPreferences.h"
#import "ZDCPreferenceUtilities.h"

/* extern */ NSString *const ZDCLocalPreferencesChangedNotification = @"ZDCLocalPreferencesChangedNotification";
/* extern */ NSString *const ZDCLocalPreferencesChanged_UserInfo_Key = @"key";

@implementation ZDCLocalPreferences {
@protected

	dispatch_queue_t queue;
}

@synthesize collection = collection;
@synthesize proxy = databaseConnectionProxy;

- (instancetype)initWithCollection:(NSString *)inCollection
                             proxy:(YapDatabaseConnectionProxy *)inProxy
{
	if ((self = [super init]))
	{
		collection = [inCollection copy];
		databaseConnectionProxy = inProxy;
		
		queue = dispatch_queue_create("ZDCLocalPreferences", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)postChangeNotification:(NSString *)prefKey
{
	NSParameterAssert(prefKey != nil);
	
	// We MUST post these notifications to the main thread.
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			ZDCLocalPreferencesChanged_UserInfo_Key: prefKey
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCLocalPreferencesChangedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getter & Setter Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (nullable id)defaultObjectForKey:(NSString *)key
{
	// Override me in subclass
	
	return nil;
}

/**
 * See header file for description.
 */
- (nullable id)objectForKey:(NSString *)key
{
	return [self objectForKey:key isDefault:NULL];
}

/**
 * See header file for description.
 */
- (nullable id)objectForKey:(NSString *)key isDefault:(BOOL *_Nullable)isDefaultPtr
{
	if (key == nil) return nil;
	
	__block id result = nil;
	
	dispatch_sync(queue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = [databaseConnectionProxy objectForKey:key inCollection:collection];
		
	#pragma clang diagnostic pop
	});
	
	if (result == nil)
	{
		result = [self defaultObjectForKey:key];
		if (isDefaultPtr) *isDefaultPtr = YES;
	}
	else
	{
		if (isDefaultPtr) *isDefaultPtr = NO;
	}
	
	return result;
}

/**
 * See header file for description.
 */
- (void)setObject:(nullable id)object forKey:(NSString *)key
{
	if (key == nil)
	{
	#ifndef NS_BLOCK_ASSERTIONS
		NSAssert(NO, @"Attempting to `setObject:forKey:` with nil key");
	#else
		ZDCLogError(@"%@ - Ignoring nil key !", THIS_METHOD);
	#endif
		return;
	}
	
	__block BOOL shouldPostChangeNotification = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"

		id previousDatabaseObject = [databaseConnectionProxy objectForKey:key inCollection:collection];
		if ([previousDatabaseObject isEqual:object])
		{
			// Nothing to write - this same object already exists in database
		}
		else
		{
			id defaultObject = [self defaultObjectForKey:key];
			if ([defaultObject isEqual:object])
			{
				if (previousDatabaseObject)
				{
					// Remove the previousDatabaseObject,
					// but no need to write the new object to disk as it matches the default value.
					//
					[databaseConnectionProxy removeObjectForKey:key inCollection:collection];
					shouldPostChangeNotification = YES;
				}
				else
				{
					// No effective changes.
					//
					// No previousDatabaseObject to delete.
					// Nothing to write because the new object matches the default value.
					//
					// And since this is effectively no change, there's no need to post a notification.
				}
			}
			else
			{
				if (object)
				{
					// Store the new object.
					
					[databaseConnectionProxy setObject:object forKey:key inCollection:collection];
					shouldPostChangeNotification = YES;
				}
				else
				{
					if (previousDatabaseObject)
					{
						// Deleting the old database object.
						// Returning to the default value.
						
						[databaseConnectionProxy removeObjectForKey:key inCollection:collection];
						shouldPostChangeNotification = YES;
					}
					else if (defaultObject)
					{
						// Here's a confusing scenario.
						//
						// The user is trying to store nil (i.e. delete the value)
						// However, there's not a previous stored value.
						// But there iS a default value...
						//
						// So the user could be trying to do 1 of 2 things:
						// - Force a return to the default value
						// - Override the default value with nil
						//
						// There's no way to support both options.
						// So we're going to pick the most sane option:
						//
						// If you want to override the default value, you MUST store a non-nil value.
						// For example, you could store NSNull.
						//
						// So no effective change was performed.
					}
					else
					{
						// The user has asked us to delete the value.
						// But there wasn't a value stored for the key.
						// And there's not a default value for the key.
						//
						// In other words, no effective change was performed.
					}
				}
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldPostChangeNotification) {
		[self postChangeNotification:key];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience (Getters)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)boolForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities boolValueFromObject:[self objectForKey:key]];
}

- (float)floatForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities floatValueFromObject:[self objectForKey:key]];
}

- (double)doubleForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities doubleValueFromObject:[self objectForKey:key]];
}

- (NSInteger)integerForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities integerValueFromObject:[self objectForKey:key]];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities unsignedIntegerValueFromObject:[self objectForKey:key]];
}

- (NSString *)stringForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities stringValueFromObject:[self objectForKey:key]];
}

- (NSNumber *)numberForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities numberValueFromObject:[self objectForKey:key]];
}

- (NSData *)dataForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities dataValueFromObject:[self objectForKey:key]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience (Setters)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setBool:(BOOL)value forKey:(NSString *)key
{
	[self setObject:@(value) forKey:key];
}

- (void)setFloat:(float)value forKey:(NSString *)key
{
	[self setObject:@(value) forKey:key];
}

- (void)setDouble:(double)value forKey:(NSString *)key
{
	[self setObject:@(value) forKey:key];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key
{
	[self setObject:@(value) forKey:key];
}

- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key
{
	[self setObject:@(value) forKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience (Defaults)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)defaultBoolForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities boolValueFromObject:[self defaultObjectForKey:key]];
}

- (float)defaultFloatForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities floatValueFromObject:[self defaultObjectForKey:key]];
}

- (double)defaultDoubleForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities doubleValueFromObject:[self defaultObjectForKey:key]];
}

- (NSInteger)defaultIntegerForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities integerValueFromObject:[self defaultObjectForKey:key]];
}

- (NSUInteger)defaultUnsignedIntegerForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities unsignedIntegerValueFromObject:[self defaultObjectForKey:key]];
}

- (NSString *)defaultStringForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities stringValueFromObject:[self defaultObjectForKey:key]];
}

- (NSNumber *)defaultNumberForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities numberValueFromObject:[self defaultObjectForKey:key]];
}

- (NSData *)defaultDataForKey:(NSString *)key
{
	return [ZDCPreferenceUtilities dataValueFromObject:[self defaultObjectForKey:key]];
}

@end
