/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "AccountSetup_Base.h"

#import "Auth0Utilities.h"
#import "CredentialsManager.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLocalUser.h"
#import "ZDCLocalUserAuth.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCUserPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSDate+ZeroDark.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

#define MUST_IMPLEMENT_IN_SUBCLASS                                                                                    \
 @throw [NSException exceptionWithName: NSInternalInconsistencyException                                  \
                                reason: [NSString stringWithFormat:@"You must override %@ in a subclass", \
                                          NSStringFromSelector(_cmd)] userInfo:nil];


#if TARGET_OS_IPHONE

@implementation ZDCAccountSetupViewControllerProxy

-(void)pushCreateAccount
{
	if([self isKindOfClass:[AccountSetup_Base class]])
	{
		AccountSetup_Base *base = (AccountSetup_Base*) self;
		[base pushCreateAccount];
	}
}

-(void)pushSignInToAccount
{
	if([self isKindOfClass:[AccountSetup_Base class]])
	{
		AccountSetup_Base *base = (AccountSetup_Base*) self;
		[base pushSignInToAccount];
	}
}
@end

#endif


@implementation AccountSetup_Base

@synthesize zdc = zdc;
@synthesize setupMode = setupMode;
@synthesize identityMode = identityMode;
@synthesize selectedProvider = selectedProvider;
@synthesize userProfile = userProfile;
@synthesize privKeyData = privKeyData;
@synthesize activationEmail = activationEmail;

@synthesize auth = auth;
@synthesize user = user;
@synthesize privKey = privKey;
@synthesize accessKey = accessKey;


-(void)resetAll
{
	selectedProvider    = nil;
	userProfile         = nil;
	activationEmail     = nil;
	auth                = nil;
	privKey             = nil;
	accessKey           = nil;
	identityMode        = IdenititySelectionMode_NewAccount;
}


- (NSError *)errorWithDescription:(NSString *)description statusCode:(NSUInteger)statusCode
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:statusCode userInfo:userInfo];
}


- (NSError *)errorOperationCanceled
{
	
	NSString *domain = NSStringFromClass([self class]);
	
	return [NSError errorWithDomain:domain
										code:NSURLErrorCancelled
								  userInfo:@{ NSLocalizedDescriptionKey: @"User Canceled Operation" }];
}


-(void) handleFail    // prototype method
{
	NSAssert(true, @"handleFail function must be overide  - implemention error");
}

-(void) handleInternalError:(NSError*)error
{
	[self showError:@"Internal Error"
			  message:error.localizedDescription completionBlock:^{
				  
				  [self handleFail];
			  }];
	
}

-(BOOL)isAlreadyLinkedError:(NSError*)error
{
	BOOL alreadyLinked = NO;
	
	if([error.domain isEqualToString:AFURLResponseSerializationErrorDomain])
	{
		NSHTTPURLResponse* response = [[error userInfo] objectForKey:AFNetworkingOperationFailingURLResponseErrorKey];
		
		if(response && [response isKindOfClass:[NSHTTPURLResponse class]])
		{
			NSInteger statusCode = response.statusCode;
			if(statusCode == 400 && error.code == -1011)
			{
				alreadyLinked = YES;
			}
			
		}
	}
	
	return alreadyLinked;
}

-(void) showWait:(NSString* __nonnull)title
			message:(NSString* __nullable)message
 completionBlock:(dispatch_block_t __nullable)completionBlock
{
	MUST_IMPLEMENT_IN_SUBCLASS
	
}

-(void) cancelWait
{
	MUST_IMPLEMENT_IN_SUBCLASS
	
}

-(void) popFromCurrentView
{
	MUST_IMPLEMENT_IN_SUBCLASS
	
}

-(void) showError:(NSString* __nonnull)title
			 message:(NSString* __nullable)message
  completionBlock:(dispatch_block_t __nullable)completionBlock
{
	MUST_IMPLEMENT_IN_SUBCLASS
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)commonInitWithUserID:(NSString *)userID error:(NSError **)errorOut
{
	NSError* error = NULL;
	BOOL    sucess = NO;
	
	YapDatabaseConnection *roConnection = zdc.databaseManager.roDatabaseConnection;
	[roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCUser* thisUser = nil;
		
		thisUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		if(thisUser.isLocal)
		{
			self.user = (ZDCLocalUser*)thisUser;
			self.auth = [transaction objectForKey:thisUser.uuid inCollection:kZDCCollection_UserAuth];
		}
	}];
	
	if(!user || !auth )
		error = [self errorWithDescription:@"Internal param error" statusCode:500] ;
	else
		sucess = YES;
	
	if(errorOut)
		*errorOut = error;
	
	return sucess;
	
}


- (ZDCLocalUser *)localUserForUserID:(NSString *)userID
{
	__block ZDCLocalUser *result = nil;
	[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
		if (user.isLocal) {
			result = (ZDCLocalUser *)user;
		}
	}];
	
	return result;
}

