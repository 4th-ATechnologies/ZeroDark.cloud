/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "KeyBackup_Base.h"

#import "ZeroDarkCloudPrivate.h"
#import "Auth0Utilities.h"
#import "AWSCredentialsManager.h"
#import "A0UserIdentity.h"
#import "ZDCAccessCode.h"
#import "ZDCLocalUser.h"
#import "ZDCLocalUserAuth.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCSplitKey.h"

// Categories
#import "NSData+S4.h"
#import "NSError+S4.h"
#import "NSString+ZeroDark.h"


#import "ZDCLogging.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


#define MUST_IMPLEMENT  \
@throw [NSException exceptionWithName:NSInternalInconsistencyException \
reason:[NSString stringWithFormat:@"You must override %@ in a subclass", \
NSStringFromSelector(_cmd)]  userInfo:nil];


@implementation KeyBackup_Base
{
	NSData* 	keyData;
	
	NSArray<NSString*> * cachedWordList;
}

@synthesize owner =  owner;
@synthesize currentLanguageId = currentLanguageId;
@synthesize user = user;
@synthesize accessKeyData = accessKeyData;

- (void)commonInit
{
	NSString *localeIdentifier = [[NSLocale currentLocale] localeIdentifier];
	currentLanguageId = [BIP39Mnemonic languageIDForlocaleIdentifier:localeIdentifier];
	cachedWordList = NULL;

	keyData = NULL;
}

-(void)setCurrentLanguageId:(NSString *)currentLanguageIdIn
{
	currentLanguageId = currentLanguageIdIn;
	cachedWordList = NULL;
}

-(NSArray<NSString*>*) currentBIP39WordList
{
	if(!cachedWordList)
	{
		cachedWordList = [BIP39Mnemonic wordListForLanguageID:currentLanguageId error:nil];
	}
	return cachedWordList;
}


-(NSData*)accessKeyData
{
	return  keyData;
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

-(void) showError:(NSString* __nonnull)title
			 message:(NSString* __nullable)message
  completionBlock:(dispatch_block_t __nullable)completionBlock
{
	MUST_IMPLEMENT
	
}
#pragma mark - Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(BOOL) commonInitWithUserID:(NSString* __nonnull)userID error:(NSError **)errorOut
{
	NSError* error = NULL;
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		ZDCUser* thisUser = nil;
		
		thisUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		if(thisUser.isLocal)
		{
			self.user = (ZDCLocalUser*)thisUser;
			
		}
	}];
	
	if(!user )
	{
		error = [self errorWithDescription:@"Internal param error" statusCode:500] ;
	}
	else
	{
		keyData = [self accessKeyDataWithError:&error];
	}
	
	if(errorOut)
		*errorOut = error;
	
	return !error;
}

- (NSString *)accessKeyStringWithPasscode:(NSString * _Nullable )passcode
									  p2kAlgorithm:(P2K_Algorithm)p2kAlgorithm
												error:(NSError *_Nullable *_Nullable) outError
{
	NSError* 	error = NULL;
	NSString*   accessKeyString = NULL;
	
	NSData* salt = [self.user.syncedSalt dataUsingEncoding:NSUTF8StringEncoding];
	
	accessKeyString = [ZDCAccessCode accessKeyStringFromData:self.accessKeyData
															  withPasscode:passcode
															  p2kAlgorithm:p2kAlgorithm
																	  userID:self.user.uuid
																		 salt:salt 
																		error:&error];
	
	if(error) goto done;
	
done:
	
	if(outError)
		*outError = error;
	
	return accessKeyString;
}

-(void) setBackupVerifiedForUserID:(NSString*)userID
						 completionBlock:(dispatch_block_t)completionBlock
{
	[owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCLocalUser* existingUser = nil;
		
		existingUser = [transaction objectForKey:self->user.uuid inCollection:kZDCCollection_Users];
		if (existingUser)
		{
			if ([existingUser isKindOfClass:[ZDCLocalUser class]])
			{
				existingUser = [existingUser copy];
				
				existingUser.hasBackedUpAccessCode = YES;
				[transaction setObject:existingUser
									 forKey:existingUser.uuid
							 inCollection:kZDCCollection_Users];
			}
		}
		
	} completionBlock:^{
		
		if(completionBlock)
			completionBlock();
	}];
	
}

