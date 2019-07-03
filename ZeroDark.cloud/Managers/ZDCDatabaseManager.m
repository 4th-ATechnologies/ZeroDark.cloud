#import "ZDCDatabaseManagerPrivate.h"

#import "ZDCConstants.h"
#import "ZDCCachedResponse.h"
#import "ZDCCloudPrivate.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCNodePrivate.h"
#import "ZDCTask.h"
#import "ZDCUserPrivate.h"
#import "ZDCSplitKey.h"

#import "NSURLResponse+ZeroDark.h"

#import <libkern/OSAtomic.h>
#import <os/lock.h>
#import <YapDatabase/YapDatabaseAtomic.h>
#import <ZDCSyncableObjC/ZDCObject.h>

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif

NSString *const UIDatabaseConnectionWillUpdateNotification = @"UIDatabaseConnectionWillUpdateNotification";
NSString *const UIDatabaseConnectionDidUpdateNotification  = @"UIDatabaseConnectionDidUpdateNotification";
NSString *const kNotificationsKey = @"notifications";

NSString *const Ext_Relationship              = @"ZeroDark:graph";
NSString *const Ext_Index_Nodes               = @"ZeroDark:idx_nodes";
NSString *const Ext_Index_Users               = @"ZeroDark:idx_users";
NSString *const Ext_View_LocalUsers           = @"ZeroDark:localUsers";
NSString *const Ext_View_Filesystem_Name      = @"ZeroDark:fsName";
NSString *const Ext_View_Filesystem_CloudName = @"ZeroDark:fsCloudName";
NSString *const Ext_View_Flat                 = @"ZeroDark:flat";
NSString *const Ext_View_Cloud_DirPrefix      = @"ZeroDark:fsCloudDirPrefix";
NSString *const Ext_CloudCore_Prefix          = @"ZeroDark:cloud_";
NSString *const Ext_ActionManager             = @"ZeroDark:action";
NSString *const Ext_View_SplitKeys            = @"ZeroDark:splitKeys";
NSString *const Ext_View_SplitKeys_Date  		 = @"ZeroDark:splitKeys.createDate";


NSString *const Index_Nodes_Column_CloudID    = @"cloudID";
NSString *const Index_Nodes_Column_DirPrefix  = @"dirPrefix";

NSString *const Index_Users_Column_RandomUUID = @"random_uuid";


@implementation ZDCDatabaseManager
{
	__weak ZeroDarkCloud *owner;
	
	YapDatabaseActionManager *actionManager;
	
	NSArray<YapCollectionKey *> *previouslyRegisteredCloudExtTuples;
	
	YAPUnfairLock spinlock;
	NSMutableDictionary<YapCollectionKey*, ZDCCloud*> *registeredCloudDict;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.databaseManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
		
		spinlock = OS_SPINLOCK_INIT;
		registeredCloudDict = [[NSMutableDictionary alloc] initWithCapacity:4];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize database = database;
@synthesize uiDatabaseConnection = uiDatabaseConnection;
@synthesize roConnectionPool = roConnectionPool;
@dynamic roDatabaseConnection;
@synthesize rwDatabaseConnection = rwDatabaseConnection;
@synthesize databaseConnectionProxy = databaseConnectionProxy;

- (YapDatabaseConnection *)uiDatabaseConnection
{
	NSAssert([NSThread isMainThread], @"Can't use the uiDatabaseConnection outside the main thread");
	
	return uiDatabaseConnection;
}

- (YapDatabaseConnection *)roDatabaseConnection
{
	return [roConnectionPool connection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The serializer block converts objects into encrypted data blobs.
 *
 * First we use the NSCoding protocol to turn the object into a data blob.
 * Thus all objects that go into the databse need only support the NSCoding protocol.
 * Then we encrypt the data blob.
**/
- (YapDatabaseSerializer)databaseSerializer:(ZDCDatabaseConfig *)config
                                collections:(NSSet<NSString*> *)zdcCollections
{
	YapDatabaseSerializer clientSerializer = config.serializer;
	YapDatabaseSerializer zdcSerializer = ^(NSString *collection, NSString *key, id object){
		
		return [NSKeyedArchiver archivedDataWithRootObject:object];
	};
	
	YapDatabaseSerializer serializer = ^(NSString *collection, NSString *key, id object){
		
		if ([zdcCollections containsObject:collection])
		{
			return zdcSerializer(collection, key, object);
		}
		else
		{
			if (clientSerializer) {
				return clientSerializer(collection, key, object);
			} else {
				return zdcSerializer(collection, key, object);
			}
		}
	};
	
	return serializer;
}

/**
 * The deserializer block converts encrypted data blobs back into objects.
**/
- (YapDatabaseDeserializer)databaseDeserializer:(ZDCDatabaseConfig *)config
                                    collections:(NSSet<NSString*> *)zdcCollections
{
	YapDatabaseDeserializer clientDeserializer = config.deserializer;
	YapDatabaseDeserializer zdcDeserializer = ^(NSString *collection, NSString *key, NSData *data){
		
		id object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		if ([object isKindOfClass:[ZDCObject class]])
		{
			[(ZDCObject *)object makeImmutable];
		}
		
		return object;
	};
	
	YapDatabaseDeserializer deserializer = ^(NSString *collection, NSString *key, NSData *data){
		
		if ([zdcCollections containsObject:collection])
		{
			return zdcDeserializer(collection, key, data);
		}
		else
		{
			if (clientDeserializer) {
				return clientDeserializer(collection, key, data);
			} else {
				return zdcDeserializer(collection, key, data);
			}
		}
	};
	
	return deserializer;
}

- (YapDatabasePreSanitizer)databasePreSanitizer:(ZDCDatabaseConfig *)config
                                    collections:(NSSet<NSString*> *)zdcCollections
{
	YapDatabasePreSanitizer clientPreSanitizer = config.preSanitizer;
	YapDatabasePreSanitizer zdcPreSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[ZDCObject class]])
		{
			[(ZDCObject *)object makeImmutable];
		}
		
		return object;
	};
	
	YapDatabasePreSanitizer preSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([zdcCollections containsObject:collection])
		{
			return zdcPreSanitizer(collection, key, object);
		}
		else
		{
			if (clientPreSanitizer) {
				return clientPreSanitizer(collection, key, object);
			} else {
				return zdcPreSanitizer(collection, key, object);
			}
		}
	};
	
	return preSanitizer;
}

