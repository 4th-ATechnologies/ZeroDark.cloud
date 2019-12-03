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
#pragma mark External API
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
		
		BOOL needsDownload = NO;
		BOOL needsRefresh = NO;
		
		if (user)
		{
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
					completionBlock(user, nil);
				}});
			}
			
			// Todo: add logic for needsRefresh
		}
		else
		{
			needsDownload = YES;
		}
		
		if (needsDownload)
		{
			[weakSelf _fetchRemoteUserWithID: remoteUserID
			                     requesterID: localUserID
			                 completionQueue: completionQueue
			                 completionBlock: completionBlock];
		}
		else if (needsRefresh)
		{
			[weakSelf _fetchRemoteUserWithID: remoteUserID
			                     requesterID: localUserID
			                 completionQueue: nil
			                 completionBlock: nil];
		}
	}];
}

- (void)createUserFromResult:(ZDCSearchResult *)inSearchResult
                 requesterID:(NSString *)inLocalUserID
             completionQueue:(nullable dispatch_queue_t)completionQueue
             completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(inSearchResult != nil);
	NSParameterAssert(inLocalUserID != nil);
	
	ZDCSearchResult *searchResult = [inSearchResult copy];
	NSString *remoteUserID = searchResult.userID;
	NSString *localUserID = [inLocalUserID copy];
	
	void (^InvokeCompletionBlock)(ZDCUser*, NSError*) = ^(ZDCUser *user, NSError *error){
		
		if (completionBlock == nil) return;
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			
			completionBlock(user, error);
		}});
	};
	
	ZDCUser *user = [[ZDCUser alloc] initWithUUID:remoteUserID];
	user.aws_region = searchResult.aws_region;
	user.aws_bucket = searchResult.aws_bucket;
	
	user.identities = searchResult.identities;
	user.preferredIdentityID = searchResult.preferredIdentityID;
	user.lastRefresh_profile = [NSDate date];
	
	__weak typeof(self) weakSelf = self;
	
	__block void (^fetchPubKey)(void);
	__block void (^storeInfoInDatabase)(ZDCPublicKey *pubKey);
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	// STEP 1 of 2:
	//
	// Fetch pubKey, which we deem as required information about the user.
	//
	fetchPubKey = ^void (){ @autoreleasepool {
		
		ZDCLogVerbose(@"fetchPubKey() - %@", remoteUserID);
		NSAssert(user != nil, @"Bad state");
		
		[weakSelf _fetchPubKey: user
		           requesterID: localUserID
		       completionQueue: concurrentQueue
		       completionBlock:^(ZDCPublicKey *publicKey, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			user.publicKeyID = publicKey.uuid;
			
			storeInfoInDatabase(publicKey);
		}];
	}};
	
	// STEP 2 of 2:
	//
	// Store the user & pubKey in the database (if needed).
	//
	storeInfoInDatabase = ^void (ZDCPublicKey *pubKey){ @autoreleasepool {
		
		ZDCLogVerbose(@"storeUserInDatabase() - %@", remoteUserID);
		
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
			
			ZDCPublicKey *existingPubKey =
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
			
		} completionQueue:concurrentQueue completionBlock:^{

			InvokeCompletionBlock(databaseUser, nil);
		}];
	}};
	
	// Start process
	fetchPubKey();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Download Control
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal method that handles the download flow.
 */