- (ZDCLocalUser *)localUserForAuth0ID:(NSString *)auth0ID
{
	ZDCLocalUserManager *localUserManager = zdc.localUserManager;
	
	__block ZDCLocalUser *result = nil;
	[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[localUserManager enumerateLocalUsersWithTransaction: transaction
		                                          usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
		{
			if ([localUser identityWithID:auth0ID] != nil)
			{
				result = localUser;
				*stop = YES;
			}
		}];
	}];
	
	return result;
}


- (void)saveLocalUserAndAuthWithCompletion:(dispatch_block_t)completionBlock
{
	NSParameterAssert(user != nil);
	NSParameterAssert(auth != nil);
	
	ZDCLocalUser *_user = [user copy];
	ZDCLocalUserAuth *_auth = [auth copy];
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCLocalUser *existingUser = [transaction objectForKey:_user.uuid inCollection:kZDCCollection_Users];
		if (existingUser)
		{
			if ([existingUser isKindOfClass:[ZDCLocalUser class]])
			{
				existingUser = [existingUser copy];
			}
			else // Need to convert from S4User to S4LocalUser
			{
				ZDCLocalUser *localUser = [[ZDCLocalUser alloc] initWithUUID:existingUser.uuid];
				[existingUser copyTo:localUser];
				
				existingUser = localUser;
			}
			
			// Merge values from _user
			
			existingUser.aws_bucket          = _user.aws_bucket;
			existingUser.aws_region          = _user.aws_region;
			existingUser.activationDate      = _user.activationDate;
			existingUser.syncedSalt          = _user.syncedSalt;
			existingUser.aws_stage           = _user.aws_stage;
			existingUser.isPayingCustomer    = _user.isPayingCustomer;
			existingUser.lastRefresh_profile = _user.lastRefresh_profile;
			existingUser.identities          = _user.identities;
			
			// copy the preferred if it isnt set yet
			if (!existingUser.preferredIdentityID && _user.preferredIdentityID) {
				existingUser.preferredIdentityID = _user.preferredIdentityID;
			}
		}
		else
		{
			existingUser = _user;
		}
		
		[transaction setObject: existingUser
							 forKey: existingUser.uuid
					 inCollection: kZDCCollection_Users];
		
		[transaction setObject: _auth
							 forKey: existingUser.uuid
					 inCollection: kZDCCollection_UserAuth];
		
	} completionBlock:^{
		
		if(completionBlock)
			completionBlock();
	}];
}



/*
 tell the server that we are using this owner.treeID, and to do whatever
 activation is needed.. if this is a new user we will care about things like
 synced salt and bucket creation
 */
- (void)setupUserOnServerWithCompletion:(void (^)(NSError *error))completionBlock
{
	NSParameterAssert(user != nil);
	NSParameterAssert(auth != nil);
	
	void (^invokeCompletionBlock)(NSError * error) = ^(NSError * error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(error);
			});
		}
	};
	
	__weak typeof(self) weakSelf = self;
	
	// in case this user has never registered this app.
	[zdc.restManager setupAccountForLocalUser: self.user
	                                 withAuth: self.auth
	                                  treeIDs: @[zdc.primaryTreeID]
	                          completionQueue: nil
									completionBlock:^(NSString * _Nullable bucket,
																NSString *_Nullable stage,
																NSString *_Nullable syncedSalt,
																NSDate *_Nullable activationDate,
																NSError * _Nullable error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;
		 
		 if(error)
		 {
			 invokeCompletionBlock(error);
			 return;
		 }
		 
		 __block ZDCLocalUser*  localUser  = nil;
		 
		 [strongSelf->zdc.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			 
			 __strong typeof(self) strongSelf = weakSelf;
			 if (!strongSelf) return;
			 
			 localUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
			 localUser = localUser.copy;
			 
			 // should we overwrite the bucket?  shouldnt be an issue
			 localUser.aws_bucket = bucket;
			 localUser.aws_stage = stage;
			 
			 localUser.syncedSalt = syncedSalt;
			 localUser.activationDate = activationDate;
			 
			 [transaction setObject:localUser
								  forKey:localUser.uuid
						  inCollection:kZDCCollection_Users];
			 
			 strongSelf->user = localUser;
			 
		 } completionBlock:^{
			 
			 invokeCompletionBlock(nil);
		}];
	}];
}

- (ZDCLocalUser *)createLocalUserFromProfile:(ZDCUserProfile *)profile
{
	NSString *userID = profile.appMetadata_awsID;
	if (userID == nil)
	{
		ZDCLogWarn(@"profile is missing required info: app_metadata.aws_id");
		return nil;
	}
	
	ZDCLocalUser *user = [[ZDCLocalUser alloc] initWithUUID:userID];
	
	AWSRegion region = [AWSRegions regionForName:profile.appMetadata_region];
	NSString *bucket = profile.appMetadata_bucket;
	
	// If we're creating a new users, the user won't have a region/bucket at this point.
	
	user.aws_region = region;
	user.aws_bucket = bucket;
	user.lastRefresh_profile = [NSDate date];
	
	user.identities = profile.identities;
	user.auth0_primary = profile.userID;
	
	return user;
}

