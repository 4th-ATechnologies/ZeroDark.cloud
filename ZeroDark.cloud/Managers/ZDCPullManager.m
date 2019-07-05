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
#import "ZDCLogging.h"
#import "ZDCNodePrivate.h"
#import "ZDCChangeList.h"
#import "ZDCPullItem.h"
#import "ZDCPullStateManager.h"
#import "ZDCPushManagerPrivate.h"
#import "ZDCSyncManagerPrivate.h"
#import "ZDCWebManager.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSError+Auth0API.h"
#import "NSError+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

// Libraries
#import <YapDatabase/YapDatabaseAtomic.h>
#import <libkern/OSAtomic.h>
#import <os/lock.h>
#import <stdatomic.h>

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

static NSString* NSStringFromPullResult(ZDCPullResult cloudPullResult)
{
	switch (cloudPullResult)
	{
		case ZDCPullResult_Success           : return @"Success";
		case ZDCPullResult_ManuallyAborted   : return @"ManuallyAborted";
		case ZDCPullResult_Fail_Auth         : return @"Fail_Auth";
		case ZDCPullResult_Fail_CloudChanged : return @"Fail_CloudChanged";
		case ZDCPullResult_Fail_Unknown      : return @"Fail_Unknown";
		default                              : return @"?";
	}
}

typedef NS_ENUM(NSInteger, ZDCPullErrorReason) {
	
	ZDCPullErrorReason_None = 0,
	
	ZDCPullErrorReason_IgnoringPartialFile,
	ZDCPullErrorReason_MissingMessageAttachment,
	ZDCPullErrorReason_ExceededMaxRetries,
	ZDCPullErrorReason_AwsAuthError,
	ZDCPullErrorReason_Auth0Error,
	ZDCPullErrorReason_DecryptionError,
	ZDCPullErrorReason_BadData,
	ZDCPullErrorReason_HttpStatusCode,
	ZDCPullErrorReason_FileIDMismatch,
	ZDCPullErrorReason_ShareWithinShare
};

@interface ZDCPullTaskResult : NSObject

+ (ZDCPullTaskResult *)success;

// General status
@property (nonatomic, readwrite) ZDCPullResult pullResult;
@property (nonatomic, readwrite) ZDCPullErrorReason pullErrorReason;
@property (nonatomic, readwrite) NSInteger httpStatusCode;
@property (nonatomic, readwrite) NSError *underlyingError;

// Node info
@property (nonatomic, readwrite) NSString *nodeID;

@end

@implementation ZDCPullTaskResult

+ (ZDCPullTaskResult *)success
{
	ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
	result.pullResult = ZDCPullResult_Success;
	
	return result;
}

@end

