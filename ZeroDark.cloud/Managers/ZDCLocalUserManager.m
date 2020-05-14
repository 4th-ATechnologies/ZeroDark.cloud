/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCLocalUserManagerPrivate.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "AWSPayload.h"
#import "BIP39Mnemonic.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCCloudNodeManager.h"
#import "ZDCDatabaseManagerPrivate.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLogging.h"
#import "ZDCPublicKeyPrivate.h"
#import "ZDCSymmetricKeyPrivate.h"
#import "ZDCTrunkNodePrivate.h"
#import "ZDCUserPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSData+AWSUtilities.h"
#import "NSData+S4.h"
#import "NSDate+ZeroDark.h"
#import "NSError+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelInfo;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

static NSString *const k_userID      = @"userID";
static NSString *const k_displayName = @"displayName";

@implementation ZDCLocalUserManager
{
	__weak ZeroDarkCloud *zdc;
	
	Auth0ProviderManager *providerManager;

	dispatch_queue_t queue;
	void *IsOnQueueKey;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.localUserManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		providerManager = zdc.auth0ProviderManager;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Single User Mode
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (nullable ZDCLocalUser *)anyLocalUser:(YapDatabaseReadTransaction *)transaction
{
	__block ZDCLocalUser *result = nil;
	[self enumerateLocalUsersWithTransaction: transaction
	                              usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
	{
		result = localUser;
		*stop = YES;
	}];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark List & Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (NSArray<NSString *> *)allLocalUserIDs:(YapDatabaseReadTransaction *)transaction
{
	NSMutableArray<NSString *> *results = nil;
	
	YapDatabaseViewTransaction *localUsersView = [transaction ext:Ext_View_LocalUsers];
	if (localUsersView) {
		results = [NSMutableArray arrayWithCapacity:[localUsersView numberOfItemsInGroup:@""]];
	}
	else {
		results = [NSMutableArray array];
	}
	
	[self enumerateLocalUserIDsWithTransaction:transaction usingBlock:^(NSString *localUserID, BOOL *stop) {
		
		[results addObject:localUserID];
	}];
	
	return results;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (NSArray<ZDCLocalUser *> *)allLocalUsers:(YapDatabaseReadTransaction *)transaction
{
	NSMutableArray<ZDCLocalUser *> *results = nil;
	
	YapDatabaseViewTransaction *localUsersView = [transaction ext:Ext_View_LocalUsers];
	if (localUsersView) {
		results = [NSMutableArray arrayWithCapacity:[localUsersView numberOfItemsInGroup:@""]];
	}
	else {
		results = [NSMutableArray array];
	}
	
	[self enumerateLocalUsersWithTransaction:transaction usingBlock:^(ZDCLocalUser *localUser, BOOL *stop) {
		
		[results addObject:localUser];
	}];
	
	return results;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (void)enumerateLocalUserIDsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                  usingBlock:(void (^)(NSString *localUserID, BOOL *stop))enumBlock
{
	if (enumBlock == nil) return;
	
	YapDatabaseViewTransaction *localUsersView = [transaction ext:Ext_View_LocalUsers];
	if (localUsersView)
	{
		[localUsersView enumerateKeysInGroup:@"" usingBlock:
		    ^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
		{
			enumBlock(key, stop);
		}];
	}
	else
	{
		// Backup Plan (defensive programming)
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Users usingBlock:
		    ^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCUser *user = (ZDCUser *)object;
			if (user.isLocal)
			{
				enumBlock(user.uuid, stop);
			}
		}];
	}
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (void)enumerateLocalUsersWithTransaction:(YapDatabaseReadTransaction *)transaction
                                usingBlock:(void (^)(ZDCLocalUser *localUser, BOOL *stop))enumBlock
{
	if (enumBlock == nil) return;
	
	YapDatabaseViewTransaction *localUsersView = [transaction ext:Ext_View_LocalUsers];
	if (localUsersView)
	{
		[localUsersView enumerateKeysAndObjectsInGroup:@"" usingBlock:
		    ^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
			enumBlock((ZDCLocalUser *)object, stop);
		}];
	}
	else
	{
		// Backup Plan (defensive programming)
		
		[transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Users usingBlock:
		    ^(NSString *key, id object, BOOL *stop)
		{
			__unsafe_unretained ZDCUser *user = (ZDCUser *)object;
			if (user.isLocal)
			{
				enumBlock((ZDCLocalUser *)user, stop);
			}
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (void)deleteLocalUser:(NSString *)localUserID
            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
	if (!user || !user.isLocal)
	{
		return;
	}
	
	ZDCLocalUser *localUser = (ZDCLocalUser *)user;
	
	// Step 1 of 7:
	//
	// Convert the localUser to a remote user.
	//
	// Note: This is no longer required, and we may wish to remove this step.
        
	ZDCUser *remoteUser = [[ZDCUser alloc] initWithUUID:localUser.uuid];
	[localUser copyTo:remoteUser];
	
	ZDCPublicKey *privateKey =
	  [transaction objectForKey: localUser.publicKeyID
	               inCollection: kZDCCollection_PublicKeys];
	
	ZDCPublicKey *pubKey = [[ZDCPublicKey alloc] init];
	[privateKey copyToPublicKey:pubKey];
	
	remoteUser.publicKeyID = pubKey.uuid;
	
	[transaction setObject: pubKey
	                forKey: pubKey.uuid
	          inCollection: kZDCCollection_PublicKeys];
	
	[transaction setObject: remoteUser
	                forKey: remoteUser.uuid
	          inCollection: kZDCCollection_Users];
	
	// Step 2 of 7:
	//
	// Migrate user's avatar from persistent to cached.
	
	[zdc.diskManager makeUserAvatarPersistent:NO forUserID:localUserID];
	
	// Step 3 of 7:
	//
	// Delete the localUser & associated:
	// - privateKey
	// - accessKey
	// - authentication
	
	[transaction removeObjectForKey:privateKey.uuid inCollection:kZDCCollection_PublicKeys];

	[transaction removeObjectForKey:localUser.accessKeyID inCollection:kZDCCollection_SymmetricKeys];
	
	[transaction removeObjectForKey:localUser.uuid inCollection:kZDCCollection_UserAuth];
	
	[transaction removeObjectForKey:localUser.uuid inCollection:kZDCCollection_Users];
	
	// Step 4 of 7:
	//
	// Delete any splitKeys for this user.
	
	NSMutableArray *splitsToDelete = [NSMutableArray array];
	YapDatabaseViewTransaction *vtSplitKey = [transaction ext:Ext_View_SplitKeys];
	
	[vtSplitKey enumerateKeysInGroup: localUserID
	                      usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL * stop)
	{
		if ([collection isEqualToString:kZDCCollection_SplitKeys])
		{
			[splitsToDelete addObject:key];
		}
	}];
		
	if (splitsToDelete.count > 0)
	{
		[transaction removeObjectsForKeys:splitsToDelete inCollection:kZDCCollection_SplitKeys];
	}

	// Step 5 of 7:
	//
	// Delete all treesystem nodes.
	
	NSArray<NSString *> *allNodeIDs =
     [zdc.nodeManager allNodeIDsWithLocalUserID: localUserID
	                                 transaction: transaction];
    
	[transaction removeObjectsForKeys:allNodeIDs inCollection:kZDCCollection_Nodes];
    
	NSArray<NSString *> *allCloudNodeIDs =
	  [[ZDCCloudNodeManager sharedInstance] allCloudNodeIDsWithLocalUserID: localUserID
	                                                           transaction: transaction];
	
	[transaction removeObjectsForKeys:allCloudNodeIDs inCollection:kZDCCollection_CloudNodes];
	
	// Step 6 of 7:
	//
	// Delete all trunk nodes.
	
	NSArray<NSString*> *treeIDs = [zdc.databaseManager currentlyRegisteredTreeIDsForUser:localUserID];
	NSMutableArray<NSString*> *trunkNodeIDs = [NSMutableArray arrayWithCapacity:(4 * treeIDs.count)];
	
	for (NSString *treeID in treeIDs)
	{
		[trunkNodeIDs addObject:
			[ZDCTrunkNode uuidForLocalUserID:localUserID treeID:treeID trunk:ZDCTreesystemTrunk_Home]];
		[trunkNodeIDs addObject:
			[ZDCTrunkNode uuidForLocalUserID:localUserID treeID:treeID trunk:ZDCTreesystemTrunk_Prefs]];
		[trunkNodeIDs addObject:
			[ZDCTrunkNode uuidForLocalUserID:localUserID treeID:treeID trunk:ZDCTreesystemTrunk_Inbox]];
		[trunkNodeIDs addObject:
			[ZDCTrunkNode uuidForLocalUserID:localUserID treeID:treeID trunk:ZDCTreesystemTrunk_Outbox]];
	}

	[transaction removeObjectsForKeys:trunkNodeIDs inCollection:kZDCCollection_Nodes];
	
	// Step 7 of 7:
	//
	// Delete the user's pullState.
	
	[transaction removeObjectForKey:localUserID inCollection:kZDCCollection_PullState];
	
	// NOTES:
	//
	// - the SyncManager unregisters the ZDCCloud extension for us
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debugging & Development
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCLocalUserManager.html
 */
- (ZDCLocalUser *)createLocalUserFromJSON:(NSDictionary *)json
                              transaction:(YapDatabaseReadWriteTransaction *)transaction
                                    error:(NSError **)outError
{
	NSError* (^ErrorWithDescription)(NSString*) = ^(NSString *description) {
		
		return [NSError errorWithDomain: NSStringFromClass([self class])
		                           code: 400
		                       userInfo: @{ NSLocalizedDescriptionKey: description }];
	};
	NSError* (^ErrorWithInvalidKey)(NSString*) = ^(NSString *key){
		
		NSString *description = [NSString stringWithFormat:@"json has missing/invalid key: %@", key];
		return ErrorWithDescription(description);
	};
	
	NSString *localUserID = json[@"localUserID"];
	if (![localUserID isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"localUserID");
		return nil;
	}
	
	ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
	if (localUser) {
		if (outError) *outError =  ErrorWithDescription(@"localUser already exists in database");
		return nil;
	}
	
	localUser = [[ZDCLocalUser alloc] initWithUUID:localUserID];
	
	NSString *regionStr = json[@"region"];
	if (![regionStr isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"region");
		return nil;
	}
	
	AWSRegion region = [AWSRegions regionForName:regionStr];
	if (region == AWSRegion_Invalid) {
		if (outError) *outError = ErrorWithInvalidKey(@"region");
		return nil;
	}
	localUser.aws_region = region;
	
	NSString *bucket = json[@"bucket"];
	if (![bucket isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"bucket");
		return nil;
	}
	localUser.aws_bucket = bucket;
	
	NSString *stage = json[@"stage"];
	if (![stage isKindOfClass:[NSString class]]) {
		if (outError) *outError =  ErrorWithInvalidKey(@"stage");
		return nil;
	}
	localUser.aws_stage = stage;
	
	NSArray *identities = json[@"identities"];
	if (![identities isKindOfClass:[NSArray class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"identities");
		return nil;
	}
	NSMutableArray *parsed = [NSMutableArray arrayWithCapacity:identities.count];
	for (NSDictionary *identity in identities)
	{
		if (![identity isKindOfClass:[NSDictionary class]]) {
			if (outError) *outError = ErrorWithInvalidKey(@"identities");
			return nil;
		}
		
		ZDCUserIdentity *ident = [[ZDCUserIdentity alloc] initWithDictionary:identity];
		
		if (ident == nil) {
			if (outError) *outError = ErrorWithInvalidKey(@"identities");
			return nil;
		}
		
		[parsed addObject:ident];
	}
	localUser.identities = parsed;
	
	NSString *refreshToken = json[@"refreshToken"];
	if (![refreshToken isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"refreshToken");
		return nil;
	}
	
	ZDCLocalUserAuth *localUserAuth = [[ZDCLocalUserAuth alloc] init];
	localUserAuth.coop_refreshToken = refreshToken;
	
	NSString *syncedSalt = json[@"syncedSalt"];
	if (![syncedSalt isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"syncedSalt");
		return nil;
	}
	
	NSString *privKeyWords = json[@"privKeyWords"];
	if (![syncedSalt isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"privKeyWords");
		return nil;
	}
	
	NSArray<NSString*> *mnemonicWords =
	  [privKeyWords componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	const Cipher_Algorithm encryptionAlgorithm = kCipher_Algorithm_2FISH256;
	NSError *error = nil;
	
	NSData *accessKeyData =
	  [BIP39Mnemonic keyFromMnemonic: mnemonicWords
	                      passphrase: syncedSalt
	                      languageID: @"en_US"
	                           error: &error];
	
	if (error) {
		ZDCLogError(@"BIP39Mnemonic: keyFromMnemonic failed: %@", error);
		if (outError) *outError = error;
		return nil;
	}
	
	NSString *privKeyJSON = json[@"privKey"];
	if ([privKeyJSON isKindOfClass:[NSDictionary class]])
	{
		NSData *privKeyData = [NSJSONSerialization dataWithJSONObject:privKeyJSON options:0 error:nil];
		privKeyJSON = [[NSString alloc] initWithData:privKeyData encoding:NSUTF8StringEncoding];
	}
	
	if (![privKeyJSON isKindOfClass:[NSString class]]) {
		if (outError) *outError = ErrorWithInvalidKey(@"privKey");
		return nil;
	}
	
	ZDCPublicKey *privKey =
	  [zdc.cryptoTools createPrivateKeyFromJSON: privKeyJSON
	                                  accessKey: accessKeyData
	                        encryptionAlgorithm: encryptionAlgorithm
	                                localUserID: localUser.uuid
	                                      error: &error];
	
	if (error) {
		ZDCLogError(@"CryptoTools: createPrivateKeyFromJSON failed: %@", error);
		if (outError) *outError = error;
		return nil;
	}
	
	ZDCSymmetricKey *accessKey =
	  [zdc.cryptoTools createSymmetricKey: accessKeyData
	                  encryptionAlgorithm: encryptionAlgorithm
	                                error: &error];
	
	if (error) {
		ZDCLogError(@"CryptoTools: createSymmetricKey failed: %@", error);
		if (outError) *outError = error;
		return nil;
	}
	
	localUser.publicKeyID = privKey.uuid;
	localUser.accessKeyID = accessKey.uuid;
	
	[transaction setObject:localUser forKey:localUser.uuid inCollection:kZDCCollection_Users];
	[transaction setObject:localUserAuth forKey:localUser.uuid inCollection:kZDCCollection_UserAuth];
	[transaction setObject:privKey forKey:privKey.uuid inCollection:kZDCCollection_PublicKeys];
	[transaction setObject:accessKey forKey:accessKey.uuid inCollection:kZDCCollection_SymmetricKeys];
	
	[self createTrunkNodesForLocalUser: localUser
	                     withAccessKey: accessKey
	                       transaction: transaction];
	
	if (outError) *outError = nil;
	return localUser;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private User Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standardized routine for creating all the trunk nodes.
 * Get access via: #import "ZDCLocalUserManagerPrivate.h"
 */
- (void)createTrunkNodesForLocalUser:(ZDCLocalUser *)localUser
                       withAccessKey:(ZDCSymmetricKey *)accessKey
                         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSArray<NSNumber*> *trunks = @[
		@(ZDCTreesystemTrunk_Home),
		@(ZDCTreesystemTrunk_Prefs),
		@(ZDCTreesystemTrunk_Inbox),
		@(ZDCTreesystemTrunk_Outbox)
	];
	
	NSString *const treeID = zdc.primaryTreeID;
	
	for (NSNumber *trunkNum in trunks)
	{
		ZDCTreesystemTrunk trunk = (ZDCTreesystemTrunk)[trunkNum integerValue];
		NSString *key = [ZDCTrunkNode uuidForLocalUserID:localUser.uuid treeID:treeID trunk:trunk];
		
		if (![transaction hasObjectForKey:key inCollection:kZDCCollection_Nodes])
		{
			ZDCTrunkNode *trunkNode =
			  [[ZDCTrunkNode alloc] initWithLocalUserID: localUser.uuid
			                                     treeID: treeID
			                                      trunk: trunk];
	
			[zdc.cryptoTools setDirSaltForTrunkNode: trunkNode
			                          withLocalUser: localUser
			                              accessKey: accessKey];
	
			ZDCShareList *shareList =
			  [ZDCShareList defaultShareListForTrunk: trunk
			                         withLocalUserID: localUser.uuid];
	
			[shareList enumerateListWithBlock:^(NSString *key, ZDCShareItem *shareItem, BOOL *stop) {
	
				[trunkNode.shareList addShareItem:shareItem forKey:key];
			}];
	
			[transaction setObject: trunkNode
			                forKey: trunkNode.uuid
			          inCollection: kZDCCollection_Nodes];
		}
	}
}

- (void)refreshAuth0ProfilesForLocalUserID:(NSString *)localUserID
                           completionQueue:(nullable dispatch_queue_t)completionQueue
                           completionBlock:(nullable void (^)( NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	NSParameterAssert(localUserID != nil);

	void (^InvokeCompletionBlock)(NSError * error) = ^(NSError * error){

		if (completionBlock == nil) return;

		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{
			completionBlock(error);
		});
	};
	
	__weak typeof(self) weakSelf = self;
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__block ZDCUserProfile *profile = nil;

	__block void (^parameterCheck)(void);
	__block void (^fetchProfile)(ZDCLocalUser *localUser);
	__block void (^updateDatabase)(void);

	// STEP 1 :
	//
	// parameter check
	//
	parameterCheck = ^{ @autoreleasepool {

		ZeroDarkCloud *zdc = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				zdc = strongSelf->zdc;
			}
		}
		
		__block ZDCLocalUser *localUser = nil;
		__block ZDCLocalUserAuth *auth = nil;
		
		[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {

			localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
			auth = [transaction objectForKey:localUserID inCollection:kZDCCollection_UserAuth];
		}];

		if (!localUser || !auth)
		{
			InvokeCompletionBlock([self errorWithDescription:@"Bad parameter: localUser has no auth"]);
			return;
		}

		fetchProfile(localUser);
	}};


	// STEP 2 :
	//
	// fetch latest profile from server
	//

	fetchProfile = ^void (ZDCLocalUser *localUser){ @autoreleasepool {

		ZeroDarkCloud *zdc = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				zdc = strongSelf->zdc;
			}
		}
		
		[zdc.restManager fetchAuth0Profile: localUser.uuid
		                       requesterID: localUser.uuid
		                   completionQueue: concurrentQueue
		                   completionBlock:
		^(NSURLResponse *urlResponse, id responseObject, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlock(error);
				return;
			}
			
			NSInteger statusCode = urlResponse.httpStatusCode;
			if (statusCode != 200)
			{
				error = [self errorWithDescription:@"Bad Status response" statusCode:statusCode];
				
				InvokeCompletionBlock(error);
				return;
			}
			
			NSDictionary *dict = nil;
			
			if ([responseObject isKindOfClass:[NSDictionary class]])
			{
				dict = (NSDictionary *)responseObject;
			}
			else if ([responseObject isKindOfClass:[NSData class]])
			{
				NSData *data = (NSData *)responseObject;
				
				id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
				if ([value isKindOfClass:[NSDictionary class]])
				{
					dict = (NSDictionary *)value;
				}
			}
			
			if (dict)
			{
				profile = [[ZDCUserProfile alloc] initWithDictionary:dict];
			}
			
			if (profile)
			{
				updateDatabase();
			}
			else
			{
				error = [self errorWithDescription:@"Unexpected server response"];
				InvokeCompletionBlock(error);
			}
		}];
	}};

	// STEP 3 :
	//
	// update the user database with new values
	//

	updateDatabase = ^{ @autoreleasepool {

		ZeroDarkCloud *zdc = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				zdc = strongSelf->zdc;
			}
		}

		YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

			ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
			
			localUser = [localUser copy];
			localUser.identities = profile.identities;
			localUser.lastRefresh_profile = [NSDate date];
			
			[transaction setObject: localUser
			                forKey: localUser.uuid
			          inCollection: kZDCCollection_Users];

		} completionBlock:^{

			// Done !
			InvokeCompletionBlock(nil);
		}];
	}};

	parameterCheck();
}