- (YapDatabasePostSanitizer)databasePostSanitizer:(ZDCDatabaseConfig *)config
                                      collections:(NSSet<NSString*> *)zdcCollections
{
	YapDatabasePostSanitizer clientPostSanitizer = config.postSanitizer;
	YapDatabasePostSanitizer zdcPostSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[ZDCObject class]])
		{
			[(ZDCObject *)object clearChangeTracking];
		}
	};
	
	YapDatabasePostSanitizer postSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([zdcCollections containsObject:collection])
		{
			zdcPostSanitizer(collection, key, object);
		}
		else
		{
			if (clientPostSanitizer) {
				return clientPostSanitizer(collection, key, object);
			} else {
				return zdcPostSanitizer(collection, key, object);
			}
		}
	};
	
	return postSanitizer;
}

- (BOOL)setupDatabase:(ZDCDatabaseConfig *)config
{
	DDLogAutoTrace();
	
	// Create the database
	
	NSString *databasePath = owner.databasePath.filePathURL.path;
	DDLogDebug(@"databasePath = %@", databasePath);
	
	YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
	options.corruptAction = YapDatabaseCorruptAction_Rename;
	options.pragmaMMapSize = (1024 * 1024 * 4);
	options.aggressiveWALTruncationSize = (1024 * 1024 * 16);
	
#ifdef SQLITE_HAS_CODEC
	
	NSData *const databaseKey = [config.encryptionKey copy];
	options.cipherKeyBlock = ^ NSData *(void){
		
		return databaseKey;
	};
	
#endif
	
	NSSet<NSString*> *collections = [NSSet setWithArray:@[
		kZDCCollection_CachedResponse,
		kZDCCollection_CloudNodes,
		kZDCCollection_Nodes,
		kZDCCollection_Prefs,
		kZDCCollection_PublicKeys,
		kZDCCollection_PullState,
		kZDCCollection_Reminders,
		kZDCCollection_SessionStorage,
		kZDCCollection_SymmetricKeys,
		kZDCCollection_Tasks,
		kZDCCollection_Users,
		kZDCCollection_UserAuth,
		kZDCCollection_SplitKeys,
	]];
	
	database = [[YapDatabase alloc] initWithPath: databasePath
	                                  serializer: [self databaseSerializer:config collections:collections]
	                                deserializer: [self databaseDeserializer:config collections:collections]
	                                preSanitizer: [self databasePreSanitizer:config collections:collections]
	                               postSanitizer: [self databasePostSanitizer:config collections:collections]
	                                     options: options];
	
	if (database == nil) {
		return NO;
	}
	
	database.connectionDefaults.objectPolicy = YapDatabasePolicyShare;
	database.connectionDefaults.metadataPolicy = YapDatabasePolicyShare;
	
	// Create a dedicated read-only connection for the UI (main thread).
	// It will use a longLivedReadTransaction,
	// and uses the UIDatabaseConnectionModifiedNotification to post when it updates.
	
	uiDatabaseConnection = [database newConnection];
	uiDatabaseConnection.objectCacheLimit = 1000;
	uiDatabaseConnection.metadataCacheLimit = 1000;
	uiDatabaseConnection.name = @"uiDatabaseConnection";
#if DEBUG
	uiDatabaseConnection.permittedTransactions = YDB_MainThreadOnly | YDB_SyncReadTransaction /* NO asyncReads! */;
#endif
	
	// Create convenience connections for other classes.
	// They can be used by classes that don't need a dedicated connection.
	// Basically it helps to cut down on [database newConnection] one-off's.
	
	YapDatabaseConnectionConfig *roConfig = [[YapDatabaseConnectionConfig alloc] init];
	roConfig.objectCacheLimit = 1000;
	roConfig.metadataCacheLimit = 1000;
	
	roConnectionPool = [[YapDatabaseConnectionPool alloc] initWithDatabase:database];
	roConnectionPool.connectionDefaults = roConfig;
	roConnectionPool.didCreateNewConnectionBlock = ^(YapDatabaseConnection *connection) {
		
		connection.name = @"roDatabaseConnection";
	#if DEBUG
		connection.permittedTransactions = YDB_AnyReadTransaction;
	#endif
	};
	
	rwDatabaseConnection = [database newConnection];
	rwDatabaseConnection.objectCacheLimit = 1000;
	rwDatabaseConnection.metadataCacheLimit = 1000;
	rwDatabaseConnection.name = @"rwDatabaseConnection";
	
	databaseConnectionProxy =
	  [[YapDatabaseConnectionProxy alloc] initWithDatabase: database
	                                    readOnlyConnection: [roConnectionPool connection]
	                                   readWriteConnection: rwDatabaseConnection];
	
	// Setup all the extensions
	
	[self setupRelationship];
	[self setupIndex_Nodes];
	[self setupIndex_Users];
	[self setupView_LocalUsers];
	[self setupView_Filesystem_Name];
	[self setupView_Filesystem_CloudName];
	[self setupView_Flat];
	[self setupView_CloudDirPrefix];
	[self setupView_SplitKeys];
	[self setupView_SplitKeys_Date];
	[self setupCloudExtensions];
	[self setupActionManager];

	if (config.extensionsRegistration)
	{
		@try {
			config.extensionsRegistration(database);
			
		} @catch (NSException * __unused exception) {}
	}

	[database flushExtensionRequestsWithCompletionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                                    completionBlock:
	^{
		[self didRegisterAllExtensions];
	}];
	
	//
	// Start the longLivedReadTransaction on the UI connection.
	//
	
	[uiDatabaseConnection enableExceptionsForImplicitlyEndingLongLivedReadTransaction];
	[uiDatabaseConnection beginLongLivedReadTransaction];
	
	// Register for notifications
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(yapDatabaseModified:)
	                                             name: YapDatabaseModifiedNotification
	                                           object: database];
	
	return YES;
}

