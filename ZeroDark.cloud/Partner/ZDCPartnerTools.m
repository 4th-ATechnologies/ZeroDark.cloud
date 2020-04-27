/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import "ZDCPartnerTools.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCLogging.h"
#import "ZDCUserPrivate.h"

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
	
	NSError* (^ErrorWithInvalidKey)(NSString*) = ^(NSString *key){
		
		NSString *description = [NSString stringWithFormat:@"info has missing/invalid key: %@", key];
		return ErrorWithDescription(description);
	};
	
	NSString *localUserID = info.userID;
	
	ZDCLocalUser *localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
	if ([localUser isKindOfClass:[ZDCLocalUser class]]) {
		if (outError) *outError = ErrorWithDescription(@"localUser already exists in database");
		return nil;
	}
	
	localUser = [[ZDCLocalUser alloc] initWithUUID:localUserID];
	
	if (info.region == AWSRegion_Invalid) {
		if (outError) *outError = ErrorWithInvalidKey(@"region");
		return nil;
	}
	localUser.aws_region = info.region;
	localUser.aws_bucket = info.bucket;
	localUser.aws_stage  = info.stage;
	localUser.syncedSalt = info.salt;
	
	localUser.identities = [NSArray array];
	
	ZDCLocalUserAuth *localUserAuth = [[ZDCLocalUserAuth alloc] init];
	
	// Todo...
	
//	localUser.publicKeyID = privKey.uuid;
//	localUser.accessKeyID = accessKey.uuid;
	
	[transaction setObject:localUser forKey:localUser.uuid inCollection:kZDCCollection_Users];
	[transaction setObject:localUserAuth forKey:localUser.uuid inCollection:kZDCCollection_UserAuth];
//	[transaction setObject:privKey forKey:privKey.uuid inCollection:kZDCCollection_PublicKeys];
//	[transaction setObject:accessKey forKey:accessKey.uuid inCollection:kZDCCollection_SymmetricKeys];
	
//	[self createTrunkNodesForLocalUser: localUser
//	                     withAccessKey: accessKey
//	                       transaction: transaction];
	
	if (outError) *outError = nil;
	return localUser;
}

@end
