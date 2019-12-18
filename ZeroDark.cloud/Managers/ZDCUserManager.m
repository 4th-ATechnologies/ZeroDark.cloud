/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserManagerPrivate.h"

#import "Auth0Utilities.h"
#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCConstants.h"
#import "ZDCDatabaseManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCUserSearchManager.h"
#import "ZDCUserPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSURLResponse+ZeroDark.h"

// Libraries
#import <AFNetworking/AFNetworking.h>

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


@interface ZDCUserDisplay ()
@property (nonatomic, readwrite, copy) NSString *displayName;
@end

@implementation ZDCUserDisplay

@synthesize userID = _userID;
@synthesize displayName = _displayName;

- (instancetype)initWithUserID:(NSString *)userID displayName:(NSString *)displayName
{
	if ((self = [super init]))
	{
		_userID = [userID copy];
		_displayName = [_displayName copy];
	}
	return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCUserManager
{
	__weak ZeroDarkCloud *zdc;
	
	YapDatabaseConnection *internal_roConnection;
	ZDCAsyncCompletionDispatch *asyncCompletionDispatch;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.remoteUserManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		internal_roConnection = [zdc.databaseManager internal_roConnection];
		asyncCompletionDispatch = [[ZDCAsyncCompletionDispatch alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fetch API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUserManager.html
 */
- (void)fetchUserWithID:(NSString *)remoteUserID
            requesterID:(NSString *)localUserID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(nullable void (^)(ZDCUser *remoteUser, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUserID != nil);
	NSParameterAssert(localUserID != nil);
	
	remoteUserID = [remoteUserID copy];
	localUserID = [localUserID copy];
	
	// Convert from any random anonymous userID to the standardized anonymous userID that
	// we use for the ZDCUser in the database.
	//
	// For example:
	// "1ymbquw673gttwpb" => "anonymoususerid1"
	//
	if ([ZDCUser isAnonymousID:remoteUserID])
	{
		remoteUserID = kZDCAnonymousUserID;
	}
	
	__block ZDCUser *user = nil;
	__weak typeof(self) weakSelf = self;
	
	[internal_roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		user = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
		
		if (user)
		{
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
					completionBlock(user, nil);
				}});
			}
			return;
		}
		
		[weakSelf _fetchRemoteUserWithID: remoteUserID
		                     requesterID: localUserID
		                 completionQueue: completionQueue
		                 completionBlock: completionBlock];
	}];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUserManager.html
 */
- (void)fetchPublicKey:(ZDCUser *)remoteUser
           requesterID:(NSString *)inLocalUserID
       completionQueue:(nullable dispatch_queue_t)completionQueue
       completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUser != nil);
	NSParameterAssert(inLocalUserID != nil);
	
	NSString *localUserID = [inLocalUserID copy];
	
	if (remoteUser.publicKeyID || [ZDCUser isAnonymousID:remoteUser.uuid])
	{
		// Nothing to fetch:
		// - user already has a public key, or
		// - anonymous users don't have a public key
		//
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(remoteUser, nil);
			}});
		}
		return;
	}
	
	[self _fetchPublicKey: remoteUser
	          requesterID: localUserID
	      completionQueue: completionQueue
	      completionBlock: completionBlock];
}
/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUserManager.html
 */
- (void)refreshIdentities:(ZDCUser *)remoteUser
              requesterID:(NSString *)inLocalUserID
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUser != nil);
	NSParameterAssert(inLocalUserID != nil);
	
	NSString *remoteUserID = remoteUser.uuid;
	NSString *localUserID = [inLocalUserID copy];
	
	if ([ZDCUser isAnonymousID:remoteUserID])
	{
		// Nothing to refresh:
		// - anonymous users don't have any linked identities
		//
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(remoteUser, nil);
			}});
		}
		return;
	}
	
	[self _refreshIdentities: remoteUserID
	             requesterID: localUserID
	         completionQueue: completionQueue
	         completionBlock: completionBlock];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCUserManager.html
 */
