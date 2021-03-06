/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

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
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

NSString *const UIDatabaseConnectionWillUpdateNotification = @"UIDatabaseConnectionWillUpdateNotification";
NSString *const UIDatabaseConnectionDidUpdateNotification  = @"UIDatabaseConnectionDidUpdateNotification";
NSString *const kNotificationsKey = @"notifications";

NSString *const Ext_Relationship              = @"ZeroDark:graph";
NSString *const Ext_Index_Nodes               = @"ZeroDark:idx_nodes";
NSString *const Ext_Index_Users               = @"ZeroDark:idx_users";
NSString *const Ext_View_LocalUsers           = @"ZeroDark:localUsers";
NSString *const Ext_View_Treesystem_Name      = @"ZeroDark:fsName";
NSString *const Ext_View_Treesystem_CloudName = @"ZeroDark:fsCloudName";
NSString *const Ext_View_Flat                 = @"ZeroDark:flat";
NSString *const Ext_View_CloudNode_DirPrefix  = @"ZeroDark:fsCloudDirPrefix";
NSString *const Ext_View_SplitKeys            = @"ZeroDark:splitKeys";
NSString *const Ext_View_SplitKeys_Date  		 = @"ZeroDark:splitKeys.createDate";
NSString *const Ext_CloudCore_Prefix          = @"ZeroDark:cloud_";
NSString *const Ext_ActionManager             = @"ZeroDark:action";



NSString *const Index_Nodes_Column_CloudID    = @"cloudID";
NSString *const Index_Nodes_Column_DirPrefix  = @"dirPrefix";
NSString *const Index_Nodes_Column_PointeeID  = @"pointeeID";

NSString *const Index_Users_Column_RandomUUID = @"random_uuid";


@implementation ZDCDatabaseManager {
	
	__weak ZeroDarkCloud *zdc;
	dispatch_queue_t serialQueue;
	
	YapDatabaseConnection *_internal_roConnection;
	YapDatabaseConnection *_internal_rwConnection;
	YapDatabaseConnection *_internal_decryptConnection;
	
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
		zdc = inOwner;
		
		serialQueue = dispatch_queue_create("ZDCDatabaseManager", DISPATCH_QUEUE_SERIAL);
		
		spinlock = YAP_UNFAIR_LOCK_INIT;
		registeredCloudDict = [[NSMutableDictionary alloc] initWithCapacity:4];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
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
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For internal use only (by the ZeroDarkCloud Framework).
 */
- (YapDatabaseConnection *)internal_roConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_internal_roConnection == nil)
		{
			_internal_roConnection = [database newConnection];
			_internal_roConnection.name = @"ZeroDarkCloud.Internal.roConnection";
			
		#if DEBUG
			_internal_roConnection.permittedTransactions = YDB_AnyReadTransaction;
		#endif
		}
		
		connection = _internal_roConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

/**
 * For internal use only (by the ZeroDarkCloud Framework).
 */
- (YapDatabaseConnection *)internal_rwConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_internal_rwConnection == nil)
		{
			_internal_rwConnection = [database newConnection];
			_internal_rwConnection.name = @"ZeroDarkCloud.Internal.rwConnection";
			
		#if DEBUG
			_internal_rwConnection.permittedTransactions = YDB_AnyReadWriteTransaction;
		#endif
		}
		
		connection = _internal_rwConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

/**
 * For internal use only (by the ZeroDarkCloud Framework).
 */
- (YapDatabaseConnection *)internal_decryptConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_internal_decryptConnection == nil)
		{
			_internal_decryptConnection = [database newConnection];
			_internal_decryptConnection.name = @"ZeroDarkCloud.Internal.decryptConnection";
			
		#if DEBUG
			_internal_decryptConnection.permittedTransactions = YDB_AnyReadTransaction;
		#endif
		}
		
		connection = _internal_decryptConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The serializer block converts objects into encrypted data blobs.
 *
 * (All of the objects used by the ZeroDarkCloud framework support the NSCoding protocol.)
 */
- (YapDatabaseSerializer)databaseSerializer
{
	YapDatabaseSerializer serializer = ^(NSString *collection, NSString *key, id object){
		
		return [NSKeyedArchiver archivedDataWithRootObject:object];
	};
	
	return serializer;
}

