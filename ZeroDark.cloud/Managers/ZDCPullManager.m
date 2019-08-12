/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPullManagerPrivate.h"

#import "AWSSignature.h"
#import "S3Request.h"
#import "S3Response.h"
#import "S3ResponseParser.h"
#import "ZDCCachedResponse.h"
#import "ZDCCloudNodeManager.h"
#import "ZDCCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCDatabaseManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCNodePrivate.h"
#import "ZDCChangeList.h"
#import "ZDCPullItem.h"
#import "ZDCPullStateManager.h"
#import "ZDCPullTaskCompletion.h"
#import "ZDCPullTaskResult.h"
#import "ZDCPushManagerPrivate.h"
#import "ZDCProxyList.h"
#import "ZDCRestManager.h"
#import "ZDCSyncManagerPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+Auth0API.h"
#import "NSError+ZeroDark.h"
#import "NSString+ZeroDark.h"
#import "NSURLRequest+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

#ifndef robbie_hanson
  #define robbie_hanson 1
#endif

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int ddLogLevel = DDLogLevelVerbose | DDLogFlagTrace;
#elif DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

/* extern */ NSString *const kAuth0IDKey = @"auth0";
/* extern */ NSString *const kETagKey    = @"eTag";

static NSUInteger const kMaxFailCount = 8;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCPullManager {
@private
	
	__weak ZeroDarkCloud *zdc;
	
	dispatch_queue_t concurrentQueue;
	
	ZDCPullStateManager *pullStateManager;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.pullManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner
{
	if ((self = [super init]))
	{
		zdc = owner;
		
		concurrentQueue = dispatch_queue_create("ZDCPullManager.concurrent", DISPATCH_QUEUE_CONCURRENT);
		pullStateManager = [[ZDCPullStateManager alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseConnection *)roConnection
{
	return [zdc.databaseManager internal_roConnection];
}

- (YapDatabaseConnection *)rwConnection
{
	return [zdc.databaseManager internal_rwConnection];
}

- (YapDatabaseConnection *)decryptConnection
{
	return [zdc.databaseManager internal_decryptConnection];
}

- (ZDCCloudTransaction *)cloudTransactionForPullState:(ZDCPullState *)pullState
                                          transaction:(YapDatabaseReadTransaction *)transaction
{
	NSString *const extName =
	  [zdc.databaseManager cloudExtNameForUser: pullState.localUserID
	                                       app: pullState.zAppID];
	
	return (ZDCCloudTransaction *)[transaction ext:extName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*
- (void)postAvatarUpdatedNotification:(NSString *)localUserID
                         withFilename:(NSString *)filename
                                 eTag:(NSString *)eTag
{
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(filename != nil);

	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kUserIDKey  : localUserID,
			kAuth0IDKey : filename,
			kETagKey    : eTag ?: @""
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName: CloudSyncAvatarChangedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

- (void)postAuth0ProfileUpdatedNotification:(NSString *)userID
{
	NSParameterAssert(userID != nil);
	
	dispatch_block_t block = ^{
		
		NSDictionary *userInfo = @{
			kUserIDKey : userID
		};
		
		[[NSNotificationCenter defaultCenter] postNotificationName:CloudSyncAuth0ProfileChangedNotification
		                                                    object:self
		                                                  userInfo:userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}
*/
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	return [NSError errorWithClass:[self class] code:0 description:description];
}

- (NSError *)errorWithStatusCode:(NSInteger)statusCode
{
	return [self errorWithDescription:[NSString stringWithFormat:@"HTTP statusCode = %ld", (long)statusCode]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)pullRemoteChangesForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	ZDCPullState *newPullState =
	  [pullStateManager maybeCreatePullStateForLocalUserID: localUserID
	                                                zAppID: zAppID];
	
	// The 'maybeCreatePullStateForUser' method returns nil if
	// there's already a pull in progress for the <localUserID, zAppID> tuple.
	
	if (newPullState)
	{
		[self startPullWithPullState:newPullState];
	}
}

/**
 * See header file for description.
 */
- (void)abortPullForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	ZDCPullState *deletedState =
	  [pullStateManager deletePullStateForLocalUserID: localUserID
	                                           zAppID: zAppID];
	if (deletedState)
	{
		for (NSURLSessionTask *task in deletedState.tasks)
		{
			[task cancel];
		}
		
		[zdc.syncManager notifyPullStoppedForLocalUserID: localUserID
		                                          zAppID: zAppID
		                                      withResult: ZDCPullResult_ManuallyAborted];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Project API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Forwarded from ZeroDarkCloud.
 *
 * Our job here is to update the ZDCChangeList according to the information in the push notification.
 * We do NOT start any pull operations here.
 */
- (void)processPushNotification:(ZDCPushInfo *)pushInfo
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(void (^)(BOOL needsPull))completionBlock
{
	BOOL isTriggeredFromLocalPush = NO;
	
	ZDCRequestInfo *requestInfo = pushInfo.requestInfo;
	if (requestInfo)
	{
		isTriggeredFromLocalPush =
		  [zdc.networkTools isRecentRequestID: requestInfo.requestID
		                              forUser: requestInfo.localUserID];
	}
	
	__block BOOL needsPull = NO;
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSString *change_userID   = pushInfo.localUserID;
		NSString *change_oldID    = pushInfo.changeID_old;
		NSString *change_newID    = pushInfo.changeID_new;
		
		ZDCChangeList *pullInfo = [transaction objectForKey:change_userID inCollection:kZDCCollection_PullState];
		
		if (pullInfo == nil) {
			return; // from transaction block
		}
			
		BOOL isSingleChange = NO;
		if (pushInfo.changeInfo && [pushInfo.changeInfo.uuid isEqualToString:pushInfo.changeID_new])
		{
			isSingleChange = YES;
		}
		else
		{
			// There are multiple changes.
			// For example, this may be the result of a copy-leaf operation, which generated:
			//
			// - put-if-nonexistent (rcrd)
			// - put-if-nonexistent (data)
			//
			// Thus:
			// - pushInfo.changeInfo is for the rcrd.
			// - pushInfo.changeID_new is for the data.
		}
			
		if (isTriggeredFromLocalPush)
		{
			if (isSingleChange && [pullInfo.latestChangeID_local isEqualToString:change_oldID])
			{
				// We can safely fast-forward our changeToken,
				// as we were previously up-to-date, and we triggered the change.
				
				pullInfo = [pullInfo copy];
				[pullInfo didReceiveLocallyTriggeredPushWithOldChangeID: change_oldID
				                                            newChangeID: change_newID];
				
				[transaction setObject:pullInfo forKey:change_userID inCollection:kZDCCollection_PullState];
				
				// needsPull remains NO
			}
			else
			{
				// Although we triggered this particular change,
				// the server is indicating there are other changes we don't know about.
				
				needsPull = YES;
			}
		}
		else
		{
			if (isSingleChange && change_oldID && change_newID)
			{
				// Server is reporting a single change.
				
				pullInfo = [pullInfo copy];
				[pullInfo didReceivePushWithChange: pushInfo.changeInfo
				                       oldChangeID: change_oldID
				                       newChangeID: change_newID];
				
				[transaction setObject:pullInfo forKey:change_userID inCollection:kZDCCollection_PullState];
				
				needsPull = YES;
			}
			else
			{
				// Server is reporting a multi-change.
				// Which means we're several changes behind the server.
				
				needsPull = YES;
			}
		}
			
	} completionQueue:completionQueue completionBlock:^{
			
		if (completionBlock) {
			completionBlock(needsPull);
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal bootstrap method to start the recursive sync algorithm.
**/
- (void)startPullWithPullState:(ZDCPullState *)pullState
{
	DDLogTrace(@"[%@] StartPull", pullState.localUserID);
	
	[zdc.syncManager notifyPullStartedForLocalUserID: pullState.localUserID
	                                          zAppID: pullState.zAppID];
	
#if ZDCPullManager_Fake_Pull
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), concurrentQueue, ^{
		
		[self->pullStateManager deletePullState:pullState];
		[self->owner.syncManager notifyPullStoppedForLocalUserID: pullState.localUserID
			                                               zAppID: pullState.zAppID
			                                           withResult: ZDCPullResult_Success];
	});
	return;
	
#endif
	
	ZDCPullTaskCompletion finalCompletionBlock =
	^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) { @autoreleasepool {
		
		DDLogTrace(@"[%@] FinishPull: %@", pullState.localUserID, result);
		
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		if (result.pullResult == ZDCPullResult_Success) {
			NSAssert(transaction != nil, @"Bad parameter for block: transaction is nil (with success status)");
		}
		
		if (result.pullResult == ZDCPullResult_Success)
		{
			ZDCChangeList *pullInfo =
			  [transaction objectForKey:pullState.localUserID inCollection:kZDCCollection_PullState];
		
			if (pullInfo.latestChangeID_remote && !pullInfo.latestChangeID_local)
			{
				pullInfo = [pullInfo copy];
				[pullInfo didCompleteFullPull];
			
				[transaction setObject: pullInfo
				                forKey: pullState.localUserID
				          inCollection: kZDCCollection_PullState];
			}
			
			[self processMissingItems:pullState transaction:transaction];
			[self fetchUnknownUsers:pullState];
			
			// There are several things we want to do AFTER the readwrite transaction has completed.
			// This is because, if we perform the tasks right at this moment,
			// the readwrite transaction hasn't completed,
			// and thus a read to the database will see a previous state.
			//
			// We want the following tasks to see the database AFTER the readwrite has completed.
			
			NSString *latestChangeToken = pullInfo.latestChangeID_local;
			[transaction addCompletionQueue:self->concurrentQueue completionBlock:^{
			
				[self->zdc.syncManager notifyPullStoppedForLocalUserID: pullState.localUserID
				                                                zAppID: pullState.zAppID
				                                            withResult: result.pullResult];
	
				[self->zdc.pushManager resumeOperationsPendingPullCompletion: latestChangeToken
				                                              forLocalUserID: pullState.localUserID
				                                                      zAppID: pullState.zAppID];
			}];
			
			[self->pullStateManager deletePullState:pullState];
		}
		else
		{
			[self->pullStateManager deletePullState:pullState];
			[self->zdc.syncManager notifyPullStoppedForLocalUserID: pullState.localUserID
			                                                zAppID: pullState.zAppID
			                                            withResult: result.pullResult];
		}
	}};
	
#if DEBUG && robbie_hanson && 0 // Force full pull (for testing)
	
	[self fallbackToFullPullWithPullState: pullState
	                      finalCompletion: finalCompletionBlock];
	
#else
	
	__block ZDCChangeList *pullInfo = nil;
	[zdc.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		pullInfo = [transaction objectForKey:pullState.localUserID inCollection:kZDCCollection_PullState];
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		if ([self->pullStateManager isPullCancelled:pullState])
		{
			return;
		}
		
		[self continuePullWithPullInfo: pullInfo
		                     pullState: pullState
		               finalCompletion: finalCompletionBlock];
	}];
	
#endif
}

/**
 * @param pullState
 *   The ZDCPullState, vended via the ZDCPullStateManager.
 *   Only one pullState per localUserID is allowed by the manager.
 *
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)continuePullWithPullInfo:(ZDCChangeList *)pullInfo
                       pullState:(ZDCPullState *)pullState
                 finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] ContinuePull", pullState.localUserID);
	
	if (pullInfo.latestChangeID_local)
	{
		// We can do a "quick pull".
		
		if (![pullInfo hasPendingChange])
		{
			if (pullState.hasProcessedChanges && !pullState.needsFetchMoreChanges)
			{
				// We're done !
				//
				// We processed all the pending changes we received,
				// and there are no indications of more pending changes on the server.
				
				[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
					
					finalCompletionBlock(transaction, [ZDCPullTaskResult success]);
				}];
			}
			else
			{
				// Fetch changes from the server since last pull.
				//
				// When this method completes:
				// - if it found changes, it will invoke continuePull again
				// - else it will invoke finalCompletionBlock
			
				[self fetchChangesSince: pullInfo.latestChangeID_local
				              failCount: 0
				              pullState: pullState
				        finalCompletion: finalCompletionBlock];
			}
		}
		else
		{
			// Process next item in pendingChanges.
			//
			// When this method completes:
			// - it will invoke continuePull again
			
			pullState.hasProcessedChanges = YES;
			
			NSOrderedSet<NSString *> *changeIDs = nil;
			ZDCChangeItem *change = [pullInfo popNextPendingChange:&changeIDs];
			
			[self processPendingChange: change
			                 changeIDs: changeIDs
			                 pullState: pullState
			           finalCompletion: finalCompletionBlock];
		}
	}
	else
	{
		// We need to do a "full pull".
		// This is much slower (and more expensive) than a quick pull.

		if (pullInfo.latestChangeID_remote == nil)
		{
			// Get the latest change token from the server.
			// After the full pull, we can use this to fetch iterative updates.
			//
			// When this method completes:
			// - it will invoke continuePull again
			
			[self prefetchLatestChangeTokenWithFailCount: 0
			                                   pullState: pullState
			                             finalCompletion: finalCompletionBlock];
		}
		else
		{
			DDLogTrace(@"[%@] StartFullPull", pullState.localUserID);
			
			// Start full pull algorithm.
			//
			// When this method completes:
			// - it will invoke completionBlock
			
			[self startFullPull:pullState finalCompletion:finalCompletionBlock];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Quick Pull
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)fetchChangesSince:(NSString *)latestChangeToken_local
                failCount:(NSUInteger)failCount
                pullState:(ZDCPullState *)pullState
          finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] FetchChanges", pullState.localUserID);
	
	__block NSURLSessionDataTask *task = nil;
	
	void (^processingBlock)(NSURLResponse *, id, NSError *) =
	^(NSURLResponse *urlResponse, id responseObject, NSError *error) { @autoreleasepool {
		
		[pullState removeTask:task];
		
		// Certain errors should not be tried again.
		// These include:
		// - 401 (auth failed) : we need to alert user
		
		NSInteger statusCode = urlResponse.httpStatusCode;
		
		if (urlResponse && error)
		{
			NSData *data = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
			NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if (msg)
			{
				DDLogError(@"[%@] API-Gateway: /pull/{change_token}: err (ignoring): %@",
				           pullState.localUserID, msg);
			}
			
			error = nil; // we only care about non-server-response errors
		}
		
		if (error || (statusCode == 503))
		{
			// Try request again (using exponential backoff)
			
			NSUInteger newFailCount = failCount + 1;
			
			if (newFailCount > kMaxFailCount)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_ExceededMaxRetries;
				result.underlyingError = error;
				
				finalCompletionBlock(nil, result);
			}
			else
			{
				[self fetchChangesSince: latestChangeToken_local
				              failCount: newFailCount
				              pullState: pullState
				        finalCompletion: finalCompletionBlock];
			}
			
			return;
		}
		else if (statusCode == 401 || statusCode == 403) // Unauthorized
		{
			[zdc.networkTools handleAuthFailureForUser: pullState.localUserID
			                                 withError: error
			                                 pullState: pullState];
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Auth;
			result.pullErrorReason = ZDCPullErrorReason_AwsAuthError;
			
			finalCompletionBlock(nil, result);
			return;
		}
		
		NSString *latestChangeToken_remote = nil;
		NSMutableArray<ZDCChangeItem *> *changes = nil;
		
		if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			NSDictionary *response = (NSDictionary *)responseObject;
			
			id value = response[@"latest_change_token"];
			if ([value isKindOfClass:[NSString class]])
			{
				latestChangeToken_remote = (NSString *)value;
			}
			
			value = response[@"changes"];
			if ([value isKindOfClass:[NSArray class]])
			{
				NSArray *rawChanges = (NSArray *)value;
				
				changes = [NSMutableArray arrayWithCapacity:rawChanges.count];
				
				for (NSDictionary *dict in rawChanges)
				{
					if ([dict isKindOfClass:[NSDictionary class]])
					{
						ZDCChangeItem *change = [ZDCChangeItem parseChangeInfo:dict];
						if (change) {
							[changes addObject:change];
						}
					}
				}
			}
		}
		
		if (latestChangeToken_remote == nil)
		{
			// This is an unexpected result.
			// The server is designed such that it will automatically create a changeToken if the table is empty.
			//
			// Thus we should always expect a changeToken.
			// Even for new users who have never performed a PUT operation.
			// Even when redis database reboots.
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Other;
			result.pullErrorReason = ZDCPullErrorReason_BadData;
			
			if ([responseObject isKindOfClass:[NSData class]])
			{
				NSString *msg = [[NSString alloc] initWithData:(NSData *)responseObject encoding:NSUTF8StringEncoding];
				if (msg)
				{
					NSString *errMsg = [NSString stringWithFormat:@"API-Gateway: /pull/{change_token}: response: %@", msg];
					
					DDLogError(@"[%@] %@", pullState.localUserID, errMsg);
					result.underlyingError = [self errorWithDescription:errMsg];
				}
			}
			
			finalCompletionBlock(nil, result);
			return;
		}
		
		// There are 4 possible scenarios:
		//
		// 1. We're completely up-to-date:
		//    - the changes array is empty
		//    - the latestChangeToken from the server matches our local version
		//
		// 2. We're a little behind:
		//    - the changes array is non-empty
		//    - the latestChangeToken matches the last item in the changes array
		//
		// 3. We're far behind:
		//    - the changes array is non-empty
		//    - the latestChangeToken does NOT match the last item in the changes array
		//    - this means we need to perform another fetch to get the next batch
		//
		// 3. We're really out of date (requires full pull):
		//    - the changes array is empty
		//    - the latestChangeToken from the server does not match our local version
		
		BOOL isUpToDate = NO;
		BOOL requiresFullPull = NO;
		
		if (changes.count == 0)
		{
			if ([latestChangeToken_remote isEqualToString:latestChangeToken_local])
				isUpToDate = YES;
			else
				requiresFullPull = YES;
		}
		else
		{
			NSString *lastChangeID = [[changes lastObject] uuid];
			
			if ([lastChangeID isEqualToString:latestChangeToken_remote])
				pullState.needsFetchMoreChanges = NO;
			else
				pullState.needsFetchMoreChanges = YES;
		}
		
		if (isUpToDate)
		{
			[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				finalCompletionBlock(transaction, [ZDCPullTaskResult success]);
			}];
		}
		else if (requiresFullPull)
		{
			__block ZDCChangeList *pullInfo = nil;
			
			[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				pullInfo = [[ZDCChangeList alloc] initWithLatestChangeID_remote:latestChangeToken_remote];
				
				[transaction setObject: pullInfo
				                forKey: pullState.localUserID
				          inCollection: kZDCCollection_PullState];
				
			} completionQueue:concurrentQueue completionBlock:^{
				
				[self continuePullWithPullInfo: pullInfo
				                     pullState: pullState
				               finalCompletion: finalCompletionBlock];
			}];
		}
		else // found changes
		{
			__block ZDCChangeList *pullInfo = nil;
			
			[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				pullInfo = [transaction objectForKey:pullState.localUserID inCollection:kZDCCollection_PullState];
				
				if (pullInfo == nil)
					pullInfo = [[ZDCChangeList alloc] init];
				else
					pullInfo = [pullInfo copy];
				
				[pullInfo didFetchChanges: changes
				                    since: latestChangeToken_local
				                   latest: latestChangeToken_remote];
				
				[transaction setObject: pullInfo
									 forKey: pullState.localUserID
							 inCollection: kZDCCollection_PullState];
				
			} completionQueue:concurrentQueue completionBlock:^{
				
				[self continuePullWithPullInfo: pullInfo
				                     pullState: pullState
				               finalCompletion: finalCompletionBlock];
			}];
		}
		
	}};
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		[zdc.awsCredentialsManager getAWSCredentialsForUser: pullState.localUserID
		                                    completionQueue: concurrentQueue
		                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use processingBlock to execute exponential backoff.
					
					processingBlock(nil, nil, error);
					return;
				}
				else
				{
					[zdc.networkTools handleAuthFailureForUser: pullState.localUserID
					                                 withError: error
					                                 pullState: pullState];
					
					ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
					result.pullResult = ZDCPullResult_Fail_Auth;
					result.pullErrorReason = ZDCPullErrorReason_Auth0Error;
					result.underlyingError = error;
					
					finalCompletionBlock(nil, result);
					return;
				}
			}
			
			ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:pullState.localUserID];
		#if TARGET_OS_IPHONE
			AFURLSessionManager *session = sessionInfo.foregroundSession;
		#else
			AFURLSessionManager *session = sessionInfo.session;
		#endif
			ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
			
			AWSRegion region = userInfo.region;
			NSString *stage = userInfo.stage;
			if (!stage)
			{
			#ifdef AWS_STAGE // See PrefixHeader.pch
				stage = AWS_STAGE;
			#else
				stage = @"prod";
			#endif
			}
			
			NSString *changeToken = nil;
			if (latestChangeToken_local.length > 0)
				changeToken = latestChangeToken_local;
			else
				changeToken = @"empty";
			
			NSString *path = [NSString stringWithFormat:@"/pull/%@", changeToken];
			
			NSURLComponents *urlComponents = [zdc.restManager apiGatewayForRegion:region stage:stage path:path];
			
			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
			request.HTTPMethod = @"GET";
			
			[AWSSignature signRequest:request
			               withRegion:region
			                  service:AWSService_APIGateway
			              accessKeyID:auth.aws_accessKeyID
			                   secret:auth.aws_secret
			                  session:auth.aws_session];
			
			task = [session dataTaskWithRequest: request
			                     uploadProgress: nil
			                   downloadProgress: nil
			                  completionHandler: processingBlock];
			
			// Only start the task ([task resume]) if sync hasn't been cancelled.
			
			if (![pullStateManager isPullCancelled:pullState])
			{
				[pullState addTask:task];
				[task resume];
			}
		}];
	}};
	
	if (failCount == 0)
	{
		requestBlock();
	}
	else
	{
		NSTimeInterval delay = [zdc.networkTools exponentialBackoffForFailCount:failCount];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), concurrentQueue, ^{
			
			requestBlock();
		});
	}
}

/**
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)processPendingChange:(ZDCChangeItem *)change
                   changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                   pullState:(ZDCPullState *)pullState
             finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	NSString *command = change.command;
	
	if ([command isEqualToString:@"put-if-match"])
	{
		[self processPendingChange_PutIfMatch: change
		                            changeIDs: changeIDs
		                            pullState: pullState
		                      finalCompletion: finalCompletionBlock];
	}
	else if ([command isEqualToString:@"put-if-nonexistent"])
	{
		[self processPendingChange_PutIfNonexistent: change
		                                  changeIDs: changeIDs
		                                  pullState: pullState
		                            finalCompletion: finalCompletionBlock];
	}
	else if ([command isEqualToString:@"move"])
	{
		[self processPendingChange_Move: change
		                      changeIDs: changeIDs
		                      pullState: pullState
		                finalCompletion: finalCompletionBlock];
	}
	else if ([command isEqualToString:@"delete-leaf"] ||
	         [command isEqualToString:@"delete-node"])
	{
		[self processPendingChange_Delete: change
		                        changeIDs: changeIDs
		                        pullState: pullState
		                  finalCompletion: finalCompletionBlock];
	}
	else if ([command isEqualToString:@"update-avatar"])
	{
		// Notify avatar system that an avatar image (for a localUser) may have changed.
		
	//	NSString *avatarFilename = [change.path lastPathComponent];
	//	NSString *eTag           = change.eTag;
	//	
	//	[self skipPendingChange:change
	//	              changeIDs:changeIDs
	//	              pullState:pullState
	//	        finalCompletion:finalCompletionBlock
	//	  transactionCompletion:^{
	//
	//		[self postAvatarUpdatedNotification:localUserID withFilename:avatarFilename eTag:eTag];
	//	}];
	}
	else if ([command isEqualToString:@"update-auth0"])
	{
	//	[self skipPendingChange:change
	//	              changeIDs:changeIDs
	//	              pullState:pullState
	//	        finalCompletion:finalCompletionBlock
	//	  transactionCompletion:^{
	//
	//		[self postAuth0ProfileUpdatedNotification:localUserID];
	//	}];
	}
	else
	{
		DDLogWarn(@"[%@] Unknown command: %@", pullState.localUserID, command);
		
		// Fallback to performing a full sync.
		[self fallbackToFullPullWithPullState: pullState
		                      finalCompletion: finalCompletionBlock];
	}
}

/**
 * A 'put-if-match' operation means that an existing node in the cloud has been modified/updated.
 * This means we should know about the node.
 *
 * If the RCRD was updated, then we'll want to download the new RCRD file.
 * If the DATA was updated, then we'll notifiy the delegate about it.
 *
 * @param change
 *   A parsed change dictionary (sent to us in JSON format).
 *
 * @param changeIDs
 *   If multiple changes were coalesced, this gives us the full list of coalesced changes.
 *   These are the items we'll pop from the pending list upon successful processing.
 *
 * @param pullState
 *   General info about the current pull operation.
 *
 * @param finalCompletionBlock
 *   The block to invoke after the ENTIRE pull process is complete.
 *   If this method fails, we will invoke the block.
 *   However, if it succeeds, we will continue on to the next step in the state diagram.
**/
- (void)processPendingChange_PutIfMatch:(ZDCChangeItem *)change
                              changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                              pullState:(ZDCPullState *)pullState
                        finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] ProcessPendingChange: put-if-match", pullState.localUserID);

	NSString *cloudID   = change.fileID;
	NSString *path      = change.path;
	NSString *eTag      = change.eTag;
	NSString *bucket    = change.bucket;
	NSString *regionStr = change.region;
	NSDate *timestamp   = change.timestamp;

	ZDCCloudPath *cloudPath = [ZDCCloudPath cloudPathFromPath:path];
	AWSRegion region = [AWSRegions regionForName:regionStr];
	
	if (cloudID == nil || cloudPath == nil || region == AWSRegion_Invalid || bucket == nil)
	{
		// Bad change item !
		
		DDLogTrace(@"[%@] BadChangeItem: %@", pullState.localUserID, change);
		
		[self fallbackToFullPullWithPullState:pullState finalCompletion:finalCompletionBlock];
		return;
	}
	
	BOOL isRcrd = [cloudPath.fileNameExt isEqualToString:kZDCCloudFileExtension_Rcrd];
	
	ZDCPullTaskCompletion continuationBlock =
	^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) { @autoreleasepool {
		
		DDLogTrace(@"[%@] ProcessPendingChange: put-if-match: result = %@",
		           pullState.localUserID, result);
		
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		if (result.pullResult == ZDCPullResult_Success) {
			NSAssert(transaction != nil, @"Bad parameter for block: transaction is nil (with success status)");
		}
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			// One would think AWS would return a 404 for files that no longer exist.
			// But one would be wrong !
			//
			// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
			//
			if (result.httpStatusCode == 404 || result.httpStatusCode == 403)
			{
				[self fallbackToFullPullWithPullState: pullState
				                      finalCompletion: finalCompletionBlock];
			}
			else
			{
				finalCompletionBlock(transaction, result);
			}
			
			return;
		}
		
		ZDCChangeList *pullInfo =
		  [transaction objectForKey: pullState.localUserID
		               inCollection: kZDCCollection_PullState];
		
		pullInfo = [pullInfo copy];
		[pullInfo didProcessChangeIDs:[changeIDs set]];
		
		[transaction setObject: pullInfo
		                forKey: pullState.localUserID
		          inCollection: kZDCCollection_PullState];
		
		[transaction addCompletionQueue:concurrentQueue completionBlock:^{
			
			[self continuePullWithPullInfo: pullInfo
			                     pullState: pullState
			               finalCompletion: finalCompletionBlock];
		}];
	}};
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCNode *node = nil;
		ZDCCloudNode *cloudNode = nil;
		
		// We are expecting to know about this node.
		// But there are some edge cases to understand.
		//
		// Scenario #1
		//   There is a matching local node with a non-nil cloudID.
		//   So we can find it in the database normally.
		//
		// Scenario #2
		//   There is a matching local node, but it has a nil cloudID because we're in the middle of uploading it.
		//   This edge case may occur if we're pushing & pulling simultaneously.
		//   And the timing happens just right such that the pull side ends up
		//   processing the change before the push side gets the response from its operation.
		//
		// Scenario #3
		//   The node has been marked for deletion locally.
		//   This means we don't have a ZDCNode instance stored locally,
		//   but we do have a ZDCCloudNode for it.
		//
		// Scenario #4
		//   We don't know about this node because we've somehow gotten out-of-sync with the cloud.
		
		
		// First we look for a node that matches this cloudID.
		// Recall that cloudID is assigned by the server and is immutable.
		//
		// Also note that we'll find a match even if the node has been moved or renamed,
		// either locally or in the cloud.
		//
		node = [[ZDCNodeManager sharedInstance] findNodeWithCloudID: cloudID
		                                                localUserID: pullState.localUserID
		                                                     zAppID: pullState.zAppID
		                                                transaction: transaction];
		
		if (!node)
		{
			// Possible scenario #2 IF:
			// - there's a node with this cloudPath
			// - AND it has a nil cloudID
			
			ZDCNode *altNode =
			  [[ZDCNodeManager sharedInstance] findNodeWithCloudPath: cloudPath
			                                                  bucket: bucket
			                                                  region: region
			                                             localUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                             transaction: transaction];
			if (altNode.cloudID == nil) {
				node = altNode;
			}
		}
		
		if (!node)
		{
			// Possible scenario #3
			
			cloudNode = [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: cloudPath
			                                                                      bucket: bucket
			                                                                      region: region
			                                                                 localUserID: pullState.localUserID
			                                                                 transaction: transaction];
		}
		
		BOOL done = YES;
		
		if (node)
		{
			// Sceanrio #1 or #2
			//
			// We know about the node, so we just need to determine if it's changed.
			
			if (isRcrd) // RCRD changed (treesystem metadata such as: name, permissions, etc)
			{
				if (eTag && [node.eTag_rcrd isEqualToString:eTag])
				{
					// The node is already up-to-date
				}
				else
				{
					// The node's RCRD has been updated.
					// We need to download it to find out what changed.
					
					ZDCPullItem *item = [[ZDCPullItem alloc] init];
					item.region = region;
					item.bucket = bucket;
					item.parents = @[ node.parentID ];
					
					item.rcrdCloudPath = cloudPath;
					item.rcrdETag = eTag;
					item.rcrdLastModified = timestamp;
					
					item.rcrdCompletionBlock = continuationBlock;
					item.ptrCompletionBlock = nil; // don't need to update sub-tree
					item.dirCompletionBlock = nil; // don't need to update sub-tree
					
					done = NO;
					[self pullItem:item pullState:pullState];
				}
			}
			else // DATA changed (encrypted node content)
			{
				if (eTag && [node.eTag_data isEqualToString:eTag])
				{
					// The node is already up-to-date
				}
				else
				{
					node = [node copy];
					node.eTag_data = eTag;
					node.lastModified_data = timestamp;
					
					[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
					
					ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
					[zdc.delegate didDiscoverModifiedNode: node
					                           withChange: ZDCNodeChange_Data
					                               atPath: path
					                          transaction: transaction];
				}
			}
		}
		else if (cloudNode)
		{
			// Scenario #3
			//
			// We know about this particular node.
			// However, we've marked the node for deletion locally.
			// So we're ignoring changes to the node for now.
			
			if (isRcrd)
			{
				if (eTag && ![cloudNode.eTag_rcrd isEqualToString:eTag])
				{
					cloudNode = [cloudNode copy];
					cloudNode.eTag_rcrd = eTag;
					
					[transaction setObject:cloudNode forKey:cloudNode.uuid inCollection:kZDCCollection_CloudNodes];
				}
			}
			else
			{
				if (eTag && ![cloudNode.eTag_data isEqualToString:eTag])
				{
					cloudNode = [cloudNode copy];
					cloudNode.eTag_data = eTag;
					
					[transaction setObject:cloudNode forKey:cloudNode.uuid inCollection:kZDCCollection_CloudNodes];
				}
			}
		}
		else
		{
			// Scenario #4
			//
			// Since this is a "put-if-match" operation, we SHOULD know about the node already.
			// But apparently we don't.
			// Somehow we're out-of-sync, and need to fallback to performing a full sync.
			
			done = NO;
			[self fallbackToFullPullWithPullState: pullState
			                      finalCompletion: finalCompletionBlock];
		}
		
		if (done) {
			continuationBlock(transaction, [ZDCPullTaskResult success]);
		}
	}];
}

/**
 * A 'put-if-nonexistent' operation means that a new node was added to the server.
 * We're not expecting to know about the node, unless it was our device that uploaded it.
 *
 * If a new RCRD file was uploaded, then we'll want to download the new RCRD file.
 * If a new DATA file was uploaded, then we'll notifiy the delegate about it.
 *
 * @param change
 *   A parsed change dictionary (sent to us in JSON format).
 *
 * @param changeIDs
 *   If multiple changes were coalesced, this gives us the full list of coalesced changes.
 *   These are the items we'll pop from the pending list upon successful processing.
 *
 * @param pullState
 *   General info about the current pull operation.
 *
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)processPendingChange_PutIfNonexistent:(ZDCChangeItem *)change
                                    changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                                    pullState:(ZDCPullState *)pullState
                              finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] ProcessPendingChange: put-if-nonexistent", pullState.localUserID);

	NSString *cloudID   = change.fileID;
	NSString *path      = change.path;
	NSString *eTag      = change.eTag;
	NSString *bucket    = change.bucket;
	NSString *regionStr = change.region;
	NSDate *timestamp   = change.timestamp;
	
	ZDCCloudPath *cloudPath = [ZDCCloudPath cloudPathFromPath:path];
	AWSRegion region = [AWSRegions regionForName:regionStr];
	
	if (cloudID == nil || cloudPath == nil || region == AWSRegion_Invalid || bucket == nil)
	{
		// Bad change item !
		
		DDLogTrace(@"[%@] BadChangeItem: %@", pullState.localUserID, change);
		
		[self fallbackToFullPullWithPullState:pullState finalCompletion:finalCompletionBlock];
		return;
	}
	
	BOOL isRcrd = [cloudPath.fileNameExt isEqualToString:kZDCCloudFileExtension_Rcrd];
	
	ZDCPullTaskMultiCompletion *multiCompletion = nil;
	{ // Scoping

		ZDCPullTaskSingleCompletion taskCompletion =
		^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result, uint remaining) {
	
			NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
			if (result.pullResult == ZDCPullResult_Success) {
				NSAssert(transaction != nil, @"Bad parameter for block: transaction is nil (with success status)");
			}
			
			DDLogTrace(@"[%@] ProcessPendingChange: put-if-nonexistent: remaining = %u",
			           pullState.localUserID, remaining);
		};
	
		ZDCPullTaskCompletion finalCompletion =
		^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) {
	
			DDLogTrace(@"[%@] ProcessPendingChange: put-if-nonexistent: result = %@",
			           pullState.localUserID, result);
	
			if (result.pullResult != ZDCPullResult_Success)
			{
				// One would think AWS would return a 404 for files that no longer exist.
				// But one would be wrong !
				//
				// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
				//
				if (result.httpStatusCode == 404 || result.httpStatusCode == 403)
				{
					[self fallbackToFullPullWithPullState: pullState
					                      finalCompletion: finalCompletionBlock];
				}
				else
				{
					finalCompletionBlock(transaction, result);
				}
	
				return;
			}
	
			ZDCChangeList *pullInfo =
			  [transaction objectForKey: pullState.localUserID
			               inCollection: kZDCCollection_PullState];
	
			pullInfo = [pullInfo copy];
			[pullInfo didProcessChangeIDs:[changeIDs set]];
	
			[transaction setObject: pullInfo
								 forKey: pullState.localUserID
						 inCollection: kZDCCollection_PullState];
	
			[transaction addCompletionQueue:concurrentQueue completionBlock:^{
	
				[self continuePullWithPullInfo: pullInfo
				                     pullState: pullState
				               finalCompletion: finalCompletionBlock];
			}];
		};
		
		multiCompletion =
		  [[ZDCPullTaskMultiCompletion alloc] initWithPendingCount: 1
		                                       taskCompletionBlock: taskCompletion
		                                      finalCompletionBlock: finalCompletion];
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
		ZDCNode *node = nil;
		ZDCCloudNode *cloudNode = nil;
		
		// Since this is a 'put-if-nonexistent' operation,
		// we're not expecting to know about the node unless our device uploaded it.
		//
		// Scenario #1
		//   There is a matching local node with a non-nil cloudID.
		//   This usually happens when our device uploaded the file.
		//   It's also possible if we just performed a full pull,
		//   and our local state is actually a little bit ahead of our stored pullID.
		//
		// Scenario #2
		//   There is a matching local node, but it has a nil cloudID because we're in the middle of uploading it.
		//   This edge case may occur if we're pushing & pulling simultaneously.
		//   And the timing happens just right such that the pull side ends up
		//   processing the change before the push side gets the response from its operation.
		//
		// Scenario #3
		//   We already know about this node,
		//   but we've already marked it for deletion.
		//
		// Scenario #4
		//   We don't know about this node because some other device uploaded it.
		
		// First we look for a node that matches this cloudID.
		// Recall that cloudID is assigned by the server and is immutable.
		//
		// Also note that we'll find a match even if the node has been moved or renamed,
		// either locally or in the cloud.
		//
		node = [[ZDCNodeManager sharedInstance] findNodeWithCloudID: cloudID
		                                                localUserID: pullState.localUserID
		                                                     zAppID: pullState.zAppID
		                                                transaction: transaction];
		
		if (!node)
		{
			// Possible scenario #2 IF:
			// - there's a node with this cloudPath
			// - AND it has a nil cloudID
			
			ZDCNode *altNode =
			  [[ZDCNodeManager sharedInstance] findNodeWithCloudPath: cloudPath
			                                                  bucket: bucket
			                                                  region: region
			                                             localUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                             transaction: transaction];
			
			if (altNode.cloudID == nil) {
				node = altNode;
			}
		}
		
		if (!node)
		{
			// Possible scenario #3
			
			cloudNode =
			  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: cloudPath
			                                                            bucket: bucket
			                                                            region: region
			                                                       localUserID: pullState.localUserID
			                                                       transaction: transaction];
		}
		
		BOOL aborted = NO;
		
		if (node)
		{
			// Scenario #1 or #2
			
			if (isRcrd)
			{
				if (eTag && [node.eTag_rcrd isEqualToString:eTag])
				{
					// The node is already up-to-date
				}
				else
				{
					// We know about this node,
					// but somehow it's out-of-date already.
					
					ZDCPullItem *item = [[ZDCPullItem alloc] init];
					item.region = region;
					item.bucket = bucket;
					item.parents = @[ node.parentID ]; // only need direct parent
					
					item.rcrdCloudPath = cloudPath;
					item.rcrdETag = eTag;
					item.rcrdLastModified = timestamp;
					
					item.rcrdCompletionBlock = multiCompletion.wrapper;
					item.ptrCompletionBlock = multiCompletion.wrapper;
					item.dirCompletionBlock = nil;
					
					[multiCompletion incrementPendingCount:2];
					[self pullItem:item pullState:pullState];
				}
			}
			else
			{
				if (eTag && [node.eTag_data isEqualToString:eTag])
				{
					// The node is already up-to-date
				}
				else
				{
					node = [node copy];
					node.eTag_data = eTag;
					node.lastModified_data = timestamp;
					
					[transaction setObject: node
					                forKey: node.uuid
					          inCollection: kZDCCollection_Nodes];
					
					ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
					[zdc.delegate didDiscoverModifiedNode: node
					                           withChange: ZDCNodeChange_Data
					                               atPath: path
					                          transaction: transaction];
				}
			}
		}
		else if (cloudNode)
		{
			// Scenario #3
			
			if (isRcrd)
			{
				if (eTag && ![cloudNode.eTag_rcrd isEqualToString:eTag])
				{
					cloudNode = [cloudNode copy];
					cloudNode.eTag_rcrd = eTag;
					
					[transaction setObject: cloudNode
					                forKey: cloudNode.uuid
					          inCollection: kZDCCollection_CloudNodes];
				}
			}
			else
			{
				if (eTag && ![cloudNode.eTag_data isEqualToString:eTag])
				{
					cloudNode = [cloudNode copy];
					cloudNode.eTag_data = eTag;
					
					[transaction setObject: cloudNode
					                forKey: cloudNode.uuid
					          inCollection: kZDCCollection_CloudNodes];
				}
			}
		}
		else // if (!node && !cloudNode)
		{
			// Scenario #4
			//
			// We just found out about a new node.
			
			ZDCNode *parentNode =
				  [[ZDCNodeManager sharedInstance] findNodeWithDirPrefix: cloudPath.dirPrefix
				                                                  bucket: bucket
				                                                  region: region
				                                             localUserID: pullState.localUserID
				                                                  zAppID: pullState.zAppID
				                                             transaction: transaction];
			
			if (parentNode == nil)
			{
				// If we don't know about the parent node,
				// then we've somehow become out-of-sync with the cloud.
				// And we need to fallback to a full pull.
				
				aborted = YES;
				[self fallbackToFullPullWithPullState: pullState
				                      finalCompletion: finalCompletionBlock];
			}
			else if (isRcrd)
			{
				ZDCPullItem *item = [[ZDCPullItem alloc] init];
				item.region = region;
				item.bucket = bucket;
				item.parents = @[ parentNode.uuid ]; // only need direct parent (not a full pull)
				
				item.rcrdCloudPath = cloudPath;
				item.rcrdETag = eTag;
				item.rcrdLastModified = timestamp;
				
				item.rcrdCompletionBlock = multiCompletion.wrapper;
				item.ptrCompletionBlock = multiCompletion.wrapper;
				item.dirCompletionBlock = nil;
				
				[multiCompletion incrementPendingCount:2];
				[self pullItem:item pullState:pullState];
			}
			else
			{
				ZDCPullItem *item = [[ZDCPullItem alloc] init];
				item.region = region;
				item.bucket = bucket;
				item.parents = @[ parentNode.uuid ]; // only need direct parent (not a full pull)
				
				item.rcrdCloudPath = [cloudPath copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				
				item.dataCloudPath = cloudPath;
				item.dataETag = eTag;
				item.dataLastModified = timestamp;
				
				item.rcrdCompletionBlock = multiCompletion.wrapper;
				item.ptrCompletionBlock = multiCompletion.wrapper;
				item.dirCompletionBlock = nil;
				
				[multiCompletion incrementPendingCount:2];
				[self pullItem:item pullState:pullState];
			}
		}
		
		if (!aborted) {
			multiCompletion.wrapper(transaction, [ZDCPullTaskResult success]);
		}
	}];
}

/**
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)processPendingChange_Move:(ZDCChangeItem *)change
                        changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                        pullState:(ZDCPullState *)pullState
                  finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] ProcessPendingChange: move", pullState.localUserID);

	NSString *cloudID   = change.fileID;
	NSString *srcPath   = change.srcPath;
	NSString *dstPath   = change.dstPath;
	NSString *eTag      = change.eTag;
	NSString *bucket    = change.bucket;
	NSString *regionStr = change.region;
	NSDate *timestamp   = change.timestamp;
	
	ZDCCloudPath *srcCloudPath = [ZDCCloudPath cloudPathFromPath:srcPath];
	ZDCCloudPath *dstCloudPath = [ZDCCloudPath cloudPathFromPath:dstPath];
	AWSRegion region = [AWSRegions regionForName:regionStr];
	
	if (cloudID == nil || srcCloudPath == nil || dstCloudPath == nil || region == AWSRegion_Invalid || bucket == nil)
	{
		// Bad change item !
		
		DDLogTrace(@"[%@] BadChangeItem: %@", pullState.localUserID, change);
		
		[self fallbackToFullPullWithPullState:pullState finalCompletion:finalCompletionBlock];
		return;
	}
	
	ZDCPullTaskCompletion continuationBlock =
	^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) { @autoreleasepool {
		
		DDLogTrace(@"[%@] ProcessPendingChange: move: result = %@",
		           pullState.localUserID, result);
		
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		if (result.pullResult == ZDCPullResult_Success) {
			NSAssert(transaction != nil, @"Bad parameter for block: transaction is nil (with success status)");
		}
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			// One would think AWS would return a 404 for files that no longer exist.
			// But one would be wrong !
			//
			// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
			//
			if (result.httpStatusCode == 404 || result.httpStatusCode == 403)
			{
				[self fallbackToFullPullWithPullState: pullState
											 finalCompletion: finalCompletionBlock];
			}
			else
			{
				finalCompletionBlock(transaction, result);
			}
			
			return;
		}
		
		ZDCChangeList *pullInfo =
		  [transaction objectForKey: pullState.localUserID
		               inCollection: kZDCCollection_PullState];
		
		pullInfo = [pullInfo copy];
		[pullInfo didProcessChangeIDs:[changeIDs set]];
		
		[transaction setObject: pullInfo
		                forKey: pullState.localUserID
		          inCollection: kZDCCollection_PullState];
		
		[transaction addCompletionQueue:concurrentQueue completionBlock:^{
		
			[self continuePullWithPullInfo: pullInfo
			                     pullState: pullState
			               finalCompletion: finalCompletionBlock];
		}];
	}};
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
		ZDCNode *node = nil;
		ZDCNode *dstParentNode = nil;
		
		ZDCCloudNode *srcCloudNode = nil;
		ZDCCloudNode *dstCloudNode = nil;
		
		// Since this is a 'move' operation,
		// we're not expecting to know about the node being moved.
		//
		// Scenario #1
		//   We have a matching local node with a non-nil cloudID.
		//   So we can fetch it from the database using only the cloudID.
		//
		// Scenario #2
		//   We have a matching local node, but it has a nil cloudID.
		//   This is an extreme edge case.
		//   It would mean some other device managed to move/rename the node we just uploaded,
		//   before our push system has processed the original upload operation.
		//
		// Scenario #3
		//   We already know about this node,
		//   but we've already marked it for deletion.
		//
		// Scenario #4
		//   We're out of sync with the cloud, and we don't know about the node at all.
		
		node = [[ZDCNodeManager sharedInstance] findNodeWithCloudID: cloudID
		                                                localUserID: pullState.localUserID
		                                                     zAppID: pullState.zAppID
		                                                transaction: transaction];
		
		if (!node)
		{
			// Possible scenario #2 IF:
			// - there's a node with this cloudPath
			// - AND it has a nil cloudID
			
			ZDCNode *altNode =
			  [[ZDCNodeManager sharedInstance] findNodeWithCloudPath: srcCloudPath
			                                                  bucket: bucket
			                                                  region: region
			                                             localUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                             transaction: transaction];
			
			if (altNode.cloudID == nil) {
				node = altNode;
			}
		}
		
		if (node)
		{
			ZDCNode *parentNode = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
			
			if ([parentNode.dirPrefix isEqualToString:dstCloudPath.dirPrefix]) {
				dstParentNode = parentNode;
			}
		}
		
		if (!dstParentNode)
		{
			dstParentNode =
			  [[ZDCNodeManager sharedInstance] findNodeWithDirPrefix: dstCloudPath.dirPrefix
			                                                  bucket: bucket
			                                                  region: region
			                                             localUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                             transaction: transaction];
		}
		
		if (!node)
		{
			srcCloudNode =
			  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: srcCloudPath
			                                                            bucket: bucket
			                                                            region: region
			                                                       localUserID: pullState.localUserID
			                                                       transaction: transaction];
			
			dstCloudNode =
			  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: dstCloudPath
			                                                            bucket: bucket
			                                                            region: region
			                                                       localUserID: pullState.localUserID
			                                                       transaction: transaction];
		}
		
		BOOL done = YES;
		BOOL forceFullPull = NO;
		
		if (node)
		{
			// Scenario #1 or #2
			
			if (dstParentNode)
			{
				// Expected flow under good conditions.
				// Fetch the modified RCRD, so we can get its name & possibly new permissions list.
				
				ZDCPullItem *item = [[ZDCPullItem alloc] init];
				item.region = region;
				item.bucket = bucket;
				item.parents = @[ dstParentNode.uuid ]; // only need direct parent
				
				item.rcrdCloudPath = [dstCloudPath copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				item.rcrdETag = eTag;
				item.rcrdLastModified = timestamp;
				
				item.rcrdCompletionBlock = continuationBlock;
				item.ptrCompletionBlock = nil; // don't need to update sub-tree
				item.dirCompletionBlock = nil; // don't need to update sub-tree
				
				done = NO;
				[self pullItem:item pullState:pullState];
			}
			else // if (!dstParentNode)
			{
				// We expect to know about the destination, but we don't.
				// So we've somehow gotten out-of-sync with the cloud, and need to fallback to a full pull.
				
				done = NO;
				forceFullPull = YES;
			}
		}
		else if (srcCloudNode || dstCloudNode)
		{
			// Scenario #3
			
			if (srcCloudNode && dstCloudNode)
			{
				// We're a little bit out-of-sync.
				// But we just need to delete the srcCloudNode.
				
				[transaction removeObjectForKey:srcCloudNode.uuid inCollection:kZDCCollection_CloudNodes];
				srcCloudNode = nil;
			}
			//
			// yes, break here (not else if)
			//
			if (srcCloudNode)
			{
				srcCloudNode = [srcCloudNode copy];
				srcCloudNode.eTag_rcrd = eTag;
				srcCloudNode.cloudLocator =
				  [[ZDCCloudLocator alloc] initWithRegion:region bucket:bucket cloudPath:dstCloudPath];
				
				[transaction setObject:srcCloudNode forKey:srcCloudNode.uuid inCollection:kZDCCollection_CloudNodes];
			}
			else if (![dstCloudNode.eTag_rcrd isEqualToString:eTag])
			{
				dstCloudNode = [dstCloudNode copy];
				dstCloudNode.eTag_rcrd = eTag;
				
				[transaction setObject:dstCloudNode forKey:dstCloudNode.uuid inCollection:kZDCCollection_CloudNodes];
			}
		}
		else // if (!node && !cloudNode)
		{
			done = NO;
			forceFullPull = YES;
		}
		
		if (done) {
			continuationBlock(transaction, [ZDCPullTaskResult success]);
		}
		else if (forceFullPull)
		{
			[self fallbackToFullPullWithPullState: pullState
			                      finalCompletion: finalCompletionBlock];
		}
	}];
}

- (void)processPendingChange_Delete:(ZDCChangeItem *)change
                          changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                          pullState:(ZDCPullState *)pullState
                    finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] ProcessPendingChange: delete", pullState.localUserID);

	NSString *cloudID   = change.fileID;
	NSString *path      = change.path;
	NSString *bucket    = change.bucket;
	NSString *regionStr = change.region;
	NSDate *timestamp   = change.timestamp;
	
	ZDCCloudPath *cloudPath = [ZDCCloudPath cloudPathFromPath:path];
	AWSRegion region = [AWSRegions regionForName:regionStr];
	
	if (cloudID == nil || cloudPath == nil || region == AWSRegion_Invalid || bucket == nil)
	{
		// Bad change item !
		
		DDLogTrace(@"[%@] BadChangeItem: %@", pullState.localUserID, change);
		
		[self fallbackToFullPullWithPullState:pullState finalCompletion:finalCompletionBlock];
		return;
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCNode *node = nil;
		ZDCCloudNode *cloudNode = nil;
		
		// This is a 'delete' operation, so we're expecting to know about the node.
		// Unless it was our device that performed the delete operation.
		//
		// Scenario #1
		//   We have a matching local node, with a non-nil cloudID.
		//   So we can find it in the database using only the cloudID.
		//
		// Scenario #2
		//   We already deleted the node locally,
		//   and we have a matching ZDCCloudNode placeholder for it.
		//
		// Scenario #3
		//   We don't know anything about this node.
		//   Usually this means our device performed the delete operation,
		//   and already deleted everthing from the database.
		
		node = [[ZDCNodeManager sharedInstance] findNodeWithCloudID: cloudID
		                                                localUserID: pullState.localUserID
		                                                     zAppID: pullState.zAppID
		                                                transaction: transaction];
		
		if (!node)
		{
			cloudNode =
			  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: cloudPath
			                                                            bucket: bucket
			                                                            region: region
			                                                       localUserID: pullState.localUserID
			                                                       transaction: transaction];
		}
		
		if (node)
		{
			[self remoteDeleteNode: node
			             timestamp: timestamp
			             pullState: pullState
			           transaction: transaction];
		}
		else if (cloudNode)
		{
			[transaction removeObjectForKey:cloudNode.uuid inCollection:kZDCCollection_CloudNodes];
		}
		else // if (!node && !cloudNode)
		{
			// We're being told to delete a node that we don't know about.
			// There are a couple possible reasons:
			//
			// Reason #1:
			//   This delete has been merged with other operation's (as an optimization) (changeIDs.count > 1).
			//   What's happening here is that a node was uploaded & then deleted (before we could ever sync it).
			//   So we can just skip the entire set of operations.
			//
			// Reason #2:
			//   Our device performed the delete, and cleaned up the database already.
			//   This occurred in the PushManager, when it received a success response from the server.
			//
			// Reason #3:
			//    Theoretically, we could be out-of-sync with the cloud too.
			//    However, there's really no reason to jump to this conclusion here, as reason #2 is more likely.
		}
		
		// Done !
		
		ZDCChangeList *pullInfo =
		  [transaction objectForKey: pullState.localUserID
		               inCollection: kZDCCollection_PullState];
		
		pullInfo = [pullInfo copy];
		[pullInfo didProcessChangeIDs:[changeIDs set]];
		
		[transaction setObject: pullInfo
		                forKey: pullState.localUserID
		          inCollection: kZDCCollection_PullState];
		
		[transaction addCompletionQueue:concurrentQueue completionBlock:^{
		
			[self continuePullWithPullInfo: pullInfo
			                     pullState: pullState
			               finalCompletion: finalCompletionBlock];
		}];
	}];
}

/**
 * If there's no reason to process the change, we can use this method to skip it.
 *
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)skipPendingChange:(ZDCChangeItem *)change
                changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                pullState:(ZDCPullState *)pullState
          finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	[self skipPendingChange: change
	              changeIDs: changeIDs
	              pullState: pullState
	        finalCompletion: finalCompletionBlock
	  transactionCompletion: nil];
}

- (void)skipPendingChange:(ZDCChangeItem *)change
                changeIDs:(NSOrderedSet<NSString *> *)changeIDs
                pullState:(ZDCPullState *)pullState
          finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
    transactionCompletion:(dispatch_block_t)transactionCompletionBlock
{
	NSString *const localUserID = pullState.localUserID;
	
	__block ZDCChangeList *pullInfo = nil;
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		pullInfo = [transaction objectForKey:localUserID inCollection:kZDCCollection_PullState];
		
		pullInfo = [pullInfo copy];
		[pullInfo didProcessChangeIDs:[changeIDs set]];
		
		[transaction setObject:pullInfo forKey:localUserID inCollection:kZDCCollection_PullState];
		
		if (transactionCompletionBlock){
			[transaction addCompletionQueue:concurrentQueue completionBlock:transactionCompletionBlock];
		}
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[self continuePullWithPullInfo: pullInfo
		                     pullState: pullState
		               finalCompletion: finalCompletionBlock];
	}];
}

/**
 * If quick sync fails for some reason, we should use full sync as a fallback mechanism.
 *
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)fallbackToFullPullWithPullState:(ZDCPullState *)pullState
                        finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	NSString *const localUserID = pullState.localUserID;
	DDLogTrace(@"[%@] FallbackToFullPull", localUserID);
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:localUserID inCollection:kZDCCollection_PullState];
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[self continuePullWithPullInfo: nil // we deleted it to force a full sync
		                     pullState: pullState
		               finalCompletion: finalCompletionBlock];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Full Pull
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Ask the server for the latest change token.
 * This gives us an "anchor" that we can use later.
 * So after we do a full pull, we can come back and use the "anchor" to start performing quick pulls.
 *
 * @param finalCompletionBlock
 *   The block to invoke after the entire sync process is complete.
 *   If this method fails, it will invoke the block.
 *   However, if it succeeds, it will continue on to the next step in the state diagram.
**/
- (void)prefetchLatestChangeTokenWithFailCount:(NSUInteger)failCount
                                     pullState:(ZDCPullState *)pullState
                               finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	NSString *const localUserID = pullState.localUserID;
	DDLogTrace(@"[%@] PrefetchLatestChangeToken", localUserID);
	
	if (failCount > kMaxFailCount)
	{
		ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
		result.pullResult = ZDCPullResult_Fail_Other;
		result.pullErrorReason = ZDCPullErrorReason_ExceededMaxRetries;
		
		finalCompletionBlock(nil, result);
		return;
	}
	
	__block NSURLSessionDataTask *task = nil;
	
	void (^processingBlock)(NSURLResponse *urlResponse, id responseObject, NSError *error);
	processingBlock = ^(NSURLResponse *urlResponse, id responseObject, NSError *error) { @autoreleasepool {
		
		[pullState removeTask:task];
		
		// Certain errors should not be tried again.
		// These include:
		// - 401 (auth failed) : we need to alert user
		
		NSInteger statusCode = urlResponse.httpStatusCode;
		
		if (urlResponse && error)
		{
			NSData *data = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
			NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if (msg)
			{
				DDLogError(@"[%@] API-Gateway: /pull: err (ignoring): %@", localUserID, msg);
			}
			
			error = nil; // we only care about non-server-response errors
		}
		
		if (error || (statusCode == 503))
		{
			// Try request again (using exponential backoff)
			
			[self prefetchLatestChangeTokenWithFailCount: (failCount + 1)
			                                   pullState: pullState
			                             finalCompletion: finalCompletionBlock];
			
			return;
		}
		else if (statusCode == 401 || statusCode == 403) // Unauthorized
		{
			[zdc.networkTools handleAuthFailureForUser: localUserID
			                                 withError: error
			                                 pullState: pullState];
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Auth;
			result.pullErrorReason = ZDCPullErrorReason_AwsAuthError;
			
			finalCompletionBlock(nil, result);
			return;
		}
		
		NSDictionary *response = nil;
		NSString *latestChangeToken = nil;
		
		if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			response = (NSDictionary *)responseObject;
			
			id value = response[@"change_token"];
			if ([value isKindOfClass:[NSString class]])
			{
				latestChangeToken = (NSString *)value;
			}
		}
		
		if (latestChangeToken == nil)
		{
			// This is an unexpected result.
			// The server is designed such that it will automatically create a changeToken if the table is empty.
			//
			// Thus we should always expect a changeToken.
			// Even for new users who have never performed a PUT operation.
			// Even when redis database reboots.
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Other;
			result.pullErrorReason = ZDCPullErrorReason_BadData;
			
			if ([responseObject isKindOfClass:[NSData class]])
			{
				NSString *msg = [[NSString alloc] initWithData:(NSData *)responseObject encoding:NSUTF8StringEncoding];
				if (msg)
				{
					NSString *errMsg = [NSString stringWithFormat:@"API-Gateway: /pull: unexpected response: %@", msg];
					
					DDLogError(@"[%@] %@", localUserID, errMsg);
					result.underlyingError = [self errorWithDescription:errMsg];
				}
			}
			
			finalCompletionBlock(nil, result);
			return;
		}
		
		__block ZDCChangeList *pullInfo = nil;
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			if ([pullStateManager isPullCancelled:pullState])
			{
				return;
			}
			
			pullInfo = [[ZDCChangeList alloc] initWithLatestChangeID_remote:latestChangeToken];
			
			[transaction setObject:pullInfo
			                forKey:localUserID
			          inCollection:kZDCCollection_PullState];
			
		} completionQueue:concurrentQueue completionBlock:^{
			
			[self continuePullWithPullInfo: pullInfo
			                     pullState: pullState
			               finalCompletion: finalCompletionBlock];
		}];
	}};
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
		                                    completionQueue: concurrentQueue
		                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
 			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use processingBlock to execute exponential backoff.
					
					processingBlock(nil, nil, error);
					return;
				}
				else
				{
					[zdc.networkTools handleAuthFailureForUser: localUserID
					                                 withError: error
					                                 pullState: pullState];
					
					ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
					result.pullResult = ZDCPullResult_Fail_Auth;
					result.pullErrorReason = ZDCPullErrorReason_Auth0Error;
					result.underlyingError = error;
					
					finalCompletionBlock(nil, result);
					return;
				}
			}
			
			ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
			
		#if TARGET_OS_IPHONE
			AFURLSessionManager *session = sessionInfo.foregroundSession;
		#else
			AFURLSessionManager *session = sessionInfo.session;
		#endif
			ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
			
			AWSRegion region = userInfo.region;
			NSString *stage = userInfo.stage;
			if (!stage)
			{
			#ifdef AWS_STAGE // See PrefixHeader.pch
				stage = AWS_STAGE;
			#else
				stage = @"prod";
			#endif
			}
			
			NSString *path = @"/pull";
			NSURLComponents *urlComponents = [zdc.restManager apiGatewayForRegion:region stage:stage path:path];
			
			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
			request.HTTPMethod = @"GET";
			
			[AWSSignature signRequest:request
								withRegion:region
									service:AWSService_APIGateway
							  accessKeyID:auth.aws_accessKeyID
									 secret:auth.aws_secret
									session:auth.aws_session];
			
			task = [session dataTaskWithRequest: request
			                     uploadProgress: nil
			                   downloadProgress: nil
			                  completionHandler: processingBlock];
			
			// Only start the task ([task resume]) if sync hasn't been cancelled.
			
			if (![pullStateManager isPullCancelled:pullState])
			{
				[pullState addTask:task];
				[task resume];
			}
		}];
	}};
	
	if (failCount == 0)
	{
		requestBlock();
	}
	else
	{
		NSTimeInterval delay = [zdc.networkTools exponentialBackoffForFailCount:failCount];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), concurrentQueue, ^{
			
			requestBlock();
		});
	}
}