// MARK: database login
// for an existing account - attempt to login to database account

- (void)databaseAccountCreateWithUserName:(NSString *)username
                                 password:(NSString *)password
                          completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(username != nil);
	NSParameterAssert(password != nil);
	NSParameterAssert(completionBlock != nil);
#else
	if (completionBlock == nil) return;
#endif
	
	void (^InvokeCompletionBlock)(AccountState, NSError*) = ^(AccountState accountState, NSError *error){
		
		if ([NSThread isMainThread])
		{
			completionBlock(accountState, error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(accountState, error);
			});
		}
	};
	
	Auth0APIManager *auth0APIManager = [Auth0APIManager sharedInstance];
	CredentialsManager *credentialsManager = zdc.credentialsManager;
	
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__weak typeof(self) weakSelf = self;
	[auth0APIManager createUserWithEmail: [Auth0Utilities create4thAEmailForUsername:username]
	                            username: username
	                            password: password
	                     auth0Connection: kAuth0DBConnection_UserAuth
	                      completionQueue: backgroundQueue
	                      completionBlock:^(NSString *auth0ID, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		if (error)
		{
			if (strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
				InvokeCompletionBlock(AccountState_LinkingID, error);
			else
				InvokeCompletionBlock(AccountState_CreationFail, error);
			
			return;
		}
		
		[auth0APIManager loginAndGetProfileWithUsername: username
		                                       password: password
		                                auth0Connection: kAuth0DBConnection_UserAuth
		                                completionQueue: backgroundQueue
		                                completionBlock:^(Auth0LoginProfileResult *result, NSError *error)
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			  
			if (error)
			{
				if (strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
					InvokeCompletionBlock(AccountState_LinkingID,error);
				else
					InvokeCompletionBlock(AccountState_CreationFail,error);
				
				return;
			}
			
			[credentialsManager fetchAWSCredentialsWithJWT: result.idToken
			                                         stage: @"prod"
			                               completionQueue: backgroundQueue
			                               completionBlock:^(NSDictionary *delegation, NSError *error)
			{
				__strong typeof(self) strongSelf = weakSelf;
				if (strongSelf == nil) return;
				
				if (error)
				{
					// The account signup succeeded, but the request to fetch AWS credentials failed.
					// This is an odd edge case.
					
					if (strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
						InvokeCompletionBlock(AccountState_LinkingID,error);
					else
						InvokeCompletionBlock(AccountState_CreationFail,error);
					
					return;
				}
				
				ZDCLocalUserAuth* localUserAuth = nil;
				
				BOOL parseSuccess =
				  [credentialsManager parseLocalUserAuth: &localUserAuth
				                          fromDelegation: delegation
				                            refreshToken: result.refreshToken
				                                 idToken: result.idToken];
				
				if (!parseSuccess)
				{
					// The account signup succeeded, but the the  AWS credentials didnt parse.
					// This is an odd edge case.
					
					error = [self errorWithDescription:@"AWSCredentialsManager file" statusCode:0];
					
					if(self.identityMode == IdenititySelectionMode_ExistingAccount)
						InvokeCompletionBlock(AccountState_LinkingID,error);
					else
						InvokeCompletionBlock(AccountState_CreationFail,error);
					
					return;
				}
				
				if (strongSelf->identityMode == IdenititySelectionMode_NewAccount)
				{
					// acccount was created.
					
					// Save what we know so far
					strongSelf->userProfile = result.profile;
					strongSelf->auth        = localUserAuth;
					strongSelf->user        = [self createLocalUserFromProfile:result.profile];
					
					[strongSelf saveLocalUserAndAuthWithCompletion:^{
						InvokeCompletionBlock(AccountState_NeedsRegionSelection, nil);
					}];
				}
				else if (strongSelf->identityMode == IdenititySelectionMode_ExistingAccount)
				{
					// add this profile
					[strongSelf linkProfile: result.profile
					          toLocalUserID: strongSelf->user.uuid
					        completionQueue: dispatch_get_main_queue()
					        completionBlock:^(NSError * _Nonnull error)
					{
						InvokeCompletionBlock(AccountState_LinkingID, error);
					}];
				}
				else
				{
					error = [self errorWithDescription:@"Internal state error" statusCode:500];
					InvokeCompletionBlock(AccountState_CreationFail, error);
				}
					
			}];
		}];
	}];
}

// for an existing account - attempt to login to database account

- (void)databaseAccountLoginWithUsername:(NSString *)username
                                password:(NSString *)password
                         completionBlock:(void (^)(AccountState accountState, NSError *error))completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(username != nil);
	NSParameterAssert(password != nil);
	NSParameterAssert(completionBlock != nil);
#else
	if (completionBlock == nil) return;
#endif
	
	void (^InvokeCompletionBlock)(AccountState, NSError*) = ^(AccountState accountState, NSError *error){
		
		if ([NSThread isMainThread])
		{
			completionBlock(accountState, error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(accountState, error);
			});
		}
	};
	
	Auth0APIManager *auth0APIManager = [Auth0APIManager sharedInstance];
	CredentialsManager *credentialsManager = zdc.credentialsManager;
	
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__weak typeof(self) weakSelf = self;
	[auth0APIManager loginAndGetProfileWithUsername: username
	                                       password: password
	                                auth0Connection: kAuth0DBConnection_UserAuth
	                                completionQueue: backgroundQueue
	                                completionBlock:^(Auth0LoginProfileResult *result, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		 
		if (error)
		{
			if (strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
				InvokeCompletionBlock(AccountState_LinkingID, error);
			else
				InvokeCompletionBlock(AccountState_CreationFail, error);
			
			return;
		}
		 
		// Did the user attempt to reauthoize with an account that isn't linked ?
		//
		if (strongSelf.identityMode == IdenititySelectionMode_ReauthorizeAccount
		 && ![strongSelf.user.uuid isEqual:result.profile.appMetadata[@"aws_id"]])
		{
			NSString *msg = @"This identity is not linked to your account.";
			error = [self errorWithDescription:msg statusCode:0];
			
			InvokeCompletionBlock(AccountState_Reauthorized, error);
			return;
		}
		
		[credentialsManager fetchAWSCredentialsWithJWT: result.idToken
		                                         stage: @"prod"
		                               completionQueue: backgroundQueue
		                               completionBlock:^(NSDictionary *delegation, NSError *error)
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
				  
			if (error)
			{
				if (strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
					InvokeCompletionBlock(AccountState_LinkingID,error);
				else
					InvokeCompletionBlock(AccountState_CreationFail,error);
				
				return;
			}
			
			ZDCLocalUserAuth *newAuth = nil;
			
			BOOL parseSuccess =
			  [credentialsManager parseLocalUserAuth: &newAuth
			                          fromDelegation: delegation
			                            refreshToken: result.refreshToken
			                                 idToken: result.idToken];
			
			if (!parseSuccess)
			{
				// The login succeeded, but the the AWS credentials didn't parse.
				// This is an odd edge case.
				
				error = [self errorWithDescription:@"AWSCredentialsManager file" statusCode:0];
				
				if (self.identityMode == IdenititySelectionMode_ExistingAccount)
					InvokeCompletionBlock(AccountState_LinkingID, error);
				else
					InvokeCompletionBlock(AccountState_CreationFail, error);
				
				return;
			}
			
			if (strongSelf.identityMode == IdenititySelectionMode_NewAccount)
			{
				[strongSelf startUserCreationWithAuth: newAuth
				                              profile: result.profile
				                      completionBlock: completionBlock];
			}
			else if (strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
			{
				[strongSelf linkProfile: result.profile
				          toLocalUserID: strongSelf->user.uuid
				        completionQueue: dispatch_get_main_queue()
				        completionBlock:^(NSError *error)
				{
					
					InvokeCompletionBlock(AccountState_LinkingID,error);
				}];
			}
			else if (strongSelf.identityMode == IdenititySelectionMode_ReauthorizeAccount)
			{
				[strongSelf reauthorizeUserID: strongSelf->user.uuid
				             withRefreshToken: newAuth.coop_refreshToken
				              completionBlock:^(NSError *error)
				{
													 
					InvokeCompletionBlock(AccountState_Reauthorized,error);
				}];
			}
			else
			{
				error = [self errorWithDescription:@"Internal state error" statusCode:500];
				InvokeCompletionBlock(AccountState_CreationFail, error);
			}
		}];
	
	}];
}



// MARK: social account login
// entrypoint for 
- (void)socialAccountLoginWithAuth:(ZDCLocalUserAuth *)localUserAuth
                           profile:(ZDCUserProfile *)profile
                   completionBlock:(void (^)(AccountState accountState, NSError * error))completionBlock
{
	[self startUserCreationWithAuth: localUserAuth
	                        profile: profile
	                completionBlock: completionBlock];
}


// MARK: continuing user setup
-(void) continueUserSetupWithCompletionBlock:(void (^)(AccountState accountState, NSError * error))completionBlock
{
	__weak typeof(self) weakSelf = self;

	void (^InvokeCompletionBlock)(AccountState, NSError*) =
	^(AccountState accountState, NSError *error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(accountState,error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(accountState,error);
			});
		}
	};
	
	NSParameterAssert(completionBlock);
	NSParameterAssert(user != nil);
	NSParameterAssert(auth != nil);
	
	// waiting for region
	if(user.aws_region == AWSRegion_Invalid)
	{
		InvokeCompletionBlock(AccountState_NeedsRegionSelection,nil);
		return;
	}
	
	// we might never created a key or have failed to unlock in the past
	// either way we will reset our privkey and try again.
	
	if((user.aws_bucket.length == 0)
		||  (user.accessKeyID.length == 0)
		||  (user.publicKeyID.length == 0))
	{
		[self setupUserOnServerWithCompletion:^(NSError *error) {
			
			
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;

			if (error)
			{
				InvokeCompletionBlock(AccountState_CreationFail,error);
				return;
			}
			
			[strongSelf->zdc.localUserManager setupPubPrivKeyForLocalUser: strongSelf->user
																	 withAuth: strongSelf->auth
															completionQueue: dispatch_get_main_queue()
															completionBlock:^(NSData *pkData, NSError *error)
			 {
				 __strong typeof(self) strongSelf = weakSelf;
				 if(!strongSelf) return;

				 // did key creation or upload fail?
				 if(error)
				 {
					 InvokeCompletionBlock(AccountState_CreationFail,error);
				 }
				 // user is setup and has priv key on server
				 else if(pkData)
				 {
					 // we need to unlock the key
					 strongSelf->privKeyData = pkData;
					 InvokeCompletionBlock(AccountState_NeedsCloneClode,nil);
				 }
				 // user is setup and privkey has been loaded to server
				 else
				 {
					 if(!strongSelf->user.hasRecoveryConnection )
					 {
						 [strongSelf finalizeLocalUserWithCompletion:^{
							 InvokeCompletionBlock(AccountState_Ready,nil);
						 }];
						 
					 }
					 else
						 InvokeCompletionBlock(AccountState_Ready,nil);
				 }
			 }];
			
		}];
	}
	else if(user.accountNeedsA0Token)
	{
		InvokeCompletionBlock(AccountState_NeedsReauthentication,nil);
	}
	else if(!user.hasRecoveryConnection )
	{
		[self finalizeLocalUserWithCompletion:^{
			InvokeCompletionBlock(AccountState_Ready,nil);
		}];
		return ;
	}
	else
	{
		// nothing needs to be done?
		InvokeCompletionBlock(AccountState_Ready,nil);
	}
}