- (void)recheckBlockchain:(ZDCUser *)remoteUser
              requesterID:(NSString *)inLocalUserID
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUser != nil);
	NSParameterAssert(inLocalUserID != nil);
	
	NSString *remoteUserID = remoteUser.uuid;
	NSString *localUserID = [inLocalUserID copy];
	
	if ([ZDCUser isAnonymousID:remoteUserID])
	{
		// Nothing to check:
		// - anonymous users don't have a publicKey
		//
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(remoteUser, nil);
			}});
		}
		return;
	}
	
	[self _recheckBlockchain: remoteUser
	             requesterID: localUserID
	         completionQueue: completionQueue
	         completionBlock: completionBlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Download Control
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal method that handles the download flow.
 */
- (void)_fetchRemoteUserWithID:(NSString *)remoteUserID
                   requesterID:(NSString *)localUserID
               completionQueue:(nullable dispatch_queue_t)inCompletionQueue
               completionBlock:(nullable void (^)(ZDCUser *remoteUser, NSError *error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUserID != nil);
	NSParameterAssert(localUserID != nil);
	
	// Convert from any random anonymous userID to the standardized anonymous userID
	// we use for the ZDCUser in the database.
	//
	// For example:
	// "1ymbquw673gttwpb" => "anonymoususerid1"
	//
	BOOL isAnonymousUser = NO;
	if ([ZDCUser isAnonymousID:remoteUserID])
	{
		remoteUserID = kZDCAnonymousUserID;
		isAnonymousUser = YES;
	}
	
	if (inCompletionBlock == nil) {
		inCompletionBlock = ^(ZDCUser *user, NSError *error){};
	}
	
	NSString *const requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), remoteUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The {inCompletionQueue, inCompletionBlock} tuple have been added to the existing request's list.
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	
	void (^InvokeCompletionBlocks)(ZDCUser*, NSError*) = ^(ZDCUser *user, NSError *error){ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[strongSelf->asyncCompletionDispatch popCompletionQueues: &completionQueues
		                                        completionBlocks: &completionBlocks
		                                                  forKey: requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCUser*, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(user, error);
			}});
		}
	}};

	__block void (^fetchBasicInfo)(void);
	__block void (^fetchAuth0Info)(ZDCUser *user);
	__block void (^storeUserInDatabase)(ZDCUser *user);
	__block void (^createAnonymousUser)(void);
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	// STEP 1 of 3:
	//
	// Fetch basic info about the user including:
	// - region
	// - bucket
	//
	fetchBasicInfo = ^void (){ @autoreleasepool {
		
		[weakSelf _fetchRemoteUser: remoteUserID
		               requesterID: localUserID
		           completionQueue: concurrentQueue
		           completionBlock:^(ZDCUser *user, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			fetchAuth0Info(user);
		}];
	}};

	// STEP 2 of 3:
	//
	// Fetch auth0 user profiles
	//
	fetchAuth0Info = ^void (ZDCUser *user){ @autoreleasepool {

		ZDCLogVerbose(@"fetchAuth0Info() - %@", remoteUserID);
		NSAssert(user != nil, @"Bad state");
		
		[weakSelf _fetchFilteredAuth0Profile: remoteUserID
		                         requesterID: localUserID
		                     completionQueue: concurrentQueue
		                     completionBlock:^(ZDCUserProfile *profile, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			user.identities = profile.identities;
			user.lastRefresh_profile = [NSDate date];
			
			storeUserInDatabase(user);
		}];
	}};

	// STEP 3 of 3:
	//
	// Store the user in the database (if needed).
	//
	storeUserInDatabase = ^void (ZDCUser *user){ @autoreleasepool {
		
		ZDCLogVerbose(@"storeUserInDatabase() - %@", remoteUserID);
		NSAssert(user != nil, @"Bad state");
		
		ZDCDatabaseManager *databaseManager = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				databaseManager = strongSelf->zdc.databaseManager;
			}
		}
		
		__block ZDCUser *databaseUser = nil;
		
		[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			ZDCUser *existingUser = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
			if (existingUser)
			{
				databaseUser = existingUser;
			}
			else
			{
				[transaction setObject:user forKey:user.uuid inCollection:kZDCCollection_Users];
				databaseUser = user;
			}
			
		/*	ZDCPublicKey *existingPubKey =
			  [transaction objectForKey: databaseUser.publicKeyID
			               inCollection: kZDCCollection_PublicKeys];
			
			if (!existingPubKey && pubKey)
			{
				[transaction setObject:pubKey forKey:pubKey.uuid inCollection:kZDCCollection_PublicKeys];
				
				if (![pubKey.uuid isEqualToString:databaseUser.publicKeyID])
				{
					// Two possibilities here:
					// - databaseUser.publicKey is nil
					// - databaseUser.publicKey is invalid
					
					databaseUser = [databaseUser copy];
					databaseUser.publicKeyID = pubKey.uuid;
					
					[transaction setObject: databaseUser
					                forKey: databaseUser.uuid
					          inCollection: kZDCCollection_Users];
				}
			}
		*/
			
		} completionQueue:concurrentQueue completionBlock:^{

			InvokeCompletionBlocks(databaseUser, nil);
		}];
	}};
	
	// Alternative flow for anonymous userID's
	//
	createAnonymousUser = ^{ @autoreleasepool {
		
		ZDCUser *user = [[ZDCUser alloc] initWithUUID:kZDCAnonymousUserID];
		
		// Next step
		storeUserInDatabase(user);
	}};
	
	if (isAnonymousUser) {
		createAnonymousUser();
	}
	else {
		fetchBasicInfo();
	}
}