- (void)startFullPull:(ZDCPullState *)pullState finalCompletion:(ZDCPullTaskCompletion)finalCompletionBlock
{
	DDLogTrace(@"[%@] Start full pull", pullState.localUserID);
	
	NSParameterAssert(pullState != nil);
	NSParameterAssert(finalCompletionBlock != nil);
	
	// We're starting a full pull, so mark the PullState accordingly
	
	pullState.isFullPull = YES;
	
	// Here's what we need to do:
	//
	// 1. Fetch everything we immediately need from the database:
	//    - the user's bucket & region
	//    - the container nodes
	//
	// 2. Initialize the pullState 'unprocessed' lists
	//    - unprocessedNodeIDs (per container)
	//
	//    This is the list of nodes we know about, and expect to be on the server.
	//    We need this information to detect if a a node has been deleted.
	//
	// 3. Do a full S3 LIST of the entire bucket.
	//    This is a recursive process, and may require a few requests to get the entire set.
	//
	// 4. Kick off the process to sync each container (in parallel)
	// 
	
	__block NSString *bucket = nil;
	__block AWSRegion region = AWSRegion_Invalid;
	
	NSString *const localUserID = pullState.localUserID;
	NSString *const zAppID = pullState.zAppID;
	
	NSArray<NSString *> *trunkIDs = @[
		[ZDCTrunkNode uuidForLocalUserID:localUserID zAppID:zAppID trunk:ZDCTreesystemTrunk_Home],
	//	[ZDCTrunkNode uuidForLocalUserID:localUserID zAppID:zAppID trunk:ZDCTreesystemTrunk_Prefs],
	//	[ZDCTrunkNode uuidForLocalUserID:localUserID zAppID:zAppID trunk:ZDCTreesystemTrunk_Inbox],
	//	[ZDCTrunkNode uuidForLocalUserID:localUserID zAppID:zAppID trunk:ZDCTreesystemTrunk_Outbox]
	];
	
	NSMutableArray<ZDCTrunkNode *> *trunkNodes = [NSMutableArray arrayWithCapacity:trunkIDs.count];
	
	[[self roConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Fetch needed information for the pull
		
		ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
		bucket = user.aws_bucket;
		region = user.aws_region;
		
		for (NSString *trunkID in trunkIDs)
		{
			ZDCTrunkNode *trunkNode = [transaction objectForKey:trunkID inCollection:kZDCCollection_Nodes];
			if (trunkNode) {
				[trunkNodes addObject:trunkNode];
			}
			else {
				NSAssert(NO, @"You forgot to create the container nodes when you created the localUser!");
			}
		}
		
		// Get a snapshot of which nodeIDs we expect to be on the server.
		
		NSArray<NSString *> *expectedNodeIDs =
		  [[ZDCNodeManager sharedInstance] allUploadedNodeIDsWithLocalUserID: localUserID
		                                                              zAppID: zAppID
		                                                         transaction: transaction];
		
		[pullState addUnprocessedNodeIDs:expectedNodeIDs];
		
		// Get a snapshot of which avatar files we expect to be on the server.
		
	//	NSArray<NSString *> *expectedAvatarFilenames =
	//	  [CloudNodeManager allUploadedAvatarFilenamesWithLocalUserID:localUserID transaction:transaction];
	//
	//	[pullState addUnprocessedAvatarFilenames:expectedAvatarFilenames];
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[self listBucket: bucket
		          region: region
		       pullState: pullState
		      completion:^(ZDCPullTaskResult *result)
		{
			NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
			
			if ([pullStateManager isPullCancelled:pullState]) {
				return;
			}
			
			if (result.pullResult != ZDCPullResult_Success)
			{
				finalCompletionBlock(nil, result);
				return;
			}
			
			ZDCPullTaskMultiCompletion *multiCompletion = nil;
			{ // Scoping
				
				ZDCPullTaskSingleCompletion taskCompletion =
				^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result, uint remaining){
	
					NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
					if (result.pullResult == ZDCPullResult_Success) {
						NSAssert(transaction != nil, @"Bad parameter for block: transaction is nil (with success status)");
					}
	
					dispatch_async(concurrentQueue, ^{ @autoreleasepool {
	
						if (![pullStateManager isPullCancelled:pullState]) {
							[self dequeueNextItemIfPossible:pullState];
						}
					}});
	
					DDLogTrace(@"[%@] Trunk nodes remaining = %u", pullState.localUserID, remaining);
				};
	
				multiCompletion =
				  [[ZDCPullTaskMultiCompletion alloc] initWithPendingCount: (uint)trunkNodes.count
				                                       taskCompletionBlock: taskCompletion
				                                      finalCompletionBlock: finalCompletionBlock];
			}
			
			for (ZDCTrunkNode *trunkNode in trunkNodes)
			{
				[self syncNode: trunkNode
				        bucket: bucket
				        region: region
				     pullState: pullState
				    completion: multiCompletion.wrapper];
			}
			
		//	[self syncAvatarsWithBucket: bucket
		//	                     region: region
		//	                  pullState: pullState
		//	                 completion: innerCompletionBlock]; Don't forget to change pendingCount initialization
			
			NSAssert(trunkNodes.count != 0, @"Pull is never going to complete!");
		}];
	}];
}