- (void)setupRelationship
{
	DDLogAutoTrace();
	
	//
	// GRAPH RELATIONSHIP
	//
	// Create "graph" extension.
	// It manages relationships between objects, and handles cascading deletes.
	//
	
	YapDatabaseRelationship *ext = [[YapDatabaseRelationship alloc] initWithVersionTag:@"1"];
	
	NSString *extName = Ext_Relationship;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupIndex_Nodes
{
	DDLogAutoTrace();
	
	//
	// SECONDARY INDEX - NODES
	//
	// Indexes the following:
	// - ZDCNode.cloudID
	// - ZDCNode.dirPrefix
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:Index_Nodes_Column_CloudID   withType:YapDatabaseSecondaryIndexTypeText];
	[setup addColumn:Index_Nodes_Column_DirPrefix withType:YapDatabaseSecondaryIndexTypeText];
	
	YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict,
	      NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCNode class]], @"Invalid class detected !");
		__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
		
		dict[Index_Nodes_Column_CloudID] = node.cloudID;
		dict[Index_Nodes_Column_DirPrefix] = node.dirPrefix;
	}];
	
	NSString *const versionTag = @"2018-03-09"; // <-- change me if you modify handler block
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_Nodes];
	
	YapDatabaseSecondaryIndexOptions *options = [[YapDatabaseSecondaryIndexOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseSecondaryIndex *ext =
	  [[YapDatabaseSecondaryIndex alloc] initWithSetup: setup
	                                           handler: handler
	                                        versionTag: versionTag
	                                           options: options];
	
	NSString *const extName = Ext_Index_Nodes;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupIndex_Users
{
	DDLogAutoTrace();
	
	//
	// SECONDARY INDEX - USERS
	//
	// Indexes the following:
	// - ZDCUser.random
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:Index_Users_Column_RandomUUID withType:YapDatabaseSecondaryIndexTypeText];
	
	YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict,
	      NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCUser class]], @"Invalid class detected !");
		__unsafe_unretained ZDCUser *user = (ZDCUser *)object;
		
		dict[Index_Users_Column_RandomUUID] = user.random_uuid;
	}];
	
	NSString *const versionTag = @"2018-03-22"; // <-- change me if you modify handler block
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_Users];
	
	YapDatabaseSecondaryIndexOptions *options = [[YapDatabaseSecondaryIndexOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseSecondaryIndex *ext =
	  [[YapDatabaseSecondaryIndex alloc] initWithSetup: setup
	                                           handler: handler
	                                        versionTag: versionTag
	                                           options: options];
	
	NSString *const extName = Ext_Index_Users;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}


- (void)setupView_LocalUsers
{
	DDLogAutoTrace();
	
    //
    // VIEW - LOCAL USERS
    //
    // Sorts all localUsers by name (localized)
    //
	
    YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCUser class]], @"Invalid class detected !");
		__unsafe_unretained ZDCUser *user = (ZDCUser *)object;
		
		if (user.isLocal) {
			return @"";
		}
		
		return nil; // exclude from view
	}];
	
    YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained ZDCUser *user1 = (ZDCUser *)obj1;
		__unsafe_unretained ZDCUser *user2 = (ZDCUser *)obj2;
		
		NSString *name1 = user1.displayName;
		NSString *name2 = user2.displayName;
		
		return [name1 localizedCaseInsensitiveCompare:name2];
	}];
	
	NSString *version = @"1.2"; // <---------- change me if you modify grouping or sorting block <----------
	NSString *locale = [[NSLocale currentLocale] localeIdentifier];
	
	NSString *tag = [NSString stringWithFormat:@"%@-%@", version, locale];
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_Users];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping: grouping
	                                        sorting: sorting
	                                     versionTag: tag
	                                        options: options];
	
	NSString *const extName = Ext_View_LocalUsers;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_Filesystem_Name
{
	DDLogAutoTrace();
	
	//
	// VIEW - FILE SYSTEM (ZDCNode's sorted by cleartext name)
	//
	// Sorts items into a hierarchical system, sorted by names.
	//
	// ZDCNode's:
	//   - group(localUserID)       -> values(files and sub-directories in root directory)
	//   - group(parentDirectoryID) -> values(files and sub-directories in given directory)
	//
	//   ^Sorting is done according to ZDCNode.name (cleartext name)
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		// Don't forget to change `version` (below) if you modify this block.
		//
		
		NSAssert([object isKindOfClass:[ZDCNode class]], @"Invalid class detected !");
		__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
		
		// Sanity checks:
		if (node.name == nil)
		{
			// Apple's documentation for 'localizedCaseInsensitiveCompare' (used in the sorting block) states:
			//
			// > [The parameter] must not be nil. If this value is nil,
			// > the behavior is undefined and may change in future versions of OS X.
			
			return nil;
		}
		
		// All regular nodes have a parentID.
		// Container nodes don't have a parentID.
		// Signal nodes don't have a parentID.
		//
		return node.parentID;
		//
		// Don't forget to change `version` (below) if you modify this block.
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		// Don't forget to change `version` (below) if you modify this block.
		//
		
		__unsafe_unretained ZDCNode *node1 = (ZDCNode *)obj1;
		__unsafe_unretained ZDCNode *node2 = (ZDCNode *)obj2;
		
		NSComparisonResult result = [node1.name localizedCaseInsensitiveCompare:node2.name];
		if (result == NSOrderedSame) {
			result = [node1.uuid compare:node2.uuid]; // name collision may occur in non-root containers.
		}
		
		return result;
		//
		// Don't forget to change `version` (below) if you modify this block.
	}];
	
	NSString *version = @"2019-01-30"; // <---------- change me if you modify grouping or sorting block <----------
	NSString *locale = [[NSLocale currentLocale] localeIdentifier]; // because of localized name comparison
	
	NSString *versionTag = [NSString stringWithFormat:@"%@-%@", version, locale];
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_Nodes];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping:grouping
	                                        sorting:sorting
	                                     versionTag:versionTag
	                                        options:options];
	
	NSString *const extName = Ext_View_Filesystem_Name;
	[database asyncRegisterExtension:ext
	                        withName:extName
	                 completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_Filesystem_CloudName
{
	DDLogAutoTrace();
	
	//
	// VIEW - FILE SYSTEM (ZDCNode's sorted by cloudName)
	//
	// Sorts items into a hierarchical system, sorted by cloudName.
	//
	// ZDCNode's:
	//   - group(parentID) -> values(direct children of the given parent)
	//
	//   ^Sorting is done according to node's cloudName.
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		// Don't forget to change `version` (below) if you modify this block.
		//
		NSAssert([object isKindOfClass:[ZDCNode class]], @"Invalid class detected !");
		__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
		
		NSString *cloudName = [[ZDCCloudPathManager sharedInstance] cloudNameForNode:node transaction:transaction];
		if (cloudName == nil)
		{
			// Apple's documentation for 'compare:' (used in the sorting block) states:
			//
			// > [The parameter] must not be nil. If this value is nil,
			// > the behavior is undefined and may change in future versions of OS X.
			
			return nil;
		}
		
		// All regular nodes have a parentID.
		// Container nodes don't have a parentID.
		// Signal nodes don't have a parentID.
		//
		return node.parentID;
		//
		// Don't forget to change `version` (below) if you modify this block.
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		// Don't forget to change `version` (below) if you modify this block.
		//
		__unsafe_unretained ZDCNode *node1 = (ZDCNode *)obj1;
		__unsafe_unretained ZDCNode *node2 = (ZDCNode *)obj2;
		
		ZDCCloudPathManager *cloudPathManager = [ZDCCloudPathManager sharedInstance];
		
		NSString *cloudName1 = [cloudPathManager cloudNameForNode:node1 transaction:transaction];
		NSString *cloudName2 = [cloudPathManager cloudNameForNode:node2 transaction:transaction];
		
		NSComparisonResult result = [cloudName1 compare:cloudName2];
		if (result == NSOrderedSame) {
			result = [node1.uuid compare:node2.uuid];
		}
		
		return result;
		//
		// Don't forget to change `version` (below) if you modify this block.
	}];
	
	NSString *versionTag = @"2019-03-05"; // <---------- change me if you modify grouping or sorting block <----------
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_Nodes];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping: grouping
	                                        sorting: sorting
	                                     versionTag: versionTag
	                                        options: options];
	
	NSString *const extName = Ext_View_Filesystem_CloudName;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_Flat
{
	DDLogAutoTrace();
	
	//
	// VIEW - FLAT
	//
	// Sorts all files & directories into a flat system.
	//
	// group(localUserID) -> values(every single file & directory)
	//
	// Note:
	// This view is the parent view for other filteredViews.
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCNode class]], @"Invalid class detected !");
		__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
		
		// IMPORTANT: This is a utility view which is used by MANY other utility methods.
		// For example:
		//
		// - [ZDCNodeManager enumerateNodeIDsWithParentID:::]
		// - [ZDCNodeManager enumerateNodesWithParentID:::]
		// - [ZDCNodeManager findNodeWithName:::]
		// - [ZDCNodeManager findNodeWithCloudID:::]
		// - [ZDCNodeManager findNodeWithCloudName:::]
		// - [ZDCNodeManager findNodeWithChildPrefix:::]
		//
		// As such, it is REQUIRED that this extension contains EVERY node belonging to the local user.
		// Absolutely ZERO filtering is allowed in this extension.
		//
		// If you need filtering, you may NOT do it here.
		// You MUST do it in a child extension.
		
		if (node.parentID == nil) return nil; // exclude container nodes
		
		ZDCContainerNode *containerNode =
		  [[ZDCNodeManager sharedInstance] containerNodeForNode:node transaction:transaction];
		
		if (containerNode == nil) return nil;
		
		return [ZDCDatabaseManager groupForLocalUserID:node.localUserID zAppID:containerNode.zAppID];
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSString *group,
	      NSString *collection1, NSString *key1, id obj1,
	      NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained ZDCNode *node1 = (ZDCNode *)obj1;
		__unsafe_unretained ZDCNode *node2 = (ZDCNode *)obj2;
		
		return [node1.uuid compare:node2.uuid];
	}];
	
	NSString *versionTag = @"2019-01-30"; // <---------- change me if you modify grouping or sorting block <----------
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_Nodes];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping:grouping
	                                        sorting:sorting
	                                     versionTag:versionTag
	                                        options:options];
	
	NSString *const extName = Ext_View_Flat;
	[database asyncRegisterExtension:ext
	                        withName:extName
	                 completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_CloudDirPrefix
{
	DDLogAutoTrace();
	
	//
	// VIEW - HIERARCHICAL CLOUD (sorted by dirPrefix)
	//
	// Sorts all ZDCCloudNode's into a hierarchical system.
	//
	// group(localUserID|dirPrefix) -> values(ZDCCloudNode's with given dirPrefix)
	//
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		// Don't forget to change `version` (below) if you modify this block.
		//
		
		NSAssert([object isKindOfClass:[ZDCCloudNode class]], @"Invalid class detected !");
		__unsafe_unretained ZDCCloudNode *cloudNode = (ZDCCloudNode *)object;
		
		ZDCCloudLocator *cloudLocator = cloudNode.cloudLocator;
		ZDCCloudPath *cloudPath = cloudLocator.cloudPath;
		
		return [ZDCDatabaseManager groupForLocalUserID: cloudNode.localUserID
		                                        region: cloudLocator.region
		                                        bucket: cloudLocator.bucket
		                                     appPrefix: cloudPath.appPrefix
		                                     dirPrefix: cloudPath.dirPrefix];
		
		//
		// Don't forget to change `version` (below) if you modify this block.
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		// Don't forget to change `version` (below) if you modify this block.
		//
		
		__unsafe_unretained ZDCCloudNode *cloudNode1 = (ZDCCloudNode *)obj1;
		__unsafe_unretained ZDCCloudNode *cloudNode2 = (ZDCCloudNode *)obj2;
		
		NSString *fileName1 = [cloudNode1.cloudLocator.cloudPath fileNameWithExt:nil];
		NSString *fileName2 = [cloudNode2.cloudLocator.cloudPath fileNameWithExt:nil];
		
		if (fileName1 == nil) fileName1 = @"";
		if (fileName2 == nil) fileName2 = @"";
		
		return [fileName1 compare:fileName2];
		
		//
		// Don't forget to change `version` (below) if you modify this block.
	}];
	
	NSString *version = @"2019-04-19"; // <---------- change me if you modify grouping or sorting block <----------
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_CloudNodes];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping:grouping
	                                        sorting:sorting
	                                     versionTag:version
	                                        options:options];
	
	NSString *const extName = Ext_View_Cloud_DirPrefix;
	[database asyncRegisterExtension:ext
	                        withName:extName
	                 completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_SplitKeys
{
	DDLogAutoTrace();
	
	  //
    // VIEW - SplitKeys for user
    //
    // Sorts all SplitKeys by splitNum (localized)
    //
	
    YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCSplitKey class]], @"Invalid class detected !");
		__unsafe_unretained ZDCSplitKey *split = (ZDCSplitKey *)object;
		
		return split.localUserID;
	}];
	
    YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained ZDCSplitKey *split1 = (ZDCSplitKey *)obj1;
		__unsafe_unretained ZDCSplitKey *split2 = (ZDCSplitKey *)obj2;
		
		return [@(split1.splitNum) compare:	@(split2.splitNum)];
	}];
	
	NSString *versionTag = @"1.0"; // <---------- change me if you modify grouping or sorting block <----------

	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_SplitKeys];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping: grouping
	                                        sorting: sorting
	                                     versionTag: versionTag
	                                        options: options];
	
	NSString *const extName = Ext_View_SplitKeys;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_SplitKeys_Date
{
	DDLogAutoTrace();
	
	//
	// VIEW - SplitKeys for user
	//
	// Sorts all SplitKeys by splitNum Create date
	//
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCSplitKey class]], @"Invalid class detected !");
		__unsafe_unretained ZDCSplitKey *split = (ZDCSplitKey *)object;
		
		return split.localUserID;
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
	     NSString *collection1, NSString *key1, id obj1,
	     NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained ZDCSplitKey *split1 = (ZDCSplitKey *)obj1;
		__unsafe_unretained ZDCSplitKey *split2 = (ZDCSplitKey *)obj2;
		
		return [split2.creationDate compare: split1.creationDate];
	}];
	
	NSString *versionTag = @"1.1"; // <---------- change me if you modify grouping or sorting block <----------
	
	NSSet *whitelist = [NSSet setWithObject:kZDCCollection_SplitKeys];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:whitelist];
	
	YapDatabaseAutoView *ext =
	  [[YapDatabaseAutoView alloc] initWithGrouping: grouping
	                                        sorting: sorting
	                                     versionTag: versionTag
	                                        options: options];
	
	NSString *const extName = Ext_View_SplitKeys_Date;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupCloudExtensions
{
	DDLogAutoTrace();
	
	//
	// CLOUD CORE
	//
	// The cloud core extension manages the upload queue for local users.
	//
	
	NSMutableArray<YapCollectionKey *> *tuples = nil;
	
	NSArray<NSString *> *previouslyRegisteredExtensionNames = database.previouslyRegisteredExtensionNames;
	for (NSString *extName in previouslyRegisteredExtensionNames)
	{
		if ([extName hasPrefix:Ext_CloudCore_Prefix])
		{
			NSString *suffix = [extName substringFromIndex:[Ext_CloudCore_Prefix length]];
			
			// Example suffix: z55tqmfr9kix1p1gntotqpwkacpuoyno_com.4th-a.storm4
			
			NSArray<NSString*> *components = [suffix componentsSeparatedByString:@"_"];
			
			if ((components.count == 2) && (components[0].length == 32)) // sanity checks
			{
				NSString *localUserID = components[0];
				NSString *appID = components[1];
				
				YapDatabaseCloudCore* ext = [self registerCloudExtensionForUser:localUserID app:appID];
				if(ext)
				{
					if (tuples == nil) {
						tuples = [NSMutableArray arrayWithCapacity:4];
					}
					
					YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, appID);
					[tuples addObject:tuple];
				}
			}
		}
	}
	
	// The 'previouslyRegisteredCloudExtTuples' variable MUST be non-nil at the completion of this method !
	//
	previouslyRegisteredCloudExtTuples = tuples ? [tuples copy] : [NSArray array];
}