/**
 * Updates the pubKey in the cloud by signing the new set of auth0 ID's into the JSON.
 **/
- (void)updatePubKeyForLocalUserID:(NSString *)localUserID
                   completionQueue:(dispatch_queue_t)completionQueue
			  completionBlock:(void (^)(NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;

	void (^InvokeCompletionBlock)(NSError*) = ^(NSError *error){

		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(error);
			}});
		}
	};

	void (^processingBlock)(NSURLResponse*, id, NSError*) =
	^(NSURLResponse *response, id responseObject, NSError *error)
	{
		//	if (!error)
		//	{
		//		NSInteger statusCode = response.httpStatusCode;
		//		if (statusCode != 200)
		//		{
		//			error = [self errorWithDescription:@"internal error : server call to privPubKey return unexpected value"];
		//		}
		//	}

		// We're ignoring errors here since this code isn't implemented server-side anyways.

		InvokeCompletionBlock(nil);
	};

	__block NSError *error     = nil;
	__block NSData *pubKeyData = nil;

	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		ZDCCryptoTools *cryptoTools = strongSelf->zdc.cryptoTools;

		ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		if (!localUser || !localUser.isLocal)
		{
			error = [self errorWithDescription:@"Bad parameter: unknown localUser"];
			return;
		}

		ZDCSymmetricKey *cloneKey =
		  [transaction objectForKey: localUser.accessKeyID
		               inCollection: kZDCCollection_SymmetricKeys];
		
		if (!cloneKey)
		{
			error = [self errorWithDescription:@"Bad parameter: cloneKey is nil"];
			return;
		}

		NSMutableArray *identityIDs = [NSMutableArray arrayWithCapacity:localUser.identities.count];
		for (ZDCUserIdentity *ident in localUser.identities)
		{
			// dont add recovery IDs to the public key
			if(!ident.isRecoveryAccount)
				[identityIDs addObject:ident.identityID];
		}
		
		NSData *auth0IDData =
		  [NSJSONSerialization dataWithJSONObject: identityIDs
		                                  options: 0
		                                    error: &error];
		
		if (error) return; // from transaction block

		[cryptoTools updateKeyProperty: kZDCCloudKey_Auth0ID
		                         value: auth0IDData
		               withPublicKeyID: localUser.publicKeyID
		                   transaction: transaction
		                         error: &error];
		
		if (error) return; // from transaction block

		ZDCPublicKey *privateKey =
		  [transaction objectForKey: localUser.publicKeyID
		               inCollection: kZDCCollection_PublicKeys];

		pubKeyData = [cryptoTools exportPublicKey:privateKey error:&error];

	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{

		if (error)
		{
			InvokeCompletionBlock(error);
			return;
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		ZDCRestManager *restManager = strongSelf->zdc.restManager;

		[restManager updatePubKeySigs: pubKeyData
		               forLocalUserID: localUserID
		              completionQueue: dispatch_get_main_queue()
		              completionBlock: processingBlock];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private Key Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description: ZDCLocalUserManagerPrivate.h
 */
- (void)setupPubPrivKeyForLocalUser:(ZDCLocalUser *)localUser
                           withAuth:(ZDCLocalUserAuth *)auth
                          accessKey:(ZDCSymmetricKey *)accessKey
                    completionQueue:(nullable dispatch_queue_t)completionQueue
                    completionBlock:(void (^)(ZDCLocalUser *_Nullable localUser,
                                                    NSData *_Nullable privKeyToUnlock,
                                                   NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();

	NSParameterAssert([localUser isKindOfClass:[ZDCLocalUser class]]);
	NSParameterAssert(auth != nil);
	NSParameterAssert(accessKey != nil);
	NSParameterAssert(completionBlock != nil);
	
	void (^Fail)(SetupPrivPubKeyErrorCode, NSString*, NSError*) =
	^(SetupPrivPubKeyErrorCode code, NSString *msg, NSError *underlyingError){
		
		NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
		if (msg) {
			userInfo[NSLocalizedDescriptionKey] = msg;
		}
		if (underlyingError) {
			userInfo[NSUnderlyingErrorKey] = underlyingError;
		}
		
		NSString *domain = NSStringFromClass([self class]);
		NSError *error = [NSError errorWithDomain:domain code:code userInfo:userInfo];
		
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			completionBlock(nil, nil, error);
		}});
	};
	
	void (^Succeed)(ZDCLocalUser*, NSData*) = ^(ZDCLocalUser *localUser, NSData *privKeyToUnlock) {
		
		// Exactly 1 of parameters must be non-nil.
		//
		if (localUser) {
			NSParameterAssert(privKeyToUnlock == nil);
		} else {
			NSParameterAssert(privKeyToUnlock != nil);
		}
		
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			completionBlock(localUser, privKeyToUnlock, nil);
		}});
	};
	
	// Here's how this works:
	//
	// - The public key is stored on the server in cleartext (non-encrypted JSON).
	//   In terms of S3 permissions, the pubKey file is accessible to the world.
	//
	// - The private key is stored on the server in an encrypted form.
	//   (PBKDF2 with the privKey bits encrypted with the accessKey.)
	//   In terms of S3 permissions, the privKey file is only accessible to the localUser.
	//   The private key can only be unlocked with the user's accessKey, which ZeroDark never knows.
	//   For co-op users, the accessKey is the thing the user backs up.
	//
	// - Neither of these files are directly writable by the user because the 2 files need
	//   to be set together in an atomic fashion. So, instead, the user goes through the REST API.
	//
	// - The REST API checks to see if there's already a pair of files setup by the user,
	//   and if so, it returns those to the caller.
	//
	// - Otherwise it accepts the posted pair (cleartext pubKey + encrypted privKey),
	//   and stores those for the user.
	//
	// So this method generates a random privKey/pubKey pair, and then calls the REST API.
	// The server will either accept our keypair, and give us a success response.
	// Or it will give us a conflict response, and pass us the existing keypair.
	
	ZDCPublicKey *privateKey = nil;
	NSError *error = nil;

	// Create temporary private key,
	// but don't update DB until we know what the real values on the server are.

	privateKey = [ZDCPublicKey createPrivateKeyWithUserID: localUser.uuid
	                                            algorithm: kCipher_Algorithm_ECC41417
	                                           storageKey: zdc.storageKey
	                                                error: &error];
	
	if (error) {
		Fail(SetupPrivPubKeyErrorCode_CryptoError, @"Error generating random privateKey", error);
		return;
	}

	// When we create the .pubKey file, we can include the user's linked identities.
	// And then we sign that info with the private key.
	//
	// It's one little extra thing we do for added security.
	
	NSMutableArray *identityIDs = [NSMutableArray arrayWithCapacity:localUser.identities.count];
	for (ZDCUserIdentity *ident in localUser.identities)
	{
		[identityIDs addObject:ident.identityID];
	}
	
	NSData *auth0IDData =
	  [NSJSONSerialization dataWithJSONObject: identityIDs
	                                  options: 0
	                                    error: nil];

	[privateKey updateKeyProperty: kZDCCloudKey_Auth0ID
	                        value: auth0IDData
	                   storageKey: zdc.storageKey
	                        error: &error];

	if (error) {
		Fail(SetupPrivPubKeyErrorCode_CryptoError, @"Error updating privKey property", error);
		return;
	}

	// Generate the privKey file.
	// This is a JSON file, with the privKey bits encrypted with the given accessKey.
	//
	// The output looks something like this:
	// {
	//   "version": 1,
	//   "encoding": "Twofish-256",
	//   "keySuite": "Curve41417",
	//   "mac": "9L0f/OrLDNs=",
	//   "keyID": "w43ok0USZU2201IAf1cY6g==",
	//   "privKey": "vsTntsXvhx1Ofct05OH+5owKRHu/t6AZfx8Gt4zHlccRCpBjojbNLgZ/oM6YdBT9s6SwAt/Vnycl5rT/YaCYN90Rdr8dYACZpGo0lOLy8l3V9WoVpALFXeiFC0zQVtSruDJpOKBE6ikXJFDRSIcd38nVqY5hc6UuaVtft2oPBovYJER6gaJWbpe7ZcpqdG02Gv9Wzuc/yH0VGlsPsFUN4bUSKaw7naEPx+5+zUo+4lUWZKYwZbtYNuhYppbrvo3V",
	//   "start-date": "2020-05-06T17:22:05Z",
	//   "userID": "nxcemc5r156qeuqc6oeqqg7gco43hxp3"
	// }
	
	NSData *privKeyData = [zdc.cryptoTools exportPrivateKey: privateKey
	                                            encryptedTo: accessKey // <- private bits encrypted with accessKey
	                                                  error: &error];
	if (error) {
		Fail(SetupPrivPubKeyErrorCode_CryptoError, @"Error exporting encrypted privKey file", error);
		return;
	}

	// Generate the pubKey file.
	// This is a non-encrypted JSON file.
	
	NSData *pubKeyData = [zdc.cryptoTools exportPublicKey: privateKey // only exports the public bits
	                                                error: &error];
	
	if (error) {
		Fail(SetupPrivPubKeyErrorCode_CryptoError, @"Error exporting pubKey file", error);
		return;
	}

	__block void(^IssueRequest)(void);
	__block void(^ProcessResponse)(NSData*, NSURLResponse*, NSError*);
	__block void(^RetryRequest)(void);

	__block NSUInteger failCount = 0;
	
	__strong ZeroDarkCloud *zdc = self->zdc;
	__weak typeof(self) weakSelf = self;

	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	IssueRequest = ^{ @autoreleasepool {

		[zdc.restManager uploadEncryptedPrivKey: privKeyData
		                                 pubKey: pubKeyData
		                           forLocalUser: localUser
		                               withAuth: auth
		                        completionQueue: bgQueue
		                        completionBlock: ProcessResponse];
	}};
	
	ProcessResponse = ^(NSData *data, NSURLResponse *response, NSError *uploadError){ @autoreleasepool {

		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		if (uploadError) {
			Fail(SetupPrivPubKeyErrorCode_NetworkError, nil, uploadError);
			return;
		}

		NSInteger statusCode = response.httpStatusCode;

		if (statusCode == 200 || statusCode == 201)
		{
			// The server accepted our keypair.
			// So write everything to the database, and then notify caller of our success.
			//
			// The following are written to the database:
			// - localUser
			// - privateKey
			// - accessKey
			// - auth
			
			[strongSelf saveLocalUser: localUser
			               privateKey: privateKey
			                accessKey: accessKey
			                     auth: auth
			          completionQueue: bgQueue
			          completionBlock:^(ZDCLocalUser *updatedLocalUser)
			{
				Succeed(updatedLocalUser, nil);
			}];
		}
		else if (statusCode == 409)  // Conflict - keys are already there
		{
			// The user account already has a privKey/pubKey pair stored in the cloud.
			//
			// This just means the user has already logged in before.
			// Either they did so on another device,
			// or they did so on this device (but then deleted the app, or deleted the database, etc).
			//
			// In any case, it means the server sent us the existing pubKey and (wrapped) privKey.
			
			NSData *privKeyData = nil;

			NSError *parsingError = nil;
			NSDictionary *jsonDict =
			  [NSJSONSerialization JSONObjectWithData: data
			                                  options: 0
			                                    error: &parsingError];

			if (parsingError) {
				Fail(SetupPrivPubKeyErrorCode_ServerError, @"Error parsing JSON response", parsingError);
				return;
			}

			NSString *privKeyString = jsonDict[@"privKey"];
			if ([privKeyString isKindOfClass:[NSString class]])
			{
				privKeyData = [[NSData alloc] initWithBase64EncodedString:privKeyString options:0];
			}

			if (privKeyData == nil)
			{
				Fail(SetupPrivPubKeyErrorCode_ServerError, @"response.privKey isn't valid base64 data", nil);
				return;
			}

			// Ensure privKeyData is valid (represents a wrapped privateKey)
			NSString *locator = [zdc.cryptoTools keyIDforPrivateKeyData:privKeyData error:&parsingError];

			if (parsingError) {
				Fail(SetupPrivPubKeyErrorCode_ServerError, @"Error validating response.privKey", parsingError);
				return;
			}
			
			if (localUser.publicKeyID == nil) // <= this is what we expect to be true
			{
				Succeed(nil, privKeyData);
			}
			else // if (localUser.publicKeyID)
			{
				// The localUser appears to have a key already.
				// This is unexpected, but let's see if the existing key matches the server at least.
				
				__block ZDCLocalUser *existingLocalUser = nil;
				__block ZDCPublicKey *existingPubKey = nil;
				
				YapDatabaseConnection *roConnection = zdc.databaseManager.roDatabaseConnection;
				[roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {

					ZDCUser *existingUser = [transaction objectForKey: localUser.uuid
					                                     inCollection: kZDCCollection_Users];
					
					if ([existingUser isKindOfClass:[ZDCLocalUser class]])
					{
						existingLocalUser = (ZDCLocalUser *)existingUser;
						
						existingPubKey = [transaction objectForKey: existingLocalUser.publicKeyID
						                              inCollection: kZDCCollection_PublicKeys];
					}
				}];

				BOOL userAccountIsAlreadySetup =
				  (existingLocalUser && existingLocalUser.accessKeyID && existingLocalUser.publicKeyID) &&
				  ([existingPubKey.keyID isEqualToString:locator] && existingPubKey.isPrivateKey);
				
				if (userAccountIsAlreadySetup)
				{
					// Well alrighty then. Guess you didn't need to call this method, huh?
					
					Succeed(existingLocalUser, nil);
				}
				else
				{
					// We need to decrypt pkData.
					// This may require prompting the user for their accessKey.

					Succeed(nil, privKeyData);
				}
			}
		}
		else if (statusCode == 423)
		{
			// The server failed while attempting to get a lock for the user's privKey/pubKey pair.
			// This is unlikely, but possible.
			//
			// We should retry after a short period of time.

			failCount++;
			RetryRequest();
		}
		else
		{
			NSString *msg = [NSString stringWithFormat:
				@"Server returned unknown statusCode: %i", (int)statusCode];

			Fail(SetupPrivPubKeyErrorCode_ServerError, msg, nil);
		}
	}};

	RetryRequest = ^{ @autoreleasepool {

		if (failCount >= 10)
		{
			// We only retry the request if the server sends us a 423 response.
			// In other words:
			//   The network is working just fine.
			//   But the server keeps telling us its unable to get a needed lock.
			//
			NSString *msg = @"Server call continually failed.";

			Fail(SetupPrivPubKeyErrorCode_ServerError, msg, nil);
			return;
		}

		NSTimeInterval delayInSeconds = 0;
		if (failCount <= 5) {
			delayInSeconds = 0.2; // 200 milliseconds
		}
		else {
			delayInSeconds = 0.5; // 500 milliseconds
		}
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), bgQueue, ^{

			IssueRequest();
		});
	}};
	
	// Start
	IssueRequest();
}