-(NSData*)accessKeyDataWithError:(NSError *_Nullable *_Nullable)outError
{
	NSError* error = NULL;
	S4Err 	 err = kS4Err_NoErr;
	
	__block ZDCSymmetricKey* cloneKey = NULL;
	S4KeyContextRef         *symKeyCtx = NULL;
	S4KeyContextRef         cloneKeyCtx = kInvalidS4KeyContextRef;
	size_t                  keyCount = 0;
	NSData*                 accessKeyData   = NULL;
	void*               keyData = NULL;
	size_t              keyDataLen = 0;
	
	if(!user)return NULL;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		cloneKey = [transaction objectForKey:user.accessKeyID inCollection:kZDCCollection_SymmetricKeys];
	}];
#pragma clang diagnostic pop

	// decode the cloneKey
	err = S4Key_DeserializeKeys((uint8_t *)cloneKey.keyJSON.UTF8String,
										 (size_t)cloneKey.keyJSON.UTF8LengthInBytes, &keyCount, &symKeyCtx ); CKERR;
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
	
	err = S4Key_DecryptFromS4Key(symKeyCtx[0], owner.storageKey, &cloneKeyCtx); CKERR;
	
	// get the actual clone data bytes
	err = S4Key_GetAllocatedProperty(cloneKeyCtx, kS4KeyProp_KeyData, NULL, &keyData, &keyDataLen ); CKERR;
	
	accessKeyData = [NSData allocSecureDataWithLength:keyDataLen];
	COPY(keyData, accessKeyData.bytes, keyDataLen);
	
	//	cloneData = [[NSData alloc] initWithBytesNoCopy:keyData
	//											 length:keyDataLen
	//									   freeWhenDone:NO];        // we free it below explicity
	
done:
	
	if(S4KeyContextRefIsValid(cloneKeyCtx))
		S4Key_Free(cloneKeyCtx);
	
	if(symKeyCtx)
	{
		if(S4KeyContextRefIsValid(symKeyCtx[0]))
		{
			S4Key_Free(symKeyCtx[0]);
		}
		XFREE(symKeyCtx);
	}
	
	if(keyData)
	{
		ZERO(keyData, keyDataLen);
		XFREE(keyData);
	}
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(outError)
		*outError = error;
	
	return accessKeyData;
}


//MARK: create key split

-(NSUInteger)nextAvailableSplitNumForLocalUserID:(NSString *)localUserID
											withTransaction:(YapDatabaseReadTransaction *)transaction
{
	__block NSUInteger splitNum = UINT_MAX;
	
	YapDatabaseAutoViewTransaction *viewTransaction = [transaction ext:Ext_View_SplitKeys];
	if (viewTransaction)
	{
		while(1) {
			splitNum = arc4random() % 2048;
			YapDatabaseViewFind *find = [YapDatabaseViewFind withObjectBlock:
												  ^(NSString *collection, NSString *key, id object)
												  {
													  __unsafe_unretained ZDCSplitKey* split = (ZDCSplitKey *)object;
													  
													  // IMPORTANT: YapDatabaseViewFind must match the sortingBlock such that:
													  //
													  // myView = @[ A, B, C, D, E, F, G ]
													  //                ^^^^^^^
													  //   sortingBlock(A, B) => NSOrderedAscending
													  //   findBlock(A)       => NSOrderedAscending
													  //
													  //   sortingBlock(E, D) => NSOrderedDescending
													  //   findBlock(E)       => NSOrderedDescending
													  //
													  //   findBlock(B) => NSOrderedSame
													  //   findBlock(C) => NSOrderedSame
													  //   findBlock(D) => NSOrderedSame
													  
													  return [@(split.splitNum) compare:@(splitNum)];
												  }];
			
			// binary search performance !!!
			NSUInteger index = [viewTransaction findFirstMatchInGroup:localUserID using:find];
			
			if (index == NSNotFound)
			{
				break;
			}
		}
	}
	
	return splitNum;
}


