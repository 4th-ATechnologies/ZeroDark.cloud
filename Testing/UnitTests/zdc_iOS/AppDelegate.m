/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "AppDelegate.h"
#import "ZDCDelegate.h"

#import <ZeroDarkCloud/ZeroDarkCloud.h>

@implementation AppDelegate {
	ZeroDarkCloud *zdc;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
//	[self setupZeroDarkCloud];
	
	return YES;
}

- (BOOL)setupZeroDarkCloud
{
	ZDCDelegate *delegate = [[ZDCDelegate alloc] init];
	NSString *dbName = @"test.sqlite";
	
	if (YES)
	{
		NSArray<NSURL*> *urls = [ZDCDirectoryManager fileURLsForDatabaseName:dbName];
		for (NSURL *url in urls)
		{
			[[NSFileManager defaultManager] removeItemAtURL:url error:nil];
		}
	}
	
	ZDCConfig *config = [[ZDCConfig alloc] initWithPrimaryTreeID:@"com.4th-a.storm4"];
	config.databaseName = dbName;
	
	zdc = [[ZeroDarkCloud alloc] initWithDelegate: delegate
	                                       config: config];
	
	NSLog(@"zdc: %@", zdc);
	
	NSError *error = nil;
	NSData *databaseKey = nil;
	
	databaseKey = [zdc.databaseKeyManager unlockUsingKeychain:&error];
	if (error) {
		NSLog(@"Error fetching database key: %@", error);
		return NO;
	}
	
	ZDCDatabaseConfig *dbConfig = [[ZDCDatabaseConfig alloc] initWithEncryptionKey:databaseKey];
	
	error = [zdc unlockOrCreateDatabase:dbConfig];
	if (error) {
		NSLog(@"Error unlocking database: %@", error);
		return NO;
	}
	
	return YES;
}

@end
