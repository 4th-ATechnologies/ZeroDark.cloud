/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "AccountSetup_Base.h"
#import "ZeroDarkCloudPrivate.h"
#import "AWSCredentialsManager.h"
#import "A0UserIdentity.h"
#import "ZDCLocalUserAuth.h"
#import "ZDCLocalUserPrivate.h"
#import "Auth0Utilities.h"
#import "ZDCLocalUserManagerPrivate.h"

#import "ZDCLocalUser.h"

#import "NSDate+ZeroDark.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif


#define MUST_IMPLEMENT  \
@throw [NSException exceptionWithName:NSInternalInconsistencyException \
reason:[NSString stringWithFormat:@"You must override %@ in a subclass", \
NSStringFromSelector(_cmd)]  userInfo:nil];


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
@synthesize owner =  owner;
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
	MUST_IMPLEMENT
	
}

-(void) cancelWait
{
	MUST_IMPLEMENT
	
}

-(void) popFromCurrentView
{
	MUST_IMPLEMENT
	
}

-(void) showError:(NSString* __nonnull)title
			 message:(NSString* __nullable)message
  completionBlock:(dispatch_block_t __nullable)completionBlock
{
	MUST_IMPLEMENT
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(BOOL) commonInitWithUserID:(NSString* __nonnull)userID error:(NSError **)errorOut
{
	NSError* error = NULL;
	BOOL    sucess = NO;
	
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
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


-(ZDCLocalUser*) localUserForUserID:(NSString*) userID
{
	// check for existing user,
	__block ZDCLocalUser* existingLocalUser = nil;
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		ZDCUser *matchingUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
		if(matchingUser.isLocal)
			existingLocalUser = (ZDCLocalUser*)matchingUser;
	}];
	
	return existingLocalUser;
}


-(ZDCLocalUser*) localUserForAuth0ID:(NSString*) auth0ID
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	// check for existing user,
	__block ZDCLocalUser* foundUser = nil;
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		
		[owner.localUserManager enumerateLocalUsersWithTransaction:transaction
																		usingBlock:^(ZDCLocalUser * _Nonnull localUser, BOOL * _Nonnull stop)
		 {
			 if([localUser.auth0_profiles.allKeys containsObject:auth0ID])
			 {
				 foundUser = localUser;
				 *stop = YES;
			 }
		 }];
	}];
	
	return foundUser;
#pragma clang diagnostic pop

}


- (void)saveLocalUserAndAuthWithCompletion:(dispatch_block_t)completionBlock
{
	NSParameterAssert(user != nil);
	NSParameterAssert(auth != nil);
	
	__block ZDCLocalUser* existingUser = nil;
	
	[owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		existingUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
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
			
			// if user exists the merge the needed values.
			
			existingUser.aws_bucket       = self->user.aws_bucket;
			existingUser.aws_region       = self->user.aws_region;
			existingUser.activationDate   = self->user.activationDate;
			existingUser.syncedSalt       = self->user.syncedSalt;
			existingUser.aws_stage        = self->user.aws_stage;
			existingUser.isPayingCustomer = self->user.isPayingCustomer;
			existingUser.auth0_profiles   = self->user.auth0_profiles;
			existingUser.auth0_primary    = self->user.auth0_primary;
			existingUser.auth0_lastUpdated = self->user.auth0_lastUpdated;
			
			// copy the perfered if it isnt set yet
			if(!existingUser.auth0_preferredID && self->user.auth0_preferredID)
				existingUser.auth0_preferredID = self->user.auth0_preferredID;
		}
		else
		{
			existingUser = self->user;
		}
		
		[transaction setObject:existingUser
							 forKey:existingUser.uuid
					 inCollection:kZDCCollection_Users];
		
		[transaction setObject:self->auth
							 forKey:existingUser.uuid
					 inCollection:kZDCCollection_UserAuth];
		
	} completionBlock:^{
		
		if(completionBlock)
			completionBlock();
	}];
}