- (void)listBucket:(NSString *)bucket
            region:(AWSRegion)region
         pullState:(ZDCPullState *)pullState
        completion:(void(^)(ZDCPullTaskResult *result))completionBlock
{
	NSString *const localUserID = pullState.localUserID;
	DDLogTrace(@"[%@] List bucket: %@", localUserID, bucket);
	
	__block NSURLSessionDataTask *task = nil;
	
	__block void (^processingBlock)(NSURLResponse*, id, NSError *);
	__block void (^requestBlock)(void);
	__block void (^retryRequestBlock)(NSError *);
	
	__block NSUInteger failCount = 0;
	__block NSString *continuationToken = nil;
	
	processingBlock = ^(NSURLResponse *urlResponse, id responseObject, NSError *error) { @autoreleasepool {
		
		[pullState removeTask:task];
		
		// Certain errors should not be tried again.
		// These include:
		// - 401 (auth failed) : we need to alert user
		
		NSInteger statusCode = urlResponse.httpStatusCode;
		
		if (error)
		{
			NSData *data = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
			NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if (msg)
			{
				DDLogError(@"S3 list-dir: error.data: %@", msg);
			}
		}
		
		if (urlResponse && error)
		{
			error = nil; // we only care about non-server-response errors
		}
		
		if (error || (statusCode == 503))
		{
			// Try request again (using exponential backoff)
			
			failCount++;
			retryRequestBlock(error);
			return;
		}
		else if (statusCode == 401 || statusCode == 403) // Unauthorized
		{
			[zdc.networkTools handleAuthFailureForUser:localUserID withError:error pullState:pullState];
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Auth;
			result.pullErrorReason = ZDCPullErrorReason_AwsAuthError;
			
			completionBlock(result);
			return;
		}
		
		S3Response_ListBucket *s3Response = nil;
		
		if ([responseObject isKindOfClass:[S3Response class]])
		{
			s3Response = [(S3Response *)responseObject listBucket];
		}
		else if (statusCode == 200 && [responseObject isKindOfClass:[NSDictionary class]])
		{
			s3Response = [[S3ResponseParser parseJSONDict:(NSDictionary *)responseObject
			                                     withType:S3ResponseType_ListBucket] listBucket];
		}
		
		if (s3Response == nil)
		{
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Other;
			result.pullErrorReason = ZDCPullErrorReason_BadData;
			
			if ([responseObject isKindOfClass:[NSData class]])
			{
				NSString *msg = [[NSString alloc] initWithData:(NSData *)responseObject encoding:NSUTF8StringEncoding];
				if (msg)
				{
					NSString *errMsg = [NSString stringWithFormat:@"S3 list-dir: response: %@", msg];
					
					DDLogError(@"%@", errMsg);
					result.underlyingError = [self errorWithDescription:errMsg];
				}
			}
			
			completionBlock(result);
			return;
		}
		
		[pullState pushList:s3Response.objectList withRootNodeID:localUserID];
		
		if (s3Response.nextContinuationToken)
		{
			DDLogRed(@"s3Response.nextContinuationToken: %@", s3Response.nextContinuationToken);
			
			failCount = 0;
			continuationToken = s3Response.nextContinuationToken;
			
			requestBlock();
		}
		else
		{
			completionBlock([ZDCPullTaskResult success]);
		}
	}};
	
	// Setup the block that issues the HTTP request to the server.
	// We're either going to issue this request immediately,
	// or we're going to delay it due to exponential backoff,
	// which may be required if the server is experiencing overwhelming demand.
	
	requestBlock = ^{ @autoreleasepool {
		
		[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
		                                    completionQueue: concurrentQueue
		                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
 			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use processingBlock to execute exponential backoff.
					
					processingBlock(nil, nil, error);
					return;
				}
				else
				{
					[zdc.networkTools handleAuthFailureForUser: localUserID
					                                 withError: error
					                                 pullState: pullState];
					
					ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
					result.pullResult = ZDCPullResult_Fail_Auth;
					result.pullErrorReason = ZDCPullErrorReason_Auth0Error;
					result.underlyingError = error;
					
					completionBlock(result);
					return;
				}
			}
			
			ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		#if TARGET_OS_IPHONE
			AFURLSessionManager *session = sessionInfo.foregroundSession;
		#else
			AFURLSessionManager *session = sessionInfo.session;
		#endif
			
			NSString *prefix = [NSString stringWithFormat:@"%@/", pullState.zAppID];
			
			NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithCapacity:4];
			
			[queryItems addObject:[NSURLQueryItem queryItemWithName:@"list-type" value:@"2"]];
			[queryItems addObject:[NSURLQueryItem queryItemWithName:@"prefix"    value:prefix]];
			
			if (continuationToken) {
				[queryItems addObject:[NSURLQueryItem queryItemWithName:@"continuation-token" value:continuationToken]];
			}
			
			NSURLComponents *urlComponents = nil;
			NSMutableURLRequest *request =
			  [S3Request getBucket:bucket
			              inRegion:region
			        withQueryItems:queryItems
			      outUrlComponents:&urlComponents];
			
			[AWSSignature signRequest:request
			               withRegion:region
			                  service:AWSService_S3
			              accessKeyID:auth.aws_accessKeyID
			                   secret:auth.aws_secret
			                  session:auth.aws_session];
			
		#if DEBUG && robbie_hanson
			DDLogDonut(@"%@", [request zdcDescription]);
		#endif
			
			task = [session dataTaskWithRequest: request
			                     uploadProgress: nil
			                   downloadProgress: nil
			                  completionHandler: processingBlock];
			
			// Only start the task ([task resume]) if sync hasn't been cancelled.
			
			if (![pullStateManager isPullCancelled:pullState])
			{
				[pullState addTask:task];
				[task resume];
			}
		}];
	}};
	
	retryRequestBlock = ^(NSError *error){ @autoreleasepool {
		
		if (failCount > kMaxFailCount)
		{
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Other;
			result.pullErrorReason = ZDCPullErrorReason_ExceededMaxRetries;
			result.underlyingError = error;
			
			completionBlock(result);
			return;
		}
		
		NSTimeInterval delay = [zdc.networkTools exponentialBackoffForFailCount:failCount];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), concurrentQueue, ^{
			
			requestBlock();
		});
	}};
	
	requestBlock();
}