- (void)setupActionManager
{
	DDLogAutoTrace();
	
	//
	// ACTION MANAGER
	//
	// The action manager is controlled by various model objects,
	// which instruct it to run various blocks at various times.
	//
	// For example, to refresh an icon from the web, or delete some cached object.
	
	YapActionScheduler scheduler = [self actionManagerScheduler];
	actionManager = [[YapDatabaseActionManager alloc] initWithConnection:nil options:nil scheduler:scheduler];
	
	// We don't want the action manager to start doing stuff until:
	// - all the extensions are up & ready
	//
	[actionManager suspend];
	
	NSString *const extName = Ext_ActionManager;
	[database asyncRegisterExtension: actionManager
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)yapDatabaseModified:(NSNotification *)ignored
{
	// Notify observers we're about to update the database connection
	
	[[NSNotificationCenter defaultCenter] postNotificationName: UIDatabaseConnectionWillUpdateNotification
	                                                    object: self];
	
	// Move uiDatabaseConnection to the latest commit.
	// Do so atomically, and fetch all the notifications for each commit we jump.
	
	NSArray *notifications = [uiDatabaseConnection beginLongLivedReadTransaction];
	
	// Notify observers that the uiDatabaseConnection was updated
	
	NSDictionary *userInfo = @{
	  kNotificationsKey : notifications,
	};

	[[NSNotificationCenter defaultCenter] postNotificationName: UIDatabaseConnectionDidUpdateNotification
	                                                    object: self
	                                                  userInfo: userInfo];
}

- (void)didRegisterAllExtensions
{
	DDLogAutoTrace();
	
	// The actionManager was inititalized in a suspended state.
	//
	[actionManager resume];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For use within:
 * - Ext_View_Flat
 */
+ (NSString *)groupForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	return [NSString stringWithFormat:@"%@|%@", localUserID, zAppID];
}

/**
 * For use within:
 * - Ext_View_Cloud_DirPrefix
 */
+ (NSString *)groupForLocalUserID:(NSString *)localUserID
                           region:(AWSRegion)region
                           bucket:(NSString *)bucket
                        appPrefix:(NSString *)appPrefix
                        dirPrefix:(NSString *)dirPrefix
{
	return [NSString stringWithFormat:@"%@|%@|%@|%@/%@",
		localUserID,
		[AWSRegions shortNameForRegion:region],
		bucket,
		appPrefix,
		dirPrefix];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Action Manager
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapActionScheduler)actionManagerScheduler
{
	YapActionItemBlock action_cachedResponse_uncache = [self action_cachedResponse_uncache];
	
	YapActionItemBlock action_localUser_registerPushToken = [self action_localUser_registerPushToken];
	YapActionItemBlock action_localUser_checkAccountDeleted = [self action_localUser_checkAccountDeleted];
	YapActionItemBlock action_localUser_createRecoveryConnection = [self action_localUser_createRecoveryConnection];
	
	YapActionItemBlock action_task = [self action_task];
	
	YapActionScheduler scheduler =
	^NSArray<YapActionItem*> *_Nullable (NSString *collection, NSString *key, id object){ @autoreleasepool {
		
		if ([object isKindOfClass:[ZDCCachedResponse class]])
		{
			__unsafe_unretained ZDCCachedResponse *obj = (ZDCCachedResponse *)object;
			
			YapActionItem *uncacheAction =
				[[YapActionItem alloc] initWithIdentifier: @"uncache"
				                                     date: obj.uncacheDate
				                             retryTimeout: 0
				                         requiresInternet: NO
				                                    block: action_cachedResponse_uncache];
			
			return @[ uncacheAction ];
		}
		else if ([object isKindOfClass:[ZDCLocalUser class]])
		{
			__unsafe_unretained ZDCLocalUser *localUser = (ZDCLocalUser *)object;
			
			YapActionItem *preferredIDAction = nil;
			YapActionItem *registerPushTokenAction = nil;
			YapActionItem *createRecoveryConnectionAction = nil;
			YapActionItem *checkAccountDeletedAction = nil;
			
			if (localUser.needsRegisterPushToken)
			{
				registerPushTokenAction =
				  [[YapActionItem alloc] initWithIdentifier: @"registerPushToken"
				                                       date: nil
				                               retryTimeout: 120 // when to assume failure, and re-invoke block
				                           requiresInternet: YES
				                                      block: action_localUser_registerPushToken];
			}
			
			if (localUser.needsCheckAccountDeleted)
			{
				checkAccountDeletedAction =
				  [[YapActionItem alloc] initWithIdentifier: @"checkAccountDeleted"
				                                       date: nil
				                               retryTimeout: 120 // when to assume failure, and re-invoke block
				                           requiresInternet: YES
				                                      block: action_localUser_checkAccountDeleted];
			}
			
			if (localUser.needsCreateRecoveryConnection)
			{
				createRecoveryConnectionAction =
				  [[YapActionItem alloc] initWithIdentifier: @"createRecoveryConnection"
				                                       date: nil
				                               retryTimeout: 120 // when to assume failure, and re-invoke block
				                           requiresInternet: YES
				                                      block: action_localUser_createRecoveryConnection];
			}
			
			if (preferredIDAction              ||
			    registerPushTokenAction        ||
			    createRecoveryConnectionAction ||
			    checkAccountDeletedAction       )
			{
				NSMutableArray *actionItems = [NSMutableArray arrayWithCapacity:3];
				
				if (preferredIDAction) {
					[actionItems addObject:preferredIDAction];
				}
				if (registerPushTokenAction) {
					[actionItems addObject:registerPushTokenAction];
				}
				if (createRecoveryConnectionAction) {
					[actionItems addObject:createRecoveryConnectionAction];
				}
				if (checkAccountDeletedAction) {
					[actionItems addObject:checkAccountDeletedAction];
				}
				
				return actionItems;
			}
			else
			{
				return nil;
			}
		}
		else if ([object isKindOfClass:[ZDCTask class]])
		{
			YapActionItem *actionItem = [(ZDCTask *)object actionItem:action_task];
			
			if (actionItem)
				return @[ actionItem ];
			else
				return nil;
		}
		
		return nil;
	}};
	
	return scheduler;
}

- (YapActionItemBlock)action_cachedResponse_uncache
{
	__weak typeof(self) weakSelf = self;
	
	YapActionItemBlock block = ^(NSString *collection, NSString *key, ZDCCachedResponse *item, id metadata){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		YapDatabaseConnection *rwConnection = strongSelf->owner.databaseManager.rwDatabaseConnection;
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			[transaction removeObjectForKey:key inCollection:collection];
		}];
	};
	
	return block;
}