/**
 * The deserializer block converts encrypted data blobs back into objects.
 *
 * (All of the objects used by the ZeroDarkCloud framework support the NSCoding protocol.)
 */
- (YapDatabaseDeserializer)databaseDeserializer
{
	YapDatabaseDeserializer deserializer = ^(NSString *collection, NSString *key, NSData *data){
		
		id object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		if ([object isKindOfClass:[ZDCObject class]])
		{
			[(ZDCObject *)object makeImmutable];
		}
		
		return object;
	};
	
	return deserializer;
}

- (YapDatabasePreSanitizer)databasePreSanitizer
{
	YapDatabasePreSanitizer preSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[ZDCObject class]])
		{
			[(ZDCObject *)object makeImmutable];
		}
		
		return object;
	};
	
	return preSanitizer;
}

- (YapDatabasePostSanitizer)databasePostSanitizer
{
	YapDatabasePostSanitizer postSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[ZDCObject class]])
		{
			[(ZDCObject *)object clearChangeTracking];
		}
	};
	
	return postSanitizer;
}

- (BOOL)setupDatabase:(ZDCDatabaseConfig *)config
{
	ZDCLogAutoTrace();
	
	// Create the database
	
	[NSKeyedUnarchiver setClass:[ZDCTrunkNode class] forClassName:@"ZDCContainerNode"];
	
	NSURL *databaseURL = zdc.databasePath;
	ZDCLogVerbose(@"databaseURL = %@", databaseURL);
	
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
	
	database = [[YapDatabase alloc] initWithURL:databaseURL options:options];
	if (database == nil) {
		return NO;
	}
	
	YapDatabaseSerializer serializer = [self databaseSerializer];
	YapDatabaseDeserializer deserializer = [self databaseDeserializer];
	YapDatabasePreSanitizer preSanitizer = [self databasePreSanitizer];
	YapDatabasePostSanitizer postSanitizer = [self databasePostSanitizer];
	
	NSArray<NSString*> *collections = @[
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
	];
	
	[database registerSerializer: serializer
	                deserializer: deserializer
	                preSanitizer: preSanitizer
	               postSanitizer: postSanitizer
	              forCollections: collections];
	
	for (NSString *collection in collections)
	{
		[database setObjectPolicy:YapDatabasePolicyShare forCollection:collection];
	}
	
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
	[self setupView_Treesystem_Name];
	[self setupView_Treesystem_CloudName];
	[self setupView_Flat];
	[self setupView_CloudDirPrefix];
	[self setupView_SplitKeys];
	[self setupView_SplitKeys_Date];
	[self setupCloudExtensions];
	[self setupActionManager];

	if (config.configHook)
	{
		@try {
			config.configHook(database);
			
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
	ZDCLogAutoTrace();
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupIndex_Nodes
{
	ZDCLogAutoTrace();
	
	//
	// SECONDARY INDEX - NODES
	//
	// Indexes the following:
	// - ZDCNode.cloudID
	// - ZDCNode.dirPrefix
	// - ZDCNode.pointeeID
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:Index_Nodes_Column_CloudID   withType:YapDatabaseSecondaryIndexTypeText];
	[setup addColumn:Index_Nodes_Column_DirPrefix withType:YapDatabaseSecondaryIndexTypeText];
	[setup addColumn:Index_Nodes_Column_PointeeID withType:YapDatabaseSecondaryIndexTypeText];
	
	YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict,
	      NSString *collection, NSString *key, id object)
	{
		NSAssert([object isKindOfClass:[ZDCNode class]], @"Invalid class detected !");
		__unsafe_unretained ZDCNode *node = (ZDCNode *)object;
		
		dict[Index_Nodes_Column_CloudID] = node.cloudID;
		dict[Index_Nodes_Column_DirPrefix] = node.dirPrefix;
		dict[Index_Nodes_Column_PointeeID] = node.pointeeID;
	}];
	
	NSString *const versionTag = @"2019-07-17"; // <-- change me if you modify handler block
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupIndex_Users
{
	ZDCLogAutoTrace();
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}


- (void)setupView_LocalUsers
{
	ZDCLogAutoTrace();
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_Treesystem_Name
{
	ZDCLogAutoTrace();
	
	//
	// VIEW - TREESYSTEM (ZDCNode's sorted by cleartext name)
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
		
		// Regular nodes have a parentID.
		// Graft nodes have a special parentID: "<localUserID>|<treeID>|graft".
		// Detached nodes have a special parentID: "<localUserID>|<treeID>|detached".
		// Container nodes don't have a parentID.
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
	
	NSString *const extName = Ext_View_Treesystem_Name;
	[database asyncRegisterExtension:ext
	                        withName:extName
	                 completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_Treesystem_CloudName
{
	ZDCLogAutoTrace();
	
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
		
		// Regular nodes have a parentID.
		// Graft nodes have a special parentID: "<localUserID>|<treeID>|graft".
		// Detached nodes have a special parentID: "<localUserID>|<treeID>|detached".
		// Container nodes don't have a parentID.
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
	
	NSString *const extName = Ext_View_Treesystem_CloudName;
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_Flat
{
	ZDCLogAutoTrace();
	
	//
	// VIEW - FLAT
	//
	// Sorts all files & directories into a flat system.
	//
	// group(localUserID, treeID) -> values(every single node)
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
		
		if (node.parentID == nil) return nil; // exclude trunk nodes
		
		ZDCTrunkNode *trunkNode =
		  [[ZDCNodeManager sharedInstance] trunkNodeForNode:node transaction:transaction];
		
		if (trunkNode == nil) return nil;
		
		return [ZDCDatabaseManager groupForLocalUserID:node.localUserID treeID:trunkNode.treeID];
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_CloudDirPrefix
{
	ZDCLogAutoTrace();
	
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
		                                        treeID: cloudPath.treeID
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
	
	NSString *const extName = Ext_View_CloudNode_DirPrefix;
	[database asyncRegisterExtension:ext
	                        withName:extName
	                 completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready) {
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_SplitKeys
{
	ZDCLogAutoTrace();
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupView_SplitKeys_Date
{
	ZDCLogAutoTrace();
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
}

- (void)setupCloudExtensions
{
	ZDCLogAutoTrace();
	
	//
	// CLOUD CORE
	//
	// The cloud core extension manages the upload queue for local users.
	//
	// We register 1 shared ZDCCloud instance (with localUserID="*" and treeID="*").
	// This instance is only used for uploading user avatars.
	//
	// And then we automatically re-register any ZDCCloud instances that were registered from last app launch.
	
	NSMutableArray<YapCollectionKey *> *tuples = [NSMutableArray arrayWithCapacity:4];
	BOOL foundAvatarExt = NO;
	
	NSArray<NSString *> *previouslyRegisteredExtensionNames = database.previouslyRegisteredExtensionNames;
	for (NSString *extName in previouslyRegisteredExtensionNames)
	{
		if ([extName hasPrefix:Ext_CloudCore_Prefix])
		{
			NSString *suffix = [extName substringFromIndex:[Ext_CloudCore_Prefix length]];
			
			// Example suffix: z55tqmfr9kix1p1gntotqpwkacpuoyno_com.4th-a.storm4
			
			NSArray<NSString*> *components = [suffix componentsSeparatedByString:@"_"];
			
			if (components.count == 2)
			{
				NSString *localUserID = components[0];
				NSString *treeID = components[1];
				
				[self registerCloudExtensionForUserID:localUserID treeID:treeID];
				[tuples addObject:YapCollectionKeyCreate(localUserID, treeID)];
				
				if ([localUserID isEqualToString:@"*"] && [treeID isEqualToString:@"*"])
				{
					foundAvatarExt = YES;
				}
			}
		}
	}
	
	if (!foundAvatarExt)
	{
		[self registerCloudExtensionForUserID:@"*" treeID:@"*"];
		[tuples addObject:YapCollectionKeyCreate(@"*", @"*")];
	}
	
	// The 'previouslyRegisteredCloudExtTuples' variable MUST be non-nil at the completion of this method !
	//
	previouslyRegisteredCloudExtTuples = tuples ? [tuples copy] : [NSArray array];
}

- (void)setupActionManager
{
	ZDCLogAutoTrace();
	
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
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
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
	ZDCLogAutoTrace();
	
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
+ (NSString *)groupForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	return [NSString stringWithFormat:@"%@|%@", localUserID, treeID];
}

/**
 * For use within:
 * - Ext_View_CloudNode_DirPrefix
 */
+ (NSString *)groupForLocalUserID:(NSString *)localUserID
                           region:(AWSRegion)region
                           bucket:(NSString *)bucket
                           treeID:(NSString *)treeID
                        dirPrefix:(NSString *)dirPrefix
{
	return [NSString stringWithFormat:@"%@|%@|%@|%@/%@",
		localUserID,
		[AWSRegions shortNameForRegion:region],
		bucket,
		treeID,
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
		
		YapDatabaseConnection *rwConnection = strongSelf->zdc.databaseManager.rwDatabaseConnection;
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
		
		ZDCRestManager *restManager = nil;
		
		{ // Scoping: don't retain strongSelf accidentally within network completion callback
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			restManager = strongSelf->zdc.restManager;
		}
		
		NSString *localUserID = key;
		NSString *pushToken = localUser.pushToken;
		
		ZDCLogVerbose(@"Registering push token for user: %@, token :%@", localUserID, pushToken);
		
		[restManager registerPushTokenForLocalUser: localUser
		                           completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
		                           completionBlock:^(NSURLResponse *urlResponse, id responseObject, NSError *error)
		{
			NSInteger statusCode = [urlResponse httpStatusCode];
	
			if (!error && (statusCode == 200))
			{
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf == nil) return;
				
				YapDatabaseConnection *rwConnection = strongSelf->rwDatabaseConnection;
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
					ZDCLogInfo(@"registerPushToken failed with status code: %d", (int)statusCode);
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
		
		ZDCRestManager *restManager = nil;
		
		{ // Scoping: don't retain strongSelf accidentally within network completion callback
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			restManager = strongSelf->zdc.restManager;
		}
		
		NSString *localUserID = key;
		
		[restManager fetchUserExists: localUserID
		             completionQueue: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)
		             completionBlock:^(BOOL exists, NSError *error)
		{
			if (error)
			{
				// YapActionManager will automatically try again in the future.
				return;
			}
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			YapDatabaseConnection *rwConnection = strongSelf->rwDatabaseConnection;
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
			
			localUserManager = strongSelf->zdc.localUserManager;
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
			[task performTask:strongSelf->zdc];
		}
	};
	
	return block;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)cloudExtNameForUserID:(NSString *)localUserID
{
	return [self cloudExtNameForUserID:localUserID treeID:zdc.primaryTreeID];
}

/**
 * A separate ZDCCloud instance must be registered for every <localUserID, appID> tuple.
**/
- (NSString *)cloudExtNameForUserID:(NSString *)localUserID treeID:(NSString *)appID
{
	// Example: "ZeroDark:cloud_z55tqmfr9kix1p1gntotqpwkacpuoyno_com.4th-a.storm4"
	// 
	return [NSString stringWithFormat:@"%@%@_%@",
	          Ext_CloudCore_Prefix, (localUserID ?: @"?"), (appID ?: @"?")];
}

/**
 * See header file for description.
 */
- (NSArray<ZDCCloud *> *)cloudExtsForUserID:(NSString *)inLocalUserID
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
- (nullable ZDCCloud *)cloudExtForUserID:(NSString *)localUserID
{
	return [self cloudExtForUserID:localUserID treeID:zdc.primaryTreeID];
}

/**
 * See header file for description.
 */
- (nullable ZDCCloud *)cloudExtForUserID:(NSString *)localUserID treeID:(NSString *)appID
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
- (ZDCCloud *)registerCloudExtensionForUserID:(NSString *)inLocalUserID treeID:(NSString *)inTreeID
{
	ZDCLogAutoTrace();
	
	NSString *localUserID = [inLocalUserID copy]; // mutable string protection
	NSString *treeID = [inTreeID copy];           // mutable string protection
	
	BOOL isAvatarExt = [localUserID isEqualToString:@"*"];
	if (!isAvatarExt)
	{
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
	}
	
	ZDCCloud *ext =
	  [[ZDCCloud alloc] initWithLocalUserID: localUserID
	                                 treeID: treeID];
	
	id <YapDatabaseCloudCorePipelineDelegate> pipelineDelegate =
	  (id <YapDatabaseCloudCorePipelineDelegate>)zdc;
	
	YapDatabaseCloudCorePipeline *pipeline =
	  [[YapDatabaseCloudCorePipeline alloc] initWithName: YapDatabaseCloudCoreDefaultPipelineName
	                                           algorithm: YDBCloudCorePipelineAlgorithm_FlatGraph
	                                            delegate: pipelineDelegate];
	
	[ext registerPipeline:pipeline];
	
	// We always start the extension suspended.
	// Every call to suspend must be matched with a call to resume.
	
	// ZDCSyncManager will resume the extension when:
	//
	// - it's completed a pull (to ensure we've processed cloud changes)
	// - it knows we have network connectivity
	//
	[ext suspend];
	
#if TARGET_OS_IPHONE
	if (previouslyRegisteredCloudExtTuples == nil)
	{
		// CloudCore extensions that are re-registered during database setup get a few extra suspensions.
		
		// This method is getting called before the PushManager has been initialized.
		// So we let ZeroDarkCloud finish its initialization process,
		// and then it inovkes [ext resume] when it's done.
		//
		// @see [ZeroDarkCloud unlockOrCreateDatabase:error:]
		//
		[ext suspend];
		
		// The ZDCSessionManager handles resuming background uploads/downloads.
		// We don't want to start the push queue until after its resumed its list of active uploads.
		// So we let it do its thing, and it will invoke [ext resume] when it's done.
		//
		// @see [ZDCSessionManager restoreTasksInBackgroundSessions]
		//
		[ext suspend];
	}
#endif
	
#if TARGET_EXTENSION
	[ext suspendWithCount:1000]; // Never run
#endif
	
	// Debugging ?
	// Want to keep the queue suspended so you can inspect it ?
	// Uncomment these lines:
	//
//	[ext suspend];
//	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//		[ext resume];
//	});
	
	NSString *extName = [self cloudExtNameForUserID:localUserID treeID:treeID];
	[database asyncRegisterExtension: ext
	                        withName: extName
	                 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                 completionBlock:^(BOOL ready)
	{
		if (!ready)
		{
			ZDCLogError(@"Error registering \"%@\" !!!", extName);
		}
	}];
	
	ZDCCloud *result = nil;
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, treeID);
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
- (void)unregisterCloudExtensionForUserID:(NSString *)localUserID treeID:(NSString *)treeID
{
	NSString *extName = [self cloudExtNameForUserID:localUserID treeID:treeID];
	
	[database asyncUnregisterExtensionWithName:extName completionBlock:^{
		
		ZDCLogVerbose(@"Unregistered extension: %@", extName);
	}];
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, treeID);
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
- (NSArray<NSString *> *)currentlyRegisteredTreeIDsForUser:(NSString *)inLocalUserID
{
	NSMutableArray<NSString*> *treeIDs = [NSMutableArray array];
	
	YAPUnfairLockLock(&spinlock);
	@try {
		
		for (YapCollectionKey *tuple in registeredCloudDict)
		{
			NSString *localUserID = tuple.collection;
			NSString *treeID      = tuple.key;
			
			if ([inLocalUserID isEqualToString:localUserID])
			{
				[treeIDs addObject:treeID];
			}
		}
	}
	@finally {
		YAPUnfairLockUnlock(&spinlock);
	}
	
	return treeIDs;
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
		if (![localUserID isEqualToString:@"*"])
		{
			[localUserIDs addObject:localUserID];
		}
	}
	
	return localUserIDs;
}

/**
 * Exposes the `previouslyRegisteredCloudExtTuples` snapshot.
 * Exported via: "ZDCDatabaseManagerPrivate.h"
 */
- (NSArray<NSString *> *)previouslyRegisteredTreeIDsForUser:(NSString *)localUserID
{
	NSMutableArray<NSString *> *treeIDs = [NSMutableArray arrayWithCapacity:1];
	
	for (YapCollectionKey *tuple in previouslyRegisteredCloudExtTuples)
	{
		if ([localUserID isEqualToString:tuple.collection])
		{
			[treeIDs addObject:tuple.key];
		}
	}
	
	return treeIDs;
}

@end