/**
 * Enumerates the listed items in the given directory, and processes each according to neeeds.
**/
- (void)syncNode:(ZDCNode *)node
          bucket:(NSString *)bucket
          region:(AWSRegion)region
       pullState:(ZDCPullState *)pullState
      completion:(ZDCPullTaskCompletion)nodeCompletion
{
	NSParameterAssert(node != nil);
	NSParameterAssert(bucket != nil);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(pullState != nil);
	NSParameterAssert(nodeCompletion != nil);
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		if ([pullStateManager isPullCancelled:pullState])
		{
			return;
		}
		
		ZDCTreesystemPath *log_path = nil;
		if (ddLogLevel & DDLogFlagTrace)
		{
			log_path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
			DDLogTrace(@"[%@] Sync node: %@", pullState.localUserID, log_path.fullPath);
		}
		
		// Step 1 of 4
		//
		// By the time this method is called, we already have a list of every item.
		// That is, we already have a `S3ObjectInfo` instance for each item in the cloud.
		//
		// All of these items are sitting in the pullState,
		// and we simply need to pop them based on their s3-key-prefix & anchor.
		
		ZDCNode *anchorNode = [[ZDCNodeManager sharedInstance] anchorNodeForNode:node transaction:transaction];
		
		NSString *zAppID = anchorNode.anchor.zAppID;
		if (!zAppID && [anchorNode isKindOfClass:[ZDCTrunkNode class]]) {
			zAppID = [(ZDCTrunkNode *)anchorNode zAppID];
		}
		
		NSString *rootNodeID = nil;
		if ([anchorNode isKindOfClass:[ZDCTrunkNode class]]) {
			rootNodeID = anchorNode.localUserID;
		}
		else {
			rootNodeID = anchorNode.uuid;
		}
		
		NSString *prefix = [NSString stringWithFormat:@"%@/%@/", zAppID, node.dirPrefix];
		NSArray<S3ObjectInfo *> *dirList = [pullState popListWithPrefix:prefix rootNodeID:rootNodeID];
		
		// Step 2 of 4
		//
		// Prep work for processing files & sub-directories.
	
		ZDCPullTaskMultiCompletion *multiCompletion = nil;
		{ // Scoping
			
			ZDCPullTaskSingleCompletion taskCompletion =
			^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result, uint remaining){
	
				NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
				if (result.pullResult == ZDCPullResult_Success) {
					NSAssert(transaction != nil, @"Bad parameter for block: transaction is nil (with success status)");
				}
	
				dispatch_async(concurrentQueue, ^{ @autoreleasepool {
	
					if (![pullStateManager isPullCancelled:pullState]) {
						[self dequeueNextItemIfPossible:pullState];
					}
				}});
	
				DDLogTrace(@"[%@] Syncing node's children (remaining=%u): %@",
							  pullState.localUserID, remaining, log_path.fullPath);
			};
	
			multiCompletion =
			  [[ZDCPullTaskMultiCompletion alloc] initWithPendingCount: 1 // Yes, one is correct. See last step.
			                                       taskCompletionBlock: taskCompletion
			                                      finalCompletionBlock: nodeCompletion];
		}
		
		NSMutableArray<S3ObjectInfo *>* remainingFiles = [dirList mutableCopy];
	
		S3ObjectInfo* (^PopFileWithExtension)(NSString*) = ^S3ObjectInfo* (NSString *inFileExtension){
			
			S3ObjectInfo *matchingInfo = nil;

			NSUInteger index = 0;
			for (S3ObjectInfo *info in remainingFiles)
			{
				NSString *fileExtension = [info.key pathExtension];
	
				if ([fileExtension isEqualToString:inFileExtension])
				{
					matchingInfo = info;
					[remainingFiles removeObjectAtIndex:index];
					break;
				}
	
				index++;
			}
	
			return matchingInfo;
		};
		
		S3ObjectInfo* (^PopFileWithKey)(NSString*) = ^S3ObjectInfo* (NSString *inKey){
			
			S3ObjectInfo *matchingInfo = nil;

			NSUInteger index = 0;
			for (S3ObjectInfo *info in remainingFiles)
			{
				if ([info.key isEqualToString:inKey])
				{
					matchingInfo = info;
					[remainingFiles removeObjectAtIndex:index];
					break;
				}
	
				index++;
			}
	
			return matchingInfo;
		};
		
		// Step 3 of 4
		//
		// Process all "*.rcrd" & "*.data" objects in the list,
		// and check them against what we have in our system.
		//
		// If we find any RCRD items that need to be downloaded, queue a download for them.
		// If we find any DATA items that have been updated,
		// update the corresponding S4Node & notify the delegate.
		
		NSArray<NSString*> *parents =
		  [[ZDCNodeManager sharedInstance] parentNodeIDsForNode:node transaction:transaction];
		parents = [parents arrayByAddingObject:node.uuid];
		
		S3ObjectInfo *nodeRcrd = nil;
		S3ObjectInfo *nodeData = nil;
	
		while ((nodeRcrd = PopFileWithExtension(kZDCCloudFileExtension_Rcrd)))
		{
			NSString *bareKey = [nodeRcrd.key stringByDeletingPathExtension];
			NSString *dataKey = [bareKey stringByAppendingPathExtension:kZDCCloudFileExtension_Data];
	
			nodeData = PopFileWithKey(dataKey);
			
			ZDCCloudPath *rcrdCloudPath = [ZDCCloudPath cloudPathFromPath:nodeRcrd.key];
			if (rcrdCloudPath == nil)
			{
				DDLogTrace(@"[%@] Ignoring invalid node path: %@", pullState.localUserID, nodeRcrd.key);
				continue;
			}
	
			// Here's what we know at this point (given the nodeRcrd & nodeData):
			// - the cloud path(s)
			// - the eTag(s)
			//
			// We cannot say, with certainty, anything about the RCRD contents unless:
			// - we have a matching S4Node in the database
			// - AND the eTags match
			//
			// Here are some cases to consider:
			//
			// 1. We have a matching S4Node, but one or more eTags don't match.
			//    (i.e. the RCRD and/or DATA fork have been modified)
			//
			// 2. We have a matching ZDCCloudNode, but not a matching S4Node because we deleted it.
			//    (i.e. we have a delete-node operation in the queue for the item)
			
			ZDCNode *node =
			  [[ZDCNodeManager sharedInstance] findNodeWithCloudPath: rcrdCloudPath
			                                                  bucket: bucket
			                                                  region: region
			                                             localUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                             transaction: transaction];
			
			if (node == nil)
			{
				ZDCCloudNode *cloudNode =
				  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: rcrdCloudPath
				                                                            bucket: bucket
				                                                            region: region
				                                                       localUserID: pullState.localUserID
				                                                       transaction: transaction];
				
				if (cloudNode && [cloudNode.eTag_rcrd isEqualToString:nodeRcrd.eTag])
				{
					// We already know about this item.
					// We have a ZDCCloudNode in the database because we've queued a delete operation for this node.
					
					continue;
				}
			}
	
			if (!node || ![node.eTag_rcrd isEqualToString:nodeRcrd.eTag])
			{
				// We either don't know about this node, or it's been changed.
				// If the node has been changed, then we have no way of knowing what changed.
				// There are several possibilities, such as:
				//
				// - the node was modified (e.g. the list of permissions changed)
				// - the original node was moved or deleted, and a new node was put in its place
				//
				// So we need to download the .rcrd file.
				// After parsing it we can decide the next processing step.
	
				ZDCPullItem *item = [[ZDCPullItem alloc] init];
				item.region = region;
				item.bucket = bucket;
				item.parents = parents;
				
				item.rcrdCloudPath = rcrdCloudPath;
				item.rcrdETag = nodeRcrd.eTag;
				item.rcrdLastModified = nodeRcrd.lastModified;
				
				item.dataCloudPath = [rcrdCloudPath copyWithFileNameExt:kZDCCloudFileExtension_Data];
				item.dataETag = nodeData.eTag;
				item.dataLastModified = nodeData.lastModified;
				
				item.rcrdCompletionBlock = multiCompletion.wrapper;
				item.ptrCompletionBlock = nil;
				item.dirCompletionBlock = multiCompletion.wrapper; // if node has children
				
				[multiCompletion incrementPendingCount:2];
				[self queuePullItem:item pullState:pullState];
			}
			else
			{
				// Node RCRD is up-to-date.
				[pullState removeUnprocessedNodeID:node.uuid];
				
				if (nodeData && ![nodeData.eTag isEqualToString:node.eTag_data])
				{
					node = [node copy];
					node.eTag_data = nodeData.eTag;
					
					[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
					
					ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
					[zdc.delegate didDiscoverModifiedNode: node
					                           withChange: ZDCNodeChange_Data
					                               atPath: path
					                          transaction: transaction];
				}
				
				if (node.isPointer)
				{
					ZDCNode *pointee = [transaction objectForKey:node.pointeeID inCollection:kZDCCollection_Nodes];
					
					if (pointee)
					{
						ZDCPullItem *item = [[ZDCPullItem alloc] init];
						item.region = region;
						item.bucket = bucket;
						item.parents = parents;
						
						item.rcrdCloudPath = rcrdCloudPath;
						item.rcrdETag = nodeRcrd.eTag;
						item.rcrdLastModified = nodeRcrd.lastModified;
						
						item.dataCloudPath = [rcrdCloudPath copyWithFileNameExt:kZDCCloudFileExtension_Data];
						item.dataETag = nodeData.eTag;
						item.dataLastModified = nodeData.lastModified;
						
						item.rcrdCompletionBlock = multiCompletion.wrapper;
						item.ptrCompletionBlock = nil;
						item.dirCompletionBlock = multiCompletion.wrapper; // if node has children
						
						[multiCompletion incrementPendingCount:2];
						[self syncPointeeNode: pointee
						          pointerNode: node
						             pullItem: item
						            pullState: pullState];
					}
				}
				else if (node.dirPrefix)
				{
					[multiCompletion incrementPendingCount:1];
					[self syncNode: node
					        bucket: bucket
					        region: region
					     pullState: pullState
					    completion: multiCompletion.wrapper];
				}
			}
	
		} // end: while ((nodeRcrd = PopFileWithExtension(kZDCCloudFileExtension_Rcrd)))
		
		// Step 4 of 4
		//
		// The pendingCount was initialized with a value of 1.
		// This was to prevent the innerCompletionBlock from completing before we've queued up all possible sub-tasks.
		// Now that all needed sub-tasks are queued, we can release it.
		//
		// At the same time, the processing of this directory may not have resulted in any other tasks being created.
		// So we need to invoke the innerCompletionBlock anyway.
		//
		// If there weren't any other sub-tasks, then we'll recursively call completionBlocks,
		// moving up the treesystem hierarchy until we reach a directory that isn't complete.
	
		multiCompletion.wrapper(transaction, [ZDCPullTaskResult success]);
	}];
}