- (YapActionItemBlock)action_localUser_registerPushToken
{
	__weak typeof(self) weakSelf = self;
	
	YapActionItemBlock block = ^(NSString *collection, NSString *key, ZDCLocalUser *localUser, id metadata){
		
		ZDCWebManager *webManager = nil;
		
		{ // Scoping: don't retain strongSelf accidentally within network completion callback
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			webManager = strongSelf->owner.webManager;
		}
		
		NSString *localUserID = key;
		NSString *pushToken = localUser.pushToken;
		
		DDLogBlue(@"Registering push token for user: %@, token :%@", localUserID, pushToken);
		
		[webManager registerPushTokenForLocalUser: localUser
		                          completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
		                          completionBlock:^(NSURLResponse *urlResponse, id responseObject, NSError *error)
		{
			NSInteger statusCode = [urlResponse httpStatusCode];
	
			if (!error && (statusCode == 200))
			{
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf == nil) return;
				
				YapDatabaseConnection *rwConnection = strongSelf->owner.databaseManager.rwDatabaseConnection;
				[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
					ZDCLocalUser *updatedUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
					updatedUser = [updatedUser copy];
					
					if (updatedUser && [updatedUser.pushToken isEqual:pushToken])
					{
						updatedUser.needsRegisterPushToken = NO;
						updatedUser.lastPushTokenRegistration = [NSDate date];
				
						[transaction setObject:updatedUser forKey:updatedUser.uuid inCollection:kZDCCollection_Users];
					}
				}];
			}
			else
			{
				// YapActionManager will automatically try again in the future.
		
				if (!error) {
					DDLogRed(@"registerPushToken failed with status code: %d", (int)statusCode);
				}
			}
		}];
	};
	
	return block;
}