- (void)_fetchRemoteUserWithID:(NSString *)inRemoteUserID
                   requesterID:(NSString *)inLocalUserID
               completionQueue:(nullable dispatch_queue_t)inCompletionQueue
               completionBlock:(nullable void (^)(ZDCUser *remoteUser, NSError *error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(inRemoteUserID != nil);
	NSParameterAssert(inLocalUserID != nil);
	
	NSString *remoteUserID = [inRemoteUserID copy];
	NSString *localUserID = [inLocalUserID copy];
	
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
	
	NSString *const requestKey = [NSString stringWithFormat:@"createUser|%@", remoteUserID];
	
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
	__block void (^fetchPubKey)(ZDCUser *user);
	__block void (^storeInfoInDatabase)(ZDCUser *user, ZDCPublicKey *pubKey);
	__block void (^createAnonymousUser)(void);
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	// STEP 1 of 4:
	//
	// Fetch basic info about the user including:
	// - region
	// - bucket
	//
	fetchBasicInfo = ^(){ @autoreleasepool {
		
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

	// STEP 2 of 4:
	//
	// Fetch auth0 user profiles
	//
	fetchAuth0Info = ^void (ZDCUser *user){ @autoreleasepool {

		ZDCLogVerbose(@"fetchAuth0Info() - %@", remoteUserID);
		NSAssert(user != nil, @"Bad state");
		
		[weakSelf _fetchFilteredAuth0Profile: user
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
			
			fetchPubKey(user);
		}];
	}};

	// STEP 3 of 4:
	//
	// Fetch pubKey, which we deem as required information about the user.
	//
	fetchPubKey = ^void (ZDCUser *user){ @autoreleasepool {
		
		ZDCLogVerbose(@"fetchPubKey() - %@", remoteUserID);
		NSAssert(user != nil, @"Bad state");
		
		[weakSelf _fetchPubKey: user
		           requesterID: localUserID
		       completionQueue: concurrentQueue
		       completionBlock:^(ZDCPublicKey *publicKey, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlocks(nil, error);
				return;
			}
			
			user.publicKeyID = publicKey.uuid;
			
			storeInfoInDatabase(user, publicKey);
		}];
	}};

	// STEP 4 of 4:
	//
	// Store the user & pubKey in the database (if needed).
	//
	storeInfoInDatabase = ^void (ZDCUser *user, ZDCPublicKey *pubKey){ @autoreleasepool {
		
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
			
			ZDCPublicKey *existingPubKey =
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
			
		} completionQueue:concurrentQueue completionBlock:^{

			InvokeCompletionBlocks(databaseUser, nil);
		}];
	}};
	
	// Alternative flow for anonymous userID's
	//
	createAnonymousUser = ^{ @autoreleasepool {
		
		ZDCUser *user = [[ZDCUser alloc] initWithUUID:kZDCAnonymousUserID];
		
		// Next step
		storeInfoInDatabase(user, nil);
	}};
	
	if (isAnonymousUser) {
		createAnonymousUser();
	}
	else {
		fetchBasicInfo();
	}
}

/**
 * Internal method that handles the download flow.
 */
- (void)fetchPublicKeyForRemoteUserID:(NSString *)inRemoteUserID
                          requesterID:(NSString *)inLocalUserID
                      completionQueue:(dispatch_queue_t)inCompletionQueue
                      completionBlock:(void (^)(ZDCPublicKey *_Nullable pubKey, NSError *_Nullable error))inCompletionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(inRemoteUserID != nil);
	NSParameterAssert(inLocalUserID != nil);
    
	NSString *remoteUserID = [inRemoteUserID copy];
	NSString *localUserID = [inLocalUserID copy];
	
	NSString *requestKey = [NSString stringWithFormat:@"fetchKey|%@", remoteUserID];
	ZDCAsyncCompletionDispatch *asyncCompletionDispatch = self->asyncCompletionDispatch;
	
	NSUInteger requestCount =
	  [asyncCompletionDispatch pushCompletionQueue: inCompletionQueue
	                               completionBlock: inCompletionBlock
	                                        forKey: requestKey];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <inCompletionQueue, inCompletionBlock> have been added to the existing request's list.
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	
	void (^InvokeCompletionBlocks)(ZDCPublicKey*, NSError*) = ^(ZDCPublicKey *pubKey, NSError *error) {
		
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
			void (^completionBlock)(ZDCPublicKey*, NSError*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(pubKey, error);
			}});
		}
	};
    
	__block void (^fetchBasicInfo)(void);
	__block void (^fetchPubKey)(ZDCUser *user);
    
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	// STEP 1 of 2:
	//
	// Fetch basic info about the user including:
	// - region
	// - bucket
	//
	fetchBasicInfo = ^{ @autoreleasepool {
		
		ZDCLogVerbose(@"fetchBasicInfo() - %@", remoteUserID);
		
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
			
			fetchPubKey(user);
		}];
	}};
    
	// STEP 2 of 2:
	//
	// Fetch the requested publicKey.
	//
	fetchPubKey = ^void (ZDCUser *user){ @autoreleasepool {
        
		ZDCLogVerbose(@"fetchPubKey() - %@", remoteUserID);
		NSAssert(user != nil, @"Bad state");
		
		[weakSelf _fetchPubKey: user
		           requesterID: localUserID
		       completionQueue: concurrentQueue
		       completionBlock:^(ZDCPublicKey *publicKey, NSError *error)
		{
			InvokeCompletionBlocks(publicKey, error);
		}];
	}};
	
	fetchBasicInfo();
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

- (void)_fetchFilteredAuth0Profile:(ZDCUser *)remoteUser
                       requesterID:(NSString *)localUserID
                   completionQueue:(dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(ZDCUserProfile *profile, NSError *error))completionBlock
{
	[zdc.restManager fetchFilteredAuth0Profile: remoteUser.uuid
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
