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

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[self setupZeroDarkCloud];
//	[self createTestLocalUser];
	
	uint64_t nodeDataCacheSize = zdc.diskManager.maxNodeDataCacheSize;
	NSLog(@"nodeDataCacheSize: %llu", nodeDataCacheSize);
	
	zdc.diskManager.maxNodeDataCacheSize = (1024 * 1024 * 1);
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(pullStarted:)
	                                             name: ZDCPullStartedNotification
	                                           object: nil];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(pullStopped:)
	                                             name: ZDCPullStoppedNotification
	                                           object: nil];
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

- (void)createTestLocalUser
{
	NSURL *jsonURL = [[NSBundle mainBundle] URLForResource:@"TestUser" withExtension:@"json"];
	NSData *data = [NSData dataWithContentsOfURL:jsonURL];

	NSError *error = nil;
	NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	
	if (error) {
		NSLog(@"Error reading 'TestUser.json': %@", error);
		return;
	}
	
	NSLog(@"TestUser.json: %@", json);

	[zdc.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:
	  ^(YapDatabaseReadWriteTransaction *transaction)
	{
		NSError *oops =
		  [self->zdc.localUserManager createLocalUserFromJSON: json
		                                          transaction: transaction
		                                       outLocalUserID: nil];
		if (oops) {
			NSLog(@"Error creating localUser: %@", oops);
		}
	}];
}

- (void)pullStarted:(NSNotification *)notification
{
	NSLog(@"PullStarted: %@", notification.userInfo);
}

- (void)pullStopped:(NSNotification *)notification
{
	NSLog(@"pullStopped: %@", notification.userInfo);
	
	[zdc.databaseManager.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSArray<NSString*> *localUserIDs = [zdc.localUserManager allLocalUserIDs:transaction];
		NSString *localUserID = [localUserIDs firstObject];
		
		if (localUserID == nil) return;
		
		ZDCContainerNode *containerNode =
		  [zdc.nodeManager containerNodeForLocalUserID: localUserID
		                                        zAppID: zdc.zAppID
		                                     container: ZDCTreesystemContainer_Home
		                                   transaction: transaction];
		
		[zdc.nodeManager recursiveEnumerateNodesWithParentID: containerNode.uuid
		                                         transaction: transaction
		                                          usingBlock:
		^(ZDCNode *node, NSArray<ZDCNode *> *pathFromParent, BOOL *recurseInto, BOOL *stop)
		{
			ZDCTreesystemPath *path = [zdc.nodeManager pathForNode:node transaction:transaction];
			
			NSLog(@"----------");
			NSLog(@"node.uuid: %@", node.uuid);
			NSLog(@"node.path: %@", path.relativePath);
			NSLog(@"node.rcrd: %@ - %@", node.eTag_rcrd, node.lastModified_rcrd);
			NSLog(@"node.data: %@ - %@", node.eTag_data, node.lastModified_data);
			
			ZDCCloudPath *cloudPath =
			  [[ZDCCloudPathManager sharedInstance] cloudPathForNode:node transaction:transaction];
			NSLog(@"cloudPath: %@", cloudPath.path);
		}];
		
	#pragma clang diagnostic pop
	}];
}

@end