//MARK: resume and reauthoririze

-(void) resumeActivationForUserID:(NSString*)userID
				  cancelOperationFlag:(BOOL*)cancelOperationFlag
						completionBlock:(void (^)(NSError *error))completionBlock

{
//	BOOL (^testForCancel)(void) = ^BOOL(){
//		
//		if(cancelOperationFlag && (*cancelOperationFlag == YES))
//		{
//			if (completionBlock == nil) return(YES);
//			
//			NSError* abortError = [self errorOperationCanceled];
//			
//			if ([NSThread isMainThread])
//			{
//				completionBlock(abortError);
//			}
//			else
//			{
//				dispatch_async(dispatch_get_main_queue(), ^{
//					completionBlock(abortError);
//				});
//			}
//			return(YES);
//		}
//		
//		return (NO);
//	};
//	
//#define CHECK_CANCEL   if( testForCancel())  return;
//	
//	BOOL (^testForError)(NSError* error) = ^BOOL(NSError* error){
//		
//		if(error)
//		{
//			if (completionBlock == nil) return(YES);
//			
//			if ([NSThread isMainThread])
//			{
//				completionBlock(error);
//			}
//			else
//			{
//				dispatch_async(dispatch_get_main_queue(), ^{
//					completionBlock(error);
//				});
//			}
//			return(YES);
//		}
//		return (NO);
//	};
//	
//#define HANDLE_ERROR(_err_)   if( testForError(_err_))  return;
	
	void (^invokeCompletionBlock)(NSError * error) = ^(NSError * error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(error);
			});
		}
	};
	
