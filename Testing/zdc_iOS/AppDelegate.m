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
	[self setupZeroDarkCloud];
	[self testXattrs];
	
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
	
	zdc = [[ZeroDarkCloud alloc] initWithDelegate: delegate
	                                 databaseName: dbName
	                                       zAppID: @"com.4th-a.storm4"];
	
	NSLog(@"zdc: %@", zdc);
	
	NSError *error = nil;
	NSData *databaseKey = nil;
	
	databaseKey = [zdc.databaseKeyManager unlockUsingKeychainKeyWithError:&error];
	if (error) {
		NSLog(@"Error fetching database key: %@", error);
		return NO;
	}
	
	ZDCDatabaseConfig *config = [[ZDCDatabaseConfig alloc] initWithEncryptionKey:databaseKey];
	
	error = [zdc unlockOrCreateDatabase:config];
	if (error) {
		NSLog(@"Error unlocking database: %@", error);
		return NO;
	}
	
	return YES;
}

- (void)testXattrs
{
	// Are xattrs still broken on the simulator ???
	
	NSLog(@"maxNodeDataCacheSize: %llu", zdc.diskManager.maxNodeDataCacheSize);
	NSLog(@"maxNodeThumbnailsCacheSize: %llu", zdc.diskManager.maxNodeThumbnailsCacheSize);
	NSLog(@"maxUserAvatarsCacheSize: %llu", zdc.diskManager.maxUserAvatarsCacheSize);
	
	zdc.diskManager.maxNodeDataCacheSize = (1024 * 1024 * 1);
}

@end
