/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import "ZDCPartnerTools.h"

#import "ZDCCryptoTools.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLogging.h"
#import "ZDCPublicKeyPrivate.h"
#import "ZDCUserPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelVerbose | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation ZDCPartnerTools {
	
	__weak ZeroDarkCloud *zdc;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.partner
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)createLocalUser:(ZDCPartnerUserInfo *)info
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(ZDCLocalUser *_Nullable, NSError *_Nullable))completionBlock
{
	void (^Fail)(PartnerErrorCode, NSString*, NSError*) = ^(PartnerErrorCode code, NSString *msg, NSError *underlyingError){
		
		NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
		if (msg) {
			userInfo[NSLocalizedDescriptionKey] = msg;
		}
		if (underlyingError) {
			userInfo[NSUnderlyingErrorKey] = underlyingError;
		}
		
		NSString *domain = NSStringFromClass([self class]);
		NSError *error = [NSError errorWithDomain:domain code:code userInfo:userInfo];
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(nil, error);
			}});
		}
	};
	
	void (^Succeed)(ZDCLocalUser*) = ^(ZDCLocalUser *localUser){
		
		NSParameterAssert(localUser != nil);
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(localUser, nil);
			}});
		}
	};
	
	if (info == nil) {
		NSString *msg = @"Invalid parameter: info is nil";
		
		Fail(PartnerErrorCode_InvalidParameter, msg, nil);
		return;
	}
	
	if (info.accessKey.length != (256 / 8)) {
		NSString *msg = @"Invalid parameter: info.accessKey should be 256 bits (32 bytes)";
		
		Fail(PartnerErrorCode_InvalidParameter, msg, nil);
		return;
	}
	
	NSError *error = nil;
	ZDCSymmetricKey *accessKey = [zdc.cryptoTools createSymmetricKey: info.accessKey
	                                             encryptionAlgorithm: kCipher_Algorithm_2FISH256
	                                                           error: &error];
	
	if (error) {
		Fail(PartnerErrorCode_CryptoError, @"Error creating accessKey", error);
		return;
	}
	
	NSString *localUserID = info.userID;
	
	ZDCLocalUser *localUser = [[ZDCLocalUser alloc] initWithUUID:localUserID];
	localUser.aws_region = info.region;
	localUser.aws_bucket = info.bucket;
	localUser.aws_stage  = info.stage;
	localUser.syncedSalt = info.salt;
	localUser.identities = [NSArray array];
	
	ZDCLocalUserAuth *auth = [[ZDCLocalUserAuth alloc] init];
	auth.partner_refreshToken = info.refreshToken;
	
	ZeroDarkCloud *zdc = self->zdc;
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__block void (^SanityCheck)(void) = nil;
	__block void (^TryCreateUser)(void) = nil;
	__block void (^TryUnlockExistingPrivKey)(NSData *privKeyData) = nil;
	
	// Step 1 of 3:
	//
	// Check to see if there's already a matching localUser in the database.
	// If so (and the user's account is properly setup), then we can skip all this work.
	// 
	SanityCheck = ^{ @autoreleasepool {
		
		__block ZDCLocalUser *existingLocalUser = nil;
	
		YapDatabaseConnection *roConnection = zdc.databaseManager.roDatabaseConnection;
		[roConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
	
			id existingUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
			if ([existingUser isKindOfClass:[ZDCLocalUser class]]) {
	
				if ([(ZDCLocalUser *)existingUser hasCompletedSetup]) {
	
					existingLocalUser = (ZDCLocalUser *)existingUser;
				}
			}
	
		} completionQueue:bgQueue completionBlock:^{
	
			if (existingLocalUser) {
				Succeed(existingLocalUser);
			} else {
				TryCreateUser();
			}
		}];
		
	}};
	
	// Step 2 of 3:
	//
	// Contact the sever and attempt to set the privKey/pubKey pair for the user.
	//
	// - the pubKey file is accessible to everyone
	// - the privKey file is encrypted with the accessKey
	//
	// This task must be done exactly once by each user.
	//
	// If this hasn't been done before, the server will accept our request.
	// If it has been done before, the server will send us the existing privKey file.
	//
	TryCreateUser = ^{ @autoreleasepool {
		
		[zdc.localUserManager setupPubPrivKeyForLocalUser: localUser
		                                         withAuth: auth
		                                        accessKey: accessKey
		                                  completionQueue: bgQueue
		                                  completionBlock:
		^(ZDCLocalUser *updatedLocalUser, NSData *privKeyToUnlock, NSError *error)
		{
			if (error)
			{
				PartnerErrorCode code;
				NSString *msg = nil;
				
				switch (error.code)
				{
					case SetupPrivPubKeyErrorCode_InvalidParameter:
					      code = PartnerErrorCode_InvalidParameter; break;
					
					case SetupPrivPubKeyErrorCode_NetworkError:
					      code = PartnerErrorCode_NetworkError; break;
					
					case SetupPrivPubKeyErrorCode_ServerError:
					      code = PartnerErrorCode_ServerError; break;
					
					case SetupPrivPubKeyErrorCode_CryptoError:
					      code = PartnerErrorCode_CryptoError; break;
					
					default:
					      code = PartnerErrorCode_InvalidParameter;
					      msg = @"Underlying function returned unknown error code";
				}
				
				Fail(code, msg, error);
			}
			else if (updatedLocalUser)
			{
				Succeed(updatedLocalUser);
			}
			else
			{
				TryUnlockExistingPrivKey(privKeyToUnlock);
			}
		}];
	}};
	
	// Step 3 of 3:
	//
	// This isn't the user's first login.
	// So the server has an existing privKey/pubKey pair for the user.
	//
	// - the pubKey file is accessible to everyone
	// - the privKey file is encrypted with the accessKey
	//
	// So we need to use the accessKey to decrypt the privKey file.
	//
	TryUnlockExistingPrivKey = ^(NSData *privKeyData){
		
		NSParameterAssert(privKeyData != nil);
		
		NSString *privKeyString = [[NSString alloc] initWithData:privKeyData encoding:NSUTF8StringEncoding];
		
		NSError *decryptError = nil;
		ZDCPublicKey *privateKey =
			[zdc.cryptoTools createPrivateKeyFromJSON: privKeyString
			                                accessKey: info.accessKey
			                      encryptionAlgorithm: kCipher_Algorithm_2FISH256
			                              localUserID: localUserID
			                                    error: &decryptError];
		
		if (decryptError) {
			
			// When you create a user, you MUST pass the EXACT SAME accessKey everytime.
			// You (the partner) are responsible for managing the user's accessKey.
			
			NSString *msg =
			  @"The user already has a registered keyPair on the server,"
			  @" and the given accessKey is invalid (cannot decrypt the existing privKey file)."
			  @" Remember: for a given user, you MUST use the exact same accessKey everytime, across all devices"
			  @" Partners are responsible for managing the user's accessKey.";
			
			Fail(PartnerErrorCode_CryptoError, msg, decryptError);
			return;
		}
		
		[zdc.localUserManager saveLocalUser: localUser
		                         privateKey: privateKey
		                          accessKey: accessKey
		                               auth: auth
		                    completionQueue: bgQueue
		                    completionBlock:^(ZDCLocalUser *updatedLocalUser)
		{
			Succeed(updatedLocalUser);
		}];
	};
	
	// Start
	SanityCheck();
}

@end