#define COMPLETE(_err_)    invokeCompletionBlock(_err_); return;
	
	// reset the cancel op flag
	if(cancelOperationFlag) *cancelOperationFlag = NO;
	
	NSError* error = NULL;
	__weak typeof(self) weakSelf = self;
	
	if(! [self commonInitWithUserID:userID error:&error])
	{
		COMPLETE(error);
	}
	
	[self continueUserSetupWithCompletionBlock:^(AccountState accountState, NSError *error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

		 if(error)
		 {
			 COMPLETE(error);
		 }
		 
		 switch (accountState) {
				 
			 case AccountState_Ready:
				 [strongSelf pushAccountReady ];
				 COMPLETE(nil);
				 break;
				 
			 case AccountState_NeedsCloneClode:
				 [strongSelf pushScanClodeCode  ];
				 COMPLETE(nil);
				 break;
				 
			 case AccountState_NeedsRegionSelection:
				 [strongSelf pushRegionSelection  ];
				 COMPLETE(nil);
				 break;
				 
			 case AccountState_NeedsReauthentication:
				 [strongSelf pushReauthenticateWithUserID:userID ];
				 COMPLETE(nil);
				 break;
				 
			 default:
				 COMPLETE([self errorWithDescription:@"Internal param error" statusCode:500]) ;
		 }
	 }];    
}

#undef CHECK_CANCEL
#undef HANDLE_ERROR
#undef COMPLETE