- (void)saveLocalUser:(ZDCLocalUser *)inLocalUser
           privateKey:(ZDCPublicKey *)privateKey
            accessKey:(ZDCSymmetricKey *)accessKey
                 auth:(ZDCLocalUserAuth *)auth
      completionQueue:(dispatch_queue_t)completionQueue
      completionBlock:(void (^)(ZDCLocalUser*))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(inLocalUser != nil);
	NSParameterAssert(privateKey != nil);
	NSParameterAssert(accessKey != nil);
	NSParameterAssert(auth != nil);
	
	__block ZDCLocalUser *localUser = nil;
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Don't forget:
		// Always grab the latest version of the localUser within a transaction, and modify that.
		//
		localUser = [transaction objectForKey:inLocalUser.uuid inCollection:kZDCCollection_Users];
		if (!localUser) {
			
			localUser = inLocalUser;
		}
		else if (![localUser isKindOfClass:[ZDCLocalUser class]]) {
			
			// There's an existing remote user in the database already.
			// We're going to replace it with our local user.
			// And we're going to replace the previous publicKey with our privateKey.
			// So let's cleanup after the remote user.
			//
			[transaction removeObjectForKey:localUser.publicKeyID inCollection:kZDCCollection_PublicKeys];
			
			localUser = inLocalUser;
		}
		
		localUser = [localUser copy];
		localUser.publicKeyID = privateKey.uuid;
		localUser.accessKeyID = accessKey.uuid;
		
		[transaction setObject: localUser
		                forKey: localUser.uuid
		          inCollection: kZDCCollection_Users];
		
		[transaction setObject: privateKey
		                forKey: privateKey.uuid
		          inCollection: kZDCCollection_PublicKeys];
		
		[transaction setObject: accessKey
		                forKey: accessKey.uuid
		          inCollection: kZDCCollection_SymmetricKeys];
		
		[transaction setObject: auth
		                forKey: localUser.uuid
		          inCollection: kZDCCollection_UserAuth];
		
		[self createTrunkNodesForLocalUser: localUser
		                     withAccessKey: accessKey
		                       transaction: transaction];

	} completionQueue:completionQueue completionBlock:^{
		
		completionBlock(localUser);
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See (private) header file for documentation.
 */
- (void)createRecoveryConnectionForLocalUser:(ZDCLocalUser *)inLocalUser
                             completionQueue:(nullable dispatch_queue_t)completionQueue
                             completionBlock:(nullable void (^)(NSError *error))completionBlock
{
	__weak typeof(self) weakSelf = self;

	ZDCLogAutoTrace();

	void (^InvokeCompletionBlock)(NSError *) = ^(NSError *error){

		if (completionBlock == nil) return;

		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{
			completionBlock(error);
		});
	};

	inLocalUser = [inLocalUser immutableCopy];
	NSString *const localUserID = inLocalUser.uuid;
	
	__block NSString *recovery_auth0ID = nil;
	__block NSString *recovery_refreshToken = nil;

	__block NSString *recoveryUsername = localUserID; // for recovery ID
	__block NSString *recoveryPassword = [[NSData s4RandomBytes:32] base64EncodedStringWithOptions:0];

	__block void (^createAccount)(void);
	__block void (^loginToAccount)(void);
	__block void (^linkRecoveryID)(void);
	__block void (^updateUserToken)(void);

	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	if ([inLocalUser hasRecoveryConnection])
	{
		// There's no reason for the `localUser.needsCreateRecoveryConnection` flag to be set.
		// So we can simply unset the flag, and then we're done.
		//
		YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
			if (localUser && localUser.isLocal)
			{
				localUser = [localUser copy];
				localUser.needsCreateRecoveryConnection = NO;
			
				[transaction setObject:localUser forKey:localUser.uuid  inCollection:kZDCCollection_Users];
			}
			
		} completionQueue:dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0) completionBlock:^{
			
			InvokeCompletionBlock(nil);
		}];
		return;
	}

	// STEP 1 of 4:
	//
	// Create the recovery account in auth0.
	//

	createAccount = ^{ @autoreleasepool {

		NSString *recoveryEmail = [Auth0Utilities create4thAEmailForUsername:localUserID];

		[[Auth0APIManager sharedInstance] createUserWithEmail: recoveryEmail
		                                             username: recoveryUsername
		                                             password: recoveryPassword
		                                      auth0Connection: kAuth0DBConnection_Recovery
		                                      completionQueue: queue
		                                      completionBlock:
		  ^(NSString *auth0ID, NSError *error)
		{

			if (error)
			{
				// We might have created the usrename before but failed the login.
				// We are hosed here, since we no longer have the recovery password.
				//
				// But it's not really a big deal.
				// The server has permissions to fix our recovery account if need be.
				//
				// Note: This has nothing to do with user data.
				
				InvokeCompletionBlock(error);
				return;
			}
			
			// Next step
			loginToAccount();
		}];
	}};


	// STEP 2 of 4:
	//
	// Login to the recovery account and get the new refresh token.
	//

	loginToAccount = ^{ @autoreleasepool {

		[[Auth0APIManager sharedInstance] loginAndGetProfileWithUsername: recoveryUsername
		                                                        password: recoveryPassword
		                                                 auth0Connection: kAuth0DBConnection_Recovery
		                                                 completionQueue: queue
		                                                 completionBlock:
		^(Auth0LoginProfileResult *result, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlock(error);
				return;
			}

			recovery_auth0ID = result.profile.userID;
			recovery_refreshToken = result.refreshToken;

			// Next step
			linkRecoveryID();
		}];
	}};

	// STEP 3 of 4:
	//
	// Tell the AWS server to link the our existing auth0 user to the new recovery ID
	//

	linkRecoveryID = ^{ @autoreleasepool {

		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		ZDCRestManager *restManager = strongSelf->zdc.restManager;
		
		[restManager linkAuth0ID: inLocalUser.auth0_primary
		            toRecoveryID: recovery_auth0ID
		                 forUser: localUserID
		         completionQueue: queue
		         completionBlock:
		^(NSURLResponse *urlResponse, id responseObject, NSError *error)
		{
			NSInteger statusCode = urlResponse.httpStatusCode;

			if (error)
			{
				InvokeCompletionBlock(error);
			}
			else if (statusCode != 200)
			{
				InvokeCompletionBlock( [self errorWithDescription:@"Bad status response" statusCode:statusCode]);
			}
			else if(![responseObject isKindOfClass:[NSDictionary class]])
			{
				InvokeCompletionBlock( [self errorWithDescription:@"Unexpected server response" statusCode:500]);
			}
			else
			{
				updateUserToken();
			}
		}];
	}};

	// STEP 4 of 4:
	//
	// Update our database entry to reflect the new primary ID and refresh token
	//

	updateUserToken = ^{ @autoreleasepool {

		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		// update the refresh token for the exitsing account
		// update the auth0 primary for the exitsing account

		YapDatabaseConnection *rwConnection = strongSelf->zdc.databaseManager.rwDatabaseConnection;
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

			ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
			ZDCLocalUserAuth *auth = [transaction objectForKey:localUserID inCollection:kZDCCollection_UserAuth];

			if (!localUser || !auth)
			{
				InvokeCompletionBlock([self errorWithDescription:@"Bad parameter: localUser has no auth"]);
				return;
			}

			localUser = [localUser copy];
			localUser.needsCreateRecoveryConnection = NO;
			
			if (recovery_auth0ID) {
				localUser.auth0_primary = recovery_auth0ID;
			}
			
			[transaction setObject:localUser forKey:localUserID  inCollection:kZDCCollection_Users];
			
			if (recovery_refreshToken)
			{
				auth = [auth copy];
				auth.coop_refreshToken = recovery_refreshToken;
				
				[transaction setObject:auth forKey:localUserID inCollection:kZDCCollection_UserAuth];
			}

		} completionQueue:dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0) completionBlock:^{

			// Done !
			InvokeCompletionBlock(nil);
		}];
	}};

	createAccount();
}