- (void)_fetchPublicKey:(ZDCUser *)inRemoteUser
            requesterID:(NSString *)localUserID
        completionQueue:(nullable dispatch_queue_t)inCompletionQueue
        completionBlock:(nullable void (^)(ZDCUser *remoteUser, NSError *error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	ZDCUser *remoteUser = [inRemoteUser copy];
	NSString *remoteUserID = remoteUser.uuid;
	
	NSParameterAssert(remoteUser != nil);
	NSParameterAssert(remoteUserID != nil);
	NSParameterAssert(localUserID != nil);
	
	NSParameterAssert(![ZDCUser isAnonymousID:remoteUserID]);
	
	if (inCompletionBlock == nil) {
		inCompletionBlock = ^(ZDCUser *user, NSError *error){};
	}
	
	NSString *const requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), remoteUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The {inCompletionQueue, inCompletionBlock} tuple have been added to the existing request's list.
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	
	void (^InvokeCompletionBlocks)(ZDCUser*, NSError*) = ^(ZDCUser *user, NSError *error){ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[strongSelf->asyncCompletionDispatch popCompletionQueues: &completionQueues
		                                        completionBlocks: &completionBlocks
		                                                  forKey: requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCUser*, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(user, error);
			}});
		}
	}};

	__block void (^fetchPubKey)(void);
	__block void (^verifyPubKey)(ZDCPublicKey *pubKey);
	__block void (^updateDatabase)(ZDCPublicKey *pubKey);
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	// STEP 1 of 3:
	//
	// Fetch pubKey, which we deem as required information about the user.
	//
	fetchPubKey = ^void (){ @autoreleasepool {
		
		ZDCLogVerbose(@"fetchPubKey() - %@", remoteUserID);
		NSAssert(remoteUser != nil, @"Bad state");
		
		[weakSelf _fetchPubKey: remoteUser
		           requesterID: localUserID
		       completionQueue: concurrentQueue
		       completionBlock:^(ZDCPublicKey *publicKey, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			verifyPubKey(publicKey);
		}];
	}};
	
	// STEP 2 of 3:
	//
	// Attempt to verify the pubKey against the blockchain information.
	//
	verifyPubKey = ^void (ZDCPublicKey *pubKey){ @autoreleasepool {
		
		ZDCLogVerbose(@"verifyPubKey() - %@", remoteUserID);
		NSAssert(pubKey != nil, @"Bad state");
		
		[weakSelf _verifyPubKey: pubKey
		            requesterID: localUserID
		        completionQueue: concurrentQueue
		        completionBlock:^(ZDCPublicKey *publicKey, NSError *error)
		{
			// Todo...
		}];
	}};
	
	
	// STEP 2 of 2:
	//
	// Store the user & pubKey in the database (if needed).
	//
	updateDatabase = ^void (ZDCPublicKey *pubKey){ @autoreleasepool {
		
		ZDCLogVerbose(@"updateDatabase() - %@", remoteUserID);
		NSAssert(pubKey != nil, @"Bad state");
		
		YapDatabaseConnection *rwConnection = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				rwConnection = strongSelf->zdc.databaseManager.rwDatabaseConnection;
			}
		}
		
		__block ZDCUser *user = nil;
		
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			user = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
			
			ZDCPublicKey *existingPubKey =
			  [transaction objectForKey: user.publicKeyID
			               inCollection: kZDCCollection_PublicKeys];
			
			if (user && !existingPubKey && pubKey)
			{
				[transaction setObject:pubKey forKey:pubKey.uuid inCollection:kZDCCollection_PublicKeys];
				
				if (![pubKey.uuid isEqualToString:user.publicKeyID])
				{
					// Two possibilities here:
					// - databaseUser.publicKey is nil
					// - databaseUser.publicKey is invalid
					
					user = [user copy];
					user.publicKeyID = pubKey.uuid;
					
					[transaction setObject: user
					                forKey: user.uuid
					          inCollection: kZDCCollection_Users];
				}
			}
			
		} completionQueue:concurrentQueue completionBlock:^{

			InvokeCompletionBlocks(user, nil);
		}];
	}};
	
	// Start process
	fetchPubKey();
}