typedef void(^ZDCPullTaskCompletion)(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCPullManager {
@private
	
	__weak ZeroDarkCloud *owner;
	
	dispatch_queue_t concurrentQueue;
	
	ZDCPullStateManager *pullStateManager;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.pullManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
		
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
	return owner.databaseManager.roDatabaseConnection; // uses YapDatabaseConnectionPool :)
}

- (YapDatabaseConnection *)rwConnection
{
	return owner.networkTools.rwConnection;
}

- (YapDatabaseConnection *)decryptConnection
{
	return owner.networkTools.decryptConnection;
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
#pragma mark HTTP Headers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)addHeader:(NSMutableDictionary<NSString *, NSString *> *)headers range:(NSRange)byteRange
{
	if (byteRange.length > 0)
	{
		NSString *rangeString =
		  [NSString stringWithFormat:@"bytes=%lu-%lu",
		    (unsigned long)(byteRange.location),
		    (unsigned long)(byteRange.location + byteRange.length - 1)];
		
		headers[@"Range"] = rangeString;
	}
}

- (void)addHeader:(NSMutableDictionary<NSString *, NSString *> *)headers ifNoneMatch:(NSString *)eTag
{
	if (eTag)
	{
		NSString *quotedETag = [NSString stringWithFormat:@"\"%@\"", eTag];
		
		headers[@"If-None-Match"] = quotedETag;
	}
}

- (void)addHeader:(NSMutableDictionary<NSString *, NSString *> *)headers ifMatch:(NSString *)eTag
{
	if (eTag)
	{
		NSString *quotedETag = [NSString stringWithFormat:@"\"%@\"", eTag];
		
		headers[@"If-Match"] = quotedETag;
	}
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
		
		[owner.syncManager notifyPullStoppedForLocalUserID: localUserID
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
		  [owner.networkTools isRecentRequestID: requestInfo.requestID
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
	
	[owner.syncManager notifyPullStartedForLocalUserID: pullState.localUserID
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
		
		DDLogTrace(@"[%@] FinishPull: %@",
		           pullState.localUserID, NSStringFromPullResult(result.pullResult));
		
		NSAssert(result != nil, @"Bad parameter for block: S4SyncResult");
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
			
				[self->owner.syncManager notifyPullStoppedForLocalUserID: pullState.localUserID
				                                                  zAppID: pullState.zAppID
				                                              withResult: result.pullResult];
	
				[self->owner.pushManager resumeOperationsPendingPullCompletion: latestChangeToken
				                                                forLocalUserID: pullState.localUserID
				                                                        zAppID: pullState.zAppID];
			}];
			
			[self->pullStateManager deletePullState:pullState];
		}
		else
		{
			[self->pullStateManager deletePullState:pullState];
			[self->owner.syncManager notifyPullStoppedForLocalUserID: pullState.localUserID
			                                                  zAppID: pullState.zAppID
			                                              withResult: result.pullResult];
		}
	}};
	
#if DEBUG && robbie_hanson && 0 // Force full pull (for testing)
	
	[self fallbackToFullPullWithPullState: pullState
	                      finalCompletion: finalCompletionBlock];
	
#else
	
	__block ZDCChangeList *pullInfo = nil;
	[owner.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
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
				result.pullResult = ZDCPullResult_Fail_Unknown;
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
			[owner.networkTools handleAuthFailureForUser: pullState.localUserID
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
			result.pullResult = ZDCPullResult_Fail_Unknown;
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
		
		[owner.awsCredentialsManager getAWSCredentialsForUser: pullState.localUserID
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
					[owner.networkTools handleAuthFailureForUser: pullState.localUserID
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
			
			ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:pullState.localUserID];
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
			
			NSURLComponents *urlComponents = [owner.webManager apiGatewayForRegion:region stage:stage path:path];
			
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
		NSTimeInterval delay = [owner.networkTools exponentialBackoffForFailCount:failCount];
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
	
	BOOL isRcrd = [cloudPath.fileNameExt isEqualToString:kZDCCloudFileExtension_Rcrd];
	
	ZDCPullTaskCompletion continuationBlock =
	^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) { @autoreleasepool {
		
		DDLogTrace(@"[%@] ProcessPendingChange: put-if-match: continuationBlock: result = %ld",
		           pullState.localUserID, (long)result.pullResult);
		
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		if (result.pullResult == ZDCPullResult_Success) {
			NSAssert(transaction != nil, @"Bad parameter fro block: transaction is nil (with success status)");
		}
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			if (result.httpStatusCode == 404)
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
			
			if (isRcrd) // RCRD changed (filesystem metadata such as: name, permissions, etc)
			{
				if (eTag && [node.eTag_rcrd isEqualToString:eTag])
				{
					// The node is already up-to-date
				}
				else
				{
					// The node's RCRD has been updated.
					// We need to download it to find out what changed.
					
					done = NO;
					[self pullNodeRcrd: path
					          nodeData: nil
					          dataETag: nil
					  dataLastModified: nil
					            bucket: bucket
					            region: region
					          parentID: node.parentID
					         pullState: pullState
					    rcrdCompletion: continuationBlock
					     dirCompletion: nil]; // don't need to update sub-tree
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
					[owner.delegate didDiscoverModifiedNode: node
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
	
	BOOL isRcrd = [cloudPath.fileNameExt isEqualToString:kZDCCloudFileExtension_Rcrd];
	
	ZDCPullTaskCompletion continuationBlock =
	^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) { @autoreleasepool {
		
		DDLogTrace(@"[%@] ProcessPendingChange: put-if-nonexistent: continuationBlock: result = %ld",
		           pullState.localUserID, (long)result.pullResult);
		
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		if (result.pullResult == ZDCPullResult_Success) {
			NSAssert(transaction != nil, @"Bad parameter fro block: transaction is nil (with success status)");
		}
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			if (result.httpStatusCode == 404)
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
		
		BOOL done = YES;
		
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
					
					done = NO;
					[self pullNodeRcrd: path
					          nodeData: nil
					          dataETag: nil
					  dataLastModified: nil
					            bucket: bucket
					            region: region
					          parentID: node.parentID
					         pullState: pullState
					    rcrdCompletion: continuationBlock
					     dirCompletion: nil];
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
					[owner.delegate didDiscoverModifiedNode: node
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
				
				done = NO;
				[self fallbackToFullPullWithPullState: pullState
				                      finalCompletion: finalCompletionBlock];
			}
			else if (isRcrd)
			{
				done = NO;
				[self pullNodeRcrd: path
				          nodeData: nil
				          dataETag: nil
				  dataLastModified: nil
				            bucket: bucket
				            region: region
				          parentID: parentNode.uuid
				         pullState: pullState
				    rcrdCompletion: continuationBlock
				     dirCompletion: nil];
			}
			else
			{
				ZDCCloudPath *rcrdCloudPath = [cloudPath copyWithFileNameExt:kZDCCloudFileExtension_Rcrd];
				
				done = NO;
				[self pullNodeRcrd: rcrdCloudPath.path
				          nodeData: path
				          dataETag: eTag
				  dataLastModified: change.timestamp
				            bucket: bucket
				            region: region
				          parentID: parentNode.uuid
				         pullState: pullState
				    rcrdCompletion: continuationBlock
				     dirCompletion: nil];
			}
		}
				 
		if (done) {
			continuationBlock(transaction, [ZDCPullTaskResult success]);
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
	
	ZDCCloudPath *srcCloudPath = [ZDCCloudPath cloudPathFromPath:srcPath];
	ZDCCloudPath *dstCloudPath = [ZDCCloudPath cloudPathFromPath:dstPath];
	AWSRegion region = [AWSRegions regionForName:regionStr];
	
	ZDCPullTaskCompletion continuationBlock =
	^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result) { @autoreleasepool {
		
		DDLogTrace(@"[%@] ProcessPendingChange: move: continuationBlock: result = %ld",
		           pullState.localUserID, (long)result.pullResult);
		
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		if (result.pullResult == ZDCPullResult_Success) {
			NSAssert(transaction != nil, @"Bad parameter fro block: transaction is nil (with success status)");
		}
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			if (result.httpStatusCode == 404)
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
				
				NSString *dstRcrdPath = [dstCloudPath pathWithExt:kZDCCloudFileExtension_Rcrd];
				
				done = NO;
				[self pullNodeRcrd: dstRcrdPath
				          nodeData: nil
				          dataETag: nil
				  dataLastModified: nil
				            bucket: bucket
				            region: region
				          parentID: dstParentNode.uuid
				         pullState: pullState
				    rcrdCompletion: continuationBlock
				     dirCompletion: nil];
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
	DDLogTrace(@"[%@] FallbackToFullSync", localUserID);
	
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
		result.pullResult = ZDCPullResult_Fail_Unknown;
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
			[owner.networkTools handleAuthFailureForUser: localUserID
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
			result.pullResult = ZDCPullResult_Fail_Unknown;
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
		
		[owner.awsCredentialsManager getAWSCredentialsForUser: localUserID
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
					[owner.networkTools handleAuthFailureForUser: localUserID
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
			
			ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:localUserID];
			
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
			
			NSURLComponents *urlComponents =
				[owner.webManager apiGatewayForRegion:region stage:stage path:path];
			
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
		NSTimeInterval delay = [owner.networkTools exponentialBackoffForFailCount:failCount];
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
	
	NSArray<NSString *> *containerIDs = @[
		[ZDCContainerNode uuidForLocalUserID:localUserID zAppID:zAppID container:ZDCTreesystemContainer_Home],
		[ZDCContainerNode uuidForLocalUserID:localUserID zAppID:zAppID container:ZDCTreesystemContainer_Prefs],
		[ZDCContainerNode uuidForLocalUserID:localUserID zAppID:zAppID container:ZDCTreesystemContainer_Inbox],
		[ZDCContainerNode uuidForLocalUserID:localUserID zAppID:zAppID container:ZDCTreesystemContainer_Outbox]
	];
	
	NSMutableArray<ZDCContainerNode *> *containerNodes = [NSMutableArray arrayWithCapacity:containerIDs.count];
	
	[[self roConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Fetch needed information for the pull
		
		ZDCUser *user = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
		bucket = user.aws_bucket;
		region = user.aws_region;
		
		for (NSString *containerID in containerIDs)
		{
			ZDCContainerNode *containerNode = [transaction objectForKey:containerID inCollection:kZDCCollection_Nodes];
			if (containerNode) {
				[containerNodes addObject:containerNode];
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
			NSAssert(result != nil, @"Bad parameter for block: S4SyncResult");
			
			if ([pullStateManager isPullCancelled:pullState]) {
				return;
			}
			
			if (result.pullResult != ZDCPullResult_Success)
			{
				finalCompletionBlock(nil, result);
				return;
			}
			
			__block YAPUnfairLock innerLock = YAP_UNFAIR_LOCK_INIT;
			__block ZDCPullTaskResult *cumulativeResult = nil;
			__block atomic_uint pendingCount = containerNodes.count;
			
			ZDCPullTaskCompletion innerCompletionBlock =
			^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *opResult){ @autoreleasepool {
				
				NSAssert(opResult != nil, @"Bad parameter for block: ZDCPullTaskResult");

				YAPUnfairLockLock(&innerLock);
				@try {

					if (!cumulativeResult || opResult.pullResult != ZDCPullResult_Success)
					{
						cumulativeResult = opResult;
					}
				}
				@finally {
					YAPUnfairLockUnlock(&innerLock);
				}
				
				uint remaining = atomic_fetch_sub(&pendingCount, 1) - 1;
				if (remaining == 0)
				{
					finalCompletionBlock(transaction, cumulativeResult);
				}
			}};
			
			for (ZDCContainerNode *containerNode in containerNodes)
			{
				[self syncNode: containerNode
				        bucket: bucket
				        region: region
				     pullState: pullState
				    completion: innerCompletionBlock];
			}
			
		//	[self syncAvatarsWithBucket: bucket
		//	                     region: region
		//	                  pullState: pullState
		//	                 completion: innerCompletionBlock]; Don't forget to change pendingCount initialization
			
			NSAssert(containerNodes.count != 0, @"Pull is never going to complete!");
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
			[owner.networkTools handleAuthFailureForUser:localUserID withError:error pullState:pullState];
			
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
			result.pullResult = ZDCPullResult_Fail_Unknown;
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
		
		[owner.awsCredentialsManager getAWSCredentialsForUser: localUserID
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
					[owner.networkTools handleAuthFailureForUser: localUserID
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
			
			ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:localUserID];
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
			DDLogDonut(@"%@", [request s4Description]);
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
			result.pullResult = ZDCPullResult_Fail_Unknown;
			result.pullErrorReason = ZDCPullErrorReason_ExceededMaxRetries;
			result.underlyingError = error;
			
			completionBlock(result);
			return;
		}
		
		NSTimeInterval delay = [owner.networkTools exponentialBackoffForFailCount:failCount];
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
      completion:(ZDCPullTaskCompletion)outerCompletionBlock
{
	NSParameterAssert(node != nil);
	NSParameterAssert(bucket != nil);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(pullState != nil);
	NSParameterAssert(outerCompletionBlock != nil);
	
	NSString *const localUserID = pullState.localUserID;
	NSString *const zAppID = pullState.zAppID;
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		if ([pullStateManager isPullCancelled:pullState])
		{
			return;
		}
		
		if (ddLogLevel & DDLogFlagTrace)
		{
			ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
			DDLogTrace(@"[%@] Sync node: %@", pullState.localUserID, path.fullPath);
		}
		
		// Step 1 of 4
		//
		// By the time this method is called, we already have a list of every item.
		// That is, we already have a `S3ObjectInfo` instance for each item in the cloud.
		//
		// All of these items are sitting in the pullState,
		// and we simply need to pop them based on their s3-key-prefix & anchor.
		
		ZDCNode *anchorNode = [[ZDCNodeManager sharedInstance] anchorNodeForNode:node transaction:transaction];
		
		NSString *appPrefix = anchorNode.anchor.zAppID;
		if (!appPrefix && [anchorNode isKindOfClass:[ZDCContainerNode class]]) {
			appPrefix = [(ZDCContainerNode *)anchorNode zAppID];
		}
		
		NSString *rootNodeID = nil;
		if ([anchorNode isKindOfClass:[ZDCContainerNode class]]) {
			rootNodeID = anchorNode.localUserID;
		}
		else {
			rootNodeID = anchorNode.uuid;
		}
		
		NSString *prefix = [NSString stringWithFormat:@"%@/%@/", appPrefix, node.dirPrefix];
		NSArray<S3ObjectInfo *> *dirList = [pullState popListWithPrefix:prefix rootNodeID:rootNodeID];
		
		// Step 2 of 4
		//
		// Prep work for processing files & sub-directories.
	
		__block YAPUnfairLock innerLock = YAP_UNFAIR_LOCK_INIT;
		__block ZDCPullTaskResult *cumulativeResult = nil;
		__block atomic_uint pendingCount = 1; // Yes, one is correct. See last step.

		ZDCPullTaskCompletion innerCompletionBlock =
		^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *opResult){ @autoreleasepool {

			NSAssert(opResult != nil, @"Bad parameter for block: ZDCPullTaskResult");

			YAPUnfairLockLock(&innerLock);
			@try {

				if (!cumulativeResult || opResult.pullResult != ZDCPullResult_Success)
				{
					cumulativeResult = opResult;
				}
			}
			@finally {
				YAPUnfairLockUnlock(&innerLock);
			}

			uint remaining = atomic_fetch_sub(&pendingCount, 1) - 1;
			if (remaining == 0)
			{
				outerCompletionBlock(transaction, cumulativeResult);
			}
		}};
		
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
	
			ZDCCloudPath *cloudPath = [ZDCCloudPath cloudPathFromPath:nodeRcrd.key];
			
			ZDCNode *node =
			  [[ZDCNodeManager sharedInstance] findNodeWithCloudPath: cloudPath
			                                                  bucket: bucket
			                                                  region: region
			                                             localUserID: localUserID
			                                                  zAppID: zAppID
			                                             transaction: transaction];
			
			if (node == nil)
			{
				ZDCCloudNode *cloudNode =
				  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: cloudPath
				                                                            bucket: bucket
				                                                            region: region
				                                                       localUserID: localUserID
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
	
				atomic_fetch_add(&pendingCount, 2);
				[self queuePullNodeRcrd: nodeRcrd.key
				               rcrdETag: nodeRcrd.eTag
				       rcrdLastModified: nodeRcrd.lastModified
				               nodeData: nodeData.key
				               dataETag: nodeData.eTag
				       dataLastModified: nodeData.lastModified
				                 bucket: bucket
				                 region: region
				                parents: parents
				              pullState: pullState
				         rcrdCompletion: innerCompletionBlock
				          dirCompletion: innerCompletionBlock]; // if node might have children
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
					[owner.delegate didDiscoverModifiedNode: node
					                             withChange: ZDCNodeChange_Data
					                                 atPath: path
					                            transaction: transaction];
				}
	
				if (node.dirPrefix)
				{
					atomic_fetch_add(&pendingCount, 1);
					[self syncNode: node
					        bucket: bucket
					        region: region
					     pullState: pullState
					    completion: innerCompletionBlock];
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
		// moving up the filesystem hierarchy until we reach a directory that isn't complete.
	
		innerCompletionBlock(transaction, [ZDCPullTaskResult success]);
	}];
}

/**
 * Called when a RCRD is fetched with encapsulates a pointer to a non-local location.
 * E.g. we encounter a RCRD in Alice's local bucket that points to Bob's bucket.
**/
- (void)syncPointerNode:(ZDCNode *)pointerNode
              pullState:(ZDCPullState *)pullState
         dirCompletion:(ZDCPullTaskCompletion)dataCompletionBlock
{
	// Todo...
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
- (void)queuePullNodeRcrd:(NSString *)rcrdPath
                 rcrdETag:(NSString *)rcrdETag
         rcrdLastModified:(NSDate *)rcrdLastModified
                 nodeData:(NSString *)dataPath
                 dataETag:(NSString *)dataETag
         dataLastModified:(NSDate *)dataLastModified
                   bucket:(NSString *)bucket
                   region:(AWSRegion)region
                  parents:(NSArray<NSString *> *)parents
                pullState:(ZDCPullState *)pullState
           rcrdCompletion:(ZDCPullTaskCompletion)rcrdCompletionBlock
            dirCompletion:(ZDCPullTaskCompletion)dirCompletionBlock
{
	ZDCPullItem *item = [[ZDCPullItem alloc] init];
	
	item.rcrdPath = rcrdPath;
	item.rcrdETag = rcrdETag;
	
	item.dataPath = dataPath;
	item.dataETag = dataETag;
	item.dataLastModified = dataLastModified;
	
	item.bucket = bucket;
	item.region = region;
	
	item.parents = parents;
	
	item.rcrdCompletionBlock = rcrdCompletionBlock;
	item.dirCompletionBlock = dirCompletionBlock;
	
	[pullState pushItem:item];
	[self dequeueNextItemIfPossible:pullState];
}

- (void)dequeueNextItemIfPossible:(ZDCPullState *)pullState
{
	if (pullState.tasksCount >= 8) {
		return;
	}
	
	NSSet<NSString *> *preferredNodeIDs = nil;
	if ([owner.delegate respondsToSelector:@selector(preferredNodeIDsForPullingRcrds)]) {
		preferredNodeIDs = [owner.delegate preferredNodeIDsForPullingRcrds];
	}
	
	// Smart dequeue algorithm
	ZDCPullItem *item = [pullState popItemWithPreferredNodeIDs:preferredNodeIDs];
	if (item == nil) {
		return;
	}
	
	[self pullNodeRcrd: item.rcrdPath
	          nodeData: item.dataPath
	          dataETag: item.dataETag
	  dataLastModified: item.dataLastModified
	            bucket: item.bucket
	            region: item.region
	          parentID: [item.parents lastObject]
	         pullState: pullState
	    rcrdCompletion: item.rcrdCompletionBlock
	     dirCompletion: item.dirCompletionBlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Tools
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Pulls the *.rcrd item from server and updates the database.
 *
 * @param rcrdPath
 *   The cloudPath (as a string) of the "*.rcrd" item.
 *
 * @param dataPath
 *   The cloudPath (as a string) of the "*.data" item.
 *   Only pass this if you want the code to also sync the data item too.
 *
 * @param dataETag
 *   The known remote eTag of the ".data" item.
 *   Pass this only if you know it.
 *   I.e. during a full sync, or if the current pending change indicates it.
 */
- (void)pullNodeRcrd:(NSString *)rcrdPath
            nodeData:(nullable NSString *)dataPath
            dataETag:(nullable NSString *)dataETag
    dataLastModified:(nullable NSDate *)dataLastModified
              bucket:(NSString *)bucket
              region:(AWSRegion)region
            parentID:(NSString *)parentID
           pullState:(ZDCPullState *)pullState
      rcrdCompletion:(ZDCPullTaskCompletion)rcrdCompletionBlock
       dirCompletion:(nullable ZDCPullTaskCompletion)dirCompletionBlock
{
	DDLogTrace(@"Sync node.rcrd: %@", rcrdPath);
	
	NSParameterAssert(rcrdPath != nil);
	NSParameterAssert(bucket != nil);
	NSParameterAssert(region != AWSRegion_Invalid);
	NSParameterAssert(parentID != nil);
	NSParameterAssert(pullState != nil);
	
	// If this method is being invoked, it means we found changes on the server.
	if ([pullState isFirstChangeDetected])
	{
		// Send signal to localUserManager.
		// This allows it to update its internal state, and also post a NSNotification for the user.
		
		[owner.syncManager notifyPullFoundChangesForLocalUserID: pullState.localUserID
		                                                 zAppID: pullState.zAppID];
	}
	
	[self fetchRcrd: rcrdPath
	         bucket: bucket
	         region: region
	      pullState: pullState
	     completion:^(ZDCCloudRcrd *cloudRcrd, NSData *responseData, NSString *eTag, NSDate *lastModified,
	                  ZDCPullTaskResult *result)
	{
		NSAssert(result != nil, @"Bad parameter for block: ZDCPullTaskResult");
		
		if (result.pullResult != ZDCPullResult_Success)
		{
			// Unrecoverable failure.
			// Either cloud contents changed mid-pull, or we encountered an authentication failure.
			
			rcrdCompletionBlock(nil, result);
			if (dirCompletionBlock) {
				dirCompletionBlock(nil, result);
			}
			return;
		}
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			if ([pullStateManager isPullCancelled:pullState])
			{
				return;
			}
			
			NSString *const localUserID = pullState.localUserID;
			NSString *const zAppID = pullState.zAppID;
			
			ZDCCloudPath *remoteCloudPath = [ZDCCloudPath cloudPathFromPath:rcrdPath];
			NSString *remoteCloudName = [remoteCloudPath fileNameWithExt:nil];
			
			ZDCNodeManager *nodeManager = [ZDCNodeManager sharedInstance];
			ZDCCloudPathManager *cloudPathManager = [ZDCCloudPathManager sharedInstance];
			
			NSString *extName = [owner.databaseManager cloudExtNameForUser:localUserID app:zAppID];
			ZDCCloudTransaction *cloudTransaction = (ZDCCloudTransaction *)[transaction ext:extName];
			
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
					[pullState removeUnprocessedNodeID:node.uuid];
					
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
						
						[owner.delegate didDiscoverMovedNode: node
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
					//   That is, the local node has been moved to this directory,
					//   but the move operation hasn't hit the server yet.
					//
					// So we need resolve the conflict somehow.
					// And we start by notifying the delegate.
					
					ZDCTreesystemPath *cleartextPath =
					  [nodeManager pathForNode:node transaction:transaction];
					
					[owner.delegate didDiscoverConflict: ZDCNodeConflict_Path
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
						
						[owner.delegate didDiscoverMovedNode: node
						                                from: oldCleartextPath
						                                  to: newCleartextPath
						                         transaction: transaction];
						
						// This means we don't actually have a matching node for this file.
						
						node = nil;
					}
				}
				else // if (cloudIDMatches && cloudPathMatches)
				{
					[pullState removeUnprocessedNodeID:node.uuid];
				}
				
			} // end: edge case processing
			
			//////////
			
			if (node)
			{
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
				
				BOOL nodeHasChanges = node.hasChanges;
				if (nodeHasChanges)
				{
					[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
				}
				
				// Todo: Merge sharing information
				//
				// Note: The mergeKeys::: method may modify the node object in the database.
				
			//	[cloudTransaction mergeKeys:cloudRcrd.share forNodeID:node.uuid isPointer:isPointerRcrd];
			//
			//	node = [transaction objectForKey:node.uuid inCollection:kZDCCollection_Nodes];
				
				if (nodeHasChanges)
				{
					[node makeImmutable];
					
					ZDCTreesystemPath *path = [nodeManager pathForNode:node transaction:transaction];
					[owner.delegate didDiscoverModifiedNode: node
					                             withChange: ZDCNodeChange_Treesystem
					                                 atPath: path
					                            transaction: transaction];
				}
				
				// Check for unknown users
				
				NSSet<NSString *> *unknownUserIDs = [self unknownUserIDsForNode:node transaction:transaction];
				if (unknownUserIDs) {
					[pullState addUnknownUserIDs:unknownUserIDs];
				}
				
				rcrdCompletionBlock(transaction, [ZDCPullTaskResult success]);
				
				if (dirCompletionBlock)
				{
					if (node.isPointer)
					{
						[self syncPointerNode: node
						            pullState: pullState
						        dirCompletion: dirCompletionBlock];
						
					}
					else if ([node.dirPrefix isEqualToString:kZDCDirPrefix_Fake])
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
						
						for (ZDCNode *child in children)
						{
							[self syncNode: child
							        bucket: bucket
							        region: region
							     pullState: pullState
							    completion: dirCompletionBlock];
						}
					}
					else if (node.dirPrefix && node.dirSalt)
					{
						// Modern RCRD format.
						// Scan the node's children.
						
						[self syncNode: node
						        bucket: bucket
						        region: region
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
			else // if (node == nil)
			{
				node = [[ZDCNode alloc] initWithLocalUserID:pullState.localUserID];
				node.parentID = parentID;
				
				NSString *filename = cloudRcrd.metadata[kZDCCloudRcrd_Meta_Filename];
				if (filename)
				{
					node.name = filename;
					
					NSString *localCloudName = [cloudPathManager cloudNameForNode:node transaction:transaction];
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
				
				node.cloudID = cloudRcrd.cloudID;
				node.encryptionKey = cloudRcrd.encryptionKey;
				
				node.eTag_rcrd = eTag;
				node.lastModified_rcrd = lastModified;
				
				node.eTag_data = dataETag;
				node.lastModified_data = dataLastModified;
				
				id dirSalt = cloudRcrd.metadata[kZDCCloudRcrd_Meta_DirSalt];
				if ([dirSalt isKindOfClass:[NSString class]])
				{
					dirSalt = [[NSData alloc] initWithBase64EncodedString:(NSString *)dirSalt options:0];
				}
				if ([dirSalt isKindOfClass:[NSData class]])
				{
					node.dirSalt = dirSalt;
				}
				
				NSMutableArray<ZDCNode*> *children = nil;
				
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
				
				[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
				
				ZDCTreesystemPath *path = [nodeManager pathForNode:node transaction:transaction];
				[owner.delegate didDiscoverNewNode:node atPath:path transaction:transaction];
				
				rcrdCompletionBlock(transaction, [ZDCPullTaskResult success]);
				
				for (ZDCNode *child in children)
				{
					if (child.isImmutable) {
						// Already had this child in the database - not new, not discovered
						continue;
					}
					
					[transaction setObject:child forKey:child.uuid inCollection:kZDCCollection_Nodes];
					
					ZDCTreesystemPath *path = [nodeManager pathForNode:child transaction:transaction];
					[owner.delegate didDiscoverNewNode:child atPath:path transaction:transaction];
				}
				
				if (dirCompletionBlock)
				{
					if (node.isPointer)
					{
						[self syncPointerNode: node
						            pullState: pullState
						        dirCompletion: dirCompletionBlock];
						
					}
					else if (children)
					{
						// Node is using a deprecated RCRD format in the cloud (i.e. Storm4).
						// It's using the old cleartext children style.
						// So the node doesn't actually have any direct children.
						
						for (ZDCNode *child in children)
						{
							[self syncNode: child
							        bucket: bucket
							        region: region
							     pullState: pullState
							    completion: dirCompletionBlock];
						}
					}
					else if (node.dirPrefix && node.dirSalt)
					{
						// Modern RCRD format.
						// Scan the node's children.
						
						[self syncNode: node
						        bucket: bucket
						        region: region
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
			
		}]; // end: [[self rwConnection] asyncReadWriteWithBlock:...]
		
	}]; // end: [self fetchRcrd:...]
}

/**
 * Use this method when it's discovered that a file/directory was deleted remotely.
 * That is, the delete was performed by another device/user.
 *
 * This method will determine if its safe to delete the node and any descendents.
 * It will then only delete what it can safely,
 * and update the appropriate S4CloudNode entries.
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
	
	NSString *extName = [owner.databaseManager cloudExtNameForUser:pullState.localUserID app:pullState.zAppID];
	
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
		
		[owner.delegate didDiscoverDeletedNode: rootDeletedNode
		                                atPath: rootDeletedPath
		                             timestamp: timestamp
		                           transaction: transaction];
	}
	else
	{
		// Complicated case:
		// We can't delete the root node because there are dirty ancestors.
		
		[owner.delegate didDiscoverDeletedDirtyNode: rootDeletedNode
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
			[owner.delegate didDiscoverDeletedNode: node
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
			
			NSUInteger newFailCount = failCount + 1;
			
			if (newFailCount > kMaxFailCount)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Unknown;
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
			//
			// We need to alert the user (so they can re-auth with valid credentials).
			
			[owner.networkTools handleAuthFailureForUser:localUserID withError:error pullState:pullState];
			
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
			
			if ((statusCode != 403) && (statusCode != 404))
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
		
		NSString *eTag = [urlResponse eTag];
		NSDate *lastModified = [urlResponse lastModified];
		
		ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
		result.pullResult = ZDCPullResult_Success;
		result.httpStatusCode = statusCode;
		
		completionBlock(responseObject, eTag, lastModified, result);
		
	}}; // end processingBlock
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		[owner.awsCredentialsManager getAWSCredentialsForUser: localUserID
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
					[owner.networkTools handleAuthFailureForUser: localUserID
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
			
			ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:localUserID];
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
		NSTimeInterval delay = [owner.networkTools exponentialBackoffForFailCount:failCount];
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
				result.pullResult = ZDCPullResult_Fail_Unknown;
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
			result.pullResult = ZDCPullResult_Fail_Unknown;
			result.pullErrorReason = ZDCPullErrorReason_BadData;
			result.underlyingError = error;
			
			completionBlock(nil, nil, nil, nil, result);
			return;
		}
		
		__block ZDCCloudRcrd *cloudRcrd = nil;
		__block NSError *decryptError = nil;
		
		// Important: The decrypt process is slow.
		// And we don't want to block all the read-only database connections.
		// Especially because it's sometimes accidentally used on the main thread in a synchronous fashion.
		
		[[self decryptConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
			cloudRcrd =
			  [owner.cryptoTools decryptCloudRcrdDict: jsonDict
			                              localUserID: localUserID
			                              transaction: transaction
			                                    error: &decryptError];
			
			if (decryptError)
			{
				DDLogWarn(@"Error extracting encryptionKey from CloudKey file:\n"
				          @" - path: %@\n"
				          @" - error: %@", nodeRcrdPath, decryptError);
			}
		
		} completionQueue:concurrentQueue completionBlock: ^{
			
			if (decryptError)
			{
				ZDCPullTaskResult *result = [[ZDCPullTaskResult alloc] init];
				result.pullResult = ZDCPullResult_Fail_Unknown;
				result.pullErrorReason = ZDCPullErrorReason_DecryptionError;
				result.underlyingError = decryptError;
				
				completionBlock(cloudRcrd, responseData, eTag, lastModified, result);
			}
			else
			{
				completionBlock(cloudRcrd, responseData, eTag, lastModified, [ZDCPullTaskResult success]);
			}
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

//	[node.shareList enumerateKeysUsingBlock:^(NSString *key, BOOL *stop) {
//
//		NSString *userID = [S4ShareList userIDFromKey:key];
//		if (userID == nil) {
//			return; // from block => continue
//		}
//
//		BOOL shouldUpdateUser = NO;
//
//		if ([NSString isAnonymousID:userID])
//		{
//			userID = kS4AnonymousUserID;
//			ZDCUser *anonymousUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
//
//			if (!anonymousUser)
//			{
//				shouldUpdateUser = YES;
//			}
//		}
//		else
//		{
//			ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
//			S4PublicKey *pubKey = [transaction objectForKey:user.publicKeyID inCollection:kZDCCollection_PublicKeys];
//
//			BOOL shouldUpdateUser = NO;
//
//			if (!user || !pubKey)
//			{
//				shouldUpdateUser = YES;
//			}
//		}
//
//		if (shouldUpdateUser)
//		{
//			if (unknownUserIDs == nil)
//				unknownUserIDs = [NSMutableSet set];
//
//			[unknownUserIDs addObject:userID];
//		}
//	}];

	return unknownUserIDs;
}

/**
 * Download unknown users we might have shared with.
**/
- (void)fetchUnknownUsers:(ZDCPullState *)pullState
{
//	for (NSString *remoteUserID in unknownUserIDs)
//	{
//		[S4RemoteUserManager createRemoteUserWithID:remoteUserID
//		                                requesterID:localUserID
//		                            completionQueue:concurrentQueue
//		                            completionBlock:^(ZDCUser *remoteUser, NSError *error)
//		{
//			// Ignore...
//		}];
//	}
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