-(void) selectRegionForUserID:(NSString*)userID
							  region:(AWSRegion) region
				  completionBlock:(void (^)(NSError *error))completionBlock
{
	
	void (^invokeCompletionBlock)(NSError * error) = ^(NSError * error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(error);
			});
		}
	};
	
	[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		ZDCUser* thisUser = nil;
		
		thisUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		if(thisUser.isLocal)
		{
			self.user = (ZDCLocalUser*)thisUser;
			self.auth = [transaction objectForKey:thisUser.uuid inCollection:kZDCCollection_UserAuth];
		}
	}];
	
	if(!user || !auth )
	{
		invokeCompletionBlock([self errorWithDescription:@"User not found."
														  statusCode:0]);
		return;
	}
	
	if(user.aws_region != AWSRegion_Invalid)
	{
		
		invokeCompletionBlock([self errorWithDescription:@"Region already selected."
														  statusCode:0]);
		return;
	}
	
	// update region..   maybe we need to check if it's valid?
	self.user = [self.user copy];
	self.user.aws_region = region;
	
	[self saveLocalUserAndAuthWithCompletion:^{
		invokeCompletionBlock(nil);
	}];
	
}

- (void)startUserCreationWithAuth:(ZDCLocalUserAuth *)localUserAuth
                          profile:(ZDCUserProfile *)profile
                  completionBlock:(void (^)(AccountState accountState, NSError *error))completionBlock
{
	
	void (^InvokeCompletionBlock)(AccountState, NSError*) =
	^(AccountState accountState, NSError *error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(accountState,error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(accountState,error);
			});
		}
	};
	
	NSParameterAssert(completionBlock);
	NSParameterAssert(localUserAuth);
	NSParameterAssert(profile);
	
	// Was the user already setup on server
	BOOL wasSetup = profile.isUserBucketSetup;
	
	// check if the userID that matches an existing account
	ZDCLocalUser* existingAccount = [self localUserForAuth0ID: profile.userID];
	
	// check if this is reauthorize
	if(existingAccount
		&& existingAccount.accountNeedsA0Token
		&& existingAccount.hasRecoveryConnection
		&& !existingAccount.accountDeleted
		&& !existingAccount.accountSuspended)
	{
		[self reauthorizeUserID:existingAccount.uuid
				 withRefreshToken:localUserAuth.coop_refreshToken
				  completionBlock:^(NSError *error) {
					  
					  InvokeCompletionBlock(AccountState_Reauthorized,error);
				  }];
		return;
	}
	
	
	// save what we know so far
	userProfile = profile;
	auth        = localUserAuth;
	user        = existingAccount ?existingAccount :[self createLocalUserFromProfile:profile];
	
	[self saveLocalUserAndAuthWithCompletion:^{
		
		if (!wasSetup)
		{
			InvokeCompletionBlock(AccountState_NeedsRegionSelection,nil);
			return;
		}
		
		[self continueUserSetupWithCompletionBlock:completionBlock];
		
	}];
}

-(void)unlockUserWithAccessKey:(NSData *)accessKeyData
					completionBlock:(void (^)(NSError *error))completionBlock
{
	__weak typeof(self) weakSelf = self;

	ZDCLogAutoTrace();
	
	NSParameterAssert(completionBlock);
	
	void (^invokeCompletionBlock)(NSError * error) = ^(NSError * error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(error);
			});
		}
	};
	
	if(!privKeyData || !user )
	{
		invokeCompletionBlock([self errorWithDescription:@"Internal param error" statusCode:500]);
		return;
		
	}
	
	NSString *privKeyString = [[NSString alloc] initWithData:privKeyData encoding:NSUTF8StringEncoding];
	
	NSError *decryptError = nil;
	NSError *createError = nil;
	
	ZDCPublicKey *privateKey =
	  [zdc.cryptoTools createPrivateKeyFromJSON: privKeyString
	                                  accessKey: accessKeyData
	                        encryptionAlgorithm: kCipher_Algorithm_2FISH256
	                                localUserID: user.uuid
	                                      error: &decryptError];
	
	ZDCSymmetricKey *symKey =
	  [zdc.cryptoTools createSymmetricKey: accessKeyData
	                  encryptionAlgorithm: kCipher_Algorithm_2FISH256
	                                error: &createError];
	
	if (decryptError) {
		invokeCompletionBlock(decryptError);
		return;
	}
	if (createError) {
		invokeCompletionBlock(createError);
		return;
	}
	
	if( !privateKey)
	{
		NSString *failText = NSLocalizedString(@"Invalid access key.",
															@"Error message in login screen.");
		
		invokeCompletionBlock([self errorWithDescription:failText statusCode:500]);
		return;
	}
	
	[self saveLocalUserAndAuthWithCompletion:^{
		
		__block ZDCLocalUser*  localUser  = nil;
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
 
		
		[strongSelf->zdc.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			localUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
			localUser = localUser.copy;
			
			// clone code came externally. so it must be verified here
			localUser.hasBackedUpAccessCode = YES;
			
			localUser.publicKeyID = privateKey.uuid;
			localUser.accessKeyID = symKey.uuid;
			
			[transaction setObject:privateKey
								 forKey:privateKey.uuid
						 inCollection:kZDCCollection_PublicKeys];
			
			[transaction setObject:symKey
								 forKey:symKey.uuid
						 inCollection:kZDCCollection_SymmetricKeys];
			
			[transaction setObject:localUser
								 forKey:localUser.uuid
						 inCollection:kZDCCollection_Users];
			
			[strongSelf->zdc.localUserManager createTrunkNodesForLocalUser: localUser
			                                                   withAccessKey: symKey
			                                                     transaction: transaction];
			
		} completionBlock:^{
			
			// update properties
			self.accessKey  = symKey;
			self.privKey    = privateKey;
			self.user       = localUser;
			
			invokeCompletionBlock(nil);
		}];
	}];
}