-(void) createSplitKeyWithTotalShares:(NSUInteger)totalShares
									threshold:(NSUInteger)threshold
						 shareKeyAlgorithm:(Cipher_Algorithm)shareKeyAlgorithm
									  comment:(NSString *_Nullable)comment
							completionQueue:(nullable dispatch_queue_t)completionQueue
							completionBlock:(nullable void (^)( ZDCSplitKey *_Nullable splitKey,
																		  NSDictionary<NSString *, NSString *>*_Nullable shareDict,
																		  NSDictionary<NSString *, NSData *>*_Nullable shareKeys,
																		  NSError *_Nullable error))completionBlock
{
	
#define HANDLE_ERROR(_err_)  \
if(_err_) { \
invokeCompletionBlock(nil,nil,nil,_err_); \
return;  } \

	void (^invokeCompletionBlock)(ZDCSplitKey *_Nullable splitKey,
											NSDictionary<NSString *, NSString *>*_Nullable shareDict,
											NSDictionary<NSString *, NSData *>*_Nullable shareKeys,
											NSError *_Nullable error)
	= ^(ZDCSplitKey * splitKey,  NSDictionary* shareDict, NSDictionary* shareKeys, NSError *error){
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(splitKey,shareDict,shareKeys,error);
			}});
		}
	};
	
 	__block NSError *error = nil;
	__block ZDCSplitKey* splitKey = NULL;
	NSMutableDictionary <NSString *, NSString *> *shareDict = nil;
	NSMutableDictionary <NSString *, NSData *> *	shareKeys = nil;
	
	NSMutableDictionary <NSString *, NSString *> *managedEntries = nil;
	
	NSString* localUserID = user.uuid;
	__block NSString* publicKeyID = nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		ZDCPublicKey* pubKey = nil;
		
		pubKey = [transaction objectForKey:user.publicKeyID inCollection:kZDCCollection_PublicKeys];
		if(pubKey)
		{
			publicKeyID = pubKey.keyID;
		}
	}];
	
#pragma clang diagnostic pop
	
	if(!publicKeyID)
		error = [self errorWithDescription:@"Public Key Not found" statusCode:500] ;
	
	HANDLE_ERROR(error);
	
	// add some additional properties to our share
	NSMutableDictionary* additionalProperties = NSMutableDictionary.dictionary;
	[additionalProperties setObject:user.uuid forKey:@"userID"];
	[additionalProperties setObject:publicKeyID forKey:@"pubkeyID"];
	
	// create the actual split key
	
	NSString* splitKeyString = [ZDCAccessCode splitKeyStringFromData:self.accessKeyData
																		  totalShares:totalShares
																			 threshold:threshold
															  additionalProperties:additionalProperties
																				 shares:&shareDict
																				  error:&error];
	HANDLE_ERROR(error);
	
	
	NSDictionary* splitKeyDict = [NSJSONSerialization JSONObjectWithData:[splitKeyString dataUsingEncoding:NSUTF8StringEncoding]
																					 options:0
																						error:&error];
	HANDLE_ERROR(error);
	
	
	// if we were asked for managed shares (share key words) create the shareKeys
	if(shareKeyAlgorithm != kCipher_Algorithm_Invalid)
	{
		shareKeys  = [NSMutableDictionary dictionaryWithCapacity:shareDict.count];
		managedEntries  = [NSMutableDictionary dictionaryWithCapacity:shareDict.count];

		[shareDict enumerateKeysAndObjectsUsingBlock:^(NSString* shareID, NSString* share, BOOL * _Nonnull stop)
		 {
			 
			 NSData* encryptionKey = NULL;
			 NSString * entry = [ZDCAccessCode shareCodeEntryFromShare:share
																			 algorithm:kCipher_Algorithm_AES128
																		 encyptionKey:&encryptionKey
																				  error:&error];
			 if(error)
			 {
				 *stop = YES;
				 return ;
			 }
			 
			 [managedEntries setObject:entry forKey:shareID];
			 [shareKeys setObject:encryptionKey forKey:shareID];
		 }];
	}
	HANDLE_ERROR(error);
	
	if(managedEntries)
	{
		NSMutableDictionary * updatedSplit = [NSMutableDictionary dictionaryWithDictionary:splitKeyDict];
		if(managedEntries.count)
		{
			[updatedSplit setObject:managedEntries forKey:@"managedShares"];
		}
		
		splitKeyDict = updatedSplit;
	}
	
	NSData* splitData = [NSJSONSerialization dataWithJSONObject:splitKeyDict
																		 options:0
																			error:&error];
	HANDLE_ERROR(error);
	
	YapDatabaseConnection *rwConnection = owner.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSUInteger splitNum = [self nextAvailableSplitNumForLocalUserID:localUserID
																		withTransaction:transaction];
		
		splitKey = [[ZDCSplitKey alloc] initWithLocalUserID:localUserID
																 splitNum:splitNum
																splitData:splitData];
		
		splitKey.comment = comment;
		
		[transaction setObject:splitKey
							 forKey:splitKey.uuid
					 inCollection:kZDCCollection_SplitKeys];
		
	}completionQueue:completionQueue
								 completionBlock:^{
									 
									 invokeCompletionBlock(splitKey,shareDict,shareKeys,NULL);
									 
								 }];
	 