/**
 * Called when a RCRD is fetched with encapsulates a pointer to a non-local location.
 * E.g. we encounter a RCRD in Alice's local bucket that points to Bob's bucket.
**/
- (void)syncPointeeNode:(ZDCNode *)pointeeNode
            pointerNode:(ZDCNode *)pointerNode
               pullItem:(ZDCPullItem *)pullItem
              pullState:(ZDCPullState *)pullState
{
	if (pointeeNode.isImmutable) {
		pointeeNode = [pointeeNode copy];
	}
	[pointerNode makeImmutable];
	
	__block ZDCUser *owner = nil;
	
	__block void(^Step1)(void);
	__block void(^Step2A)(void);
	__block void(^Step2B)(void);
	__block void(^Step3)(ZDCCloudPath*, ZDCCloudRcrd*, NSString*, NSDate*);
	__block void(^Step4)(ZDCCloudPath*);
	__block void(^Fail)(ZDCPullTaskResult*);
	__block void(^PermanentFail)(ZDCNodeConflict);
	
	// Step 1 of 4:
	//
	// Fetch the ZDCUser who owns the target node.
	// We need this information to obtain the correct AWS region & bucket.
	//
	Step1 = ^{ @autoreleasepool {
		
		NSString *const ownerID = pointeeNode.anchor.userID;
		
		// Attempt to fetch the user from the database.
		// If missing, the remoteUserManager will automatically download the user for us.
		//
		[zdc.remoteUserManager fetchRemoteUserWithID: ownerID
		                                 requesterID: pullState.localUserID
		                             completionQueue: concurrentQueue
		                             completionBlock:^(ZDCUser *remoteUser, NSError *error)
		{
			if (error)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_HttpStatusCode;
				result.underlyingError = error;
				
				Fail(result);
				return;
			}
			
			owner = remoteUser;
			
			if (owner.accountDeleted)
				PermanentFail(ZDCNodeConflict_Graft_DstUserAccountDeleted);
			else
				Step2A();
		}];
	}};
	
	// Step 2 of 4:
	//
	// Download the target node.
	//
	Step2A = ^{ @autoreleasepool {
		
		NSAssert(owner != nil, @"Bad state");
		
		ZDCCloudPath *cloudPath =
		  [[ZDCCloudPath alloc] initWithZAppID: pointeeNode.anchor.zAppID
		                             dirPrefix: pointeeNode.anchor.dirPrefix
		                              fileName: pointeeNode.explicitCloudName];
		
		DDLogTrace(@"[%@] Sync pointee: %@", pullState.localUserID, cloudPath);
		
		NSString *rcrdPath = [cloudPath pathWithExt:kZDCCloudFileExtension_Rcrd];
		
		[self fetchRcrd: rcrdPath
		         bucket: owner.aws_bucket
		         region: owner.aws_region
		      pullState: pullState
		     completion:
		^(ZDCCloudRcrd *cloudRcrd, NSData *responseData,
		  NSString *eTag, NSDate *lastModified, ZDCPullTaskResult *result)
		{
			if (result.pullResult != ZDCPullResult_Success)
			{
				// One would think AWS would return a 404 for files that no longer exist.
				// But one would be wrong !
				//
				// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
				//
				if (result.httpStatusCode == 404 || result.httpStatusCode == 403)
				{
					Step2B();
				}
				else
				{
					Fail(result);
				}
			}
			else if (cloudRcrd.cloudID && ![cloudRcrd.cloudID isEqual:pointeeNode.cloudID])
			{
				Step2B();
			}
			else if (cloudRcrd.cloudID == nil || cloudRcrd.encryptionKey == nil || cloudRcrd.metadata == nil)
			{
				PermanentFail(ZDCNodeConflict_Graft_DstNodeNotReadable);
			}
			else
			{
				Step3(cloudPath, cloudRcrd, eTag, lastModified);
			}
		}];
	}};
	
	// Step 2B of 4:
	//
	// If Step2 fails, use the /lostAndFound API as a backup plan.
	//
	Step2B = ^{ @autoreleasepool {
		
		[zdc.restManager lostAndFound: pointeeNode.cloudID
		                       bucket: owner.aws_bucket
		                       region: owner.aws_region
		                  requesterID: pullState.localUserID
		              completionQueue: concurrentQueue
		              completionBlock:
		^(NSURLResponse *response, id responseObject, NSError *error)
		{
			NSInteger statusCode = [response httpStatusCode];
			if (statusCode == 404)
			{
				PermanentFail(ZDCNodeConflict_Graft_DstNodeNotFound);
				return;
			}
			
			if (error)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_HttpStatusCode;
				result.underlyingError = error;
				
				Fail(result);
				return;
			}
			
			ZDCCloudPath *cloudPath = nil;
			NSString *eTag = nil;
			NSDate *lastModified = nil;
			NSDictionary *file = nil;
			
			NSDictionary *json = responseObject;
			if ([json isKindOfClass:[NSDictionary class]])
			{
				id value = nil;
				
				value = json[@"path"];
				if ([value isKindOfClass:[NSString class]])
				{
					cloudPath = [ZDCCloudPath cloudPathFromPath:(NSString *)value];
				}
				
				value = json[@"eTag"];
				if ([value isKindOfClass:[NSString class]])
				{
					eTag = (NSString *)value;
				}
				
				value = json[@"lastModified"];
				if ([value isKindOfClass:[NSNumber class]])
				{
					uint64_t millis = [value unsignedLongLongValue];
					NSTimeInterval seconds = (double)millis / (double)1000.0;
					
					lastModified = [NSDate dateWithTimeIntervalSince1970:seconds];
				}
				
				value = json[@"file"];
				if ([value isKindOfClass:[NSDictionary class]])
				{
					file = (NSDictionary *)value;
				}
			}
			
			if (!cloudPath || !eTag || !lastModified || !file)
			{
				NSError *error = [self errorWithDescription:@"/lostAndFound API returned malformed response"];
				
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_BadData;
				result.underlyingError = error;
				
				Fail(result);
				return;
			}
			
			__block ZDCCloudRcrd *cloudRcrd = nil;
			
			[[self decryptConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
				
				cloudRcrd = [zdc.cryptoTools parseCloudRcrdDict: file
				                                    localUserID: pullState.localUserID
				                                    transaction: transaction];
				
			} completionQueue:concurrentQueue completionBlock:^{
				
				if (cloudRcrd.cloudID == nil || cloudRcrd.encryptionKey == nil || cloudRcrd.metadata == nil)
				{
					PermanentFail(ZDCNodeConflict_Graft_DstNodeNotReadable);
				}
				else
				{
					Step3(cloudPath, cloudRcrd, eTag, lastModified);
				}
			}];
		}];
	}};
	
	// Step 3 of 4:
	//
	// After we've downloaded the node, we may need to update the database.
	//
	Step3 = ^(ZDCCloudPath *cloudPath, ZDCCloudRcrd *cloudRcrd, NSString *eTag, NSDate *lastModified){ @autoreleasepool {
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			if ([pullStateManager isPullCancelled:pullState])
			{
				DDLogTrace(@"[%@] Pull aborted", pullState.localUserID);
				return;
			}
			
			ZDCNodeManager *const nodeManager = [ZDCNodeManager sharedInstance];
			ZDCCloudTransaction *const cloudTransaction =
			  [self cloudTransactionForPullState:pullState transaction:transaction];
			
			// Check for cloudPath changes.
			//
			// This happens when the pointee node was moved or renamed,
			// and we had to use the /lostAndFound API to find it.
			
			NSString *cloudName = [cloudPath fileNameWithExt:nil];
			
			if (![pointeeNode.explicitCloudName isEqualToString:cloudName])
			{
				pointeeNode.explicitCloudName = cloudName;
			}
			
			if (![pointeeNode.anchor.zAppID isEqualToString:cloudPath.zAppID] ||
			    ![pointeeNode.anchor.dirPrefix isEqualToString:cloudPath.dirPrefix])
			{
				pointeeNode.anchor =
				  [[ZDCNodeAnchor alloc] initWithUserID: owner.uuid
				                                 zAppID: cloudPath.zAppID
				                              dirPrefix: cloudPath.dirPrefix];
			}
			
			// Check for filename changes.
			//
			// This is for case-sensitive renames, which aren't handled above.
			// The cloudName is case-insensitive.
			// HASH(filename.toLowercase(), parentDir.salt)
			
			NSString *filename = cloudRcrd.metadata[kZDCCloudRcrd_Meta_Filename];
			
			if (filename && ![filename isEqualToString:pointeeNode.name])
			{
				pointeeNode.name = filename;
			}
			
			// Check for encryptionKey changes.
			
			if (![cloudRcrd.encryptionKey isEqualToData:pointeeNode.encryptionKey])
			{
				pointeeNode.encryptionKey = cloudRcrd.encryptionKey;
			}
			
			// Check for permissions changes
			
			ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:cloudRcrd.share];
			if (shareList)
			{
				NSArray<NSDictionary*> *pendingChangesets =
				  [cloudTransaction pendingPermissionsChangesetsForNodeID:pointeeNode.uuid];
				
				NSError *mergeError = nil;
				[pointeeNode.shareList mergeCloudVersion: shareList
				                   withPendingChangesets: pendingChangesets
				                                   error: &mergeError];
				
				if (mergeError) {
					DDLogError(@"Error merging shareList: %@", mergeError);
				}
			}
			
			// Check for unknown users
			
			NSSet<NSString *> *unknownUserIDs = [self unknownUserIDsForNode:pointeeNode transaction:transaction];
			if (unknownUserIDs) {
				[pullState addUnknownUserIDs:unknownUserIDs];
			}
			
			// Check for other changes
			
			if (![pointeeNode.eTag_rcrd isEqual:eTag])
			{
				pointeeNode.eTag_rcrd = eTag;
			}
			if (![pointeeNode.lastModified_rcrd isEqual:lastModified])
			{
				pointeeNode.lastModified_rcrd = lastModified;
			}
			
			// If this is a new pointeeNode,
			// then we need to process those sections that aren't allowed to change:
			//
			// - dirSalt
			// - dirPrefix / children
			
			NSMutableArray<ZDCNode*> *children = nil;
			
			BOOL isNewPointer =
			  ![transaction hasObjectForKey:pointeeNode.uuid inCollection:kZDCCollection_Nodes] ||
			  ![transaction hasObjectForKey:pointerNode.uuid inCollection:kZDCCollection_Nodes];
			
			if (isNewPointer)
			{
				// Process dirSalt
				
				id dirSalt = cloudRcrd.metadata[kZDCCloudRcrd_Meta_DirSalt];
				if ([dirSalt isKindOfClass:[NSString class]])
				{
					dirSalt = [[NSData alloc] initWithBase64EncodedString:(NSString *)dirSalt options:0];
				}
				if ([dirSalt isKindOfClass:[NSData class]])
				{
					pointeeNode.dirSalt = dirSalt;
				}
				
				// Process children
				
				if (![cloudRcrd usingAdvancedChildrenContainer])
				{
					pointeeNode.dirPrefix = [cloudRcrd dirPrefix] ?: kZDCDirPrefix_Fake;
				}
				else // fixed set of children
				{
					pointeeNode.dirPrefix = kZDCDirPrefix_Fake;
					
					[cloudRcrd enumerateChildrenWithBlock:^(NSString *name, NSString *dirPrefix, BOOL *stop){
						
						ZDCNode *child =
						  [[ZDCNodeManager sharedInstance] findNodeWithName: name
						                                           parentID: pointeeNode.uuid
						                                        transaction: transaction];
						if (child == nil)
						{
							child = [[ZDCNode alloc] initWithLocalUserID:pullState.localUserID];
							
							child.parentID = pointeeNode.uuid;
							child.name = name;
							child.dirPrefix = dirPrefix;
							child.dirSalt = pointeeNode.dirSalt;
							
							child.eTag_rcrd = pointeeNode.eTag_rcrd;
							child.lastModified_rcrd = pointeeNode.lastModified_rcrd;
						}
						
						[children addObject:child];
					}];
				}
			}
			
			// Save changes & notify delegate
			
			if (isNewPointer)
			{
				[transaction setObject:pointeeNode forKey:pointeeNode.uuid inCollection:kZDCCollection_Nodes];
				[transaction setObject:pointerNode forKey:pointerNode.uuid inCollection:kZDCCollection_Nodes];
				
				ZDCTreesystemPath *path = [nodeManager pathForNode:pointerNode transaction:transaction];
				[zdc.delegate didDiscoverNewNode:pointerNode atPath:path transaction:transaction];
				
				for (ZDCNode *child in children)
				{
					if (child.isImmutable) {
						// Already had this child in the database - not new, not discovered
						continue;
					}
					
					[transaction setObject:child forKey:child.uuid inCollection:kZDCCollection_Nodes];
					
					ZDCTreesystemPath *path = [nodeManager pathForNode:child transaction:transaction];
					[zdc.delegate didDiscoverNewNode:child atPath:path transaction:transaction];
				}
			}
			else if (pointeeNode.hasChanges)
			{
				[transaction setObject:pointeeNode forKey:pointeeNode.uuid inCollection:kZDCCollection_Nodes];
				
				ZDCTreesystemPath *path = [nodeManager pathForNode:pointerNode transaction:transaction];
				[zdc.delegate didDiscoverModifiedNode: pointerNode
				                           withChange: ZDCNodeChange_Treesystem
				                               atPath: path
				                          transaction: transaction];
			}
			
			// Handle completionBlocks
			
			ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
			ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
			ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
			
			rcrdCompletionBlock(transaction, [ZDCPullTaskResult success]);
			
			if (ptrCompletionBlock || dirCompletionBlock)
			{
				Step4(cloudPath);
			}
		}];
	}};
	
	// Step 4 of 4:
	//
	// If we're being asked to recursively pull the sub-directories,
	// then we need to ask the server for the list of children under this node.
	//
	Step4 = ^(ZDCCloudPath *cloudPath){ @autoreleasepool {
		
		NSAssert(owner != nil, @"Bad state");
		
		ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
		ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
		
		NSAssert(( ptrCompletionBlock && !dirCompletionBlock) ||
		         (!ptrCompletionBlock &&  dirCompletionBlock), @"Unexpected state: XOR required");
		
		ZDCPullTaskCompletion completionBlock = ptrCompletionBlock ?: dirCompletionBlock;
		
		[ZDCProxyList recursiveProxyList: zdc
		                          region: owner.aws_region
		                          bucket: owner.aws_bucket
		                       cloudPath: cloudPath
		                       pullState: pullState
		                 completionQueue: concurrentQueue
		                 completionBlock:^(NSArray<S3ObjectInfo *> *list, NSError *error)
		{
			if (error)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_HttpStatusCode;
				result.underlyingError = error;
				
				completionBlock(nil, result);
				return;
			}
			
			[pullState pushList:list withRootNodeID:pointeeNode.uuid];
			
			[self syncNode: pointeeNode
			        bucket: owner.aws_bucket
			        region: owner.aws_region
			     pullState: pullState
			    completion: completionBlock];
		}];
	}};
	
	Fail = ^(ZDCPullTaskResult *result){ @autoreleasepool {
		
		ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
		ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
		ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
		
		rcrdCompletionBlock(nil, result);
		
		if (ptrCompletionBlock) {
			ptrCompletionBlock(nil, result);
		}
		
		if (dirCompletionBlock) {
			dirCompletionBlock(nil, result);
		}
	}};
	
	PermanentFail = ^(ZDCNodeConflict conflict){ @autoreleasepool {
		
		__weak id<ZeroDarkCloudDelegate> delegate = zdc.delegate;
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			ZDCNodeManager *nodeManager = [ZDCNodeManager sharedInstance];
			ZDCCloudTransaction *const cloudTransaction =
			  [self cloudTransactionForPullState:pullState transaction:transaction];
			
			ZDCNode *pointerNode = nil;
			while ((pointerNode = [nodeManager findNodeWithPointeeID: pointeeNode.uuid
			                                             localUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                             transaction: transaction]))
			{
				ZDCTreesystemPath *pointerPath =
				  [[ZDCNodeManager sharedInstance] pathForNode:pointerNode transaction:transaction];
				
				[delegate didDiscoverConflict: conflict
				                      forNode: pointerNode
				                       atPath: pointerPath
				                  transaction: transaction];
				
				[cloudTransaction deleteNode:pointerNode error:nil];
				
				[delegate didDiscoverDeletedNode: pointerNode
												  atPath: pointerPath
											  timestamp: nil
											transaction: transaction];
			}
			
			// Handle completionBlocks
			//
			// Although we failed to pull the pointee node,
			// the pull result itself succeeded.
			
			ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
			ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
			ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
			
			rcrdCompletionBlock(transaction, [ZDCPullTaskResult success]);
			
			if (ptrCompletionBlock) {
				ptrCompletionBlock(transaction, [ZDCPullTaskResult success]);
			}
			
			if (dirCompletionBlock) {
				dirCompletionBlock(transaction, [ZDCPullTaskResult success]);
			}
		}];
	}};
	
	Step1();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Queue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Using a queue allows us to add a bit of smarts to our pull algorithm.
 *
 * Rather than simply firing off each request immediately (i.e. pushing the task into the NSURLSession),
 * we instead create an item to represent the request, and add it to our queue.
 * Then we can dequeue items from the queue based on a bit of simplistic logic.
 *
 * In fact, we take it a step further, and allow the delegate to influence the algorithm.
 * This was inspired by the work we did in Storm4 to prioritize downloads of files
 * based on folders that the user is currently looking at.
 */