- (YapActionItemBlock)action_localUser_checkAccountDeleted
{
	__weak typeof(self) weakSelf = self;
	
	YapActionItemBlock block = ^(NSString *collection, NSString *key, ZDCLocalUser *localUser, id metadata){
		
		ZDCWebManager *webManager = nil;
		
		{ // Scoping: don't retain strongSelf accidentally within network completion callback
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			webManager = strongSelf->owner.webManager;
		}
		
		NSString *localUserID = key;
		
		[webManager fetchUserExists: localUserID
		            completionQueue: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)
		            completionBlock:^(BOOL exists, NSError *error)
		{
			if (!error)
			{
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf == nil) return;
				
				YapDatabaseConnection *rwConnection = strongSelf->owner.databaseManager.rwDatabaseConnection;
				[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
					ZDCLocalUser *updatedUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
					updatedUser = [updatedUser copy];
	
					updatedUser.needsCheckAccountDeleted = NO;
	
					if (!exists)
					{
						updatedUser.accountDeleted = YES;
					}
					
					[transaction setObject:updatedUser forKey:updatedUser.uuid inCollection:kZDCCollection_Users];
				}];
			}
			else
			{
				// YapActionManager will automatically try again in the future.
			}
		}];
	};
	
	return block;
}

- (YapActionItemBlock)action_localUser_createRecoveryConnection
{
	__weak typeof(self) weakSelf = self;
	
	YapActionItemBlock block =
	  ^(NSString *collection, NSString *key, ZDCLocalUser *localUser, id metadata)
	{
		ZDCLocalUserManager *localUserManager = nil;
		
		{ // Scoping: don't retain strongSelf accidentally within network completion callback
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			localUserManager = strongSelf->owner.localUserManager;
		}
		
		[localUserManager createRecoveryConnectionForLocalUser:localUser completionQueue:nil completionBlock:nil];
	};
	
	return block;
}

