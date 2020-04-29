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
- (ZDCLocalUser *)createLocalUser:(ZDCPartnerUserInfo *)info
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
                            error:(NSError *_Nullable *_Nullable)outError
{
	NSError* (^ErrorWithDescription)(NSString*) = ^(NSString *description) {
		
		return [NSError errorWithDomain: NSStringFromClass([self class])
		                           code: 400
		                       userInfo: @{ NSLocalizedDescriptionKey: description }];
	};
	
	NSError *error = nil;
	NSString *localUserID = info.userID;
	
	ZDCLocalUser *localUser = nil;
	ZDCLocalUserAuth *localUserAuth = nil;
	ZDCPublicKey *privateKey = nil;
	ZDCSymmetricKey *accessKey = nil;
	
	if (info == nil)
	{
		error = ErrorWithDescription(@"Invalid parameter: info is nil");
		goto done;
	}
	
	localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
	if ([localUser isKindOfClass:[ZDCLocalUser class]])
	{
		error = ErrorWithDescription(@"localUser already exists in database");
		goto done;
	}
	
	localUser = [[ZDCLocalUser alloc] initWithUUID:localUserID];
	localUser.aws_region = info.region;
	localUser.aws_bucket = info.bucket;
	localUser.aws_stage  = info.stage;
	localUser.syncedSalt = info.salt;
	localUser.identities = [NSArray array];
	
	localUserAuth = [[ZDCLocalUserAuth alloc] init];
	localUserAuth.partner_refreshToken = info.refreshToken;	
	
	privateKey = [ZDCPublicKey createPrivateKeyWithUserID: localUser.uuid
	                                            algorithm: kCipher_Algorithm_ECC41417
	                                           storageKey: zdc.storageKey
	                                                error: &error];
	
	if (error) {
		goto done;
	}
	
	accessKey = [zdc.cryptoTools createSymmetricKey: info.accessKey
	                            encryptionAlgorithm: kCipher_Algorithm_2FISH256
	                                          error: &error];
	
	if (error) {
		goto done;
	}
	
	localUser.publicKeyID = privateKey.uuid;
	localUser.accessKeyID = accessKey.uuid;
	
	[transaction setObject:localUser     forKey:localUser.uuid  inCollection:kZDCCollection_Users];
	[transaction setObject:localUserAuth forKey:localUser.uuid  inCollection:kZDCCollection_UserAuth];
	[transaction setObject:privateKey    forKey:privateKey.uuid inCollection:kZDCCollection_PublicKeys];
	[transaction setObject:accessKey     forKey:accessKey.uuid  inCollection:kZDCCollection_SymmetricKeys];
	
	[zdc.localUserManager createTrunkNodesForLocalUser: localUser
	                                     withAccessKey: accessKey
	                                       transaction: transaction];
	
done:
	
	if (outError) *outError = nil;
	return localUser;
}

@end