- (void)queuePullItem:(ZDCPullItem *)item
            pullState:(ZDCPullState *)pullState
{
	[pullState enqueueItem:item];
	[self dequeueNextItemIfPossible:pullState];
}

- (void)dequeueNextItemIfPossible:(ZDCPullState *)pullState
{
	if (pullState.tasksCount >= 8) {
		return;
	}
	
	NSSet<NSString *> *preferredNodeIDs = nil;
	if ([zdc.delegate respondsToSelector:@selector(preferredNodeIDsForPullingRcrds)]) {
		preferredNodeIDs = [zdc.delegate preferredNodeIDsForPullingRcrds];
	}
	
	// Smart dequeue algorithm
	ZDCPullItem *item = [pullState dequeueItemWithPreferredNodeIDs:preferredNodeIDs];
	if (item == nil) {
		return;
	}
	
	[self pullItem:item pullState:pullState];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Tools
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Pulls the *.rcrd item from server and updates the database.
 *
 * Will conditionally recurse into the node's children, if a non-nil dirCompletionBlock is given.
 */
- (void)pullItem:(ZDCPullItem *)pullItem pullState:(ZDCPullState *)pullState
{
	DDLogTrace(@"[%@] Pull item: %@", pullState.localUserID, pullItem.rcrdCloudPath);
	
	NSParameterAssert(pullItem != nil);
	NSParameterAssert(pullState != nil);
	
	NSParameterAssert(pullItem.region != AWSRegion_Invalid);
	NSParameterAssert(pullItem.bucket != nil);
	NSParameterAssert(pullItem.rcrdCloudPath != nil);
	
	NSParameterAssert(pullItem.parents.count > 0);
	
	NSParameterAssert(pullItem.rcrdCompletionBlock != nil);
	
	// If this method is being invoked, it means we found changes on the server.
	if ([pullState isFirstChangeDetected])
	{
		// Send signal to localUserManager.
		// This allows it to update its internal state, and also post a NSNotification for the user.
		
		[zdc.syncManager notifyPullFoundChangesForLocalUserID: pullState.localUserID
		                                               zAppID: pullState.zAppID];
	}
	
	[self fetchRcrd: [pullItem.rcrdCloudPath path]
	         bucket: pullItem.bucket
	         region: pullItem.region
	      pullState: pullState
	     completion:^(ZDCCloudRcrd *cloudRcrd, NSData *responseData, NSString *eTag, NSDate *lastModified,
	                  ZDCPullTaskResult *result)
	{
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			// Pull failure.
			//
			// Possible reasons:
			// - Authentication failure
			// - Network failure
			// - Cloud contents changed mid-pull
			
			DDLogInfo(@"[%@] FetchRcrd failure: %@", pullState.localUserID, result);
			
			ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
			ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
			ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
			
			rcrdCompletionBlock(nil, result);
			if (ptrCompletionBlock) {
				ptrCompletionBlock(nil, result);
			}
			if (dirCompletionBlock) {
				dirCompletionBlock(nil, result);
			}
			return;
		}
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			if ([pullStateManager isPullCancelled:pullState])
			{
				DDLogTrace(@"[%@] Pull aborted", pullState.localUserID);
				return;
			}
			
			if (cloudRcrd.cloudID == nil || cloudRcrd.encryptionKey == nil || cloudRcrd.metadata == nil)
			{
				DDLogTrace(@"[%@] No read-permissions for node: %@",
				           pullState.localUserID,
				           [pullItem.rcrdCloudPath pathWithExt:nil]);
				
				[self createOrUpdateCloudNode: pullItem
				                         eTag: eTag
				                 lastModified: lastModified
				                    pullState: pullState
				                  transaction: transaction];
				return;
			}
			
			NSString *parentID = [pullItem.parents lastObject];
			
			ZDCNode *node =
			  [self findNodeWithRemoteCloudPath: pullItem.rcrdCloudPath
			                          cloudRcrd: cloudRcrd
				                        parentID: parentID
			                          pullState: pullState
			                        transaction: transaction];
			
			if (node) {
				[pullState removeUnprocessedNodeID:node.uuid];
			}
			
			if (node)
			{
				[self updateNode: node
				   withCloudRcrd: cloudRcrd
				        pullItem: pullItem
				       pullState: pullState
				     transaction: transaction];
			}
			else
			{
				[self createNodeWithCloudRcrd: cloudRcrd
				                     parentID: parentID
				                     pullItem: pullItem
				                    pullState: pullState
				                  transaction: transaction];
			}
			
		}]; // end: [[self rwConnection] asyncReadWriteWithBlock:...]
		
	}]; // end: [self fetchRcrd:...]
}

- (void)createOrUpdateCloudNode:(ZDCPullItem *)pullItem
                           eTag:(NSString *)eTag
                   lastModified:(NSDate *)lastModified
                      pullState:(ZDCPullState *)pullState
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCCloudNode *cloudNode =
	  [[ZDCCloudNodeManager sharedInstance]
	    findCloudNodeWithCloudPath: pullItem.rcrdCloudPath
	                        bucket: pullItem.bucket
	                        region: pullItem.region
	                   localUserID: pullState.localUserID
	                   transaction: transaction];
	
	if (cloudNode == nil)
	{
		ZDCCloudLocator *cloudLocator =
		  [[ZDCCloudLocator alloc] initWithRegion: pullItem.region
		                                   bucket: pullItem.bucket
		                                cloudPath: pullItem.rcrdCloudPath];
		
		cloudNode =
		  [[ZDCCloudNode alloc] initWithLocalUserID: pullState.localUserID
		                               cloudLocator: cloudLocator];
	}
	
	if (![cloudNode.eTag_rcrd isEqual:eTag]) {
		cloudNode.eTag_rcrd = eTag;
	}
	if (pullItem.dataETag && ![cloudNode.eTag_data isEqual:pullItem.dataETag]) {
		cloudNode.eTag_data = pullItem.dataETag;
	}
	
	[transaction setObject:cloudNode forKey:cloudNode.uuid inCollection:kZDCCollection_CloudNodes];
	
	ZDCPullTaskResult *result = [ZDCPullTaskResult success];
	
	ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
	ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
	ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
	
	rcrdCompletionBlock(transaction, result);
	if (ptrCompletionBlock) {
		ptrCompletionBlock(transaction, result);
	}
	if (dirCompletionBlock) {
		dirCompletionBlock(transaction, result);
	}
}

/**
 * Helper method, used by `pullItem::`
 */