- (void)reauthorizeUserID:(NSString *)userID
         withRefreshToken:(NSString *)refreshToken
          completionBlock:(void (^)(NSError *error))completionBlock
{
	void (^InvokeCompletionBlock)(NSError*) = ^(NSError *error){
		
		if (completionBlock == nil) return;
		
		if ([NSThread isMainThread])
		{
			completionBlock(error);
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				completionBlock(error);
			});
		}
	};
	
	[zdc.credentialsManager resetAWSCredentialsForUser: userID
	                                  withRefreshToken: refreshToken
	                                   completionQueue: nil
	                                   completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		InvokeCompletionBlock(error);
	}];
}


- (void)finalizeLocalUserWithCompletion:(dispatch_block_t)completionBlock
{
	NSParameterAssert(user != nil);
	
	NSString *localUserID = user.uuid;
	ZDCLocalUserManager *localUserManager = zdc.localUserManager;

	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		if (localUser)
		{
			[localUserManager finalizeAccountSetupForLocalUser:localUser transaction:transaction];
		}
		
	} completionBlock:^{
		
		if (completionBlock) {
			completionBlock();
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - view push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void)pushCreateAccount
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

-(void)pushSignInToAccount
{
	MUST_IMPLEMENT_IN_SUBCLASS
}
 
- (void)pushIntro
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushResumeActivationForUserID:(NSString*)userID
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushIdentity
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushDataBaseAuthenticate
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushSocialAuthenticate
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushDataBaseAccountCreate
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushAccountReady
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushScanClodeCode
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushUnlockCloneCode:(NSString*)cloneString
{
	MUST_IMPLEMENT_IN_SUBCLASS
}

- (void)pushRegionSelection
{
	MUST_IMPLEMENT_IN_SUBCLASS
}


- (void)pushReauthenticateWithUserID:(NSString* __nonnull)userID
{
	MUST_IMPLEMENT_IN_SUBCLASS
	
}


#pragma mark - token management

- (void)linkProfile:(ZDCUserProfile *)profile
      toLocalUserID:(NSString *)localUserID
    completionQueue:(nullable dispatch_queue_t)completionQueue
    completionBlock:(nullable void (^)(NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(profile != nil);
	NSParameterAssert(localUserID != nil);
	__weak typeof(self) weakSelf = self;

	void (^InvokeCompletionBlock)(NSError*) = ^(NSError * error){
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(error);
			}});
		}
	};
	
	NSError* error = nil;
	
	if (![self commonInitWithUserID:localUserID error:&error])
	{
		InvokeCompletionBlock(error);
	}
	
	NSDictionary * app_metadata = profile.extraInfo[@"app_metadata" ];
	NSString     * aws_id = app_metadata[@"aws_id"];
	
	BOOL isAlreadyLinkedToSameUser = [aws_id isEqualToString:user.uuid];
	if (isAlreadyLinkedToSameUser)
	{
		NSString *failText = NSLocalizedString(
			@"The identity you selected is already linked to another Storm4 Account.",
			@"identity you selected is already linked."
		);
		
		InvokeCompletionBlock([self errorWithDescription:failText statusCode:500]);
	}
	
	user = [self localUserForUserID:localUserID];
	
	[zdc.restManager linkAuth0ID: profile.userID
	                     forUser: user
	             completionQueue: nil
	             completionBlock:^(NSURLResponse *urlResponse, id linkResoponse, NSError *error)
	{
		if (error)
		{
			InvokeCompletionBlock(error);
			return;
		}
		
		NSInteger statusCode = 0;
		if ([urlResponse isKindOfClass:[NSHTTPURLResponse class]])
		{
			statusCode = [(NSHTTPURLResponse *)urlResponse statusCode];
		}
		
		if (statusCode != 200)
		{
			InvokeCompletionBlock([self errorWithDescription:@"Bad status response" statusCode:statusCode]);
			return;
		}
		 
		[weakSelf processLinkUnlinkResponseAndUpdateUser: linkResoponse
		                                 completionQueue: dispatch_get_main_queue()
		                                 completionBlock:^(NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlock(error);
				return;
			}
			
			ZDCLocalUserManager *localUserManager = weakSelf.zdc.localUserManager;
			
			[localUserManager updatePubKeyForLocalUserID: localUserID
			                            completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
			                            completionBlock:^(NSError *error)
			{
				InvokeCompletionBlock(error);
			}];
		}];
	}];
}