- (void)_refreshIdentities:(NSString *)remoteUserID
               requesterID:(NSString *)localUserID
           completionQueue:(nullable dispatch_queue_t)inCompletionQueue
           completionBlock:(nullable void (^)(ZDCUser *remoteUser, NSError *error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(remoteUserID != nil);
	NSParameterAssert(localUserID != nil);
	
	NSParameterAssert(![ZDCUser isAnonymousID:remoteUserID]);
	
	if (inCompletionBlock == nil) {
		inCompletionBlock = ^(ZDCUser *user, NSError *error){};
	}
	
	NSString *const requestKey = [NSString stringWithFormat:@"%@|%@", NSStringFromSelector(_cmd), remoteUserID];
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The {inCompletionQueue, inCompletionBlock} tuple have been added to the existing request's list.
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	
	void (^InvokeCompletionBlocks)(ZDCUser*, NSError*) = ^(ZDCUser *user, NSError *error){ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[strongSelf->asyncCompletionDispatch popCompletionQueues: &completionQueues
		                                        completionBlocks: &completionBlocks
		                                                  forKey: requestKey];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(ZDCUser*, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(user, error);
			}});
		}
	}};
	
	__block void (^fetchAuth0Info)(void);
	__block void (^updateUserInfoInDatabase)(ZDCUserProfile *profile);
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	// STEP 1 of 2:
	//
	// Fetch auth0 user profiles
	//
	fetchAuth0Info = ^void (){ @autoreleasepool {

		ZDCLogVerbose(@"fetchAuth0Info() - %@", remoteUserID);
		
		[weakSelf _fetchFilteredAuth0Profile: remoteUserID
		                         requesterID: localUserID
		                     completionQueue: concurrentQueue
		                     completionBlock:^(ZDCUserProfile *profile, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			updateUserInfoInDatabase(profile);
		}];
	}};
	
	// STEP 2 of 2:
	//
	// Updated the user's info in the database.
	//
	updateUserInfoInDatabase = ^void (ZDCUserProfile *profile){ @autoreleasepool {
		
		ZDCLogVerbose(@"storeUserInDatabase() - %@", remoteUserID);
		
		ZDCDatabaseManager *databaseManager = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				databaseManager = strongSelf->zdc.databaseManager;
			}
		}
		
		__block ZDCUser *user = nil;
		
		[databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			user = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
			if (user)
			{
				user = [user copy];
				
				user.identities = profile.identities;
				user.lastRefresh_profile = [NSDate date];
				
				[transaction setObject:user forKey:user.uuid inCollection:kZDCCollection_Users];
			}
			
		} completionQueue:concurrentQueue completionBlock:^{

			InvokeCompletionBlocks(user, nil);
		}];
	}};
	
	// Start process
	fetchAuth0Info();
}