- (nullable ZDCNode *)findNodeWithRemoteCloudPath:(ZDCCloudPath *)remoteCloudPath
                                        cloudRcrd:(ZDCCloudRcrd *)cloudRcrd
                                         parentID:(NSString *)parentID
                                        pullState:(ZDCPullState *)pullState
                                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCNodeManager *const nodeManager = [ZDCNodeManager sharedInstance];
	ZDCCloudPathManager *const cloudPathManager = [ZDCCloudPathManager sharedInstance];
	
	ZDCCloudTransaction *const cloudTransaction = [self cloudTransactionForPullState:pullState transaction:transaction];
	
	NSString *remoteCloudName = [remoteCloudPath fileNameWithExt:nil];
	
	// Search for a matching node in the database.
	//
	// Search in the following order:
	// 1. look for a node with matching cloudID
	// 2. look for a node with matching <cloudName, parentID>
	
	BOOL cloudIDMatches = NO;
	BOOL cloudPathMatches = NO;
	
	ZDCNode *node =
	  [nodeManager findNodeWithCloudID: cloudRcrd.cloudID
	                       localUserID: pullState.localUserID
	                            zAppID: pullState.zAppID
	                       transaction: transaction];
	if (node)
	{
		cloudIDMatches = YES;
		
		ZDCCloudPath *localCloudPath =
		  [cloudPathManager cloudPathForNode: node
		                       fileExtension: kZDCCloudFileExtension_Rcrd
		                         transaction: transaction];
		
		cloudPathMatches = [remoteCloudPath isEqualToCloudPath:localCloudPath];
		if (!cloudPathMatches)
		{
			// The localCloudPath won't match if we have a MOVE operation in the queue
			// which hasn't been executed on the server yet.
		
			NSArray<ZDCCloudPath *> *possibilities = [cloudTransaction potentialCloudPathsForNodeID:node.uuid];
			for (ZDCCloudPath *possibleCloudPath in possibilities)
			{
				if ([possibleCloudPath isEqualToCloudPathIgnoringExt:remoteCloudPath])
				{
					cloudPathMatches = YES;
				}
			}
		}
	}
	else
	{
		node = [nodeManager findNodeWithCloudName: remoteCloudName
		                                 parentID: parentID
		                              transaction: transaction];
		if (node) {
			cloudPathMatches = YES;
		}
	}
	
	// Check to see if this node needs to be moved or marked as deleted.
	//
	// AKA - edge case checking
	
	if (node)
	{
		if (!cloudIDMatches && cloudPathMatches && !node.cloudID)
		{
			// This may actually be our uploaded rcrd.
			// In other words:
			// - we created the node locally
			// - the PushManager just pushed this item to the cloud
			// - and now the PullManager is seeing it before the PushManager
			//   has had a chance to update the node in the database.
			//
			// So how can we reliably detect this ?
			//
			// We can compare the randomly generated encryptionKey.
			
			if ([node.encryptionKey isEqualToData:cloudRcrd.encryptionKey])
			{
				// Yup, that's us.
				// Let's set the cloudID value.
				
				cloudIDMatches = YES;
				
				node = [node copy];
				node.cloudID = cloudRcrd.cloudID;
				
				[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
			}
		}
				
		if (cloudIDMatches && !cloudPathMatches)
		{
			BOOL parentMatches = [node.parentID isEqualToString:parentID];
			
			NSString *localCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
			BOOL cloudNameMatches = [localCloudName isEqualToString:remoteCloudName];
					
			if (!parentMatches || !cloudNameMatches)
			{
				// The node has been moved and/or renamed.
				// So we need to update it within the database.
			
				ZDCTreesystemPath *oldCleartextPath =
				  [nodeManager pathForNode:node transaction:transaction];
				
				ZDCCloudLocator *oldCloudLocator_bare =
				  [cloudPathManager cloudLocatorForNode: node
				                          fileExtension: nil
				                            transaction: transaction];
				
				node = [node copy];
		
				NSString *prvParentID = nil;
				if (!parentMatches)
				{
					prvParentID = node.parentID;
					node.parentID = parentID; // parentID change -> requires cloudName change
				}
		
				if (!cloudNameMatches)
				{
					node.name = cloudRcrd.metadata[kZDCCloudRcrd_Meta_Filename]; // name change -> requires cloudName change
				}
		
				localCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
				if ([localCloudName isEqualToString:remoteCloudName])
				{
					node.explicitCloudName = nil; // clear if present
				}
				else
				{
					DDLogWarn(@"Hash Mismatch: calculated cloudName(%@) != remoteCloudName(%@)",
								  localCloudName, remoteCloudName);
		
					node.explicitCloudName = remoteCloudName;
				}
		
				[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
			
				ZDCTreesystemPath *newCleartextPath =
				  [nodeManager pathForNode:node transaction:transaction];
				
				ZDCCloudLocator *newCloudLocator_bare =
				  [cloudPathManager cloudLocatorForNode: node
				                          fileExtension: nil
				                            transaction: transaction];
			
				// Since the node was moved by another device, their move takes precedence over ours.
				// So we must skip any queued move operations for the node.
				
				[cloudTransaction skipMoveOperationsForNodeID:node.uuid excluding:nil];
				
				// Modify any operations that are sitting in the queue for this file.
				// Since the node has a new cloudPath, we need to change these operations to match.
				
				ZDCCloudLocator *oldCloudLocator_rcrd = nil;
				ZDCCloudLocator *newCloudLocator_rcrd = nil;
				
				ZDCCloudLocator *oldCloudLocator_data = nil;
				ZDCCloudLocator *newCloudLocator_data = nil;
			
				oldCloudLocator_rcrd = [oldCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				newCloudLocator_rcrd = [newCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				
				oldCloudLocator_data = [oldCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Data];
				newCloudLocator_data = [newCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Data];
				
				[cloudTransaction moveCloudLocator:oldCloudLocator_bare toCloudLocator:newCloudLocator_bare];
				[cloudTransaction moveCloudLocator:oldCloudLocator_rcrd toCloudLocator:newCloudLocator_rcrd];
				[cloudTransaction moveCloudLocator:oldCloudLocator_data toCloudLocator:newCloudLocator_data];
				
				// Notify the delegate
				
				[zdc.delegate didDiscoverMovedNode: node
				                              from: oldCleartextPath
				                                to: newCleartextPath
				                       transaction: transaction];
			}
		}
		else if (!cloudIDMatches && cloudPathMatches)
		{
			// There's a node on the server with name <X>,
			// and a local node with the same name <X>. (Both in the same directory.)
			//
			// One of the following is true:
			// - The local node hasn't been pushed to the server yet.
			// - The local node currently exists on the server, but in a different directory.
			//   That is, the local node has been moved to this directory on the local device,
			//   but the move operation hasn't hit the server yet.
			//
			// So we need resolve the conflict somehow.
			// And we start by notifying the delegate.
			
			ZDCTreesystemPath *cleartextPath =
			  [nodeManager pathForNode:node transaction:transaction];
			
			[zdc.delegate didDiscoverConflict: ZDCNodeConflict_Path
			                          forNode: node
			                           atPath: cleartextPath
			                      transaction: transaction];
			
			// Did the delegate take action ?
			
			node = [nodeManager findNodeWithCloudName: remoteCloudName
			                                 parentID: parentID
			                              transaction: transaction];
			
			if (node)
			{
				// Delegate did not resolve conflict.
				// We are going to automatically rename the node.
				
				ZDCTreesystemPath *oldCleartextPath = cleartextPath;
				
				ZDCCloudLocator *oldCloudLocator_bare =
				  [cloudPathManager cloudLocatorForNode: node
				                          fileExtension: nil
				                            transaction: transaction];
				
				NSString *newName = [nodeManager resolveNamingConflictForNode:node transaction:transaction];
				
				node = [node copy];
				node.name = newName;
				node.explicitCloudName = nil;
				
				NSString *localCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
				if (![localCloudName isEqualToString:remoteCloudName])
				{
					DDLogWarn(@"Hash Mismatch: calculated cloudName(%@) != remoteCloudName(%@)",
								 localCloudName, remoteCloudName);
					
					node.explicitCloudName = remoteCloudName;
				}
				
				[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
				
				ZDCTreesystemPath *newCleartextPath =
				  [nodeManager pathForNode:node transaction:transaction];
				
				ZDCCloudLocator *newCloudLocator_bare =
				  [cloudPathManager cloudLocatorForNode: node
				                          fileExtension: nil
				                            transaction: transaction];
						
				// Modify any operations that are sitting in the queue for this file.
				// Since the node has a new cloudPath, we need to change these operations to match.
				
				ZDCCloudLocator *oldCloudLocator_rcrd = nil;
				ZDCCloudLocator *newCloudLocator_rcrd = nil;
				
				ZDCCloudLocator *oldCloudLocator_data = nil;
				ZDCCloudLocator *newCloudLocator_data = nil;
				
				oldCloudLocator_rcrd = [oldCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				newCloudLocator_rcrd = [newCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				
				oldCloudLocator_data = [oldCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Data];
				newCloudLocator_data = [newCloudLocator_bare copyWithFileNameExt:kZDCCloudFileExtension_Data];
				
				[cloudTransaction moveCloudLocator:oldCloudLocator_bare toCloudLocator:newCloudLocator_bare];
				[cloudTransaction moveCloudLocator:oldCloudLocator_rcrd toCloudLocator:newCloudLocator_rcrd];
				[cloudTransaction moveCloudLocator:oldCloudLocator_data toCloudLocator:newCloudLocator_data];
				
				// Notify the delegate
				
				[zdc.delegate didDiscoverMovedNode: node
				                              from: oldCleartextPath
				                                to: newCleartextPath
				                       transaction: transaction];
				
				// This means we don't actually have a matching node for this file.
				
				node = nil;
			}
		}
	}
	
	return node;
}

/**
 * Helper method, used by `pullItem::`
 */
- (void)updateNode:(ZDCNode *)node
     withCloudRcrd:(ZDCCloudRcrd *)cloudRcrd
          pullItem:(ZDCPullItem *)pullItem
         pullState:(ZDCPullState *)pullState
       transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCNodeManager *const nodeManager = [ZDCNodeManager sharedInstance];
	
	ZDCCloudTransaction *const cloudTransaction = [self cloudTransactionForPullState:pullState transaction:transaction];
	
	// Update node's info (if needed).
	
	if (node.isImmutable) {
		node = [node copy];
	}
	
	// Check for filename changes.
	//
	// This is for case-sensitive renames, which aren't handled above.
	// The cloudName is case-insensitive.
	// HASH(filename.toLowercase(), parentDir.salt)

	NSString *filename = cloudRcrd.metadata[kZDCCloudRcrd_Meta_Filename];

	if (filename && ![filename isEqualToString:node.name])
	{
		node.name = filename;
	}

	// Check for encryptionKey changes.

	if (![cloudRcrd.encryptionKey isEqualToData:node.encryptionKey])
	{
		node.encryptionKey = cloudRcrd.encryptionKey;
	}
	
	// Check for permissions changes
	
	ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:cloudRcrd.share];
	if (shareList)
	{
		NSArray<NSDictionary*> *pendingChangesets = [cloudTransaction pendingPermissionsChangesetsForNodeID:node.uuid];
		
		NSError *mergeError = nil;
		[node.shareList mergeCloudVersion: shareList
						withPendingChangesets: pendingChangesets
											 error: &mergeError];
		
		if (mergeError) {
			DDLogError(@"Error merging shareList: %@", mergeError);
		}
	}
	
	// Check for unknown users
	
	NSSet<NSString *> *unknownUserIDs = [self unknownUserIDsForNode:node transaction:transaction];
	if (unknownUserIDs) {
		[pullState addUnknownUserIDs:unknownUserIDs];
	}
	
	// Save changes
	
	if (node.hasChanges)
	{
		[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
		
		ZDCTreesystemPath *path = [nodeManager pathForNode:node transaction:transaction];
		[zdc.delegate didDiscoverModifiedNode: node
		                           withChange: ZDCNodeChange_Treesystem
		                               atPath: path
		                          transaction: transaction];
	}
	
	// Handle completionBlocks
	
	ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
	ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
	ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;
	
	rcrdCompletionBlock(transaction, [ZDCPullTaskResult success]);
	
	if (node.isPointer && (ptrCompletionBlock || dirCompletionBlock))
	{
		ZDCNode *pointee = nil;
		if (node.pointeeID) {
			pointee = [transaction objectForKey:node.pointeeID inCollection:kZDCCollection_Nodes];
		}
		
		pullItem.rcrdCompletionBlock = pullItem.ptrCompletionBlock;
		pullItem.ptrCompletionBlock = nil;
		
		[self syncPointeeNode: pointee
		          pointerNode: node
		             pullItem: pullItem
		            pullState: pullState];
		return;
	}
	
	if (ptrCompletionBlock) {
		// Not a pointer
		ptrCompletionBlock(transaction, [ZDCPullTaskResult success]);
	}
	
	if (dirCompletionBlock)
	{
		if ([node.dirPrefix isEqualToString:kZDCDirPrefix_Fake])
		{
			// Node is using a deprecated RCRD format in the cloud (i.e. Storm4).
			// It's using the old cleartext children style.
			// So the node doesn't actually have any direct children.
			
			NSMutableArray<ZDCNode*> *children = [NSMutableArray arrayWithCapacity:3];
			
			[nodeManager enumerateNodesWithParentID: node.uuid
			                            transaction: transaction
			                             usingBlock:^(ZDCNode *child, BOOL *stop)
			{
				[children addObject:child];
			}];
			
			ZDCPullTaskMultiCompletion *multiCompletion =
			  [[ZDCPullTaskMultiCompletion alloc] initWithPendingCount: (uint)children.count
			                                       taskCompletionBlock: nil
			                                      finalCompletionBlock: dirCompletionBlock];
			
			for (ZDCNode *child in children)
			{
				[self syncNode: child
				        bucket: pullItem.bucket
				        region: pullItem.region
				     pullState: pullState
				    completion: multiCompletion.wrapper];
			}
		}
		else if (node.dirPrefix && node.dirSalt)
		{
			// Modern RCRD format.
			// Scan the node's children.
			
			[self syncNode: node
			        bucket: pullItem.bucket
			        region: pullItem.region
			     pullState: pullState
			    completion: dirCompletionBlock];
		}
		else
		{
			// Node doesn't have any children
			
			dirCompletionBlock(transaction, [ZDCPullTaskResult success]);
		}
	}
}

- (void)createNodeWithCloudRcrd:(ZDCCloudRcrd *)cloudRcrd
                       parentID:(NSString *)parentID
                       pullItem:(ZDCPullItem *)pullItem
                      pullState:(ZDCPullState *)pullState
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCNodeManager *const nodeManager = [ZDCNodeManager sharedInstance];
	
	NSString *remoteCloudName = [pullItem.rcrdCloudPath fileNameWithExt:nil];
	
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:pullState.localUserID];
	node.parentID = parentID;
	
	NSString *filename = cloudRcrd.metadata[kZDCCloudRcrd_Meta_Filename];
	if (filename)
	{
		node.name = filename;
		
		NSString *localCloudName = [[ZDCCloudPathManager sharedInstance] cloudNameForNode:node transaction:transaction];
		if (![localCloudName isEqualToString:remoteCloudName])
		{
			DDLogWarn(@"Hash Mismatch: calculated cloudName(%@) != remoteCloudName(%@)",
						localCloudName, remoteCloudName);
			
			node.explicitCloudName = remoteCloudName;
		}
	}
	else
	{
		node.name = remoteCloudName;
		node.explicitCloudName = remoteCloudName;
	}
	
	node.senderID = cloudRcrd.sender;
	
	node.cloudID = cloudRcrd.cloudID;
	node.encryptionKey = cloudRcrd.encryptionKey;

	node.eTag_rcrd = pullItem.rcrdETag;
	node.lastModified_rcrd = pullItem.rcrdLastModified;

	node.eTag_data = pullItem.dataETag;
	node.lastModified_data = pullItem.dataLastModified;

	id dirSalt = cloudRcrd.metadata[kZDCCloudRcrd_Meta_DirSalt];
	if ([dirSalt isKindOfClass:[NSString class]])
	{
		dirSalt = [[NSData alloc] initWithBase64EncodedString:(NSString *)dirSalt options:0];
	}
	if ([dirSalt isKindOfClass:[NSData class]])
	{
		node.dirSalt = dirSalt;
	}
	
	ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:cloudRcrd.share];
	if (shareList)
	{
		NSError *mergeError = nil;
		[node.shareList mergeCloudVersion: shareList
						withPendingChangesets: nil
											 error: &mergeError];
		
		if (mergeError) {
			DDLogError(@"Error merging shareList: %@", mergeError);
		}
	}
	else
	{
		// This shouldn't happen.
		// But if it does, let's at least give the node a set of sane permissions.
		
		[nodeManager resetPermissionsForNode:node transaction:transaction];
	}
	
	NSSet<NSString *> *unknownUserIDs = [self unknownUserIDsForNode:node transaction:transaction];
	if (unknownUserIDs) {
		[pullState addUnknownUserIDs:unknownUserIDs];
	}
	
	NSMutableArray<ZDCNode*> *children = nil;
	
	ZDCNode *pointee = [self createPointeeWithCloudRcrd:cloudRcrd pullState:pullState transaction:transaction];
	if (pointee)
	{
		node.pointeeID = pointee.uuid;
		node.dirPrefix = kZDCDirPrefix_Fake;
		
		// Pointers aren't allowed to have children.
		//
		// And we're not allowed to store the pointerNode until we've downloaded the pointeeNode's RCRD file.
		// They need to be stored in the database together.
		// And the pointerNode needs to be valid before we can notify the delegate.
		//
		// This is because the delegate may want to download the node.
		// Which means, what actually gets downloaded is the pointeeNode's DATA file.
		// So the pointeeNode needs to be accurate.
		
		[self syncPointeeNode: pointee
		          pointerNode: node
		             pullItem: pullItem
		            pullState: pullState];
		return;
	}
	
	if (![cloudRcrd usingAdvancedChildrenContainer])
	{
		node.dirPrefix = [cloudRcrd dirPrefix] ?: kZDCDirPrefix_Fake;
	}
	else // fixed set of children
	{
		node.dirPrefix = kZDCDirPrefix_Fake;
		children = [NSMutableArray arrayWithCapacity:3];
		
		[cloudRcrd enumerateChildrenWithBlock:^(NSString *name, NSString *dirPrefix, BOOL *stop){
			
			ZDCNode *child =
			  [nodeManager findNodeWithName: name
			                       parentID: node.uuid
			                    transaction: transaction];
			
			if (child == nil)
			{
				child = [[ZDCNode alloc] initWithLocalUserID:pullState.localUserID];
				
				child.parentID = node.uuid;
				child.name = name;
				child.dirPrefix = dirPrefix;
				child.dirSalt = node.dirSalt;
		
				child.eTag_rcrd = node.eTag_rcrd;
				child.lastModified_rcrd = node.lastModified_rcrd;
			}
			
			[children addObject:child];
		}];
	}
	
	[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];

	ZDCTreesystemPath *path = [nodeManager pathForNode:node transaction:transaction];
	[zdc.delegate didDiscoverNewNode:node atPath:path transaction:transaction];

	for (ZDCNode *child in children)
	{
		if (child.isImmutable) {
			// Already had this child in the database - not new, not discovered
			continue;
		}
		
		[transaction setObject:child forKey:child.uuid inCollection:kZDCCollection_Nodes];
		
		ZDCTreesystemPath *path = [nodeManager pathForNode:child transaction:transaction];
		[zdc.delegate didDiscoverNewNode:child atPath:path transaction:transaction];
	}
	
	// Handle completionBlocks
	
	ZDCPullTaskCompletion rcrdCompletionBlock = pullItem.rcrdCompletionBlock;
	ZDCPullTaskCompletion ptrCompletionBlock = pullItem.ptrCompletionBlock;
	ZDCPullTaskCompletion dirCompletionBlock = pullItem.dirCompletionBlock;

	rcrdCompletionBlock(transaction, [ZDCPullTaskResult success]);
	
	if (ptrCompletionBlock) {
		// Not a pointer
		ptrCompletionBlock(transaction, [ZDCPullTaskResult success]);
	}
	
	if (dirCompletionBlock)
	{
		if (children)
		{
			// Node is using a deprecated RCRD format in the cloud (i.e. Storm4).
			// It's using the old cleartext children style.
			// So the node doesn't actually have any direct children.
			
			ZDCPullTaskMultiCompletion *multiCompletion =
			  [[ZDCPullTaskMultiCompletion alloc] initWithPendingCount: (uint)children.count
			                                       taskCompletionBlock: NULL
			                                      finalCompletionBlock: dirCompletionBlock];
			
			for (ZDCNode *child in children)
			{
				[self syncNode: child
				        bucket: pullItem.bucket
				        region: pullItem.region
				     pullState: pullState
				    completion: multiCompletion.wrapper];
			}
		}
		else if (node.dirPrefix && node.dirSalt)
		{
			// Modern RCRD format.
			// Scan the node's children.
			
			[self syncNode: node
			        bucket: pullItem.bucket
			        region: pullItem.region
			     pullState: pullState
			    completion: dirCompletionBlock];
		}
		else
		{
			// Node doesn't have any children
			
			dirCompletionBlock(transaction, [ZDCPullTaskResult success]);
		}
	}
}

- (nullable ZDCNode *)createPointeeWithCloudRcrd:(ZDCCloudRcrd *)cloudRcrd
                                       pullState:(ZDCPullState *)pullState
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	ZDCNodeManager *const nodeManager = [ZDCNodeManager sharedInstance];
	
	ZDCCloudPath *pointer_cloudPath = nil;
	NSString *pointer_cloudID = nil;
	NSString *pointer_ownerID = nil;
	
	BOOL isPointer = [cloudRcrd getPointerCloudPath: &pointer_cloudPath
	                                        cloudID: &pointer_cloudID
	                                        ownerID: &pointer_ownerID];
	
	if (!isPointer)
	{
		return nil;
	}
	
	if ([pointer_ownerID isEqualToString:pullState.localUserID])
	{
		DDLogWarn(@"Ignoring pointer to localUser's own treesystem");
		return nil;
	}
	
	ZDCNode *pointee =
	  [nodeManager findNodeWithCloudID: pointer_cloudID
	                       localUserID: pullState.localUserID
	                            zAppID: pullState.zAppID
	                       transaction: transaction];
	if (pointee)
	{
		NSString *ownerID = [nodeManager ownerIDForNode:pointee transaction:transaction];
		if (![ownerID isEqualToString:pointer_ownerID])
		{
			DDLogWarn(@"Ignoring bad pointer - cloudID collision detected");
			return nil;
		}
	}
	
	if (pointee == nil)
	{
		pointee = [[ZDCNode alloc] initWithLocalUserID:pullState.localUserID];
		pointee.parentID = [NSString stringWithFormat:@"%@|%@|graft", pullState.localUserID, pullState.zAppID];
		
		pointee.name = @"unknown";
		pointee.explicitCloudName = [pointer_cloudPath fileNameWithExt:nil];
		
		pointee.cloudID = pointer_cloudID;
		pointee.anchor =
		  [[ZDCNodeAnchor alloc] initWithUserID: pointer_ownerID
		                                 zAppID: pointer_cloudPath.zAppID
		                              dirPrefix: pointer_cloudPath.dirPrefix];
	}
	
	return pointee;
}

/**
 * Use this method when it's discovered that a file/directory was deleted remotely.
 * That is, the delete was performed by another device/user.
 *
 * This method will determine if its safe to delete the node and any descendents.
 * It will then only delete what it can safely,
 * and update the appropriate ZDCCloudNode entries.
**/
- (void)remoteDeleteNode:(ZDCNode *)rootDeletedNode
               timestamp:(nullable NSDate *)timestamp
               pullState:(ZDCPullState *)pullState
             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSString *const rootDeletedNodeID = rootDeletedNode.uuid;
	ZDCTreesystemPath *rootDeletedPath =
	  [[ZDCNodeManager sharedInstance] pathForNode:rootDeletedNode transaction:transaction];
	
	NSMutableSet<NSString *> *allNodeIDs = [NSMutableSet set];
	[allNodeIDs addObject:rootDeletedNodeID];
	
	[[ZDCNodeManager sharedInstance] recursiveEnumerateNodeIDsWithParentID: rootDeletedNode.uuid
																				  transaction: transaction
																					usingBlock:
		^(NSString *nodeID, NSArray<NSString*> *pathFromParent, BOOL *recurseInto, BOOL *stop)
	{
		[allNodeIDs addObject:nodeID];
	}];
	
	// We can delete the node if it's "clean".
	// But if it's "dirty" (has pending changes), we'll have to adapt.
	//
	// We need to:
	// - check to see if there are any "dirty" nodes
	//   * that is, any nodes with changes that are queued to be pushed to the cloud
	//   * this includes any children of the deleted node
	// - delete all the "clean" node
	
	NSMutableSet<NSString *> *dirtyNodeIDs = [NSMutableSet set];
	
	NSString *extName = [zdc.databaseManager cloudExtNameForUser:pullState.localUserID app:pullState.zAppID];
	
	[[transaction ext:extName] enumerateOperationsUsingBlock:
	  ^(YapDatabaseCloudCorePipeline *pipeline,
		 YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[ZDCCloudOperation class]])
		{
			ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
			
			if ([allNodeIDs containsObject:op.nodeID])
			{
				if (op.putType == ZDCCloudOperationPutType_Node_Rcrd ||
				    op.putType == ZDCCloudOperationPutType_Node_Data ||
					 op.type == ZDCCloudOperationType_Move)
				{
					[dirtyNodeIDs addObject:op.nodeID];
				}
			}
		}
	}];
	
	if (dirtyNodeIDs.count == 0)
	{
		// Simple case:
		// We can delete the root node.
		
		[transaction removeObjectsForKeys:[allNodeIDs allObjects] inCollection:kZDCCollection_Nodes];
		
		[zdc.delegate didDiscoverDeletedNode: rootDeletedNode
		                              atPath: rootDeletedPath
		                           timestamp: timestamp
		                         transaction: transaction];
	}
	else
	{
		// Complicated case:
		// We can't delete the root node because there are dirty ancestors.
		
		[zdc.delegate didDiscoverDeletedDirtyNode: rootDeletedNode
		                           dirtyAncestors: [dirtyNodeIDs allObjects]
		                                timestamp: timestamp
		                              transaction: transaction];
		
		NSMutableSet<NSString *> *dirtyParentNodeIDs = [NSMutableSet set];
		
		for (NSString *dirtyNodeID in dirtyNodeIDs)
		{
			ZDCNode *node = [transaction objectForKey:dirtyNodeID inCollection:kZDCCollection_Nodes];
			if (node)
			{
				NSString *parentID = node.parentID;
				while (parentID &&
				      ![parentID isEqualToString:rootDeletedNodeID] &&
				      ![dirtyParentNodeIDs containsObject:parentID])
				{
					[dirtyParentNodeIDs addObject:parentID];
					
					node = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
					parentID = node.parentID;
				}
			}
		}
		
		// Now we have the list of diry nodes,
		// and all the parents leading to the dirty nodes.
		// So we can create the opposite - the list of clean nodes.
		
		NSMutableSet<NSString *> *cleanNodeIDs = [allNodeIDs mutableCopy];
		[cleanNodeIDs removeObject:rootDeletedNodeID];
		[cleanNodeIDs minusSet:dirtyNodeIDs];
		[cleanNodeIDs minusSet:dirtyParentNodeIDs];
		
		// Now we need to extract just the top-level nodes from this list.
		//
		// To accomplish this we're going to do a depth first search.
		
		NSMutableSet<NSString*> *topLevelCleanNodeIDs = [NSMutableSet set];
		
		[[ZDCNodeManager sharedInstance] recursiveEnumerateNodeIDsWithParentID: rootDeletedNode.uuid
		                                                           transaction: transaction
		                                                            usingBlock:
		^(NSString *nodeID, NSArray<NSString *> *pathFromParent, BOOL *recurseInto, BOOL *stop)
		{
			if ([cleanNodeIDs containsObject:nodeID])
			{
				// Is this a "top-level" (clean) nodeID ?
				// YES IFF:
				// - it has zero parents that are in the `topLevelCleanNodeIDs` set
				
				BOOL isTopLevel = YES;
				for (NSString *pid in pathFromParent)
				{
					if ([topLevelCleanNodeIDs containsObject:pid]) {
						isTopLevel = NO;
						break;
					}
				}
				
				if (isTopLevel)
				{
					[topLevelCleanNodeIDs addObject:nodeID];
				}
			}
			else
			{
				// Node is "dirty". (Or one of its children is dirty.)
				// It contains changes that are still scheduled to be pushed to the cloud.
			}
		}];
		
		NSMutableArray<NSString*> *ancestors = [NSMutableArray array];
		
		for (NSString *nodeID in topLevelCleanNodeIDs)
		{
			[ancestors removeAllObjects];
			[[ZDCNodeManager sharedInstance] recursiveEnumerateNodeIDsWithParentID: nodeID
			                                                           transaction: transaction
			                                                            usingBlock:
			^(NSString *nodeID, NSArray<NSString *> *pathFromParent, BOOL *recurseInto, BOOL *stop)
			{
				[ancestors addObject:nodeID];
			}];
			
			[transaction removeObjectsForKeys:ancestors inCollection:kZDCCollection_Nodes];
			
			ZDCNode *node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
			[transaction removeObjectForKey:nodeID inCollection:kZDCCollection_Nodes];
			
			ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
			[zdc.delegate didDiscoverDeletedNode: node
			                              atPath: path
			                           timestamp: timestamp
			                         transaction: transaction];
		}
		
		NSMutableSet<NSString *> *allDirtyNodeIDs =
		  [NSMutableSet setWithCapacity:(dirtyNodeIDs.count + dirtyParentNodeIDs.count)];
		[allDirtyNodeIDs addObject:rootDeletedNodeID];
		[allDirtyNodeIDs unionSet:dirtyNodeIDs];
		[allDirtyNodeIDs unionSet:dirtyParentNodeIDs];
		
		for (NSString *nodeID in allDirtyNodeIDs)
		{
			ZDCNode *node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
			if (node)
			{
				node = [node copy];
				node.cloudID = nil;
				node.eTag_rcrd = nil;
				node.eTag_data = nil;
				
				[transaction setObject:node forKey:nodeID inCollection:kZDCCollection_Nodes];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Low-Level Fetching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard in-memory download (of *.rcrd || *.data).
**/
- (void)fetchKeyPath:(NSString *)keyPath
              bucket:(NSString *)bucket
              region:(AWSRegion)region
             headers:(NSDictionary<NSString *, NSString *> *)headers
           failCount:(NSUInteger)failCount
           pullState:(ZDCPullState *)pullState
          completion:(void (^)(id responseObject, NSString *eTag, NSDate *lastModified, ZDCPullTaskResult *result))completionBlock
{
	NSParameterAssert(keyPath != nil);
	NSParameterAssert(bucket != nil);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(pullState != nil);
	
	NSString *localUserID = pullState.localUserID;
	
	__block NSURLSessionDataTask *task = nil;
	
	void (^processingBlock)(NSURLResponse *urlResponse, id responseObject, NSError *error);
	processingBlock = ^(NSURLResponse *urlResponse, id responseObject, NSError *error) { @autoreleasepool {
		
		[pullState removeTask:task];
		
		NSInteger statusCode = urlResponse.httpStatusCode;
		
		if (urlResponse && error)
		{
			error = nil; // we only care about non-server-response errors
		}
		
		// Known status codes:
		//
		// - 200 : OK
		// - 206 : Partial Content - due to Range header
		// - 304 : Not Modified    - due to If-None-Match header
		// - 403 : Forbidden
		// - 503 : Slow Down       - we're being throttled
		
		if (error || (statusCode == 503))
		{
			// Try request again (using exponential backoff)
			
			DDLogTrace(@"[%@] Error fetching keyPath: %@ - %@", pullState.localUserID, keyPath, error);
			
			NSUInteger newFailCount = failCount + 1;
			
			if (newFailCount > kMaxFailCount)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_ExceededMaxRetries;
				result.underlyingError = error;
				
				completionBlock(nil, nil, nil, result);
				return;
			}
			else
			{
				[self fetchKeyPath: keyPath
				            bucket: bucket
				            region: region
				           headers: headers
				         failCount: newFailCount
				         pullState: pullState
				        completion: completionBlock];
			}
			
			return;
		}
		else if (statusCode == 401) // Unauthorized
		{
			// Authentication failed.
			
			DDLogTrace(@"[%@] Error fetching keyPath (401): %@", pullState.localUserID, keyPath);
			
			// We need to alert the user (so they can re-auth with valid credentials).
			
			[zdc.networkTools handleAuthFailureForUser:localUserID withError:error pullState:pullState];
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Auth;
			result.pullErrorReason = ZDCPullErrorReason_AwsAuthError;
			result.httpStatusCode = statusCode;
			
			completionBlock(nil, nil, nil, result);
			return;
		}
		else if ((statusCode != 200) && (statusCode != 206) && (statusCode != 304))
		{
			// One would think AWS would return a 404 for files that no longer exist.
			// But one would be wrong !
			//
			// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
			
			DDLogTrace(@"[%@] Error fetching keyPath (%d): %@", pullState.localUserID, (int)statusCode, keyPath);
			
			if ((statusCode != 404) && (statusCode != 403))
			{
				DDLogError(@"AWS S3 returned unknown status code: %ld", (long)statusCode);
			}
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_CloudChanged;
			result.pullErrorReason = ZDCPullErrorReason_HttpStatusCode;
			result.httpStatusCode = statusCode;
			
			completionBlock(nil, nil, nil, result);
			return;
		}
		
		DDLogTrace(@"[%@] Fetched keyPath (%d): %@", pullState.localUserID, (int)statusCode, keyPath);
		
		NSString *eTag = [urlResponse eTag];
		NSDate *lastModified = [urlResponse lastModified];
		
		ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
		result.pullResult = ZDCPullResult_Success;
		result.httpStatusCode = statusCode;
		
		completionBlock(responseObject, eTag, lastModified, result);
		
	}}; // end processingBlock
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		[zdc.awsCredentialsManager getAWSCredentialsForUser: localUserID
		                                    completionQueue: concurrentQueue
		                                    completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use processingBlock to execute exponential backoff.
					
					processingBlock(nil, nil, error);
					return;
				}
				else
				{
					[zdc.networkTools handleAuthFailureForUser: localUserID
					                                 withError: error
					                                 pullState: pullState];
					
					ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
					result.pullResult = ZDCPullResult_Fail_Auth;
					result.pullErrorReason = ZDCPullErrorReason_Auth0Error;
					result.underlyingError = error;
					
					completionBlock(nil, nil, nil, result);
					return;
				}
			}
			
			ZDCSessionInfo *sessionInfo = [zdc.sessionManager sessionInfoForUserID:localUserID];
		#if TARGET_OS_IPHONE
			AFURLSessionManager *session = sessionInfo.foregroundSession;
		#else
			AFURLSessionManager *session = sessionInfo.session;
		#endif
			
			NSURLComponents *urlComponents = nil;
			NSMutableURLRequest *request =
			  [S3Request getObject: keyPath
			              inBucket: bucket
			                region: region
			      outUrlComponents: &urlComponents];
			
			[headers enumerateKeysAndObjectsUsingBlock:^(NSString *headerField, NSString *headerValue, BOOL *stop) {
				
				[request setValue:headerValue forHTTPHeaderField:headerField];
			}];
			
			[AWSSignature signRequest: request
			               withRegion: region
			                  service: AWSService_S3
			              accessKeyID: auth.aws_accessKeyID
			                   secret: auth.aws_secret
			                  session: auth.aws_session];
			
			task = [session dataTaskWithRequest: request
			                     uploadProgress: nil
			                   downloadProgress: nil
			                  completionHandler: processingBlock];
			
			// Only start the task ([task resume]) if sync hasn't been cancelled.
			
			if (![pullStateManager isPullCancelled:pullState])
			{
				DDLogTrace(@"[%@] Fetching keyPath: %@", pullState.localUserID, keyPath);
				
				[pullState addTask:task];
				[task resume];
			}
		}];
	}};
	
	if (failCount == 0)
	{
		requestBlock();
	}
	else
	{
		NSTimeInterval delay = [zdc.networkTools exponentialBackoffForFailCount:failCount];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), concurrentQueue, ^{
			
			requestBlock();
		});
	}
}