#undef HANDLE_ERROR
}


-(void)didSendShareID:(NSString*)shareID
		  forSplitKeyID:(NSString*)splitkeyID
		completionBlock:(dispatch_block_t)completionBlock
{
	YapDatabaseConnection *rwConnection = owner.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCSplitKey* splitKey = [transaction objectForKey:splitkeyID inCollection:kZDCCollection_SplitKeys];
		if(splitKey)
		{
			splitKey = splitKey.copy;
			
			NSMutableSet* _sentShares = [NSMutableSet setWithSet:splitKey.sentShares];
			if(![_sentShares containsObject:shareID])
			{
				[_sentShares addObject:shareID];
				splitKey.sentShares = _sentShares;
				[transaction setObject:splitKey forKey:splitKey.uuid inCollection:kZDCCollection_SplitKeys];
			}
		}
		
	}completionBlock:completionBlock];
}

-(void)removeSplitKeyID:(NSString*)splitkeyID
		  completionBlock:(dispatch_block_t)completionBlock
{
	YapDatabaseConnection *rwConnection = owner.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction	removeObjectForKey:splitkeyID inCollection:kZDCCollection_SplitKeys];

	}completionBlock:completionBlock];
	
}


// FIXME: debug code
-(NSUInteger)numberOfSplitsWithTransAction:(YapDatabaseReadTransaction*)transaction
{
	NSUInteger count = 0;
	
	YapDatabaseViewTransaction *viewTransaction = [transaction ext:Ext_View_SplitKeys];
	if (viewTransaction)
	{
		count = [viewTransaction numberOfItemsInGroup:self.user.uuid];
	}
		
	return count;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - view push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//- (void)pushBackupWithUserID:(NSString*)userID 
//{
//    MUST_IMPLEMENT
//}


- (void)pushBackupAsText
{
	MUST_IMPLEMENT
}

- (void)pushBackupAsImage
{
	MUST_IMPLEMENT
}

- (void)pushVerifyText
{
	MUST_IMPLEMENT
}

- (void)pushBackupAsCombo
{
	MUST_IMPLEMENT
}

- (void)pushVerifyImage
{
	MUST_IMPLEMENT
}

- (void)pushUnlockAccessCode:(NSString* __nullable)cloneString
{
	MUST_IMPLEMENT
}


- (void)pushBackupSuccess
{
	MUST_IMPLEMENT
}

- (void)pushBackupSocial
{
	MUST_IMPLEMENT
}
-(void) popFromCurrentView
{
	MUST_IMPLEMENT
}

- (void)handleDone
{
	MUST_IMPLEMENT
}

@end