- (void)unlinkAuth0ID:(NSString *)auth0ID
		fromLocalUserID:(NSString *)localUserID
		completionQueue:(dispatch_queue_t)completionQueue
		completionBlock:(void (^)(NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(auth0ID != nil);
	NSParameterAssert(localUserID != nil);
	__weak typeof(self) weakSelf = self;

	void (^InvokeCompletionBlock)(NSError*) = ^(NSError *error) {
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(error);
			}});
		}
	};
	
	NSError *error = nil;
	if (![self commonInitWithUserID:localUserID error:&error])
	{
		InvokeCompletionBlock(error);
	}
	
	/** update the localuser to to server truth  */
	
	[zdc.localUserManager refreshAuth0ProfilesForLocalUserID:localUserID
															 completionQueue:nil
															 completionBlock:^(NSError * _Nonnull error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

		 if (error)
		 {
			 InvokeCompletionBlock(error);
			 return;
		 }
		 
		 /* refresh to the updated user */
		 if ( ! [strongSelf commonInitWithUserID:localUserID error:&error])
		 {
			 InvokeCompletionBlock(error);
		 }
		 
		 /* cant unlink the auth0_primary */
		 if([auth0ID isEqualToString:self->user.auth0_primary])
		 {
			 NSString *failText = NSLocalizedString(
																 @"The identity you selected was the primary profile.",
																 @"Internal Error - can not unlink primary profile ."
																 );
			 InvokeCompletionBlock([self errorWithDescription:failText statusCode:500]);
			 return;
			 
		 }
		 
		 /* Do we own that profile */
		 
		 if(![strongSelf->user identityWithID:auth0ID])
		 {
			 NSString *failText = NSLocalizedString(
																 @"The identity you selected was not linked.",
																 @"Internal Error - identity not linked."
																 );
			 
			 InvokeCompletionBlock([self errorWithDescription:failText statusCode:500]);
			 return;
			 
		 }
		 
		 [strongSelf->zdc.restManager unlinkAuth0ID: auth0ID
										 forUser: self->user
							  completionQueue: dispatch_get_main_queue()
							  completionBlock:^(NSURLResponse *urlResponse, id responseObject, NSError *error)
		  {
			  if (error)
			  {
				  InvokeCompletionBlock(error);
				  return;
			  }
			  
			  NSInteger statusCode = 0;
			  if ([urlResponse isKindOfClass:[NSHTTPURLResponse class]])
			  {
				  statusCode = [(NSHTTPURLResponse *)urlResponse statusCode];
			  }
			  
			  if (statusCode != 200)
			  {
				  InvokeCompletionBlock([self errorWithDescription:@"Bad status response" statusCode:statusCode]);
				  return;
			  }
			  
			  [self processLinkUnlinkResponseAndUpdateUser: responseObject
													 completionQueue: dispatch_get_main_queue()
													 completionBlock:^(NSError *error)
				{
					__strong typeof(self) strongSelf = weakSelf;
					if(!strongSelf) return;

					if (error)
					{
						InvokeCompletionBlock(error);
						return;
					}
					strongSelf->user = [self localUserForUserID: localUserID];
					
					[strongSelf->zdc.localUserManager updatePubKeyForLocalUserID: localUserID
															completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
															completionBlock:^(NSError *error)
					 {
						 InvokeCompletionBlock(error);
					 }];
				}];
			  
		  }];
		 
	 }];
}


- (void)processLinkUnlinkResponseAndUpdateUser:(id _Nullable)responseObject
										 completionQueue:(dispatch_queue_t)completionQueue
										 completionBlock:(void (^)(NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	//	NSAssert(NO, @"Not implemented"); // finish refactoring
	
	void (^InvokeCompletionBlock)(NSError *) = ^(NSError * error){
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(error);
			}});
		}
	};
	
	if (![responseObject isKindOfClass:[NSDictionary class]])
	{
		InvokeCompletionBlock([self errorWithDescription:@"Unexpected server response" statusCode:500]);
		return;
	}
	
	ZDCUserProfile *profile = [[ZDCUserProfile alloc] initWithDictionary:responseObject];

// create and array of all non recovery IDS
	NSMutableArray *identityIDs = [NSMutableArray arrayWithCapacity:profile.identities.count];
	for (ZDCUserIdentity *ident in profile.identities)
	{
		if(!ident.isRecoveryAccount)
			[identityIDs addObject:ident.identityID];
	}
 
	__block ZDCLocalUser *updatedUser = nil;
	[zdc.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		updatedUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
		if (updatedUser)
		{
			updatedUser = [updatedUser copy];
			updatedUser.identities = profile.identities;
			updatedUser.lastRefresh_profile = [NSDate date];
						
			// update preferredIdentityID if it's gone
			if (![identityIDs containsObject:updatedUser.preferredIdentityID]) {
				updatedUser.preferredIdentityID = identityIDs.firstObject;
			}
			
			[transaction setObject: updatedUser
								 forKey: updatedUser.uuid
						 inCollection: kZDCCollection_Users];
		}
		
	} completionBlock:^{
		
		self->user = updatedUser;
		
		//		[S4ThumbnailManager unCacheAvatarForUserID:updatedUser.uuid];
		InvokeCompletionBlock(nil);
	}];
	
}

@end
