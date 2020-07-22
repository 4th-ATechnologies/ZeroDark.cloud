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
//	[self setupZeroDarkCloud];
	
	dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
	dispatch_after(delay, dispatch_get_main_queue(), ^{
		
		[self createTestLocalUser];
	});
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(syncStatusChange:)
	                                             name: ZDCSyncStatusChangedNotification
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
	
	[zdc unlockOrCreateDatabase:dbConfig error:&error];
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

	__block ZDCLocalUser *newLocalUser = nil;
	__block ZDCLocalUser *existingLocalUser = nil;
	
	[zdc.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:
	  ^(YapDatabaseReadWriteTransaction *transaction)
	{
		ZDCLocalUserManager *localUserManager = self->zdc.localUserManager;
		
		NSError *error = nil;
		newLocalUser = [localUserManager createLocalUserFromJSON: json
		                                             transaction: transaction
		                                                   error: &error];
		
		if (newLocalUser == nil)
		{
			existingLocalUser = [localUserManager anyLocalUser:transaction];
		}
		
	} completionBlock:^{
		
		if (newLocalUser)
		{
			// We just created a NEW localUser.
			// So we need to wait for ZDC to sync the treesystem (i.e. perform the first PULL from the cloud).
			//
			// We're setup to receive a notification about this: ZDCPullStoppedNotification
		}
		else if (existingLocalUser)
		{
			// The localUser already exists in the database.
			// So we can explore their treesystem immediately.
			
			[self exploreTreesystem:existingLocalUser.uuid];
		}
	}];
}

- (void)exploreTreesystem:(NSString *)localUserID
{
	NSLog(@"exploreTreesystem: localUserID = %@", localUserID);
	
	if (localUserID == nil) return;
	
	[zdc.databaseManager.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCTrunkNode *trunkNode =
		  [zdc.nodeManager trunkNodeForLocalUserID: localUserID
		                                    treeID: zdc.primaryTreeID
		                                     trunk: ZDCTreesystemTrunk_Home
		                               transaction: transaction];
		
		[zdc.nodeManager recursiveEnumerateNodesWithParentID: trunkNode.uuid
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

- (void)syncStatusChange:(NSNotification *)notification
{
	
	ZDCSyncStatusNotificationInfo* info = notification.userInfo[kZDCSyncStatusNotificationInfo];
	
	switch(info.type)
	{
		case ZDCSyncStatusNotificationType_PullStarted:
			NSLog(@"PullStarted: %@", notification.userInfo);
			break;

		case ZDCSyncStatusNotificationType_PullStopped:
		{
			NSLog(@"pullStopped: %@", notification.userInfo);
 
			NSString *localUserID = info.localUserID;
			[self exploreTreesystem:localUserID];
		}
			break;
 
			default:
			break;

	}
	
 }
 
@end