- (YapActionItemBlock)action_task
{
	__weak typeof(self) weakSelf = self;
	
	YapActionItemBlock block =
	  ^(NSString *collection, NSString *key, ZDCTask *task, id metadata)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			[task performTask:strongSelf->owner];
		}
	};
	
	return block;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)cloudExtNameForUser:(NSString *)localUserID
{
	return [self cloudExtNameForUser:localUserID app:owner.zAppID];
}

/**
 * A separate ZDCCloud instance must be registered for every <localUserID, appID> tuple.
**/
- (NSString *)cloudExtNameForUser:(NSString *)localUserID app:(NSString *)appID
{
	// Example: "ZeroDark:cloud_z55tqmfr9kix1p1gntotqpwkacpuoyno_com.4th-a.storm4"
	// 
	return [NSString stringWithFormat:@"%@%@_%@",
	          Ext_CloudCore_Prefix, (localUserID ?: @"?"), (appID ?: @"?")];
}

/**
 * See header file for description.
 */
- (NSArray<ZDCCloud *> *)cloudExtsForUser:(NSString *)inLocalUserID
{
	NSMutableArray<ZDCCloud *> *cloudExts = [NSMutableArray array];
	
	YAPUnfairLockLock(&spinlock);
	@try {
		
		[registeredCloudDict enumerateKeysAndObjectsUsingBlock:
		  ^(YapCollectionKey *tuple, ZDCCloud *ext, BOOL *stop)
		{
			if ([inLocalUserID isEqualToString:tuple.collection])
			{
				[cloudExts addObject:ext];
			}
		}];
	}
	@finally {
		YAPUnfairLockUnlock(&spinlock);
	}
	
	return cloudExts;
}

/**
 * See header file for description.
 */
- (nullable ZDCCloud *)cloudExtForUser:(NSString *)localUserID
{
	return [self cloudExtForUser:localUserID app:owner.zAppID];
}

/**
 * See header file for description.
 */
- (nullable ZDCCloud *)cloudExtForUser:(NSString *)localUserID app:(NSString *)appID
{
	ZDCCloud *result = nil;
	if (localUserID && appID)
	{
		// Important !!
		//
		// We used to simply do this:
		//
	//	NSString *extName = [self cloudExtNameForUser:localUserID app:appID];
	//	return (ZDCCloud *)[database registeredExtension:extName];
		//
		// But there's a subtle bug that exists here.
		// We always register the extension asynchronously.
		// And this means the extension may not be available via [database registeredExtension:] yet.
		//
		// Thus we switched to the solution below.
		// This makes things just a little bit easier for the user (less edge-cases to worry about).
		
		YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, appID);
		
		YAPUnfairLockLock(&spinlock);
		@try {
			result = registeredCloudDict[tuple];
		}
		@finally {
			YAPUnfairLockUnlock(&spinlock);
		}
	}
	
	return result;
}