/*
 tell the server that we are using this owner.zAppID, and to do whatever
 activation is needed.. if this is a new user we will care about things like
 synced salt and bucket creation
 */

-(void)setupUserOnServerWithCompletion:(void (^)(NSError *error))completionBlock
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
	[owner.restManager setupAccountForLocalUser:self.user
												 withAuth:self.auth
												  zAppIDs:@[owner.zAppID]
										completionQueue:nil
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
		 
		 [strongSelf->owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			 
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

- (ZDCLocalUser *)createLocalUserFromProfile:(A0UserProfile *)profile
{
	NSDictionary *app_metadata = profile.extraInfo[@"app_metadata"];
	
	NSString *aws_id = app_metadata[@"aws_id"];
	if (aws_id == nil)
	{
		ZDCLogWarn(@"profile is missing required info: app_metadata.aws_id");
		return nil;
	}
	
	ZDCLocalUser *user = [[ZDCLocalUser alloc] initWithUUID:aws_id];
	
	NSString * bucket = app_metadata[@"bucket"];
	NSString * regionName = app_metadata[@"region"];
	NSDate  * auth0_updated_at = nil;
	
	//	if([profile.extraInfo objectForKey:@"updated_at"])
	//		auth0_updated_at = [NSDate dateFromRfc3339String:[profile.extraInfo objectForKey:@"updated_at"]];
	
	user.aws_bucket = bucket;
	user.aws_region = [AWSRegions regionForName:regionName];
	user.auth0_lastUpdated = auth0_updated_at;
	//	user.auth0_lastUpdated = [NSDate date];
	
	NSMutableDictionary* identities = [NSMutableDictionary dictionary];
	
	for (id item in profile.identities)
	{
		// Sanity check
		if (![item isKindOfClass:[A0UserIdentity class]]) {
			continue;
		}
		
		A0UserIdentity *ident = (A0UserIdentity *)item;
		NSString* auth0ID = [NSString stringWithFormat:@"%@|%@", ident.provider, ident.userId];
		
		NSMutableDictionary* entry = [NSMutableDictionary dictionary];
		NSString *displayName = nil;
		
		if (ident.profileData)
		{
			[entry addEntriesFromDictionary:ident.profileData];
			entry[@"connection"] = ident.connection;
			
			// fix for weird providers
			NSString *name = entry[@"name"];
			if ([name isKindOfClass:[NSNull class]]) {
				name = nil;
			}
			
			if (!name.length)
			{
				name = [Auth0Utilities correctUserNameForA0Strategy: ident.connection
																		  profile: entry];
				if (name.length) {
					entry[@"name"]= name;
				}
			}
			
			displayName = entry[@"displayName"];
			if (!displayName)  displayName = entry[@"name"];
			if (!displayName)  displayName = entry[@"nickname"];
			if (!displayName)
			{
				displayName = entry[@"email"];
				if (displayName)
				{
					if ([Auth0Utilities is4thAEmail:displayName]) {
						displayName = [Auth0Utilities usernameFrom4thAEmail:displayName];
					}
					else if ([Auth0Utilities is4thARecoveryEmail:displayName]) {
						displayName = kAuth0DBConnection_Recovery;
					}
				}
			}
			
			if (displayName) {
				entry[@"displayName"] = displayName;
			}
			
			NSString *picture =
			[Auth0ProviderManager correctPictureForAuth0ID: auth0ID
														  profileData: ident.profileData
																 region: user.aws_region
																 bucket: user.aws_bucket];
			
			if (picture) {
				entry[@"picture"] = picture;
			}
			
			identities[ident.identityId] = [entry copy];
		}
		else if ([ident.identityId isEqualToString:profile.userId])
		{
			entry[@"name"]             = profile.name;
			entry[@"nickname"]         = profile.nickname;
			entry[@"email"]            = profile.email;
			entry[@"isPrimaryProfile"] = @(YES);
			entry[@"connection"]       = ident.connection;
			
			if ([ident.provider isEqualToString:A0StrategyNameAuth0])
			{
				if ([ident.connection isEqualToString:kAuth0DBConnection_UserAuth]
					 && [Auth0Utilities is4thAEmail:profile.email])
				{
					displayName = [Auth0Utilities usernameFrom4thAEmail:profile.email];
				}
				else if ([ident.connection isEqualToString:kAuth0DBConnection_Recovery])
				{
					displayName = kAuth0DBConnection_Recovery;
				}
			}
			
			if (!displayName && profile.name.length)
				displayName =  profile.name;
			
			if (!displayName && profile.email.length)
				displayName =  profile.email;
			
			if (!displayName && profile.nickname.length)
				displayName =  profile.nickname;
			
			if (displayName)
				entry[@"displayName"]    = displayName;
			
			identities[ident.identityId] = [entry copy];
		}
		else
		{
			// No joy here
		}
	}
	
	user.auth0_profiles = identities;
	user.auth0_primary = profile.userId;
	
	return user;
}

-(nullable NSString*) closestMatchingAuth0IDFromProfile:(A0UserProfile *)profile
															  provider:(NSString*)provider
															  userName:(nullable NSString*)userName

{
	NSString* auth0ID = nil;
	
	// walk the list of identities and find closest match
	for (id item in profile.identities)
	{
		if([item isKindOfClass: [A0UserIdentity class]])
		{
			A0UserIdentity* ident = item;
			NSDictionary *profileData = ident.profileData;
			
			// ignore recovery token
			if([ident.connection  isEqualToString:kAuth0DBConnection_Recovery]) continue;
			
			if([ident.provider isEqualToString:provider])
			{
				auth0ID = ident.identityId;
				
				// if storm4 account and username matches - stop looking, you found it.
				if( [ident.connection isEqualToString:kAuth0DBConnection_UserAuth]
					&& [userName isEqualToString:profileData[@"username"]])
					break;
			}
		}
	}
	
	return auth0ID;
}


// MARK: database login
// for an existing account - attempt to login to database account

-(void) databaseAccountCreateWithUserName:(NSString*)username
											password:(NSString*)password
								  completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock
{
	void (^invokeCompletionBlock)(AccountState accountState, NSError * error) = ^(AccountState accountState, NSError * error){
		
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
	
	__weak typeof(self) weakSelf = self;
	
	
	[[Auth0APIManager sharedInstance] createUserWithEmail:[Auth0Utilities create4thAEmailForUsername:username]
																username:username
																password:password
													  auth0Connection: kAuth0DBConnection_UserAuth
													  completionQueue:nil
													  completionBlock:^(NSString * _Nullable auth0ID,
																			  NSError * _Nullable error)
	 {
		 if(error)
		 {
			 
			 if(self.identityMode == IdenititySelectionMode_ExistingAccount)
				 invokeCompletionBlock(AccountState_LinkingID,error);
			 else
				 invokeCompletionBlock(AccountState_CreationFail,error);
			 
			 return;
		 }
		 [[Auth0APIManager sharedInstance] loginAndGetProfileWithUserName:username
																					password:password
																		  auth0Connection:kAuth0DBConnection_UserAuth
																		  completionQueue:nil
																		  completionBlock:^(NSString * _Nullable auth0_refreshToken,
																								  A0UserProfile * _Nullable profile,
																								  NSError * _Nullable error)
		  {
			  __strong typeof(self) strongSelf = weakSelf;
			  
			  if(error)
			  {
				  
				  if(strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
					  invokeCompletionBlock(AccountState_LinkingID,error);
				  else
					  invokeCompletionBlock(AccountState_CreationFail,error);
				  
				  return;
			  }
			  
			  [[Auth0APIManager sharedInstance] getAWSCredentialsWithRefreshToken:auth0_refreshToken
																					completionQueue:nil
																					completionBlock:^(NSDictionary *awsToken,
																											NSError * _Nullable error)
				{
					
					ZDCLocalUserAuth* localUserAuth = nil;
					NSString* localUserID = nil;
					
					__strong typeof(self) strongSelf = weakSelf;
					
					if (error)
					{
						// The account signup succeeded, but the request to fetch AWS credentials failed.
						// This is an odd edge case.
						
						if(self.identityMode == IdenititySelectionMode_ExistingAccount)
							invokeCompletionBlock(AccountState_LinkingID,error);
						else
							invokeCompletionBlock(AccountState_CreationFail,error);
						
						return;
					}
					
					else if( [strongSelf.owner.awsCredentialsManager parseLocalUserAuth:&localUserAuth
																										uuid:&localUserID
																					fromDelegationToken:awsToken
																						withRefreshToken:auth0_refreshToken] )
					{
						
						if (strongSelf->identityMode == IdenititySelectionMode_NewAccount)
						{
							// acccount was created.
							
							// save what we know so far
							strongSelf->userProfile = profile;
							strongSelf->auth        = localUserAuth;
							strongSelf->user        = [self createLocalUserFromProfile:profile];
							
							[self saveLocalUserAndAuthWithCompletion:^{
								
								invokeCompletionBlock(AccountState_NeedsRegionSelection, NULL);
							}];
						}
						else if (strongSelf->identityMode == IdenititySelectionMode_ExistingAccount)
						{
							// add this profile
							[strongSelf linkProfile: profile
										 toLocalUserID: strongSelf->user.uuid
									  completionQueue: dispatch_get_main_queue()
									  completionBlock:^(NSError * _Nonnull error)
							 {
								 
								 invokeCompletionBlock(AccountState_LinkingID, error);
							 }];
						}
						else
						{
							invokeCompletionBlock(AccountState_CreationFail,
														 [self errorWithDescription:@"Internal state error" statusCode:500] );
							
						}
						
					}
					else
					{
						// The account signup succeeded, but the the  AWS credentials didnt parse.
						// This is an odd edge case.
						
						error = [self errorWithDescription:@"AWSCredentialsManager file" statusCode:0];
						
						if(self.identityMode == IdenititySelectionMode_ExistingAccount)
							invokeCompletionBlock(AccountState_LinkingID,error);
						else
							invokeCompletionBlock(AccountState_CreationFail,error);
						
					}
					
				}];
		  }];
		 
	 }];
	
}

// for an existing account - attempt to login to database account

-(void) databaseAccountLoginWithUserName:(NSString*)userNameIn
										  password:(NSString*)password
								 completionBlock:(void (^)(AccountState accountState, NSError * error))completionBlock
{
	
	void (^invokeCompletionBlock)(AccountState accountState, NSError * error) = ^(AccountState accountState, NSError * error){
		
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
	
	__weak typeof(self) weakSelf = self;
	
	[[Auth0APIManager sharedInstance] loginAndGetProfileWithUserName:userNameIn
																			  password:password
																	 auth0Connection:kAuth0DBConnection_UserAuth
																	 completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
																	 completionBlock:^(NSString * _Nullable auth0_refreshToken,
																							 A0UserProfile * _Nullable profile,
																							 NSError * _Nullable error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;
		 
		 if(error)
		 {
			 
			 if(strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
				 invokeCompletionBlock(AccountState_LinkingID,error);
			 else
				 invokeCompletionBlock(AccountState_CreationFail,error);
		 }
		 
		 // did the user attempt to reauthoize with an account that wasnt linked.
		 
		 else if(strongSelf.identityMode == IdenititySelectionMode_ReauthorizeAccount
					&& ![strongSelf.user.uuid isEqualToString:profile.appMetadata[@"aws_id"]])
		 {
			 
			 invokeCompletionBlock(AccountState_Reauthorized,
										  [self errorWithDescription:@"This identity is not linked to your account."
																statusCode:0]);
			 return;
		 }
		 else
		 {
			 [[Auth0APIManager sharedInstance] getAWSCredentialsWithRefreshToken:auth0_refreshToken
																				  completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
																				  completionBlock:^(NSDictionary *awsToken, NSError * _Nullable error)
			  {
				  __strong typeof(self) strongSelf = weakSelf;
				  if(!strongSelf) return;
				  
				  if(error)
				  {
					  
					  if(strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
						  invokeCompletionBlock(AccountState_LinkingID,error);
					  else
						  invokeCompletionBlock(AccountState_CreationFail,error);
				  }
				  else
				  {
					  
					  ZDCLocalUserAuth* newAuth = nil;
					  NSString* localUserID = nil;
					  
					  if( [strongSelf->owner.awsCredentialsManager parseLocalUserAuth:&newAuth
																									 uuid:&localUserID
																				 fromDelegationToken:awsToken
																					 withRefreshToken:auth0_refreshToken] )
					  {
						  __strong typeof(self) strongSelf = weakSelf;
						  if (!strongSelf) return;
						  
						  NSDictionary  *app_metadata = profile.extraInfo[kZDCUser_metadataKey];
						  NSString    	*preferedAuth0ID = app_metadata[kZDCUser_metadata_preferedAuth0ID];
						  
						  if(!preferedAuth0ID)
						  {
							  preferedAuth0ID = [strongSelf  closestMatchingAuth0IDFromProfile:profile
																										 provider:A0StrategyNameAuth0
																										 userName:userNameIn ];
						  }
						  
						  if(strongSelf.identityMode == IdenititySelectionMode_NewAccount)
						  {
							  [strongSelf startUserCreationWithAuth:newAuth
																	  profile:profile
															preferedAuth0ID:preferedAuth0ID
															completionBlock:completionBlock ];
							  
						  }
						  else if(strongSelf.identityMode == IdenititySelectionMode_ExistingAccount)
						  {
							  [strongSelf linkProfile: profile
											toLocalUserID: self->user.uuid
										 completionQueue: dispatch_get_main_queue()
										 completionBlock:^(NSError *error) {
											 invokeCompletionBlock(AccountState_LinkingID,error);
										 }];
						  }
						  else if(strongSelf.identityMode == IdenititySelectionMode_ReauthorizeAccount)
						  {
							  [strongSelf reauthorizeUserID:self->user.uuid
												withRefreshToken:newAuth.auth0_refreshToken
												 completionBlock:^(NSError *error) {
													 
													 invokeCompletionBlock(AccountState_Reauthorized,error);
													 
												 }];
						  }
						  else
						  {
							  invokeCompletionBlock(AccountState_CreationFail,
															[self errorWithDescription:@"Internal state error" statusCode:500] );
						  }
					  }
					  else
					  {
						  error = [self errorWithDescription:@"AWSCredentialsManager file" statusCode:0];
						  
						  if(self.identityMode == IdenititySelectionMode_ExistingAccount)
							  invokeCompletionBlock(AccountState_LinkingID,error);
						  else
							  invokeCompletionBlock(AccountState_CreationFail,error);
						  
					  }
					  
				  }
			  }];
		 }
		 
	 }];
}



// MARK: social account login
// entrypoint for 
-(void) socialAccountLoginWithAuth:(ZDCLocalUserAuth *)localUserAuth
									profile:(A0UserProfile *)profile
						 preferedAuth0ID:(NSString* __nonnull)preferedAuth0ID
						 completionBlock:(void (^)(AccountState accountState, NSError * error))completionBlock
{
	
	[self startUserCreationWithAuth:localUserAuth
									profile:profile
						 preferedAuth0ID:preferedAuth0ID
						 completionBlock:completionBlock ];
	
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
			
			[strongSelf->owner.localUserManager setupPubPrivKeyForLocalUser: strongSelf->user
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
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
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

-(void) startUserCreationWithAuth:(ZDCLocalUserAuth *)localUserAuth
								  profile:(A0UserProfile *)profile
						preferedAuth0ID:(NSString* __nonnull)preferedAuth0ID
						completionBlock:(void (^)(AccountState accountState, NSError * error))completionBlock
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
	ZDCLocalUser* existingAccount = [self localUserForAuth0ID: profile.userId];
	
	// check if this is reauthorize
	if(existingAccount
		&& existingAccount.accountNeedsA0Token
		&& existingAccount.hasRecoveryConnection
		&& !existingAccount.accountDeleted
		&& !existingAccount.accountSuspended)
	{
		[self reauthorizeUserID:existingAccount.uuid
				 withRefreshToken:localUserAuth.auth0_refreshToken
				  completionBlock:^(NSError *error) {
					  
					  InvokeCompletionBlock(AccountState_Reauthorized,error);
				  }];
		return;
	}
	
	
	// save what we know so far
	userProfile = profile;
	auth        = localUserAuth;
	user        = existingAccount ?existingAccount :[self createLocalUserFromProfile:profile];
	
	if(preferedAuth0ID)
	{
		user = user.copy;
		user.auth0_preferredID = preferedAuth0ID;
	}
	
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
	
	ZDCPublicKey *  privateKey = [owner.cryptoTools createPrivateKeyFromJSON:privKeyString
																						accessKey:accessKeyData
																		  encryptionAlgorithm:kCipher_Algorithm_2FISH256
																					 localUserID:user.uuid
																							 error:&decryptError];
	
	ZDCSymmetricKey *symKey = [owner.cryptoTools createSymmetricKey: accessKeyData
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
 
		[strongSelf->owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
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
			
			[strongSelf->owner.localUserManager createTrunkNodesForLocalUser: localUser
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

-(void) reauthorizeUserID:(NSString*)userID
			withRefreshToken:(NSString*)refreshToken
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
	
	[owner.awsCredentialsManager reauthorizeAWSCredentialsForUserID:userID
																  withRefreshToken:refreshToken
																	completionQueue:nil
																	completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	 {
		 invokeCompletionBlock(error);
		 
	 }];
}



- (void)finalizeLocalUserWithCompletion:(dispatch_block_t)completionBlock
{
	NSParameterAssert(user != nil);
	__weak typeof(self) weakSelf = self;

	[owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		ZDCLocalUser* existingUser = nil;
		
		existingUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
		
		if (existingUser)
		{
			[strongSelf->owner.localUserManager finalizeAccountSetupForLocalUser:existingUser
																		transaction:transaction];
		}
	}completionBlock:^{
		
		if(completionBlock)
			completionBlock();
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - view push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void)pushCreateAccount
{
	MUST_IMPLEMENT
}

-(void)pushSignInToAccount
{
	MUST_IMPLEMENT
}
 
- (void)pushIntro
{
	MUST_IMPLEMENT
}

- (void)pushResumeActivationForUserID:(NSString*)userID
{
	MUST_IMPLEMENT
}

- (void)pushIdentity
{
	MUST_IMPLEMENT
}

- (void)pushDataBaseAuthenticate
{
	MUST_IMPLEMENT
}

- (void)pushSocialAuthenticate
{
	MUST_IMPLEMENT
}

- (void)pushDataBaseAccountCreate
{
	MUST_IMPLEMENT
}

- (void)pushAccountReady
{
	MUST_IMPLEMENT
}

- (void)pushScanClodeCode
{
	MUST_IMPLEMENT
}

- (void)pushUnlockCloneCode:(NSString*)cloneString
{
	MUST_IMPLEMENT
}

- (void)pushRegionSelection
{
	MUST_IMPLEMENT
}


- (void)pushReauthenticateWithUserID:(NSString* __nonnull)userID
{
	MUST_IMPLEMENT
	
}


#pragma mark - token management

- (void)linkProfile:(A0UserProfile *)profile
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
	
	[owner.restManager linkAuth0ID: profile.userId
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
			
			ZDCLocalUserManager *localUserManager = weakSelf.owner.localUserManager;
			
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
	
	if ( ! [self commonInitWithUserID:localUserID error:&error])
	{
		InvokeCompletionBlock(error);
	}
	
	
	/** update the localuser to to server truth  */
	
	[owner.localUserManager refreshAuth0ProfilesForLocalUserID:localUserID
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
		 
		 if(![strongSelf->user.auth0_profiles.allKeys containsObject:auth0ID])
		 {
			 NSString *failText = NSLocalizedString(
																 @"The identity you selected was not linked.",
																 @"Internal Error - identity not linked."
																 );
			 
			 InvokeCompletionBlock([self errorWithDescription:failText statusCode:500]);
			 return;
			 
		 }
		 
		 [strongSelf->owner.restManager unlinkAuth0ID: auth0ID
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
					
					[strongSelf->owner.localUserManager updatePubKeyForLocalUserID: localUserID
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
	
	NSArray  * identities       = responseObject[@"identities"];
	NSString * auth0_primary    = responseObject[@"user_id"];
	NSDate   * auth0_updated_at = responseObject[@"updated_at"]?[NSDate dateFromRfc3339String:responseObject[@"updated_at"]]:nil;
	
	if (!identities.count || auth0_primary.length == 0)
	{
		InvokeCompletionBlock([self errorWithDescription:@"Unexpected server response" statusCode:500]);
		return;
	}
	
	NSMutableDictionary* auth0_profiles = [NSMutableDictionary dictionary];
	
	for (NSDictionary* item in identities)
	{
		NSMutableDictionary* entry = NSMutableDictionary.dictionary;
		
		NSDictionary * profile    = item[@"profileData"];
		NSString     * provider   = item[@"provider"];
		NSString     * connection = item[@"connection"];
		
		// force user_id to always be a string
		NSString* user_id = [NSString stringWithFormat:@"%@", item[@"user_id"] ];
		NSString* auth0ID = [NSString stringWithFormat:@"%@|%@", provider, user_id];
		
		if (!profile.count || provider.length == 0 || user_id.length == 0)
		{
			InvokeCompletionBlock( [self errorWithDescription:@"Unexpected server response" statusCode:500]);
			return;
		}
		
		[entry addEntriesFromDictionary:profile];
		entry[@"connection"] = connection;
		
		NSString * displayName = nil;
		NSString * nickname    = profile[@"nickname"];
		NSString * email       = profile[@"email"];
		NSString * name        = profile[@"name"];
		
		if ([nickname isKindOfClass:[NSNull class]]) {
			nickname = nil;
		}
		if ([email isKindOfClass:[NSNull class]]) {
			email = nil;
		}
		if ([name isKindOfClass:[NSNull class]]) {
			name = nil;
		}
		
		// fix for weird providers
		if(!name.length)
		{
			name = [Auth0Utilities correctUserNameForA0Strategy:connection
																	  profile:profile];
			if(name.length)
				entry[@"name"]    = name;
		}
		
		if([auth0ID isEqualToString:auth0_primary])
			entry[@"isPrimaryProfile"] = @(YES);
		
		if ([provider isEqualToString:A0StrategyNameAuth0])
		{
			if ([Auth0Utilities is4thAEmail:email]) {
				displayName = [Auth0Utilities usernameFrom4thAEmail:email];
			}
		}
		
		if(!displayName && name.length)
			displayName =  name;
		
		if(!displayName && email.length)
			displayName =  email;
		
		if(!displayName && nickname.length)
			displayName =  nickname;
		
		if(displayName)
			entry[@"displayName"]    = displayName;
		
		auth0_profiles[auth0ID] = [entry copy];
	}
	
	__block ZDCLocalUser *updatedUser = nil;
	[owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		updatedUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
		if (updatedUser)
		{
			updatedUser = [updatedUser copy];
			updatedUser.auth0_profiles = auth0_profiles;
			updatedUser.auth0_lastUpdated = auth0_updated_at;
			
			// update primary if its gone
			if (![auth0_profiles.allKeys containsObject:updatedUser.auth0_primary]) {
				updatedUser.auth0_primary = auth0_primary;
			}
			
			// update prefered  if the preferedAuth0ID profile is  gone
			if (![auth0_profiles.allKeys containsObject:updatedUser.auth0_preferredID ])
			{
				NSString* newPreferred = [Auth0Utilities firstAvailableAuth0IDFromProfiles:auth0_profiles];
				updatedUser.auth0_preferredID = newPreferred;
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