- (void)_recheckBlockchain:(ZDCUser *)remoteUser
               requesterID:(NSString *)localUserID
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock
{
	// Todo...
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Network Operations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_fetchRemoteUser:(NSString *)remoteUserID
             requesterID:(NSString *)localUserID
         completionQueue:(dispatch_queue_t)completionQueue
         completionBlock:(void (^)(ZDCUser *_Nullable user, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	[zdc.restManager fetchInfoForRemoteUserID: remoteUserID
	                              requesterID: localUserID
	                          completionQueue: completionQueue
	                          completionBlock:^(NSDictionary *response, NSError *error)
	{
		if (error)
		{
			BOOL isUserDeletedError = NO;
			
			NSHTTPURLResponse *serverResponse = error.userInfo[AFNetworkingOperationFailingURLResponseErrorKey];
			if ([serverResponse isKindOfClass:[NSHTTPURLResponse class]])
			{
				if (serverResponse.statusCode == 404)
				{
					isUserDeletedError = YES;
				}
			}
			
			if (isUserDeletedError)
			{
				ZDCUser *user = [[ZDCUser alloc] initWithUUID:remoteUserID];
				user.accountDeleted = YES;
				
				completionBlock(user, nil);
				return;
			}
			else
			{
				completionBlock(nil, error);
				return;
			}
		}
		
		id value;
		
		AWSRegion region = AWSRegion_Invalid;
		NSString *bucket = nil;
		
		if ((value = response[@"region"]))
		{
			if ([value isKindOfClass:[NSString class]])
			{
				NSString *regionName = (NSString *)value;
				region = [AWSRegions regionForName:regionName];
			}
		}
		
		if ((value = response[@"bucket"]))
		{
			if ([value isKindOfClass:[NSString class]])
			{
				bucket = (NSString *)value;
			}
		}
		
		if (region == AWSRegion_Invalid || !bucket)
		{
			// Got a bad response from the server ?
	
			error = [ZDCUserManager errorWithStatusCode:500 description:@"Unreadable response from server"];
			
			completionBlock(nil, error);
			return;
		}
		
		ZDCUser *user = [[ZDCUser alloc] initWithUUID:remoteUserID];
		user.aws_region = region;
		user.aws_bucket = bucket;
		
		if ((value = response[@"deleted"]))
		{
			if ([value isKindOfClass:[NSNumber class]])
			{
				user.accountDeleted = [(NSNumber *)value boolValue];
			}
		}

		completionBlock(user, nil);
	}];
}

- (void)_fetchFilteredAuth0Profile:(NSString *)remoteUserID
                       requesterID:(NSString *)localUserID
                   completionQueue:(dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(ZDCUserProfile *profile, NSError *error))completionBlock
{
	[zdc.restManager fetchFilteredAuth0Profile: remoteUserID
	                               requesterID: localUserID
	                           completionQueue: completionQueue
	                           completionBlock:^(NSURLResponse *urlResponse, id responseObject, NSError *error)
	{
		if (error)
		{
			completionBlock(nil, error);
			return;
		}
		
		NSInteger statusCode = urlResponse.httpStatusCode;
		if (statusCode != 200)
		{
			error = [ZDCUserManager errorWithStatusCode:statusCode description:@"Unexpected statusCode"];
			
			completionBlock(nil, error);
			return;
		}
		
		NSDictionary *dict = nil;
		
		if ([responseObject isKindOfClass:[NSArray class]])
		{
			NSArray *resultsArray = (NSArray *)responseObject;
			NSDictionary *result = [resultsArray firstObject];
			
			if ([result isKindOfClass:[NSDictionary class]]) {
				dict = (NSDictionary *)result;
			}
		}
		else if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			dict = (NSDictionary *)responseObject;
			NSString *errMsg = dict[@"errorMessage"];
			
			if (errMsg)
			{
				error = [ZDCUserManager errorWithStatusCode:0 description:errMsg];
				
				completionBlock(nil, error);
				return;
			}
		}
		else
		{
			error = [ZDCUserManager errorWithStatusCode:0 description:@"Bad responseObject"];
			
			completionBlock(nil, error);
			return;
		}
		
		ZDCUserProfile *profile = [[ZDCUserProfile alloc] initWithDictionary:dict];
		
		completionBlock(profile, nil);
	}];
}

- (void)_fetchPubKey:(ZDCUser *)remoteUser
         requesterID:(NSString *)localUserID
     completionQueue:(dispatch_queue_t)completionQueue
     completionBlock:(void (^)(ZDCPublicKey *publicKey, NSError *error))completionBlock
{
	[zdc.networkTools downloadDataAtPath: kZDCCloudFileName_PublicKey
	                            inBucket: remoteUser.aws_bucket
	                              region: remoteUser.aws_region
	                            withETag: nil
	                               range: nil
	                         requesterID: localUserID
	                       canBackground: NO
	                     completionQueue: completionQueue
	                     completionBlock:^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (error)
		{
			completionBlock(nil, error);
			return;
		}

		ZDCPublicKey *pubKey = nil;
		
		if ([responseObject isKindOfClass:[NSString class]])
		{
			NSString *pubKeyJSON = (NSString *)responseObject;
			pubKey = [[ZDCPublicKey alloc] initWithUserID:remoteUser.uuid pubKeyJSON:pubKeyJSON];
		}
		else if ([responseObject isKindOfClass:[NSData class]])
		{
			NSData *data = (NSData *)responseObject;
			NSString *pubKeyJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			pubKey = [[ZDCPublicKey alloc] initWithUserID:remoteUser.uuid pubKeyJSON:pubKeyJSON];
		}
		else if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *pubKeyDict = (NSDictionary *)responseObject;
			pubKey = [[ZDCPublicKey alloc] initWithUserID: remoteUser.uuid
			                                   pubKeyDict: pubKeyDict
			                                  privKeyDict: nil];
		}
			
		if (![pubKey checkKeyValidityWithError:nil])
		{
			error = [ZDCUserManager errorWithStatusCode:0 description:@"Unreadable pubKey for user"];
				
			completionBlock(nil, error);
			return;
		}
		
		completionBlock(pubKey, nil);
	}];
}