/**
 * A separate YapDatabaseCloudCore instance MUST be registered for every account.
 *
 * When the app launches, YapDatabaseCloudCore instances are automatically registered for all existing accounts.
 * If a new account is created during runtime, then this method MUST be invoked to create the proper instance.
**/
- (ZDCCloud *)registerCloudExtensionForUser:(NSString *)inLocalUserID app:(NSString *)inAppID
{
	DDLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	NSString *appID = [inAppID copy];             // mutable string protection
	
	__block ZDCLocalUser *localUser = nil;
	[self.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {

		ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		if (user.isLocal) {
			localUser = (ZDCLocalUser *)user;
		}
	}];

	if (!localUser) {
		return nil;
	}
	
	ZDCCloud *ext =
	  [[ZDCCloud alloc] initWithLocalUserID: localUserID
	                                 zAppID: appID];
	
	id <YapDatabaseCloudCorePipelineDelegate> pipelineDelegate =
	  (id <YapDatabaseCloudCorePipelineDelegate>)owner;
	
	YapDatabaseCloudCorePipeline *pipeline =
	  [[YapDatabaseCloudCorePipeline alloc] initWithName: YapDatabaseCloudCoreDefaultPipelineName
	                                           algorithm: YDBCloudCorePipelineAlgorithm_FlatGraph
	                                            delegate: pipelineDelegate];
	
	[ext registerPipeline:pipeline];
	
	// We always start the extension suspended !
	// ZDCLocalUserManager is in charge of resuming the extension (at the appropriate time).
	//
	[ext suspend];
	
#if TARGET_EXTENSION
	[ext suspendWithCount:1000]; // Never run
#endif
	
#if TARGET_OS_IPHONE
	if (previouslyRegisteredCloudExtTuples == nil)
	{
		// CloudCore extensions that are re-registered during database setup get a few extra suspensions.
		
		// The ZDCSessionManager handles resuming background uploads/downloads.
		// We don't want to start the push queue until after its resumed its list of active uploads.
		// So we let it do its thing, and it will invoke [ext resume] when it's done.
		//
		// @see [ZDCSessionManager restoreTasksInBackgroundSessions]
		//
		[ext suspend];
		
		// This method is getting called before the PushManager has been initialized.
		// So we let ZeroDarkCloud finish its initialization process,
		// and then it inovkes [ext resume] when it's done.
		//
		// @see [ZeroDarkCloud resumePushQueues]
		//
		[ext suspend];
	}
#endif
	
	// Debugging ?
	// Want to keep the queue suspended so you can inspect it ?
	// Uncomment these lines:
	//
//	[ext suspend];
//	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//		[ext resume];
//	});
	
	NSString *extName = [self cloudExtNameForUser:localUserID app:appID];
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready)
		{
			DDLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
	
	ZDCCloud *result = nil;
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, appID);
	YAPUnfairLockLock(&spinlock);
	@try {
		
		result = registeredCloudDict[tuple];
		if (result == nil)
		{
			result = ext;
			registeredCloudDict[tuple] = ext;
		}
	}
	@finally {
		YAPUnfairLockUnlock(&spinlock);
	}
	
	return result;
}

/**
 * A separate ZDCCloud instance MUST be registered for every account.
 *
 * If an account is deleted (not suspended) during runtime,
 * then this method MUST be invoked to delete the instance.
 */
- (void)unregisterCloudExtensionForUser:(NSString *)localUserID app:(NSString *)appID
{
	NSString *extName = [self cloudExtNameForUser:localUserID app:appID];
	
	[database asyncUnregisterExtensionWithName:extName completionBlock:^{
		
		DDLogVerbose(@"Unregistered extension: %@", extName);
	}];
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, appID);
	YAPUnfairLockLock(&spinlock);
	@try {
		
		registeredCloudDict[tuple] = nil;
	}
	@finally {
		YAPUnfairLockUnlock(&spinlock);
	}
}

/**
 * Exposes the `registeredCloudDict` snapshot.
 * Exported via: "ZDCDatabaseManagerPrivate.h"
 */
- (NSArray<YapCollectionKey *> *)currentlyRegisteredTuples
{
	__block NSArray<YapCollectionKey*> *allTuples = nil;
	
	YAPUnfairLockLock(&spinlock);
	@try {
		
		allTuples = [registeredCloudDict allKeys];
	}
	@finally {
		YAPUnfairLockUnlock(&spinlock);
	}
	
	return allTuples;
}

/**
 * Exposes the `registeredCloudDict` snapshot.
 * Exported via: "ZDCDatabaseManagerPrivate.h"
 */
- (NSArray<NSString *> *)currentlyRegisteredAppIDsForUser:(NSString *)inLocalUserID
{
	NSMutableArray<NSString*> *appIDs = [NSMutableArray array];
	
	YAPUnfairLockLock(&spinlock);
	@try {
		
		for (YapCollectionKey *tuple in registeredCloudDict)
		{
			NSString *localUserID = tuple.collection;
			NSString *appID       = tuple.key;
			
			if ([inLocalUserID isEqualToString:localUserID])
			{
				[appIDs addObject:appID];
			}
		}
	}
	@finally {
		YAPUnfairLockUnlock(&spinlock);
	}
	
	return appIDs;
}

/**
 * Exposes the `previouslyRegisteredCloudExtTuples` snapshot.
 * Exported via: "ZDCDatabaseManagerPrivate.h"
 */
- (NSArray<YapCollectionKey *> *)previouslyRegisteredTuples
{
	return previouslyRegisteredCloudExtTuples;
}

/**
 * Exposes the `previouslyRegisteredCloudExtTuples` snapshot.
 * Exported via: "ZDCDatabaseManagerPrivate.h"
 */
- (NSSet<NSString *> *)previouslyRegisteredLocalUserIDs
{
	NSUInteger capacity = previouslyRegisteredCloudExtTuples.count;
	NSMutableSet<NSString *> *localUserIDs = [NSMutableSet setWithCapacity:capacity];
	
	for (YapCollectionKey *tuple in previouslyRegisteredCloudExtTuples)
	{
		NSString *localUserID = tuple.collection;
		
		[localUserIDs addObject:localUserID];
	}
	
	return localUserIDs;
}

/**
 * Exposes the `previouslyRegisteredCloudExtTuples` snapshot.
 * Exported via: "ZDCDatabaseManagerPrivate.h"
 */
- (NSArray<NSString *> *)previouslyRegisteredAppIDsForUser:(NSString *)localUserID
{
	NSMutableArray<NSString *> *appIDs = [NSMutableArray arrayWithCapacity:1];
	
	for (YapCollectionKey *tuple in previouslyRegisteredCloudExtTuples)
	{
		if ([localUserID isEqualToString:tuple.collection])
		{
			[appIDs addObject:tuple.key];
		}
	}
	
	return appIDs;
}

@end