- (void)finalizeAccountSetupForLocalUser:(ZDCLocalUser *)localUser
                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	// Are we using ZeroDark.identity ?
	//
	if (localUser.identities.count > 0)
	{
		if (![localUser hasRecoveryConnection])
		{
			if (localUser.isImmutable) {
				localUser = [localUser copy];
			}
			
			localUser.needsCreateRecoveryConnection = YES;
			
			[transaction setObject:localUser forKey:localUser.uuid inCollection:kZDCCollection_Users];
		}
	}
}

/**
 * See header file for description.
 */
- (void)setNewAvatar:(nullable NSData *)newAvatarData
        forLocalUser:(ZDCLocalUser *)localUser
          identityID:(NSString *)identityID
  replacingOldAvatar:(nullable NSData *)oldAvatarData
{
	NSParameterAssert(localUser != nil);
	NSParameterAssert(identityID != nil);
	
	NSString *eTag_new = newAvatarData ? [[AWSPayload rawMD5HashForPayload:newAvatarData] lowercaseHexString] : nil;
	NSString *eTag_old = oldAvatarData ? [[AWSPayload rawMD5HashForPayload:oldAvatarData] lowercaseHexString] : nil;
	
	// When the user is adding/modifing the avatar, we obviously want to store the new avatar in the DiskManager.
	// But what about when the user is deleting the avatar ?
	//
	// We used to do this, but it was a bug:
	// [zdc.diskManager deleteUserAvatar:localUser.uuid forIdentityID:identityID]; // <= BUG
	//
	// Because the rest of the system ends up asking for the localUser's avatar again.
	// And since the DiskManager has no record of it, the system ends up downloading whatever is in the cloud.
	//
	// But that's not what we want here.
	// Instead, we need to store a nil placeholder to disk.
	
	ZDCDiskImport *import = nil;
	if (newAvatarData) {
		import = [[ZDCDiskImport alloc] initWithCleartextData:newAvatarData];
	} else {
		import = [[ZDCDiskImport alloc] init]; // import.isNilPlaceholder == YES
	}
	
	import.storePersistently = YES;
	import.eTag = eTag_new;
	
	NSError *error = nil;
	[zdc.diskManager importUserAvatar: import
	                          forUser: localUser
	                       identityID: identityID
	                            error: &error];
	
	if (error) {
		ZDCLogWarn(@"Error importing image: %@", error);
		return;
	}
	
	ZDCCloudOperation *op =
	  [[ZDCCloudOperation alloc] initWithLocalUserID: localUser.uuid
	                                          treeID: @"*"
	                                            type: ZDCCloudOperationType_Avatar];
	
	op.avatar_auth0ID = identityID;
	op.avatar_oldETag = eTag_old;
	op.avatar_newETag = eTag_new;
	
	NSString *extName = [zdc.databaseManager cloudExtNameForUserID:@"*" treeID:@"*"];
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCCloudTransaction *ext = [transaction ext:extName];
		[ext addOperation:op];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	return [NSError errorWithClass:[self class] code:0 description:description];
}

- (NSError *)errorWithDescription:(NSString *)description statusCode:(NSUInteger)statusCode
{
	return [NSError errorWithClass:[self class] code:statusCode description:description];
}

@end