- (void)_verifyPubKey:(ZDCPublicKey *)pubKey
          requesterID:(NSString *)localUserID
      completionQueue:(dispatch_queue_t)completionQueue
      completionBlock:(void (^)(ZDCPublicKey *publicKey, NSError *error))completionBlock
{
	[zdc.blockchainManager fetchBlockchainInfoForUserID: pubKey.userID
	                                        requesterID: localUserID
	                                    completionQueue: completionQueue
	                                    completionBlock:^(NSError * _Nonnull error)
	{
		// Todo...
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSError *)errorWithStatusCode:(NSInteger)statusCode description:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:statusCode userInfo:userInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sorting
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<ZDCUserDisplay*> *)sortedUnambiguousNamesForUsers:(NSArray<ZDCUser*> *)users
{
	NSString *const k_userID      = @"userID";
	NSString *const k_displayName = @"displayName";
	NSString *const k_provider    = @"provider";
	
	NSMutableDictionary *sorted = [NSMutableDictionary dictionary]; // key=displayName, value=NSMutableArray<info>
	
	for (ZDCLocalUser *user in users)
	{
		NSString *displayName = user.displayName;
		
		ZDCUserIdentity *displayIdentity = user.displayIdentity;
		NSString *provider = displayIdentity ? displayIdentity.provider : @"";
		
		NSDictionary *info = @{
			k_userID      : user.uuid,
			k_displayName : displayName,
			k_provider    : provider
		};
		
		NSMutableArray *list = sorted[displayName];
		if (list == nil)
		{
			list = [NSMutableArray arrayWithCapacity:1];
			sorted[displayName] = list;
		}
		
		[list addObject:info];
	}
	
	NSMutableArray<ZDCUserDisplay *> *results = [NSMutableArray arrayWithCapacity:users.count];
	
	for (NSString *displayName in sorted)
	{
		NSArray *list = sorted[displayName];
		
		if (list.count == 1)
		{
			// No conflicts
			
			NSDictionary *info = list[0];
			NSString *userID      = info[k_userID];
			NSString *displayName = info[k_displayName];
			
			ZDCUserDisplay *result = [[ZDCUserDisplay alloc] initWithUserID:userID displayName:displayName];
			[results addObject:result];
		}
		else
		{
			// The displayName needs disambiguation
			
			NSMutableDictionary *byProvider = [NSMutableDictionary dictionaryWithCapacity:list.count];
	
			for (NSDictionary *info in list)
			{
				NSString *provider = info[k_provider];
	
				NSMutableArray *subList = byProvider[provider];
				if (subList == nil)
				{
					subList = [NSMutableArray arrayWithCapacity:1];
					byProvider[provider] = subList;
				}
	
				[subList addObject:info];
			}
			
			for (NSString *provider in byProvider)
			{
				NSArray *subList = byProvider[provider];
		
				if (subList.count == 1)
				{
					// Append the provider: "John Doe (GitHub)"
		
					NSDictionary *info = subList[0];
					NSString *userID      = info[k_userID];
					NSString *displayName = info[k_displayName];
					NSString *provider    = info[k_provider];
					
					displayName = [displayName stringByAppendingFormat:@" (%@)", provider];
					
					ZDCUserDisplay *result = [[ZDCUserDisplay alloc] initWithUserID:userID displayName:displayName];
					[results addObject:result];
				}
				else
				{
					// Append the provider & count: "John Doe (GitHub-1)"
					
					[subList enumerateObjectsUsingBlock:^(NSDictionary *info, NSUInteger idx, BOOL *stop) {
						
						NSString *userID      = info[k_userID];
						NSString *displayName = info[k_displayName];
						NSString *provider    = info[k_provider];
						
						displayName = [displayName stringByAppendingFormat:@" (%@-%lu)", provider, (unsigned long)(idx+1)];
						
						ZDCUserDisplay *result = [[ZDCUserDisplay alloc] initWithUserID:userID displayName:displayName];
						[results addObject:result];
					}];
				}
			}
		}
	}
	
	[results sortUsingComparator:^NSComparisonResult(ZDCUserDisplay *item1, ZDCUserDisplay *item2) {
		
		NSString *name1 = item1.displayName;
		NSString *name2 = item2.displayName;
		
		return [name1 localizedStandardCompare:name2];
	}];
	
	return results;
}

@end