/**
 * Downloads & parses the *.rcrd file.
**/
- (void)fetchRcrd:(NSString *)nodeRcrdPath
           bucket:(NSString *)bucket
           region:(AWSRegion)region
        pullState:(ZDCPullState *)pullState
       completion:(void (^)(ZDCCloudRcrd *cloudRcrd, NSData *responseData, NSString *eTag, NSDate *lastModified,
                            ZDCPullTaskResult *result))completionBlock
{
	NSParameterAssert(nodeRcrdPath != nil);
	NSParameterAssert(bucket != nil);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(pullState != nil);
	
	NSString *localUserID = pullState.localUserID;
	
	void (^processingBlock)(id, NSString*, NSDate*, ZDCPullTaskResult*) =
	  ^(id responseObject, NSString *eTag, NSDate *lastModified, ZDCPullTaskResult *result){ @autoreleasepool
	{
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			completionBlock(nil, nil, nil, nil, result);
			return;
		}
		
		if (result.httpStatusCode == 304)
		{
			// We passed "If-None-Match: eTag" header,
			// and server responding with "Not Modified" response.
			//
			// This is a successful result.
			//
			// Note: The responseObject may be zero-length NSData.
			
			completionBlock(nil, nil, eTag, lastModified, result);
			return;
		}
		
		// Rcrd files are JSON dictionaries.
		// Convert the data accordingly.
		
		NSData *responseData = nil;
		NSDictionary *jsonDict = nil;
		
		if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			jsonDict = (NSDictionary *)responseObject;
		}
		else if ([responseObject isKindOfClass:[NSData class]])
		{
			responseData = (NSData *)responseObject;
			
			NSError *error = nil;
			jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)responseObject options:0 error:&error];
			
			if (error)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Other;
				result.pullErrorReason = ZDCPullErrorReason_BadData;
				result.underlyingError = error;
				
				completionBlock(nil, nil, nil, nil, result);
				return;
			}
		}
		else
		{
			NSString *dsc = [NSString stringWithFormat:@"Invalid responseObject class: %@", [responseObject class]];
			NSError *error = [self errorWithDescription:dsc];
			
			ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
			result.pullResult = ZDCPullResult_Fail_Other;
			result.pullErrorReason = ZDCPullErrorReason_BadData;
			result.underlyingError = error;
			
			completionBlock(nil, nil, nil, nil, result);
			return;
		}
		
		__block ZDCCloudRcrd *cloudRcrd = nil;
		
		// Important: The decrypt process is slow.
		// And we don't want to block all the read-only database connections.
		// Especially because it's sometimes accidentally used on the main thread in a synchronous fashion.
		
		[[self decryptConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
			cloudRcrd = [zdc.cryptoTools parseCloudRcrdDict: jsonDict
			                                    localUserID: localUserID
			                                    transaction: transaction];
		
		} completionQueue:concurrentQueue completionBlock: ^{
			
			completionBlock(cloudRcrd, responseData, eTag, lastModified, [ZDCPullTaskResult success]);
		}];
	}};
	
	// Perform network request.
	
	[self fetchKeyPath: nodeRcrdPath
	            bucket: bucket
	            region: region
	           headers: nil
	         failCount: 0
	         pullState: pullState
	        completion: processingBlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Unknown Users
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSSet<NSString *> *)unknownUserIDsForNode:(ZDCNode *)node
                                 transaction:(YapDatabaseReadTransaction *)transaction
{
	__block NSMutableSet *unknownUserIDs = nil;

	void (^maybeAddUserID)(NSString*) = ^(NSString *_Nullable userID){ @autoreleasepool {
		
		if (userID == nil) {
			return; // from block => continue
		}
		
		BOOL shouldUpdateUser = NO;
		
		if ([ZDCUser isAnonymousID:userID])
		{
			userID = kZDCAnonymousUserID;
			ZDCUser *anonymousUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
			
			if (!anonymousUser)
			{
				shouldUpdateUser = YES;
			}
		}
		else
		{
			ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
			ZDCPublicKey *pubKey = [transaction objectForKey:user.publicKeyID inCollection:kZDCCollection_PublicKeys];
			
			if (!user || !pubKey)
			{
				shouldUpdateUser = YES;
			}
		}
		
		if (shouldUpdateUser)
		{
			if (unknownUserIDs == nil)
				unknownUserIDs = [NSMutableSet set];
			
			[unknownUserIDs addObject:userID];
		}
	}};
	
	[node.shareList enumerateListWithBlock:^(NSString *key, ZDCShareItem *shareItem, BOOL *stop) {

		NSString *userID = [ZDCShareList userIDFromKey:key];
		maybeAddUserID(userID);
	}];
	
	maybeAddUserID(node.senderID);

	return unknownUserIDs;
}

/**
 * Download unknown users we might have shared with.
**/
- (void)fetchUnknownUsers:(ZDCPullState *)pullState
{
	for (NSString *remoteUserID in pullState.unknownUserIDs)
	{
		[zdc.remoteUserManager fetchRemoteUserWithID: remoteUserID
		                                 requesterID: pullState.localUserID
		                             completionQueue: concurrentQueue
		                             completionBlock:^(ZDCUser *remoteUser, NSError *error)
		{
			// Ignore...
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Cleanup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoked after the entire tree has been traversed.
**/
- (void)processMissingItems:(ZDCPullState *)pullState
                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	// Before we started the full pull, we stored a snapshot of all the different nodeIDs that we
	// expected to see on the server. And during processing, we removed those items that we encountered.
	// So whatever is left in the list represents nodes that have been deleted from the server.
	
	// - ZDCNode
	{
		NSSet<NSString *> *deletedNodeIDs = pullState.unprocessedNodeIDs;
		
		for (NSString *nodeID in deletedNodeIDs)
		{
			ZDCNode *node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
			if (node)
			{
				// Todo: Implement this (and call [delegate didDeleteNode::::]
				
			//	ZDCCloudLocator *cloudLocator =
			//	  [CloudPathManager cloudLocatorForNode:node fileExtension:nil transaction:transaction];
			//
			//	[ZDCNodeManager remoteDeleteNode: nodeID
			//	                  withCloudPath: cloudLocator.cloudPath
			//	                         bucket: cloudLocator.bucket
			//	                         region: cloudLocator.region
			//	                    transaction: transaction];
			}
		}
	}
	
	// - avatars
//	{
//		NSSet<NSString *> *deletedAvatars = pullState.unprocessedAvatarFilenames;
//		if (deletedAvatars.count > 0)
//		{
//			[transaction addCompletionQueue:concurrentQueue completionBlock:^{
//
//				for (NSString *avatarFilename in deletedAvatars)
//				{
//					[self postAvatarUpdatedNotification:localUserID withFilename:avatarFilename eTag:nil];
//				}
//			}];
//		}
//	}
}

#pragma clang diagnostic pop

@end
