/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCPushManagerPrivate.h"

#import "AWSDate.h"
#import "AWSPayload.h"
#import "AWSSignature.h"
#import "S3Request.h"
#import "S3ResponseParser.h"
#import "ZDCCloudOperationPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZDCNodePrivate.h"
#import "ZDCDataPromisePrivate.h"
#import "ZDCPollContext.h"
#import "ZDCChangeList.h"
#import "ZDCTaskContext.h"
#import "ZDCTouchContext.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSData+AWSUtilities.h"
#import "NSDate+ZeroDark.h"
#import "NSError+Auth0API.h"
#import "NSError+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

// Libraries
#import <CommonCrypto/CommonDigest.h>
#import <YapDatabase/YapDatabaseCloudCorePrivate.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif

static int const kStagingVersion = 2;

#if TARGET_OS_IPHONE
static const uint64_t multipart_minCloudFileSize = (1024 * 1024 * 10);
static const uint64_t multipart_minPartSize      = (1024 * 1024 * 5); // must be >= 5 MiB (as per S3 restrictions)
static const uint64_t multipart_maxUploadCount   = 1;
#else
  #if DEBUG && robbie_hanson
	static const uint64_t multipart_minCloudFileSize = (1024 * 1024 * 10);
	static const uint64_t multipart_minPartSize      = (1024 * 1024 * 5); // must be >= 5 MiB (as per S3 restrictions)
	static const uint64_t multipart_maxUploadCount   = 2;
  #else
	static const uint64_t multipart_minCloudFileSize = (1024 * 1024 * 10);
	static const uint64_t multipart_minPartSize      = (1024 * 1024 * 5); // must be >= 5 MiB (as per S3 restrictions)
	static const uint64_t multipart_maxUploadCount   = 2;
  #endif
#endif

static NSString *const key_tasks_initiate = @"initiate";
static NSString *const key_tasks_complete = @"complete";
static NSString *const key_tasks_abort    = @"abort";

typedef NS_ENUM(NSInteger, ZDCErrCode) {
	ZDCErrCode_unknown_user_owner                        = 10000,
	ZDCErrCode_unknown_user_caller                       = 10001,
	
	ZDCErrCode_staging_path_invalid                      = 10100,
	ZDCErrCode_staging_path_unknown_command              = 10101,
	ZDCErrCode_staging_path_src_matches_dst              = 10102,
	
	ZDCErrCode_unauthorized_missing_src_write_permission = 10201,
	ZDCErrCode_unauthorized_missing_dst_write_permission = 10202,
	ZDCErrCode_unauthorized_missing_share_permission     = 10203,
	ZDCErrCode_unauthorized_permissions_issue            = 10204,
	ZDCErrCode_unauthorized_missing_src_read_permission  = 10205,
	
	ZDCErrCode_unsupported_permissions_change            = 10300,
	ZDCErrCode_unsupported_children_change               = 10301,
	
	ZDCErrCode_staging_file_invalid_json                 = 10400,
	ZDCErrCode_staging_file_invalid_content              = 10401,
	ZDCErrCode_staging_file_too_big                      = 10402,
	ZDCErrCode_staging_file_disappeared                  = 10403,
	ZDCErrCode_staging_file_modified                     = 10404,
	
	ZDCErrCode_internal_missing_perms_file               = 10500,
	
	ZDCErrCode_precondition_src_missing                  = 10600,
	ZDCErrCode_precondition_dst_missing                  = 10601, // Deprecated
	ZDCErrCode_precondition_src_eTag_mismatch            = 10602,
	ZDCErrCode_precondition_dst_eTag_mismatch            = 10603,
	ZDCErrCode_precondition_not_leaf                     = 10604,
	ZDCErrCode_precondition_dst_parent_missing           = 10605,
	ZDCErrCode_precondition_dst_rcrd_missing             = 10606,
	ZDCErrCode_precondition_dst_data_missing             = 10607,
	ZDCErrCode_precondition_dst_fileID_mismatch          = 10608,
	ZDCErrCode_precondition_not_orphan                   = 10609
};

@implementation ZDCPushManager  {
@private
	
	__weak ZeroDarkCloud *owner;
	
	dispatch_queue_t serialQueue;
	dispatch_queue_t concurrentQueue;
	
	// Tracks all in-flight tasks:
	// - key   : YapCollectionKey<localUserID, zAppID>
	// - value : list of associated in-flight context objects
	//
	// The in-flight tasks could be any valid task type:
	// - ZDCTaskContext
	// - ZDCPollContext
	// - ZDCTouchContext
	//
	// NSMutableDictionary is NOT thread-safe,
	// and must only be accessed from within the `serialQueue`.
	//
	NSMutableDictionary<YapCollectionKey*, NSMutableArray<id>*> *inFlightContexts;
	
	// Tracks multipart tasks:
	// - key   : ZDCOperation.uuid
	// - value : list of associated multipart tasks
	//
	// NSMutableDictionary is NOT thread-safe,
	// and must only be accessed from within the `serialQueue`.
	//
	NSMutableDictionary<NSUUID*, NSMutableDictionary<id, ZDCTaskContext *> *> *multipartTasks;
	
	// Tracks requests to suspend the push queue:
	// - key   : YapCollectionKey<localUserID, zAppID>
	// - value : number (of suspensions)
	//
	// NSMutableDictionary is NOT thread-safe,
	// and must only be accessed from within the `serialQueue`.
	//
	NSMutableDictionary<YapCollectionKey*, NSNumber*> *suspendCountDict;
	
	// Tracks skipped operations.
	//
	// NSMutableSet is NOT thread-safe,
	// and must only be accessed from within the `serialQueue`.
	//
	NSMutableSet<NSUUID *> *recentlySkipped;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.pushManager
}
	
- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
		
		serialQueue     = dispatch_queue_create("ZDCPushManager.serial", DISPATCH_QUEUE_SERIAL);
		concurrentQueue = dispatch_queue_create("ZDCPushManager.concurrent", DISPATCH_QUEUE_CONCURRENT);
		
		[[NSNotificationCenter defaultCenter] addObserver: self
		                                         selector: @selector(didSkipOperations:)
		                                             name: ZDCSkippedOperationsNotification
		                                           object: nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	return [NSError errorWithClass: [self class]
	                          code: 0
	                   description: description];
}

- (NSError *)cancelledError
{
	return [NSError errorWithClass: [self class]
	                          code: NSURLErrorCancelled
	                   description: @"Operation aborted"];
}

- (BOOL)isFileModifiedDuringReadError:(NSError *)error
{
	if (error == nil) return NO;
	
	NSError *streamError = error.userInfo[NSUnderlyingErrorKey];
	
	if (streamError
	 && [streamError.domain isEqualToString:NSStringFromClass([ZDCInterruptingInputStream class])]
	 && (streamError.code == ZDCFileModifiedDuringRead))
	{
		return YES;
	}
	else
	{
		return NO;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)didSkipOperations:(NSNotification *)notification
{
	NSArray<ZDCCloudOperation*> *skippedOperations =
	  notification.userInfo[ZDCSkippedOperationsNotification_UserInfo_Ops];
	
	[self noteRecentlySkippedOperations:skippedOperations];
	[self abortOperations:skippedOperations];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)requestIDForOperation:(ZDCCloudOperation *)operation
{
	NSUUID *postResolveUUID = operation.ephemeralInfo.postResolveUUID;
	NSString *requestID = postResolveUUID ? postResolveUUID.UUIDString : operation.uuid.UUIDString;
	
	return requestID;
}

- (NSString *)stagingPathForOperation:(ZDCCloudOperation *)operation
                          withContext:(ZDCTaskContext *)context
{
	return [self stagingPathForOperation:operation withContext:context multipart:NO touch:NO];
}

- (NSString *)stagingPathForOperation:(ZDCCloudOperation *)operation
                          withContext:(ZDCTaskContext *)context
                            multipart:(BOOL)isMultipart
                                touch:(BOOL)isTouch
{
	NSParameterAssert(operation);
	NSParameterAssert(context);
	
	NSMutableString *stagingPath = [NSMutableString stringWithCapacity:1024];
	[stagingPath appendFormat:@"staging/%d/", kStagingVersion];
	
	if (isMultipart)
		[stagingPath appendFormat:@"%@:%@/", operation.cloudLocator.cloudPath.appPrefix, operation.localUserID];
	else
		[stagingPath appendFormat:@"%@/", operation.cloudLocator.cloudPath.appPrefix];
	
	if (isTouch) {
		[stagingPath appendString:@"touch:"];
	}
	
	switch (operation.type)
	{
		case ZDCCloudOperationType_Put:
		{
			NSString *fileNameExt = (operation.putType == ZDCCloudOperationPutType_Node_Data)
			  ? kZDCCloudFileExtension_Data
			  : kZDCCloudFileExtension_Rcrd;
			
			if (context.eTag)
				[stagingPath appendFormat:@"put-if-match:%@/", context.eTag];
			else
				[stagingPath appendString:@"put-if-nonexistent/"];
			
			[stagingPath appendString:operation.cloudLocator.cloudPath.dirPrefix];
			[stagingPath appendString:@"/"];
			[stagingPath appendString:[operation.cloudLocator.cloudPath fileNameWithExt:fileNameExt]];
			
			break;
		}
		case ZDCCloudOperationType_Move:
		{
			[stagingPath appendFormat:@"move:%@/%@/%@/%@/%@",
			  context.eTag,
			  operation.cloudLocator.cloudPath.dirPrefix,
			  operation.cloudLocator.cloudPath.fileName,
			  operation.dstCloudLocator.cloudPath.dirPrefix,
			  operation.dstCloudLocator.cloudPath.fileName];
			
			break;
		}
		case ZDCCloudOperationType_DeleteLeaf:
		{
			[stagingPath appendFormat:@"delete-leaf:%@", (context.eTag ?: @"")];
			
			NSString *cloudID = [operation.deletedCloudIDs anyObject];
			if (cloudID) {
				[stagingPath appendFormat:@":%@", cloudID];
			}
			else {
				[stagingPath appendString:@":"];
			}
			
			if (operation.ifOrphan) {
				[stagingPath appendString:@":if-orphan"];
			}
			
			[stagingPath appendFormat:@"/%@", operation.cloudLocator.cloudPath.dirPrefix];
			[stagingPath appendFormat:@"/%@", operation.cloudLocator.cloudPath.fileName];
			
			break;
		}
		case ZDCCloudOperationType_DeleteNode:
		{
			[stagingPath appendString:@"delete-node"];
			
			if (operation.ifOrphan) {
				[stagingPath appendString:@":if-orphan"];
			}
			
			break;
		}
		case ZDCCloudOperationType_CopyLeaf:
		{
			// staging/version/app_id/copy-leaf:srcETag/srcDir/srcFile.ext/dstUserID/dstDir/dstFile.ext/request_id
			
			[stagingPath appendFormat:@"copy-leaf:%@/%@/%@/%@/%@/%@",
			  context.eTag,
			  operation.cloudLocator.cloudPath.dirPrefix,
			  operation.cloudLocator.cloudPath.fileName,
			  operation.localUserID,
			  operation.dstCloudLocator.cloudPath.dirPrefix,
			  operation.dstCloudLocator.cloudPath.fileName];
			
			break;
		}
		default:
		{
			return nil;
		}
	}
	
	[stagingPath appendFormat:@"/%@", [self requestIDForOperation:operation]];
	
	return stagingPath;
}

/**
 * The pollStatus comes from the ZeroDark.cloud servers.
 * It's a dictionary with a pre-defined format.
 */
- (NSInteger)statusCodeFromPollStatus:(NSDictionary *)pollStatus
{
	NSInteger statusCode = 0;
	
	id value = pollStatus[@"status"];
	
	if ([value isKindOfClass:[NSNumber class]])
		statusCode = [(NSNumber *)value integerValue];
	else if ([value isKindOfClass:[NSString class]])
		statusCode = [(NSString *)value integerValue];
	
	return statusCode;
}

/**
 * The pollStatus comes from the ZeroDark.cloud servers.
 * It's a dictionary with a pre-defined format.
 */
- (BOOL)getExtCode:(NSInteger *)extCodePtr msg:(NSString **)extMsgPtr fromPollStatus:(NSDictionary *)pollStatus
{
	NSInteger extCode = 0;
	NSString *extMsg = nil;
	
	id value = pollStatus[@"ext"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *ext = (NSDictionary *)value;
		
		value = ext[@"code"];
		if ([value isKindOfClass:[NSNumber class]])
			extCode = [(NSNumber *)value integerValue];
		else if ([value isKindOfClass:[NSString class]])
			extCode = [(NSString *)value integerValue];
		
		value = ext[@"msg"];
		if ([value isKindOfClass:[NSString class]])
			extMsg = (NSString *)value;
	}
	
	if (extCodePtr) *extCodePtr = extCode;
	if (extMsgPtr) *extMsgPtr = extMsg;
	
	return ((extCode != 0) || (extMsg != nil));
}

/**
 * Javascript (aka the server) stores timestamps as an integer, representing milliseconds since unix epoch.
 * Objective-C stores timesteamps as a double, representing seconds since apple epoch.
 */
- (NSDate *)dateFromJavascriptTimestamp:(NSNumber *)value
{
	if (![value isKindOfClass:[NSNumber class]])
	{
		return nil;
	}
	
	// Value should be number of milliseconds since unix epoch.
	
	uint64_t millis = [value unsignedLongLongValue];
	NSTimeInterval seconds = (double)millis / (double)1000.0;
	
	return [NSDate dateWithTimeIntervalSince1970:seconds];
}

- (NSString *)extNameForContext:(ZDCTaskContext *)context
{
	return [owner.databaseManager cloudExtNameForUser:context.localUserID app:context.zAppID];
}

- (NSString *)extNameForOperation:(ZDCCloudOperation *)operation
{
	return [owner.databaseManager cloudExtNameForUser:operation.localUserID app:operation.zAppID];
}

- (ZDCCloudOperation *)operationForContext:(ZDCTaskContext *)context
{
	return (ZDCCloudOperation *)[[self pipelineForContext:context] operationWithUUID:context.operationUUID];
}

- (YapDatabaseCloudCorePipeline *)pipelineForContext:(ZDCTaskContext *)context
{
	ZDCCloud *ext = [owner.databaseManager cloudExtForUser:context.localUserID app:context.zAppID];
	
	return [ext pipelineWithName:context.pipeline];
}

- (YapDatabaseCloudCorePipeline *)pipelineForOperation:(ZDCCloudOperation *)operation
{
	ZDCCloud *ext = [owner.databaseManager cloudExtForUser:operation.localUserID app:operation.zAppID];
	
	return [ext pipelineWithName:operation.pipeline];
}

- (void)stashContext:(id)context
{
	NSParameterAssert(context != nil);
	
	NSString *localUserID = nil;
	NSString *zAppID = nil;
	
	if ([context isKindOfClass:[ZDCTaskContext class]])
	{
		ZDCTaskContext *ctx = (ZDCTaskContext *)context;
		
		localUserID = ctx.localUserID;
		zAppID      = ctx.zAppID;
	}
	else if ([context isKindOfClass:[ZDCPollContext class]])
	{
		ZDCTaskContext *ctx = [(ZDCPollContext *)context taskContext];
		
		localUserID = ctx.localUserID;
		zAppID      = ctx.zAppID;
	}
	else if ([context isKindOfClass:[ZDCTouchContext class]])
	{
		ZDCTaskContext *ctx = [[(ZDCTouchContext *)context pollContext] taskContext];
		
		localUserID = ctx.localUserID;
		zAppID      = ctx.zAppID;
	}
	
	NSAssert(localUserID != nil, @"Invalid context");
	NSAssert(zAppID      != nil, @"Invalid context");
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		if (inFlightContexts == nil) {
			inFlightContexts = [[NSMutableDictionary alloc] init];
		}
		
		NSMutableArray<id> *inFlightArray = inFlightContexts[tuple];
		if (inFlightArray == nil) {
			inFlightArray = inFlightContexts[tuple] = [[NSMutableArray alloc] init];
		}
		
		[inFlightArray addObject:context];
	}});
}

- (void)unstashContext:(id)context
{
	NSParameterAssert(context != nil);
	
	NSString *localUserID = nil;
	NSString *zAppID = nil;
	
	if ([context isKindOfClass:[ZDCTaskContext class]])
	{
		ZDCTaskContext *ctx = (ZDCTaskContext *)context;
		
		localUserID = ctx.localUserID;
		zAppID      = ctx.zAppID;
	}
	else if ([context isKindOfClass:[ZDCPollContext class]])
	{
		ZDCTaskContext *ctx = [(ZDCPollContext *)context taskContext];
		
		localUserID = ctx.localUserID;
		zAppID      = ctx.zAppID;
	}
	else if ([context isKindOfClass:[ZDCTouchContext class]])
	{
		ZDCTaskContext *ctx = [[(ZDCTouchContext *)context pollContext] taskContext];
		
		localUserID = ctx.localUserID;
		zAppID      = ctx.zAppID;
	}
	
	NSAssert(localUserID != nil, @"Invalid context");
	NSAssert(zAppID      != nil, @"Invalid context");
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		if (inFlightContexts == nil) {
			inFlightContexts = [[NSMutableDictionary alloc] init];
		}
		
		NSMutableArray<id> *inFlightArray = inFlightContexts[tuple];
		if (inFlightArray)
		{
			[inFlightArray removeObjectIdenticalTo:context];
		}
	}});
}

- (void)incrementSuspendCountForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(zAppID != nil);
	
	YapCollectionKey *const tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (suspendCountDict == nil) {
			suspendCountDict = [[NSMutableDictionary alloc] init];
		}
		
		NSNumber *number = suspendCountDict[tuple];
		if (number) {
			suspendCountDict[tuple] = @(number.unsignedIntegerValue + 1);
		}
		else {
			suspendCountDict[tuple] = @(1);
		}
		
	#pragma clang diagnostic pop
	}});
}

- (NSUInteger)drainSuspendCountForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	NSParameterAssert(localUserID != nil);
	NSParameterAssert(zAppID != nil);
	
	YapCollectionKey *const tuple = YapCollectionKeyCreate(localUserID, zAppID);
	
	__block NSUInteger suspendCount = 0;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSNumber *number = suspendCountDict[tuple];
		if (number)
		{
			suspendCount = [number unsignedIntegerValue];
			suspendCountDict[tuple] = nil;
		}
		
	#pragma clang diagnostic pop
	}});
	
	return suspendCount;
}

- (void)noteRecentlySkippedOperations:(NSArray<ZDCCloudOperation *> *)skippedOperations
{
	NSMutableArray<NSUUID *> *skippedOpUUIDs = [NSMutableArray arrayWithCapacity:skippedOperations.count];
	for (ZDCCloudOperation *op in skippedOperations)
	{
		[skippedOpUUIDs addObject:op.uuid];
	}
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		if (recentlySkipped == nil) {
			recentlySkipped = [[NSMutableSet alloc] init];
		}
		
		[recentlySkipped addObjectsFromArray:skippedOpUUIDs];
	}});
	
	// We need to release the memory at some point.
	// And 2 minutes sounds like more than enough of a safe buffer.
	//
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)), serialQueue, ^{ @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		for (NSUUID *uuid in skippedOpUUIDs)
		{
			[strongSelf->recentlySkipped removeObject:uuid];
		}
	}});
}

- (BOOL)isRecentlySkippedOperation:(NSUUID *)operationUUID
{
	__block BOOL result = NO;
	
	dispatch_sync(serialQueue, ^{
		result = [recentlySkipped containsObject:operationUUID];
	});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Backoff
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSTimeInterval)pollingBackoffForFailCount:(NSUInteger)failCount
{
	// - A => failCount
	// - B => new delay
	// - D => total
	//
	//  A :   B  =>   C
	// ----------------------
	//  1 :  1.0 =>   1.0
	//  2 :  1.0 =>   2.0
	//  3 :  2.0 =>   4.0
	//  4 :  2.0 =>   6.0
	//  5 :  4.0 =>  10.0
	//  6 :  4.0 =>  14.0
	//  7 :  6.0 =>  20.0
	//  8 :  6.0 =>  26.0
	//  9 :  8.0 =>  34.0
	// 10 :  8.0 =>  42.0
	// 11 : 10.0 =>  52.0
	// 12 : 10.0 =>  62.0
	// 13 : 12.0 =>  74.0
	// 14 : 12.0 =>  86.0
	// 15 : 14.0 => 100.0
	// 16 : 14.0 => 114.0
	
	if (failCount == 0)  return  0.0; // seconds
	if (failCount <= 2)  return  1.0;
	if (failCount <= 4)  return  2.0;
	if (failCount <= 6)  return  4.0;
	if (failCount <= 8)  return  6.0;
	if (failCount <= 10) return  8.0;
	if (failCount <= 12) return 10.0;
	if (failCount <= 14) return 12.0;
	else                 return 14.0;
}

- (NSUInteger)pollingModulus
{
	return 17;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Aborting Operations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)abortOperationsForLocalUserID:(NSString *)localUserID appID:(NSString *)appID
{
	DDLogAutoTrace();
	
	if (localUserID == nil) return;
	if (appID == nil) return;
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(localUserID, appID);
	
	ZDCCloud *ext = [owner.databaseManager cloudExtForUser:localUserID app:appID];
	YapDatabaseCloudCorePipeline *pipeline = [ext defaultPipeline];
	NSArray<ZDCCloudOperation *> *operations = (NSArray<ZDCCloudOperation *> *)[pipeline activeOperations];
	
	if (operations.count > 0) {
		DDLogVerbose(@"canceling operations (all reportedly active): %@", operations);
	}
	
	// Order matters:
	//
	// When cancelling operations:
	// 1. Set `abortRequested` flag
	// 2. Within serialQueue, find matching context's, and invoke [context.progress cancel]
	//
	// When checking to see if an operation has been cancelled:
	// 1. Within serialQueue, add context (with non-nil context.progress)
	// 2. Check `abortRequested` flag
	
	NSMutableSet<NSUUID*> *opUUIDsToAbort = [NSMutableSet setWithCapacity:operations.count];
	
	for (ZDCCloudOperation *op in operations)
	{
		op.ephemeralInfo.abortRequested = YES;
		[opUUIDsToAbort addObject:op.uuid];
	}
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		NSArray<id> *inFlightArray = inFlightContexts[tuple];
		for (id ctx in inFlightArray)
		{
			ZDCTaskContext *context = nil;
			
			if ([ctx isKindOfClass:[ZDCTaskContext class]])
			{
				context = (ZDCTaskContext *)ctx;
			}
			else if ([ctx isKindOfClass:[ZDCPollContext class]])
			{
				context = ((ZDCPollContext *)ctx).taskContext;
			}
			else if ([ctx isKindOfClass:[ZDCTouchContext class]])
			{
				context = ((ZDCTouchContext *)ctx).pollContext.taskContext;
			}
			
			if ([opUUIDsToAbort containsObject:context.operationUUID])
			{
				[context.progress cancel];
			}
		}
	}});
}

- (void)abortOperations:(NSArray<ZDCCloudOperation *> *)operations
{
	DDLogAutoTrace();
	
	if (operations.count > 0) {
		DDLogVerbose(@"canceling operations (may or may not be active): %@", operations);
	}
	
	// Order matters:
	//
	// When cancelling operations:
	// 1. Set `abortRequested` flag
	// 2. Within serialQueue, find matching context's, and invoke [context.progress cancel]
	//
	// When checking to see if an operation has been cancelled:
	// 1. Within serialQueue, add context (with non-nil context.progress)
	// 2. Check `abortRequested` flag
	
	NSMutableSet<NSUUID*> *opUUIDsToAbort = [NSMutableSet setWithCapacity:operations.count];
	
	for (ZDCCloudOperation *op in operations)
	{
		op.ephemeralInfo.abortRequested = YES;
		[opUUIDsToAbort addObject:op.uuid];
	}
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		for (YapCollectionKey *tuple in inFlightContexts)
		{
			NSArray<id> *inFlightArray = inFlightContexts[tuple];
			for (id ctx in inFlightArray)
			{
				ZDCTaskContext *context = nil;
				
				if ([ctx isKindOfClass:[ZDCTaskContext class]])
				{
					context = (ZDCTaskContext *)ctx;
				}
				else if ([ctx isKindOfClass:[ZDCPollContext class]])
				{
					context = ((ZDCPollContext *)ctx).taskContext;
				}
				else if ([ctx isKindOfClass:[ZDCTouchContext class]])
				{
					context = ((ZDCTouchContext *)ctx).pollContext.taskContext;
				}
				
				if ([opUUIDsToAbort containsObject:context.operationUUID])
				{
					[context.progress cancel];
				}
			}
		}
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flight Control
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startOperation:(YapDatabaseCloudCoreOperation *)op
           forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	__unsafe_unretained ZDCCloudOperation *operation = (ZDCCloudOperation *)op;
	__unsafe_unretained ZDCCloudOperation_EphemeralInfo *ephemeralInfo = operation.ephemeralInfo;

	if (ephemeralInfo.touchContext)
	{
		[self startTouchWithContext:ephemeralInfo.touchContext pipeline:pipeline];
	}
	else if (ephemeralInfo.pollContext)
	{
		[self startPollWithContext:ephemeralInfo.pollContext pipeline:pipeline];
	}
	else
	{
		ZDCCloudOperationType type = operation.type;

		if (type == ZDCCloudOperationType_Put)
		{
			if (operation.multipartInfo) {
				[self prepareMultipartOperation:operation forPipeline:pipeline];
			}
			else {
				[self preparePutOperation:operation forPipeline:pipeline];
			}
		}
		else if (type == ZDCCloudOperationType_Move)
		{
			[self prepareMoveOperation:operation forPipeline:pipeline];
		}
		else if (type == ZDCCloudOperationType_DeleteLeaf)
		{
			[self prepareDeleteLeafOperation:operation forPipeline:pipeline];
		}
		else if (type == ZDCCloudOperationType_DeleteNode)
		{
			[self prepareDeleteNodeOperation:operation forPipeline:pipeline];
		}
		else if (type == ZDCCloudOperationType_Avatar)
		{
			[self prepareAvatarOperation:operation forPipeline:pipeline];
		}
		else
		{
			DDLogError(@"%@ - Unsupported operation type: %lu", THIS_METHOD, (unsigned long)type);
		}
	}
}

/**
 * Forwarded to us from ZeroDarkCloud.
 */
- (void)processPushNotification:(ZDCPushInfo *)pushInfo
{
	// Example push:
	//
	// {
	//   "aps": {
	//	    "content-available": 1
	//   },
	//   "4th-a": {
	//     "uid": "auth0|57d9debd75e0c45d16e680fd",
	//     "old": "86374103fb134aa79f8003ab87d7dafa",
	//     "new": "f482f7183e2e46ad8146bf6d74434828",
	//     "info": {
	//       "region": "us-west-2",
	//       "bucket": "com.4th-a.user.wnc8mbqh8u1bm9ixh18qua3aa4dnqfkj",
	//       "command": "put-if-nonexistent",
	//       "path": "com.4th-a.storm4/00000000000000000000000000000000/4xe9do4f97ute6kfwqwwomoh6168eqz5.data",
	//       "fileID": "FFCA663E39174CB7A9CCE5EA233950B4",
	//       "eTag": "e6d4760605217f69a35b0dcf960ca9e3"
	//     },
	//     "req": {
	//       "uid": "auth0|57d9debd75e0c45d16e680fd",
	//       "id": "59825120-88C3-4F68-8193-A1A64C2922AC",
	//       "status": 200
	//     }
	//   }
	// }
	
	ZDCRequestInfo *requestInfo = pushInfo.requestInfo;
	if (!requestInfo) return;
	
	BOOL isTriggeredFromLocalPush =
	  [owner.networkTools isRecentRequestID: requestInfo.requestID
	                                forUser: requestInfo.localUserID];
	
	if (!isTriggeredFromLocalPush) return;
	if (requestInfo.statusCode == 0) return;
	
	// If the push notification arrives before we've completed our polling,
	// then let's go ahead and short-circuit the polling process.
	
	NSString *request_id     = requestInfo.requestID;
	NSString *request_userID = requestInfo.localUserID;
	
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:request_id];
	if (!uuid) return;
	
	ZDCCloudOperation *operation = nil;
	ZDCPollContext *pollContext = nil;
	
	NSArray<ZDCCloud*> *cloudExts = [owner.databaseManager cloudExtsForUser:request_userID];
	for (ZDCCloud *cloudExt in cloudExts)
	{
		YapDatabaseCloudCorePipeline *pipeline = [cloudExt defaultPipeline];
		if (pipeline)
		{
			ZDCCloudOperation *operation = (ZDCCloudOperation *)[pipeline operationWithUUID:uuid];
			if (operation)
			{
				pollContext = operation.ephemeralInfo.pollContext;
				break;
			}
		}
	}
	
	if (!operation) return;
	if (!pollContext) return;
	if (![pollContext atomicMarkCompleted]) return;
	
	DDLogVerbose(@"Short-circuit poll for operation %@: %ld",
	             request_id,
	       (long)pushInfo.requestInfo.statusCode);
	
	switch(operation.type)
	{
		case ZDCCloudOperationType_Put:
		{
			[self putPollDidComplete:pollContext withStatus:requestInfo.status];
			break;
		}
		case ZDCCloudOperationType_Move:
		{
			NSAssert(NO, @"Code in transition - not implemented yet");
		//	[self movePollDidComplete:pollContext withStatus:requestInfo.status];
			break;
		}
		case ZDCCloudOperationType_DeleteLeaf:
		{
			[self deleteLeafPollDidComplete:pollContext withStatus:requestInfo.status];
			break;
		}
		case ZDCCloudOperationType_DeleteNode:
		{
			[self deleteNodePollDidComplete:pollContext withStatus:requestInfo.status];
			break;
		}
		case ZDCCloudOperationType_CopyLeaf:
		{
			NSAssert(NO, @"Code in transition - not implemented yet");
		//	[self copyLeafPollDidComplete:pollContext withStatus:requestInfo.status];
			break;
		}
		default :
		{
			NSAssert(NO, @"Fatal: pollContext marked as completed, but not delivered !");
			break;
		}
	}
}

/**
 * Forwarded to us from ZDCSessionManager.
 */
- (void)downloadTaskDidComplete:(NSURLSessionDownloadTask *)task
                      inSession:(NSURLSession *)session
                      withError:(NSError *)error
                        context:(ZDCObject *)inContext
              downloadedFileURL:(NSURL *)downloadedFileURL
{
	id responseObject = nil;
	
	NSURLResponse *response = task.response;
	if (response && downloadedFileURL)
	{
		NSString *mimeType = response.MIMEType;
		
		if ([mimeType isEqualToString:@"application/json"] ||
		    [mimeType isEqualToString:@"text/json"])
		{
			NSData *fileData = [NSData dataWithContentsOfURL:downloadedFileURL];
			responseObject = [NSJSONSerialization JSONObjectWithData:fileData options:0 error:nil];
		}
		else if ([mimeType isEqualToString:@"application/xml"] ||
		         [mimeType isEqualToString:@"text/xml"])
		{
			NSData *fileData = [NSData dataWithContentsOfURL:downloadedFileURL];
			responseObject = [S3ResponseParser parseXMLData:fileData];
		}
	}
	
	if (downloadedFileURL) {
		[[NSFileManager defaultManager] removeItemAtURL:downloadedFileURL error:nil];
	}
	
	if ([inContext isKindOfClass:[ZDCPollContext class]])
	{
		ZDCPollContext *context = (ZDCPollContext *)inContext;
		
	#if DEBUG && robbie_hanson
		DDLogCookie(@"PollComplete w/ operationUUID: %@", context.taskContext.operationUUID);
	#endif
		
		[self pollDidComplete: task
		            inSession: session
		            withError: error
		              context: context
		       responseObject: responseObject];
	}
	else if ([inContext isKindOfClass:[ZDCTaskContext class]])
	{
		ZDCTaskContext *context = (ZDCTaskContext *)inContext;
		
		[self multipartTaskDidComplete: task
		                     inSession: session
		                     withError: error
		                       context: context
		                responseObject: responseObject];
	}
	else
	{
		NSAssert(NO, @"Unexpected context");
	}
}

/**
 * Forwarded to us from ZDCSessionManager.
 */
- (void)taskDidComplete:(NSURLSessionTask *)task
              inSession:(NSURLSession *)session
              withError:(nullable NSError *)error
                context:(ZDCObject *)inContext
{
	if ([inContext isKindOfClass:[ZDCTaskContext class]])
	{
		ZDCTaskContext *context = (ZDCTaskContext *)inContext;
		ZDCCloudOperation *operation = [self operationForContext:context];
		
	#if DEBUG && robbie_hanson
		DDLogCookie(@"TaskDidComplete w/ operationUUID: %@", context.operationUUID);
	#endif
	
		if (operation == nil)
		{
			if ([self isRecentlySkippedOperation:context.operationUUID])
			{
				// Code flow that brought us here:
				// - node was deleted
				// - triggered skip of all associated put operations in the queue (which were deleted from DB)
				// - triggered abort of all associated active put operations (cancel HTTPS task)
				// - we just got notified about the completion of the put operation
				//
				// There is probably an error, signifying the operation was cancelled.
				// If not, that's fine too, since we're about to delete the node anyways.
			}
			else
			{
				DDLogCookie(@"Unable to find operation w/ uuid: %@", context.operationUUID);
			}
		}
	
		switch (operation.type)
		{
			case ZDCCloudOperationType_Put:
			{
				if (operation.multipartInfo) {
					NSAssert(NO, @"Not implemented");
				}
				else {
					[self putTaskDidComplete:task inSession:session withError:error context:context];
				}
				break;
			}
			case ZDCCloudOperationType_Move:
			{
				[self moveTaskDidComplete:task inSession:session withError:error context:context];
				break;
			}
			case ZDCCloudOperationType_CopyLeaf:
			{
				NSAssert(NO, @"Not implemented");
				break;
			}
			case ZDCCloudOperationType_DeleteLeaf:
			{
				[self deleteLeafTaskDidComplete:task inSession:session withError:error context:context];
				break;
			}
			case ZDCCloudOperationType_DeleteNode:
			{
				[self deleteNodeTaskDidComplete:task inSession:session withError:error context:context];
				break;
			}
			case ZDCCloudOperationType_Avatar:
			{
				[self avatarTaskDidComplete:task inSession:session withError:error context:context];
				break;
			}
			case ZDCCloudOperationType_Invalid: break;
		}
	}
	else if ([inContext isKindOfClass:[ZDCTouchContext class]])
	{
		ZDCTouchContext *context = (ZDCTouchContext *)inContext;
		
	#if DEBUG && robbie_hanson
		DDLogCookie(@"TouchTaskDidComplete w/ operationUUID: %@", context.pollContext.taskContext.operationUUID);
	#endif
		
		[self touchDidComplete:task inSession:session withError:error context:context];
	}
	else
	{
		NSAssert(NO, @"Unexpected context");
	}
}

- (void)resumeOperationsPendingPullCompletion:(NSString *)latestChangeToken
                               forLocalUserID:(NSString *)localUserID
                                       zAppID:(NSString *)zAppID
{
	ZDCCloud *cloudExt = [owner.databaseManager cloudExtForUser:localUserID app:zAppID];
	
	__block BOOL detectedInfiniteLoop = NO;
	__block NSMutableArray<ZDCCloudOperation *> *blockedOps = [NSMutableArray array];
	
	for (YapDatabaseCloudCorePipeline *pipeline in [cloudExt registeredPipelines])
	{
		[pipeline enumerateOperationsUsingBlock:
		  ^(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
		{
			if ([operation isKindOfClass:[ZDCCloudOperation class]])
			{
				ZDCCloudOperation *op = (ZDCCloudOperation *)operation;
				
				if (op.ephemeralInfo.resolveByPulling)
				{
					[blockedOps addObject:op];
					
					if (op.ephemeralInfo.lastChangeToken)
					{
						BOOL lastPullWasEmpty = [op.ephemeralInfo.lastChangeToken isEqualToString:latestChangeToken];
						if (lastPullWasEmpty)
						{
							detectedInfiniteLoop = YES;
						}
						
						// Don't forget to null this out here.
						// Because if an infinite loop is detected, we're going to force start a full pull.
						// And after that pull finishes, this method will get called again.
						// So if the lastChangeToke is still set, it will detect another infinite loop.
						// Thus, creating an infinite loop (ironically).
						//
						op.ephemeralInfo.lastChangeToken = nil;
					}
				}
			}
		}];
	}
		
	if (detectedInfiniteLoop)
	{
		[cloudExt suspend];
		[self incrementSuspendCountForLocalUserID:localUserID zAppID:zAppID];
		
		[self forceFullPullForLocalUserID:localUserID zAppID:zAppID];
	}
	else
	{
		// we're ready to resume operation
		
		for (ZDCCloudOperation *op in blockedOps)
		{
			op.ephemeralInfo.resolveByPulling = NO;
			op.ephemeralInfo.postResolveUUID = [NSUUID UUID];
			
			NSString *ctx = NSStringFromClass([self class]);
			
			[[self pipelineForOperation:op] setHoldDate:nil forOperationWithUUID:op.uuid context:ctx];
		}
		
		NSUInteger suspendCount = [self drainSuspendCountForLocalUserID:localUserID zAppID:zAppID];
		for (NSUInteger i = 0; i < suspendCount; i++)
		{
			[cloudExt resume];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Put
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)preparePutOperation:(ZDCCloudOperation *)operation
                forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	
	// Create context with boilerplate values
	
	ZDCTaskContext *context = [[ZDCTaskContext alloc] initWithOperation:operation];
	
	// Sanity checks
	
	if (operation.cloudLocator == nil
	 || operation.cloudLocator.region == AWSRegion_Invalid
	 || operation.cloudLocator.bucket == nil
	 || operation.cloudLocator.cloudPath == nil)
	{
		DDLogWarn(@"Skipping PUT operation: invalid op.cloudLocator: %@", operation.cloudLocator);
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Prepare continuationBlocks, to be executed after preparation is complete.
	
	void (^continueWithFileData)(NSData *) =
		^(NSData *fileData){ @autoreleasepool
	{
		if (fileData == nil)
		{
			[self skipOperationWithContext:context];
			return;
		}
		
		context.sha256Hash = [AWSPayload signatureForPayload:fileData];
			
	#if TARGET_OS_IPHONE
			
		// Background NSURLSession's don't support data tasks !
		//
		// So we write the data to a temporary location on disk, in order to use a file task.
		
		NSString *fileName = [operation.uuid UUIDString];
		
		NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
		NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:fileName isDirectory:NO];
		
		NSError *error = nil;
		[fileData writeToURL:tempFileURL options:0 error:&error];
		
		if (error)
		{
			DDLogError(@"Error writing operation.data (%@): %@", tempFileURL.path, error);
		}
		
		context.uploadFileURL = tempFileURL;
		context.deleteUploadFileURL = YES;
		
		[self startPutOperation:operation withContext:context];
		
	#else // macOS
			
		context.uploadData = fileData;
		
		[self startPutOperation:operation withContext:context];
			
	#endif
	}};
	
	void (^continueWithFileURL)(NSURL*) =
		^(NSURL *fileURL){ @autoreleasepool
	{
		if (fileURL == nil)
		{
			[self skipOperationWithContext:context];
			return;
		}
		
		context.uploadFileURL = fileURL;
		
		// We need the SHA256 value in order to perform the upload.
		
		ZDCInterruptingInputStream *fileStream =
		  [[ZDCInterruptingInputStream alloc] initWithFileURL:fileURL];
		
		[AWSPayload signatureForPayloadWithStream: fileStream
		                          completionQueue: concurrentQueue
		                          completionBlock:^(NSString *sha256HashInLowercaseHex, NSError *error)
		{
			if ([self isFileModifiedDuringReadError:error])
			{
				[self retryOperationWithContext:context];
			}
			else if (sha256HashInLowercaseHex)
			{
				context.sha256Hash = sha256HashInLowercaseHex;
				[self startPutOperation:operation withContext:context];
			}
			else
			{
				[self skipOperationWithContext:context];
			}
		}];
	}};
	
	void (^continueWithFileStream)(Cleartext2CloudFileInputStream *) =
		^(Cleartext2CloudFileInputStream *fileStream){ @autoreleasepool
	{
		if (fileStream == nil)
		{
			[self skipOperationWithContext:context];
			return;
		}
		
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's don't support stream tasks !
		//
		// So we write the data to a temporary location on disk, in order to use a file task.
		
		[self writeStreamToDisk: fileStream
		        completionQueue: concurrentQueue
		        completionBlock:^(NSURL *fileURL, NSString *sha256Hash, NSError *error)
		{
			context.uploadFileURL = fileURL;
			context.deleteUploadFileURL = YES;
			
			if ([self isFileModifiedDuringReadError:error])
			{
				[self retryOperationWithContext:context];
			}
			else if (fileURL && sha256Hash)
			{
				context.sha256Hash = [sha256Hash lowercaseString];
				[self startPutOperation:operation withContext:context];
			}
			else
			{
				[self skipOperationWithContext:context];
			}
		}];
		
	#else // macOS
		
		// We need the SHA256 value in order to perform the upload.
		
		Cleartext2CloudFileInputStream *fileStreamCopy = [fileStream copy];
		
		[AWSPayload signatureForPayloadWithStream: fileStreamCopy
		                          completionQueue: concurrentQueue
		                          completionBlock:^(NSString *sha256HashInLowercaseHex, NSError *error)
		{
			if ([self isFileModifiedDuringReadError:error])
			{
				[self retryOperationWithContext:context];
			}
			else if (sha256HashInLowercaseHex)
			{
				context.sha256Hash = sha256HashInLowercaseHex;
				context.uploadStream = fileStream;
				
				[self startPutOperation:operation withContext:context];
			}
			else
			{
				[self skipOperationWithContext:context];
			}
		}];
		
	#endif
	}};
	
	ZDCCloudOperationPutType putType = operation.putType;
	
	if (putType == ZDCCloudOperationPutType_Node_Rcrd)
	{
		// Generate ".rcrd" file content
		
		__block NSError *error = nil;
		__block ZDCNode *node = nil;
		__block NSData *rcrdData = nil;
		__block NSArray<NSString*> *missingKeys = nil;
		__block NSArray<NSString*> *missingUserIDs = nil;
		__block NSArray<NSString*> *missingServerIDs = nil;
		
		ZDCCryptoTools *cryptoTools = owner.cryptoTools;
		
		[self.roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			node = [transaction objectForKey:operation.nodeID inCollection:kZDCCollection_Nodes];
			
			rcrdData = [cryptoTools cloudRcrdForNode: node
			                             transaction: transaction
			                             missingKeys: &missingKeys
			                          missingUserIDs: &missingUserIDs
			                        missingServerIDs: &missingServerIDs
			                                   error: &error];
			
			// Snapshot current pullState.
			// We use this during conflict resolution to determine if a pull had any effect.
			
			ZDCChangeList *pullInfo =
			  [transaction objectForKey:operation.localUserID inCollection:kZDCCollection_PullState];
		
			operation.ephemeralInfo.lastChangeToken = pullInfo.latestChangeID_local;
		}];
		
		context.eTag = node.eTag_rcrd;
		
		if (error)
		{
			DDLogWarn(@"Error creating PUT operation: %@: %@", operation.cloudLocator.cloudPath, error);
			
			[self skipOperationWithContext:context];
		}
		else if (missingKeys.count > 0)
		{
			[self fixMissingKeysForNodeID:operation.nodeID operation:operation];
		}
		else if (missingUserIDs.count > 0)
		{
			[self fetchMissingUsers:missingUserIDs forOperation:operation];
		}
		else
		{
			continueWithFileData(rcrdData);
		}
	}
	else if (putType == ZDCCloudOperationPutType_Node_Data)
	{
		// Generate "*.data" content
		
		ZDCCloudOperation_AsyncData *asyncNodeData = operation.ephemeralInfo.asyncData;
		
		__block ZDCNode *node = nil;
		__block ZDCData *nodeData = nil;
		__block ZDCData *nodeMetadata = nil;
		__block ZDCData *nodeThumbnail = nil;
		
		[self.roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			if (asyncNodeData)
			{
				node = asyncNodeData.node;
				nodeData = asyncNodeData.nodeData;
				nodeMetadata = asyncNodeData.nodeMetadata;
				nodeThumbnail = asyncNodeData.nodeThumbnail;
			}
			else
			{
				node = [transaction objectForKey:operation.nodeID inCollection:kZDCCollection_Nodes];
				
				ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
				nodeData = [owner.delegate dataForNode:node atPath:path transaction:transaction];
			
				if (nodeData)
				{
					nodeMetadata = [owner.delegate metadataForNode:node atPath:path transaction:transaction];
					nodeThumbnail = [owner.delegate thumbnailForNode:node atPath:path transaction:transaction];
				}
			}
			
			// Snapshot current pullState.
			// We use this during conflict resolution to determine if a pull had any effect.
			
			ZDCChangeList *pullInfo =
			  [transaction objectForKey:operation.localUserID inCollection:kZDCCollection_PullState];
			
			operation.ephemeralInfo.lastChangeToken = pullInfo.latestChangeID_local;
		}];
		
		context.eTag = node.eTag_data;
		
		if (!asyncNodeData && !nodeData)
		{
			DDLogWarn(@"Delegate failed to create data for PUT operation: %@", operation.cloudLocator.cloudPath);
			
			[self skipOperationWithContext:context];
			return;
		}
		
		BOOL hasAsyncTasks =
		    (nodeData.promise != nil)                     // need to wait for fullfilled promise
		 || (nodeMetadata && nodeMetadata.data == nil)    // need to load into memory
		 || (nodeThumbnail && nodeThumbnail.data == nil); // need to load into memory
		
		if (hasAsyncTasks)
		{
			if (asyncNodeData == nil)
			{
				operation.ephemeralInfo.asyncData =
				  [[ZDCCloudOperation_AsyncData alloc] initWithNode: node
				                                               data: nodeData
				                                       nodeMetadata: nodeMetadata
				                                      nodeThumbnail: nodeThumbnail];
			}
			
			[self resolveAsyncNodeDataForOperation:operation];
			[[self pipelineForContext:context] setStatusAsPendingForOperationWithUUID:context.operationUUID];
			return;
		}
		
		NSData *rawMetadata = nodeMetadata.data ?: operation.ephemeralInfo.asyncData.rawMetadata;
		NSData *rawThumbnail = nodeThumbnail.data ?: operation.ephemeralInfo.asyncData.rawThumbnail;
		operation.ephemeralInfo.asyncData = nil;
		
		BOOL needsMultipart =
		  [self checkNeedsMultipart: context
		                    forNode: node
		                   withData: nodeData
		                   metadata: rawMetadata
		                  thumbnail: rawThumbnail];
		
		if (needsMultipart)
		{
			// The method is preparing the operation for multipart mode.
			// It will continue the operation when its finished.
			
			return;
		}
		
		if (nodeData.data)
		{
			// The delegate gave us raw data (not encrypted).
			// We need to encrypt it by storing it in a CloudFile.
			
		#if TARGET_OS_IPHONE
			
			// iOS is going to ultimately force us to write the data to disk.
			// So we might as well do so here.
			
			[ZDCFileConversion encryptCleartextData: nodeData.data
			                     toCloudFileWithKey: node.encryptionKey
			                               metadata: rawMetadata
			                              thumbnail: rawThumbnail
			                        completionQueue: concurrentQueue
			                        completionBlock:^(ZDCCryptoFile *cryptoFile, NSError *error)
			{
				if (error) {
					[self skipOperationWithContext:context];
				}
				else {
					context.deleteUploadFileURL = YES;
					continueWithFileURL(cryptoFile.fileURL);
				}
			}];
			
		#else
			
			// On macOS we can skip the disk IO, and do everything in memory.
			
			NSError *error = nil;
			NSData *cryptoData =
			  [ZDCFileConversion encryptCleartextData: nodeData.data
			                       toCloudFileWithKey: node.encryptionKey
			                                 metadata: rawMetadata
			                                thumbnail: rawThumbnail
			                                    error: &error];
			
			if (error) {
				[self skipOperationWithContext:context];
			}
			else {
				continueWithFileData(cryptoData);
			}
			
		#endif
		}
		else if (nodeData.cleartextFileURL)
		{
			// The delegate gave us a file in cleartext (not encrypted).
			// We need to convert it to CloudFile format.
			
			ZDCInterruptingInputStream *inputStream = nil;
			Cleartext2CloudFileInputStream *cloudStream = nil;
			
			inputStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cleartextFileURL];
			
			cloudStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inputStream
			                                                        encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = rawMetadata;
			cloudStream.rawThumbnail = rawThumbnail;
			
			continueWithFileStream(cloudStream);
		}
		else if (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
		{
			// The delegate gave us a ZDCCryptoFile in CacheFile format.
			// We need to convert it to CloudFile format.
			
			ZDCInterruptingInputStream *inputStream = nil;
			CacheFile2CleartextInputStream *clearStream = nil;
			Cleartext2CloudFileInputStream *cloudStream = nil;
			
			inputStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cryptoFile.fileURL];
			inputStream.retainToken = nodeData.cryptoFile.retainToken;
			
			clearStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: inputStream
			                                                    encryptionKey: nodeData.cryptoFile.encryptionKey];
			
			cloudStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
			                                                        encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = rawMetadata;
			cloudStream.rawThumbnail = rawThumbnail;
			
			continueWithFileStream(cloudStream);
		}
		else if (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile)
		{
			// The delegate gave us a ZDCCryptoFile in CloudFile format.
			// So, if all the following are true, then we can upload directly from the file:
			//
			// - the cryptoFile.encryptionKey matches the node.encryptionKey
			// - the cryptoFile's metadata section matches the operation's metadata
			// - the cryptoFile's thumbnail section matches the operation's thumbnail
			//
			// We can save a bunch of energy if these conditions are true.
			// On macOS this mostly just means a bunch of decryption & re-encryption.
			// But on iOS is means we also get to skip re-writing the file to disk.
			
			void (^fallbackToFileStream)(void) = ^{ @autoreleasepool {
				
				ZDCInterruptingInputStream *inputStream = nil;
				CloudFile2CleartextInputStream *clearStream = nil;
				Cleartext2CloudFileInputStream *cloudStream = nil;
			
				inputStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cryptoFile.fileURL];
				inputStream.retainToken = nodeData.cryptoFile.retainToken;
			
				clearStream =
				  [[CloudFile2CleartextInputStream alloc] initWithCloudFileStream: inputStream
				                                                    encryptionKey: nodeData.cryptoFile.encryptionKey];
			
				[clearStream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
			
				cloudStream =
				  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
				                                                        encryptionKey: node.encryptionKey];
			
				cloudStream.rawMetadata = rawMetadata;
				cloudStream.rawThumbnail = rawThumbnail;
			
				continueWithFileStream(cloudStream);
			}};
				
			if ([nodeData.cryptoFile.encryptionKey isEqualToData:node.encryptionKey])
			{
				ZDCInterruptingInputStream *inputStream = nil;
				CloudFile2CleartextInputStream *clearStream = nil;
				
				inputStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cryptoFile.fileURL];
				inputStream.retainToken = nodeData.cryptoFile.retainToken;
			
				clearStream =
				  [[CloudFile2CleartextInputStream alloc] initWithCloudFileStream: inputStream
				                                                    encryptionKey: nodeData.cryptoFile.encryptionKey];
				
				[self compareMetadata: rawMetadata
				            thumbnail: rawThumbnail
				             toStream: clearStream
				      completionQueue: concurrentQueue
				      completionBlock:^(BOOL match, NSError *error)
				{
					if (error)
					{
						if ([self isFileModifiedDuringReadError:error])
						{
							[self retryOperationWithContext:context];
						}
						else
						{
							[self skipOperationWithContext:context];
						}
					}
					else
					{
						if (match) {
							continueWithFileURL(nodeData.cryptoFile.fileURL);
						}
						else {
							fallbackToFileStream();
						}
					}
				}];
			}
			else
			{
				fallbackToFileStream();
			}
		}
		else
		{
			DDLogWarn(@"Delegate returned bad data for PUT operation: %@", operation.cloudLocator.cloudPath);
			
			[self skipOperationWithContext:context];
		}
	}
	else
	{
	#if DEBUG
		NSAssert(NO, @"Unrecognized putType !");
	#else
		DDLogError(@"Unrecognized putType !");
		[self skipOperationWithContext:context];
	#endif
	}
}

- (void)startPutOperation:(ZDCCloudOperation *)operation
              withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self putTaskDidComplete:nil inSession:nil withError:error context:context];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// Calculate staging path
		
		NSString *requestID = [self requestIDForOperation:operation];
		NSString *stagingPath = [self stagingPathForOperation:operation withContext:context];
		
		// Fire off request
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request putObject: stagingPath
		              inBucket: operation.cloudLocator.bucket
		                region: operation.cloudLocator.region
		      outUrlComponents: &urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session
		               payloadSig: context.sha256Hash];
		
		NSURLSessionUploadTask *task = nil;
	#if TARGET_OS_IPHONE
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: context.uploadFileURL
		                             progress: nil
		                    completionHandler: nil];
		
	#else // macOS
		
		if (context.uploadFileURL)
		{
			task = [session uploadTaskWithRequest: request
			                             fromFile: context.uploadFileURL
			                             progress: nil
			                    completionHandler: nil];
		}
		else if (context.uploadData)
		{
			task = [session uploadTaskWithRequest: request
			                             fromData: context.uploadData
			                             progress: nil
			                    completionHandler: nil];
		}
		else if (context.uploadStream)
		{
			// We need to explicitly set the Content-Length header.
			//
			// For file & data tasks, NSURLSession is able to determine the length,
			// and sets the header for us automatically. But there's no standard API to get the length
			// of an inputStream. So we need to do this manually.
			//
			// Additionally, this is important because:
			// - It's the only way NSURLSessionTask will know countOfBytesExpectedToSend (b/c underlying stream)
			// - AFNetworking relies on NSURLSessionTask.countOfBytesExpectedToSend for its NSProgress
			// - We rely on AFNetworking.progressForTask for monitoring the upload
			
			uint64_t fileSize = 0;
			
			if ([context.uploadStream isKindOfClass:[Cleartext2CloudFileInputStream class]]) // cloudData
			{
				Cleartext2CloudFileInputStream *stream = (Cleartext2CloudFileInputStream *)context.uploadStream;
				stream = [stream copy];
				[stream open];
				
				fileSize = [[stream encryptedFileSize] unsignedLongLongValue];
			}
			else if ([context.uploadStream isKindOfClass:[ZDCInterruptingInputStream class]]) // cleartext
			{
				ZDCInterruptingInputStream *stream = (ZDCInterruptingInputStream *)context.uploadStream;
				stream = [stream copy];
				[stream open];
				
				fileSize = [[stream fileSize] unsignedLongLongValue];
			}
			
			[request setValue:[NSString stringWithFormat:@"%llu", fileSize] forHTTPHeaderField:@"Content-Length"];
			
			task = [session uploadTaskWithStreamedRequest:request
			                                     progress:nil
			                            completionHandler:nil];
			
			[owner.sessionManager associateStream: context.uploadStream
			                             withTask: task
			                            inSession: session.session];
		}
		
	#endif
		
		NSProgress *progress = [session uploadProgressForTask:task];
		context.progress = progress;
		if (progress) {
			[owner.progressManager setUploadProgress:progress forOperation:operation];
		}
		
		[self stashContext:context];
		[owner.networkTools addRecentRequestID:requestID forUser:context.localUserID];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self putTaskDidComplete: task
			               inSession: session.session
			               withError: [self cancelledError]
			                 context: context];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)putTaskDidComplete:(NSURLSessionTask *)task
                 inSession:(NSURLSession *)session
                 withError:(NSError *)error
                   context:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	
	[self unstashContext:context];
	
	NSURLResponse *response = task.response;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];

	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	// Known status codes:
	//
	// 200 - Success
	// 404 - Bucket not found (account has been deleted)
	//
	// NOTE: This is a response directly from AWS S3 - NOT from Storm4 server.
	
	if (error)
	{
		// Request failed due to client-side error.
		// Not error from the server.
		//
		// This could be:
		// - network error (e.g. lost internet connection)
		// - file modified during read error (from S4InterruptingInputStream)
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200)
	{
		// Request failed due to AWS S3 issue.
		// This is rather abnormal, and generally only occurs under specific conditions.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// Increment the failCount for the operation, so we can do exponential backoff.
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			NSDictionary *errorInfo = @{
				@"system": @"PushManager",
				@"subsystem": @"PUT S3",
				@"statusCode": @(statusCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		
		NSTimeInterval delay;
		
		if (statusCode == 401 || statusCode == 403 || statusCode == 404)
		{
			// - 401 is the traditional unauthorized response (but amazon doesn't appear to use it)
			// - 403 seems to be what amazon uses for auth failures
			// - 404 is what we get if the bucket has been deleted
			//
			// A 404 is likely our first indicator that our acount has been deleted.
			// Because the bucket gets deleted right away,
			// even though our authentication sticks around for a few hours.
			
			[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			
			// Use a longer delay here.
			// We want time to check on the status of our account.
			
			delay = 30; // seconds
		}
		else
		{
			DDLogWarn(@"Received unknown statusCode from S3: %ld", (long)statusCode);
			
			// The operation failed for some unknown reason.
			//
			// This may indicate that the server is overloaded,
			// and doing some kind of rate limiting.
			//
			// So we execute exponential backoff algorithm.
			
			delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		}
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}

	// Request succeeded !
	//
	// Start polling for staging response.
	
	[operation.ephemeralInfo s3_didSucceed];
	
	ZDCPollContext *pollContext = [[ZDCPollContext alloc] init];
	
	pollContext.taskContext = context;
	pollContext.eTag = [response eTag];
	
	[self startPollWithContext:pollContext pipeline:pipeline];
}

- (void)putPollDidComplete:(ZDCPollContext *)pollContext withStatus:(NSDictionary *)pollStatus
{
	DDLogAutoTrace();
	
	ZDCTaskContext *context = pollContext.taskContext;
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	/**
	 * pollStatus dictionary format:
	 * {
	 *   "status": <http style status code>
	 *   "ext": {
	 *     "code": <4th-a specific error code>,
	 *     "msg" : <human readable string>
	 *   }
	 *   "info": {
	 *     "fileID": <string>,
	 *     "eTag": <string>,
	 *     "ts": <integer>
	 *   }
	 * }
	**/
	
	NSInteger statusCode = [self statusCodeFromPollStatus:pollStatus];
	
	/**
	 * Known possibilities for:
	 * - put-if-match
	 * - put-if-nonexistent
	 *
	 * 200 (OK)
	 *
	 * 400 (Bad request)
	 *   - unknown_user_owner
	 *   - unknown_user_caller
	 *   - staging_path_invalid
	 *   - staging_file_invalid_json
	 *   - staging_file_invalid_content
	 *   - staging_file_too_big
	 *
	 * 401 (Unauthorized)
	 *   - unauthorized_missing_dst_write_permission
	 *   - unauthorized_missing_share_permission
	 *
	 * 403 (Forbidden)
	 *   - unsupported_permissions_change
	 *   - unsupported_children_change
	 *
	 * 404 (File not found)
	 *   - precondition_dst_unavailable
	 *
	 * 409 (Conflict)
	 *   - staging_file_disappeared
	 *   - staging_file_modified
	 *
	 * 412 (Precondition failed)
	 *   - precondition_dst_eTag_mismatch
	 *
	**/
	
	if (statusCode != 200)
	{
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		NSInteger extCode = 0;
		NSString *extMsg = nil;
		[self getExtCode:&extCode msg:&extMsg fromPollStatus:pollStatus];
		
		DDLogInfo(@"Conflict: %ld: %@", (long)extCode, extMsg);
		
		// Decide what to do
		
		BOOL shouldRestartFromScratch = NO;
		BOOL shouldAbort = NO;
		
		if (extCode == ZDCErrCode_staging_file_disappeared ||
		    extCode == ZDCErrCode_staging_file_modified     )
		{
			// These errors are extremely unlikely,
			// but may occur if somebody is trying to trick our server.
			
			NSUInteger successiveFailCount = [operation.ephemeralInfo s4_didFailWithExtStatusCode:@(extCode)];
			DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
			
			if (successiveFailCount > 10)
			{
				// Give up
				
				shouldAbort = YES;
			}
			else
			{
				// We need to restart the upload from the beginning to combat the attacker.
				//
				// Note: Even though we're restarting the upload (going back to S3 upload),
				// we've incremented the s4_failCount. Thus if this loop continues,
				// we'll ultimately abort (to prevent an infinite loop).
				
				shouldRestartFromScratch = YES;
			}
		}
		else if (extCode == ZDCErrCode_staging_file_invalid_json    ||
		         extCode == ZDCErrCode_staging_file_invalid_content ||
		         extCode == ZDCErrCode_staging_file_too_big          )
		{
			// These are client-side errors (we're uploading a bad staging file).
			// We can't recover from these errors by doing a pull.
			
			shouldAbort = YES;
		}
		else
		{
			NSUInteger successiveFailCount = [operation.ephemeralInfo s4_didFailWithExtStatusCode:@(extCode)];
			DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
			
			if (successiveFailCount > 10)
			{
				// Infinite loop prevention.
				
				shouldAbort = YES;
			}
		}
		
		// Execute plan-of-action
		
		if (shouldRestartFromScratch)
		{
			operation.ephemeralInfo.pollContext = nil;
			operation.ephemeralInfo.touchContext = nil;
			
			[[self pipelineForContext:context] setStatusAsPendingForOperationWithUUID:operation.uuid];
			return;
		}
		else if (shouldAbort)
		{
			NSDictionary *errorInfo = @{
				@"system": @"PushManager",
				@"subsystem": @"PUT ZDC",
				@"extStatusCode": @(extCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		else
		{
			operation.ephemeralInfo.resolveByPulling = YES;
		
			YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
			
			NSTimeInterval delay = 60 * 10; // safety fallback
			NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
			NSString *ctx = NSStringFromClass([self class]);
			
			[pipeline setHoldDate:holdDate forOperationWithUUID:operation.uuid context:ctx];
			[pipeline setStatusAsPendingForOperationWithUUID:operation.uuid];
		
			[owner.pullManager pullRemoteChangesForLocalUserID:operation.localUserID zAppID:operation.zAppID];
			return;
		}
	}
	
	// The operation was successful !
	
	NSString *cloudID = nil;
	NSString *eTag = nil;
	NSDate *lastModified = nil;
	
	NSDictionary *status_info = pollStatus[@"info"];
	if ([status_info isKindOfClass:[NSDictionary class]])
	{
		cloudID = status_info[@"fileID"];
		eTag    = status_info[@"eTag"];
		
		lastModified = [self dateFromJavascriptTimestamp:status_info[@"ts"]];
	}
	
	if (eTag == nil) {
		eTag = pollContext.eTag;
	}
	
	void (^completeBlock)(void) = ^{ @autoreleasepool {
		
		__block ZDCNode *node = nil;
	
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			// Mark operation as complete
			
			NSString *extName = [self extNameForContext:context];
			
			[[transaction ext:extName] completeOperationWithUUID:context.operationUUID];
			
			// Update node (if operation was node related)
			
			node = [transaction objectForKey:operation.nodeID inCollection:kZDCCollection_Nodes];
			if (node)
			{
				// Update node
				//
				// - cloudID
				// - eTag_X
				// - lastModified_X
				
				node = [node copy];
				
				if (cloudID && ![node.cloudID isEqualToString:cloudID])
				{
					node.cloudID = cloudID;
				}
				
				if (operation.putType == ZDCCloudOperationPutType_Node_Rcrd)
				{
					if (eTag && ![node.eTag_rcrd isEqualToString:eTag])
					{
						node.eTag_rcrd = eTag;
					}
					if (lastModified && ![node.lastModified_rcrd isEqualToDate:lastModified])
					{
						node.lastModified_rcrd = lastModified;
					}
				}
				else if (operation.putType == ZDCCloudOperationPutType_Node_Data)
				{
					if (eTag && ![node.eTag_data isEqualToString:eTag])
					{
						node.eTag_data = eTag;
					}
					if (lastModified && ![node.lastModified_data isEqualToDate:lastModified])
					{
						node.lastModified_data = lastModified;
					}
				}
				
				[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
				
				if (operation.putType == ZDCCloudOperationPutType_Node_Data)
				{
					ZDCTreesystemPath *path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
					
					[owner.delegate didPushNodeData:node atPath:path transaction:transaction];
				}
			}
			
			// Remove redundant operations (if needed)
			
			if (context.matchingOpUUIDs)
			{
				[[transaction ext:extName] skipOperationsPassingTest:
				 ^BOOL (YapDatabaseCloudCorePipeline *pipeline,
						  YapDatabaseCloudCoreOperation *op, NSUInteger graphIdx, BOOL *stop)
				{
					if ([context.matchingOpUUIDs containsObject:op.uuid])
					{
						return YES;
					}
					
					return NO;
				}];
			}
			
		} completionQueue:concurrentQueue completionBlock:^{
			
			[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:YES];
			
		}]; // end: readWriteTransaction.completionBlock
		
	}}; // end: completeBlock
	
	
#if TARGET_OS_OSX
	
	BOOL waitingForChecksum = NO;
	
	if (context.uploadStream || operation.multipartInfo)
	{
		// Uploading a file is a little different than uploading a RCRD or XATTR.
		//
		// We use ZDCInterruptingInputStream as part of the uploadStream.
		// So if the file is modified while it's being uploaded,
		// then we abort the upload, and restart.
		//
		// Long story short:
		//   If the file currently on disk matches what we just uploaded,
		//   then we can skip all matching operations in the queue.
		
		__block NSMutableSet<NSUUID *> *matchingOpUUIDs = nil;
		
		[[self pipelineForContext:context] enumerateOperationsUsingBlock:
			^(YapDatabaseCloudCoreOperation *opGeneric, NSUInteger graphIdx, BOOL *stop)
		{
			if ([opGeneric isKindOfClass:[ZDCCloudOperation class]])
			{
				__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)opGeneric;
				
				if (![op.uuid isEqual:operation.uuid] && // Ignore our own operation
				    [op hasSameTarget:operation])
				{
					if (matchingOpUUIDs == nil)
						matchingOpUUIDs = [NSMutableSet set];
	
					[matchingOpUUIDs addObject:op.uuid];
				}
			}
		}];
		/*
		if (matchingOpUUIDs.count > 0)
		{
			NSString *preChecksum = nil;
			NSInputStream *iStream = nil;
		 
			if (operation.multipartInfo)
			{
				preChecksum = operation.multipartInfo.sha256Hash; // over entire cloudFile
		 
				S4FileFormat format = S4FileFormat_CloudFile;
				id retainToken = nil;
				NSURL *fileURL = nil;
		 
				fileURL = [S4CacheManager cachedURLForFileID:operation.nodeID format:&format retainToken:&retainToken];
		 
				if (fileURL && (format == S4FileFormat_CloudFile))
				{
					iStream = [NSInputStream inputStreamWithURL:fileURL];
				}
				else if (fileURL && (format == S4FileFormat_CacheFile))
				{
					__block S4File *file = nil;
					[S4DatabaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		 
						S4Node *node = [transaction objectForKey:operation.nodeID inCollection:kS4Collection_Nodes];
						if ([node isKindOfClass:[S4File class]]) {
							file = (S4File *)node;
						}
					}];
		 
					CacheFile2CleartextInputStream *clearStream = nil;
					Cleartext2CloudFileInputStream *cloudStream = nil;
		 
					clearStream = [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: fileURL
					                                                             encryptionKey: file.encryptionKey];
		 
					cloudStream = [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
					                                                                    encryptionKey: file.encryptionKey];
		 
					cloudStream.rawMetadata = [S4CloudFileUtilities rawMetadataForNode:file];
					cloudStream.rawThumbnail = [S4CloudFileUtilities rawThumbnailForNode:file];
		 
					iStream = cloudStream;
				}
			}
			else // NOT multipart
			{
				preChecksum = context.sha256Hash;
				iStream = [context.uploadStream copy];
			}
		 
			if (preChecksum && iStream)
			{
				[S4FileChecksum checksumFileStream: iStream
				                    withStreamSize: 0
				                         algorithm: kHASH_Algorithm_SHA256
				                   completionQueue: concurrentQueue
				                   completionBlock:^(NSData *hash, NSError *error)
				{
					if (hash)
					{
						NSString *postChecksum = [hash lowercaseHexString];
						if ([preChecksum isEqualToString:postChecksum])
						{
							context.matchingOpUUIDs = matchingOpUUIDs;
						}
					}
		 
					completeBlock();
				}];
		 
				waitingForChecksum = YES;
			}
		
		} // end: if (matchingOpUUIDs.count > 0)
		*/
	} // end: if (context.uploadStream)
	
	if (!waitingForChecksum) {
		completeBlock();
	}
	
#else // iOS
	
	completeBlock();
	
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Put - Multipart
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareMultipartOperation:(ZDCCloudOperation *)operation forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	NSAssert(operation.multipartInfo, @"Invalid operation type");
	
#if TARGET_OS_IPHONE
	void (^continueWithFileStream)(ZDCTaskContext *, NSInputStream *) =
	^(ZDCTaskContext *context, NSInputStream *stream){ @autoreleasepool {
		
		NSParameterAssert(context != nil);
		NSParameterAssert(stream != nil);
		
		[self writeStreamToDisk: stream
		        completionQueue: concurrentQueue
		        completionBlock:^(NSURL *multipartFileURL, NSString *sha256Hash, NSError *error)
		{
			if (!multipartFileURL || !sha256Hash)
			{
				[self retryOperationWithContext:context];
				return;
			}
			
			NSString *expectedHash = operation.multipartInfo.checksums[@(context.multipart_index)];
			
			if ([sha256Hash isEqualToString:expectedHash])
			{
				context.sha256Hash = sha256Hash;
				context.uploadFileURL = multipartFileURL;
				context.deleteUploadFileURL = YES;
				
				[self startMultipartOperation:operation withContext:context];
			}
			else
			{
				// The original eTag calculation doesn't match what we just calculated.
				// This means the file has been modified, and we need to restart the operation.
				
				[self abortMultipartOperation:operation];
			}
		}];
	}};
#endif
	
#if TARGET_OS_OSX
	void (^continueWithFileStream)(ZDCTaskContext *, NSInputStream *) =
	^(ZDCTaskContext *context, NSInputStream *fileStream){ @autoreleasepool {
		
		NSParameterAssert(context != nil);
		NSParameterAssert(fileStream != nil);
		
		[AWSPayload signatureForPayloadWithStream: [fileStream copy]
		                          completionQueue: concurrentQueue
		                          completionBlock:^(NSString *sha256Hash, NSError *error)
		{
			if (error)
			{
				if ([self isFileModifiedDuringReadError:error]) {
					DDLogInfo(@"File modified during SHA256 hash: retrying operation...");
				}
				else {
					DDLogInfo(@"Error during SHA256 hash: %@", error);
				}
				
				[self removeTaskForMultipartOperation:context didSucceed:NO];
				[self retryOperationWithContext:context];
			}
			else
			{
				NSString *expectedHash = operation.multipartInfo.checksums[@(context.multipart_index)];
				
				if ([sha256Hash isEqualToString:expectedHash])
				{
					context.sha256Hash = sha256Hash;
					context.uploadStream = fileStream;
					
					[self startMultipartOperation:operation withContext:context];
				}
				else
				{
					// The original eTag calculation doesn't match what we just calculated.
					// This means the file has been modified, and we need to restart the operation.
					
					[self abortMultipartOperation:operation];
				}
			}
		}];
	}};
#endif
	
	// Prepare for multipart
	
	__block ZDCNode *node = nil;
	
	[self.roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		node = [transaction objectForKey:operation.nodeID inCollection:kZDCCollection_Nodes];
	}];
	
	if (node == nil)
	{
		// The node was deleted before we could finish uploading it
		
		ZDCTaskContext *context = [[ZDCTaskContext alloc] initWithOperation:operation];
		[self skipOperationWithContext:context];
		return;
	}
	
	ZDCTaskContext *context = nil;
	while ((context = [self nextTaskForMultipartOperation:operation]))
	{
		if (context.multipart_initiate ||
		    context.multipart_complete ||
		    context.multipart_abort)
		{
			[self startMultipartOperation:operation withContext:context];
			break;
		}
		
		ZDCData *nodeData = operation.ephemeralInfo.multipartData;
		
		uint64_t offset_min = context.multipart_index * operation.multipartInfo.chunkSize;
		uint64_t offset_max = offset_min + operation.multipartInfo.chunkSize;
		
		if (nodeData.data)
		{
			Cleartext2CloudFileInputStream *cloudStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextData: nodeData.data
			                                                  encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = operation.multipartInfo.rawMetadata;
			cloudStream.rawThumbnail = operation.multipartInfo.rawThumbnail;
			
			[cloudStream setProperty:@(offset_min) forKey:ZDCStreamFileMinOffset];
			[cloudStream setProperty:@(offset_max) forKey:ZDCStreamFileMaxOffset];
			
			continueWithFileStream(context, cloudStream);
		}
		else if (nodeData.cleartextFileURL)
		{
			ZDCInterruptingInputStream *inputStream =
			  [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cleartextFileURL];
			
			Cleartext2CloudFileInputStream *cloudStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inputStream
			                                                        encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = operation.multipartInfo.rawMetadata;
			cloudStream.rawThumbnail = operation.multipartInfo.rawThumbnail;
			
			[cloudStream setProperty:@(offset_min) forKey:ZDCStreamFileMinOffset];
			[cloudStream setProperty:@(offset_max) forKey:ZDCStreamFileMaxOffset];
			
			continueWithFileStream(context, cloudStream);
		}
		else if (nodeData.cryptoFile && (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile))
		{
			ZDCInterruptingInputStream *inputStream =
			  [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cryptoFile.fileURL];
			
			inputStream.retainToken = nodeData.cryptoFile.retainToken;
			
			Cleartext2CloudFileInputStream *cloudStream =
			[[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inputStream
																					encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = operation.multipartInfo.rawMetadata;
			cloudStream.rawThumbnail = operation.multipartInfo.rawThumbnail;
			
			[cloudStream setProperty:@(offset_min) forKey:ZDCStreamFileMinOffset];
			[cloudStream setProperty:@(offset_max) forKey:ZDCStreamFileMaxOffset];
			
			continueWithFileStream(context, cloudStream);
		}
		else if (nodeData.cryptoFile && (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile))
		{
			ZDCInterruptingInputStream *inputStream = nil;
			CacheFile2CleartextInputStream *clearStream = nil;
			Cleartext2CloudFileInputStream *cloudStream = nil;
			
			inputStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:nodeData.cryptoFile.fileURL];
			inputStream.retainToken = nodeData.cryptoFile.retainToken;
			
			clearStream = [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: inputStream
																								 encryptionKey: node.encryptionKey];
			
			cloudStream = [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
			                                                                    encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = operation.multipartInfo.rawMetadata;
			cloudStream.rawThumbnail = operation.multipartInfo.rawThumbnail;
			
			[cloudStream setProperty:@(offset_min) forKey:ZDCStreamFileMinOffset];
			[cloudStream setProperty:@(offset_max) forKey:ZDCStreamFileMaxOffset];
			
			continueWithFileStream(context, cloudStream);
		}
		else
		{
			DDLogWarn(@"Error creating PUT operation: %@: unknown cryptoFile format", operation.cloudLocator.cloudPath);
			
			[self skipOperationWithContext:context];
		}
	}
}

- (void)startMultipartOperation:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	NSAssert(operation.multipartInfo, @"Invalid operation type");
	
	if (context.multipart_initiate) {
		[self startMultipartInitiate:operation withContext:context];
	}
	else if (context.multipart_complete) {
		[self startMultipartComplete:operation withContext:context];
	}
	else if (context.multipart_abort) {
		[self startMultipartAbort:operation withContext:context];
	}
	else {
		[self startMultipartIndex:operation withContext:context];
	}
}

- (void)startMultipartInitiate:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	NSAssert(operation.multipartInfo, @"Invalid operation type");
	NSAssert(context.multipart_initiate, @"Invalid context type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self multipartTaskDidComplete:nil inSession:nil withError:error context:context responseObject:nil];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request multipartInitiate: operation.multipartInfo.stagingPath
		                      inBucket: operation.cloudLocator.bucket
		                        region: operation.cloudLocator.region
		              outUrlComponents: &urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
		// For multipart initiate tasks, we need to read and parse the response XML.
		// It will give us the uploadID, which we'll need for all future requests
		// related to this multipart task.
		
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's don't really support data tasks.
		//
		// So we have to download the tiny response to a file instead.
		
		NSURLSessionDownloadTask *task =
		  [session downloadTaskWithRequest: request
		                          progress: nil
		                       destination: nil
							  completionHandler: nil];
		
	#else
		
		__block NSURLSessionDataTask *task = nil;
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			[self multipartTaskDidComplete: task
			                     inSession: session.session
			                     withError: error
			                       context: context
			                responseObject: responseObject];
		}];
		
	#endif
		
		context.progress = [session uploadProgressForTask:task];
		[self refreshProgressForMultipartOperation:operation];
	
		[self stashContext:context];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self multipartTaskDidComplete: task
			                     inSession: session.session
			                     withError: [self cancelledError]
			                       context: context
			                responseObject: nil];
		}
		else
		{
		#if TARGET_OS_IPHONE
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
		#else
			// When SessionManager gets called for the completion of a dataTask,
			// it's not given the `responseObject`, which we need in this case.
			// So we're handling the completion manually.
		#endif
			
			[task resume];
		}
	}];
}

- (void)startMultipartIndex:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	NSAssert(operation.multipartInfo, @"Invalid operation type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self multipartTaskDidComplete:nil inSession:nil withError:error context:context responseObject:nil];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// We use zero based indexing.
		// AWS uses one based indexing.
		//
		NSUInteger aws_part = context.multipart_index + 1;
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request multipartUpload: operation.multipartInfo.stagingPath
		                withUploadID: operation.multipartInfo.uploadID
		                        part: aws_part
		                    inBucket: operation.cloudLocator.bucket
		                      region: operation.cloudLocator.region
		            outUrlComponents: &urlComponents];
		
	#if TARGET_OS_OSX
		if (context.uploadStream)
		{
			// We need to explicitly set the Content-Length header.
			//
			// For file & data tasks, NSURLSession is able to determine the length,
			// and sets the header for us automatically. But there's no standard API to get the length
			// of an inputStream. So we need to do this manually.
			//
			// Additionally, this is important because:
			// - It's the only way NSURLSessionTask will know countOfBytesExpectedToSend (b/c underlying stream)
			// - AFNetworking relies on NSURLSessionTask.countOfBytesExpectedToSend for its NSProgress
			// - We rely on AFNetworking.progressForTask for monitoring the upload
				
			uint64_t fileSize = 0;
				
			if ([context.uploadStream isKindOfClass:[Cleartext2CloudFileInputStream class]]) // cloudData
			{
				Cleartext2CloudFileInputStream *stream = (Cleartext2CloudFileInputStream *)context.uploadStream;
				[stream open];
				
				fileSize = [[stream encryptedRangeSize] unsignedLongLongValue];
			}
			else if ([context.uploadStream isKindOfClass:[ZDCInterruptingInputStream class]]) // cleartext
			{
				ZDCInterruptingInputStream *stream = (ZDCInterruptingInputStream *)context.uploadStream;
				[stream open];
				
				fileSize = [[stream fileSize] unsignedLongLongValue];
			}
			
			[request setValue:[NSString stringWithFormat:@"%llu", fileSize] forHTTPHeaderField:@"Content-Length"];
		}
	#endif
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session
		               payloadSig: context.sha256Hash];
		
		NSURLSessionDataTask *task = nil;
		
		if (context.uploadFileURL)
		{
			task = [session uploadTaskWithRequest: request
												  fromFile: context.uploadFileURL
												  progress: nil
									  completionHandler: nil];
		}
	#if TARGET_OS_OSX
		else if (context.uploadStream)
		{
			task = [session uploadTaskWithStreamedRequest: request
															 progress: nil
												 completionHandler: nil];
			
			[owner.sessionManager associateStream:context.uploadStream withTask:task inSession:session.session];
		}
	#endif
		else
		{
			NSAssert(NO, @"Unrecognized upload type");
		}
		
		context.progress = [session uploadProgressForTask:task];
		[self refreshProgressForMultipartOperation:operation];
		
		[self stashContext:context];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self multipartTaskDidComplete: task
			                     inSession: session.session
			                     withError: [self cancelledError]
			                       context: context
			                responseObject: nil];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)startMultipartComplete:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	NSAssert(operation.multipartInfo, @"Invalid operation type");
	NSAssert(context.multipart_complete, @"Invalid context type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self multipartTaskDidComplete:nil inSession:nil withError:error context:context responseObject:nil];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		NSUInteger capacity = operation.multipartInfo.eTags.count;
		NSMutableArray<NSString *> *eTags = [NSMutableArray arrayWithCapacity:capacity];
		
		NSArray<NSNumber *> *orderedKeys =
		  [[operation.multipartInfo.eTags allKeys] sortedArrayUsingSelector:@selector(compare:)];
		for (NSNumber *key in orderedKeys)
		{
			NSString *eTag = operation.multipartInfo.eTags[key];
			[eTags addObject:eTag];
		}
		
		// We don't directly hit S3.
		// Instead we go through our own server, in order to avoid pitfalls with S3.
		
		NSMutableURLRequest *request =
		  [owner.webManager multipartComplete: operation.multipartInfo.stagingPath
		                         withUploadID: operation.multipartInfo.uploadID
		                                eTags: eTags
		                             inBucket: operation.cloudLocator.bucket
		                               region: operation.cloudLocator.region
		                       forLocalUserID: operation.localUserID
		                             withAuth: auth];
		
		NSURLSessionTask *task = nil;
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's do NOT support dataTask's.
		//
		// So we write the data to a temporary location on disk, in order to use a file task.
		
		NSString *fileName = [[NSUUID UUID] UUIDString];
		
		NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
		NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:fileName isDirectory:NO];
		
		NSError *writeError = nil;
		[request.HTTPBody writeToURL:tempFileURL options:0 error:&writeError];
		
		if (writeError)
		{
			DDLogError(@"Error writing operation.data (%@): %@", tempFileURL.path, writeError);
		}
		
		request.HTTPBody = nil;
		
		context.uploadFileURL = tempFileURL;
		context.deleteUploadFileURL = YES;
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: context.uploadFileURL
		                             progress: nil
		                    completionHandler: nil];
		
	#else
	
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler: nil];
	
	#endif
		
		context.progress = [session uploadProgressForTask:task];
		[self refreshProgressForMultipartOperation:operation];
		
		NSString *requestID = [self requestIDForOperation:operation];
		
		[self stashContext:context];
		[owner.networkTools addRecentRequestID:requestID forUser:context.localUserID];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self multipartTaskDidComplete: task
			                     inSession: session.session
			                     withError: [self cancelledError]
			                       context: context
			                responseObject: nil];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)startMultipartAbort:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Put, @"Invalid operation type");
	NSAssert(operation.multipartInfo, @"Invalid operation type");
	NSAssert(context.multipart_abort, @"Invalid context type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self multipartTaskDidComplete:nil inSession:nil withError:error context:context responseObject:nil];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request multipartAbort: operation.multipartInfo.stagingPath
		               withUploadID: operation.multipartInfo.uploadID
		                   inBucket: operation.cloudLocator.bucket
		                     region: operation.cloudLocator.region
		           outUrlComponents: &urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
		NSURLSessionTask *task = nil;
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's do NOT support dataTask's.
		// So we have to fake it by instead creating an uploadTask with an empty file.
		//
		// It's goofy, but this is the hoop that Apple is making us jump through.
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: [ZDCDirectoryManager emptyUploadFileURL]
		                             progress: nil
		                    completionHandler: nil];
		
	#else
		
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler: nil];
		
	#endif
		
		context.progress = [session uploadProgressForTask:task];
		[self refreshProgressForMultipartOperation:operation];
		
		[self stashContext:context];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self multipartTaskDidComplete: task
			                     inSession: session.session
			                     withError: [self cancelledError]
			                       context: context
			                responseObject: nil];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)multipartTaskDidComplete:(NSURLSessionTask *)task
                       inSession:(NSURLSession *)session
                       withError:(NSError *)error
                         context:(ZDCTaskContext *)context
                  responseObject:(id)responseObject
{
	DDLogAutoTrace();
	
	[self unstashContext:context];
	
	NSURLResponse *response = task.response;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	// Known status codes:
	//
	// 200 - Success
	// 204 - No Content (returned for successful multipart_abort)
	// 404 - <multiple>
	//  - Bucket not found (account has been deleted)
	//  - Multipart has expired / aborted
	
	if (error)
	{
		DDLogInfo(@"multipartTask: err: %@", error.userInfo[NSLocalizedDescriptionKey] ?: error);
		
		// Request failed due to client-side error.
		// Not error from the server.
		//
		// This could be:
		// - network error (e.g. lost internet connection)
		// - file modified during read error (from S4InterruptingInputStream)
		
		[self removeTaskForMultipartOperation:context didSucceed:NO];
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely, the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200 && statusCode != 204)
	{
		// Request failed due to AWS S3 issue.
		// This is rather abnormal, and generally only occurs under specific conditions.
		
		[self removeTaskForMultipartOperation:context didSucceed:NO];
		
		// Increment the failCount for the operation, so we can do exponential backoff.
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			NSDictionary *errorInfo = @{
				@"system": @"S4PushManager",
				@"subsystem": @"PUT S3 (multipart)",
				@"statusCode": @(statusCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		
		NSTimeInterval delay = -1;
		
		if (statusCode == 401 || statusCode == 403 || statusCode == 404)
		{
			// - 401 is the traditional unauthorized response (but amazon doesn't appear to use it)
			// - 403 seems to be what amazon uses for auth failures
			// - 404 is what we get if the bucket has been deleted
			//
			// A 404 is likely our first indicator that our acount has been deleted.
			// Because the bucket gets deleted right away,
			// even though our authentication sticks around for a few hours.
			
			[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			
			if (statusCode == 404)
			{
				// A 404 may also signify that the multipart upload was deleted.
				// This could be because it expired, or was explicitly aborted.

				[self abortMultipartOperation:[self operationForContext:context]];
			}
			else
			{
				// Use a longer delay here.
				// We want time to check on the status of our account.
				
				delay = 30; // seconds
			}
		}
		else
		{
			DDLogWarn(@"Received unknown statusCode from S3: %ld", (long)statusCode);
			
			// The operation failed for some unknown reason.
			//
			// This may indicate that the server is overloaded,
			// and doing some kind of rate limiting.
			//
			// So we execute exponential backoff algorithm.
			
			delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		}
		
		if (delay >= 0)
		{
			NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
			NSString *ctx = NSStringFromClass([self class]);
			
			[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
			[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		}
		return;
	}
	
	// Request succeeded !
	
	[operation.ephemeralInfo s3_didSucceed];
	
	if (context.multipart_initiate)
	{
		// Store the uploadID in the database,
		// and then we can re-queue the operation (which will trigger the upload of parts).
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			S3Response *response = nil;
			if ([responseObject isKindOfClass:[S3Response class]])
			{
				response = (S3Response *)responseObject;
			}
			
			NSString *uploadID = response.initiateMultipartUpload.uploadID;
			
			NSString *extName = [self extNameForContext:context];
			ZDCCloudTransaction *ext = [transaction ext:extName];
			
			ZDCCloudOperation *op = (ZDCCloudOperation *)
			  [[ext operationWithUUID:context.operationUUID inPipeline:context.pipeline] copy];
			
			op.multipartInfo.uploadID = uploadID;
			
			[ext modifyOperation:op];
			
		} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
			
			[self removeTaskForMultipartOperation:context didSucceed:YES];
			[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		}];
	}
	else if (context.multipart_complete)
	{
		// Start polling for the response from the staging system
		
		[self removeTaskForMultipartOperation:context didSucceed:YES];
		
		ZDCPollContext *pollContext = [[ZDCPollContext alloc] init];
		
		pollContext.taskContext = context;
		pollContext.eTag = [response eTag];
		
		[self startPollWithContext:pollContext pipeline:pipeline];
	}
	else if (context.multipart_abort)
	{
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			NSString *extName = [self extNameForContext:context];
			ZDCCloudTransaction *ext = [transaction ext:extName];
			
			ZDCCloudOperation *op = (ZDCCloudOperation *)
			  [[ext operationWithUUID:context.operationUUID inPipeline:context.pipeline] copy];
			
			if (op.multipartInfo.needsSkip)
			{
				// Skip operation
				[ext skipOperationWithUUID:op.uuid];
			}
			else
			{
				// Restart operation
				op.multipartInfo = nil;
				[ext modifyOperation:op];
			}
			
		} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
			
			[self removeTaskForMultipartOperation:context didSucceed:YES];
			[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		}];
	}
	else
	{
		// Store eTag for part
		
		NSString *eTag = [response eTag];
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			NSString *extName = [self extNameForContext:context];
			ZDCCloudTransaction *ext = [transaction ext:extName];
			
			ZDCCloudOperation *op = (ZDCCloudOperation *)
			  [[ext operationWithUUID:context.operationUUID inPipeline:context.pipeline] copy];
			
			NSMutableDictionary *newETags = op.multipartInfo.eTags
			  ? [op.multipartInfo.eTags mutableCopy]
			  : [[NSMutableDictionary alloc] initWithCapacity:1];
			
			newETags[@(context.multipart_index)] = eTag;
			
			op.multipartInfo.eTags = newETags;
			
			[ext modifyOperation:op];
			
		} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
			
			// Keep uploading parts
			
			[self removeTaskForMultipartOperation:context didSucceed:YES];
			[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Move
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareMoveOperation:(ZDCCloudOperation *)operation forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Move, @"Invalid operation type");
	
	// Create context with boilerplate values
	
	ZDCTaskContext *context = [[ZDCTaskContext alloc] initWithOperation:operation];
	
	// Sanity checks
	
	if (operation.cloudLocator == nil
	 || operation.cloudLocator.region == AWSRegion_Invalid
	 || operation.cloudLocator.bucket == nil
	 || operation.cloudLocator.cloudPath == nil)
	{
		DDLogWarn(@"Skipping move operation: invalid op.cloudLocator: %@", operation.cloudLocator);
		
		[self skipOperationWithContext:context];
		return;
	}
	
	if (operation.dstCloudLocator == nil
	 || operation.dstCloudLocator.region == AWSRegion_Invalid
	 || operation.dstCloudLocator.bucket == nil
	 || operation.dstCloudLocator.cloudPath == nil)
	{
		DDLogWarn(@"Skipping move operation: invalid op.dstCloudLocator: %@", operation.dstCloudLocator);
		
		[self skipOperationWithContext:context];
		return;
	}
	
	if ([operation.cloudLocator isEqualToCloudLocatorIgnoringExt:operation.dstCloudLocator])
	{
		DDLogWarn(@"Skipping move operation: src == dst: %@", operation);
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Generate ".rcrd" file content
	
	__block NSError *error = nil;
	__block NSData *rcrdData = nil;
	
	__block NSArray<NSString*> *missingKeys = nil;
	__block NSArray<NSString*> *missingUserIDs = nil;
	__block NSArray<NSString*> *missingServerIDs = nil;
	
	ZDCCryptoTools *cryptoTools = owner.cryptoTools;
	
	[[self roConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		ZDCNode *node = [transaction objectForKey:operation.nodeID inCollection:kZDCCollection_Nodes];
		
		rcrdData = [cryptoTools cloudRcrdForNode: node
		                             transaction: transaction
		                             missingKeys: &missingKeys
		                          missingUserIDs: &missingUserIDs
		                        missingServerIDs: &missingServerIDs
		                                   error: &error];
		
		// The current cloudPath of the node may not match this operation.
		// This would happen if the node was moved after this operation was queued.
		// So we need to fetch the cloudNode,
		// while ensuring both the fileID & operation path both match.
		
		// Snapshot current pullState.
		// We use this during conflict resolution to determine if a pull had any effect.
		
		ZDCChangeList *pullInfo =
		  [transaction objectForKey:operation.localUserID inCollection:kZDCCollection_PullState];
		
		operation.ephemeralInfo.lastChangeToken = pullInfo.latestChangeID_local;
	}];
	
	if (error)
	{
		DDLogWarn(@"Error creating operation data (%@) %@", operation.cloudLocator.cloudPath, error);
		
		[self skipOperationWithContext:context];
	}
	else if (missingKeys.count > 0)
	{
		[self fixMissingKeysForNodeID:operation.nodeID operation:operation];
	}
	else if (missingUserIDs.count > 0)
	{
		[self fetchMissingUsers:missingUserIDs forOperation:operation];
	}
	else
	{
		context.sha256Hash = [AWSPayload signatureForPayload:rcrdData];
		
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's don't support data tasks !
		//
		// So we write the data to a temporary location on disk, in order to use a file task.
		
		NSString *fileName = [operation.uuid UUIDString];
		
		NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
		NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:fileName isDirectory:NO];
		
		NSError *error = nil;
		[rcrdData writeToURL:tempFileURL options:0 error:&error];
		
		if (error)
		{
			DDLogError(@"Error writing operation.data (%@): %@", tempFileURL.path, error);
		}
		
		context.uploadFileURL = tempFileURL;
		context.deleteUploadFileURL = YES;
		
		[self startMoveOperation:operation withContext:context];
	
	#else // macOS
		
		context.uploadData = rcrdData;
		
		[self startMoveOperation:operation withContext:context];
		
	#endif
	}
}

- (void)startMoveOperation:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Move, @"Invalid operation type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self moveTaskDidComplete:nil inSession:nil withError:error context:context];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// Calculate staging path
		
		NSString *requestID = [self requestIDForOperation:operation];
		NSString *stagingPath = [self stagingPathForOperation:operation withContext:context];
		
		// Fire off request
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request putObject:stagingPath
		              inBucket:operation.cloudLocator.bucket
		                region:operation.cloudLocator.region
		      outUrlComponents:&urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session
		               payloadSig: context.sha256Hash];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		NSURLSessionUploadTask *task = nil;
	#if TARGET_OS_IPHONE
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: context.uploadFileURL
		                             progress: nil
								  completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			if ([responseObject isKindOfClass:[NSData class]])
			{
				NSString *str = [[NSString alloc] initWithData:(NSData *)responseObject encoding:NSUTF8StringEncoding];
				DDLogInfo(@"response: %@", str);
			}
			else
			{
				DDLogInfo(@"response: %@", responseObject);
			}
		}];
		
	#else // macOS
		
		task = [session uploadTaskWithRequest:request
		                             fromData:context.uploadData
		                             progress:nil
		                    completionHandler:nil];
		
	#endif
		
		NSProgress *progress = [session uploadProgressForTask:task];
		context.progress = progress;
		if (progress) {
			[owner.progressManager setUploadProgress:progress forOperation:operation];
		}
		
		[self stashContext:context];
		[owner.networkTools addRecentRequestID:requestID forUser:context.localUserID];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self moveTaskDidComplete: task
			                inSession: session.session
			                withError: [self cancelledError]
			                  context: context];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)moveTaskDidComplete:(NSURLSessionTask *)task
                  inSession:(NSURLSession *)session
                  withError:(NSError *)error
                    context:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	
	[self unstashContext:context];
	
	NSURLResponse *response = task.response;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	// Observed status codes:
	//
	// 200 - Success
	// 404 - Bucket not found (account has been deleted)
	//
	// NOTE: This is a response directly from AWS S3 - NOT from Storm4 server.
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	if (error)
	{
		// Request failed due to network error.
		// Not error from the server.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely, the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200)
	{
		// Request failed due to AWS S3 issue.
		// This is rather abnormal, and generally only occurs under specific conditions.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			NSDictionary *errorInfo = @{
				@"system": @"S4PushManager",
				@"subsystem": @"PUT S3",
				@"statusCode": @(statusCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		
		NSTimeInterval delay;
		
		if (statusCode == 401 || statusCode == 403 || statusCode == 404)
		{
			// - 401 is the traditional unauthorized response (but amazon doesn't appear to use it)
			// - 403 seems to be what amazon uses for auth failures
			// - 404 is what we get if the bucket has been deleted
			//
			// A 404 is likely our first indicator that our acount has been deleted.
			// Because the bucket gets deleted right away,
			// even though our authentication sticks around for a few hours.
			
			[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			
			// Use a longer delay here.
			// We want time to check on the status of our account.
			
			delay = 30; // seconds
		}
		else
		{
			DDLogWarn(@"Received unknown statusCode from S3: %ld", (long)statusCode);
			
			// The operation failed for some unknown reason.
			//
			// This may indicate that the server is overloaded,
			// and doing some kind of rate limiting.
			//
			// So we execute exponential backoff algorithm.
			
			delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		}
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	
	// Request succeeded !
	//
	// Start polling for staging response.
	
	[operation.ephemeralInfo s3_didSucceed];
	
	ZDCPollContext *pollContext = [[ZDCPollContext alloc] init];
	
	pollContext.taskContext = context;
	pollContext.eTag = [response eTag];
	
	[self startPollWithContext:pollContext pipeline:pipeline];
}

- (void)movePollDidComplete:(ZDCPollContext *)pollContext withStatus:(NSDictionary *)pollStatus
{
	DDLogAutoTrace();
	
	ZDCTaskContext *context = pollContext.taskContext;
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	/**
	 * status dictionary format:
	 * {
	 *   "status": <http style status code>
	 *   "ext": {
	 *     "code": <4th-a specific error code>,
	 *     "msg" : <human readable string>
	 *   }
	 *   "info": {
	 *     "fileID": <string>,
	 *     "eTag": <string>,
	 *     "ts": <integer>
	 *   }
	 * }
	**/
	
	NSInteger statusCode = [self statusCodeFromPollStatus:pollStatus];
	
	/**
	 * Known possibilities for:
	 * - move
	 *
	 * 200 (OK)
	 *
	 * 400 (Bad request)
	 *   - unknown_user_owner
	 *   - unknown_user_caller
	 *   - staging_path_invalid
	 *   - staging_path_src_matches_dst
	 *   - staging_file_invalid_json
	 *   - staging_file_invalid_content
	 *   - staging_file_too_big
	 *
	 * 401 (Unauthorized)
	 *   - unauthorized_missing_src_write_permission
	 *   - unauthorized_missing_dst_write_permission
	 *   - unauthorized_missing_share_permission
	 *
	 * 404 (Not found)
	 *   - precondition_src_unavailable
	 *   - precondition_dst_unavailable
	 *
	 * 409 (Conflict)
	 *   - staging_file_disappeared
	 *   - staging_file_modified
	 *
	 * 412 (Precondition failed)
	 *   - precondition_src_eTag_mismatch
	 *   - precondition_dst_eTag_mismatch
	 *
	 * 500 (Server error)
	 *   - internal_missing_perms_file
	**/
	
	if (statusCode != 200)
	{
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		NSInteger extCode = 0;
		NSString *extMsg = nil;
		[self getExtCode:&extCode msg:&extMsg fromPollStatus:pollStatus];
		
		DDLogInfo(@"Conflict: %ld: %@", (long)extCode, extMsg);
		
		// Decide what to do
		
		BOOL shouldRestartFromScratch = NO;
		BOOL shouldAbort = NO;
		
		if (extCode == ZDCErrCode_staging_file_disappeared ||
		    extCode == ZDCErrCode_staging_file_modified     )
		{
			// These errors are extremely unlikely,
			// but may occur if somebody is trying to trick our server.
			
			NSUInteger successiveFailCount = [operation.ephemeralInfo s4_didFailWithExtStatusCode:@(extCode)];
			DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
			
			if (successiveFailCount > 10)
			{
				// Give up
				
				shouldAbort = YES;
			}
			else
			{
				// We need to restart the upload from the beginning to combat the attacker.
				//
				// Note: Even though we're restarting the upload (going back to S3 upload),
				// we've incremented the s4_failCount. Thus if this loop continues,
				// we'll ultimately abort (to prevent an infinite loop).
				
				shouldRestartFromScratch = YES;
			}
		}
		else if (extCode == ZDCErrCode_staging_file_invalid_json    ||
		         extCode == ZDCErrCode_staging_file_invalid_content ||
		         extCode == ZDCErrCode_staging_file_too_big          )
		{
			// These are client-side errors (we're uploading a bad staging file).
			// We can't recover from these errors by doing a pull.
			
			shouldAbort = YES;
		}
		else
		{
			NSUInteger successiveFailCount = [operation.ephemeralInfo s4_didFailWithExtStatusCode:@(extCode)];
			DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
			if (successiveFailCount > 10)
			{
				// Infinite loop prevention.
		
				shouldAbort = YES;
			}
		}
		
		// Execute plan-of-action
		
		if (shouldAbort)
		{
			NSDictionary *errorInfo = @{
				@"system": @"S4PushManager",
				@"subsystem": @"PUT S4",
				@"extStatusCode": @(extCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		else
		{
			operation.ephemeralInfo.resolveByPulling = YES;
			
			YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
			
			NSTimeInterval delay = 60 * 10; // safety fallback
			NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
			NSString *ctx = NSStringFromClass([self class]);
			
			[pipeline setHoldDate:holdDate forOperationWithUUID:operation.uuid context:ctx];
			[pipeline setStatusAsPendingForOperationWithUUID:operation.uuid];
			
			[owner.pullManager pullRemoteChangesForLocalUserID:operation.localUserID zAppID:operation.zAppID];
			return;
		}
	}
	
	// Operation succeeded !
	
	NSString *cloudID = nil;
	NSString *eTag = nil;
	NSDate *lastModified = nil;
	
	NSDictionary *status_info = pollStatus[@"info"];
	if ([status_info isKindOfClass:[NSDictionary class]])
	{
		cloudID = status_info[@"fileID"];
		eTag    = status_info[@"eTag"];
		
		lastModified = [self dateFromJavascriptTimestamp:status_info[@"ts"]];
	}
	
	if (eTag == nil) {
		eTag = pollContext.eTag;
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Mark operation as complete
		
		NSString *extName = [self extNameForContext:context];
		
		[[transaction ext:extName] completeOperationWithUUID:context.operationUUID];
		
		// Fetch node
		
		ZDCNode *node = [transaction objectForKey:operation.nodeID inCollection:kZDCCollection_Nodes];
		if (node)
		{
			// Update node:
			//
			// - cloud_lastModified
			// - new fileID
			
			node = [node copy];
			
			if (cloudID && ![cloudID isEqualToString:node.cloudID])
			{
				node.cloudID = cloudID;
			}
			
			node.eTag_rcrd = eTag;
			if (lastModified) {
				node.lastModified_rcrd = lastModified;
			}
			
			[transaction setObject:node forKey:node.uuid inCollection:kZDCCollection_Nodes];
		}
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:YES];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark DeleteLeaf
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareDeleteLeafOperation:(ZDCCloudOperation *)operation forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_DeleteLeaf, @"Invalid operation type");
	
	// Create context
	
	ZDCTaskContext *context = [[ZDCTaskContext alloc] initWithOperation:operation];
	
	// Sanity checks
	
	if (operation.cloudLocator == nil
	 || operation.cloudLocator.region == AWSRegion_Invalid
	 || operation.cloudLocator.bucket == nil
	 || operation.cloudLocator.cloudPath == nil)
	{
		DDLogWarn(@"Skipping delete-leaf operation: invalid op.cloudLocator: %@", operation.cloudLocator);
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Set needed context information
	
	[[self roConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		context.eTag = nil; // we don't care, just so long as the fileID matches
		
		// Snapshot current pullState.
		// We use this during conflict resolution to determine if a pull had any effect.
		
		ZDCChangeList *pullInfo =
		  [transaction objectForKey:operation.localUserID inCollection:kZDCCollection_PullState];
		
		operation.ephemeralInfo.lastChangeToken = pullInfo.latestChangeID_local;
	}];
	
	if (operation.deletedCloudIDs.count == 0)
	{
		DDLogWarn(@"Skipping delete-leaf operation: unknown cloudID (original upload failed): %@",
		          operation.cloudLocator);
		
		[self skipOperationWithContext:context];
	}
	else
	{
		NSAssert(operation.deletedCloudIDs.count <= 1, @"Logic error");
		
		[self startDeleteLeafOperation:operation withContext:context];
	}
}

- (void)startDeleteLeafOperation:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_DeleteLeaf, @"Invalid operation type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                     completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self deleteLeafTaskDidComplete:nil inSession:nil withError:error context:context];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// Calculate staging path
		
		NSString *requestID = [self requestIDForOperation:operation];
		NSString *stagingPath = [self stagingPathForOperation:operation withContext:context];
		
		// Fire off request
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request putObject: stagingPath
		              inBucket: operation.cloudLocator.bucket
		                region: operation.cloudLocator.region
		      outUrlComponents: &urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session
		               payloadSig: context.sha256Hash];
	
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request zdcDescription]);
	#endif
		
		NSURLSessionTask *task = nil;
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's do NOT support dataTask's.
		// So we have to fake it by instead creating an uploadTask with an empty file.
		//
		// It's goofy, but this is the hoop that Apple is making us jump through.
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: [ZDCDirectoryManager emptyUploadFileURL]
		                             progress: nil
		                    completionHandler: nil];
		
	#else
		
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler: nil];
		
	#endif
		
		NSProgress *progress = [session uploadProgressForTask:task];
		context.progress = progress;
		if (progress) {
			[owner.progressManager setUploadProgress:progress forOperation:operation];
		}
		
		[self stashContext:context];
		[owner.networkTools addRecentRequestID:requestID forUser:context.localUserID];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self deleteLeafTaskDidComplete: task
			                      inSession: session.session
			                      withError: [self cancelledError]
			                        context: context];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)deleteLeafTaskDidComplete:(NSURLSessionTask *)task
                        inSession:(NSURLSession *)session
                        withError:(NSError *)error
                          context:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	
	NSURLResponse *response = task.response;
	
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	// Known status codes:
	//
	// 200 - Success : OK
	// 404 - Bucket not found (account has been deleted)
	//
	// NOTE: This is a response directly from AWS S3 - NOT from Storm4 server.
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	if (error)
	{
		// Request failed due to network error.
		// Not error from the server.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely, the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200)
	{
		// Request failed due to AWS S3 issue.
		// This is rather abnormal, and generally only occurs under specific conditions.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			NSDictionary *errorInfo = @{
				@"system": @"PushManager",
				@"subsystem": @"PUT S3",
				@"statusCode": @(statusCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		
		NSTimeInterval delay;
		
		if (statusCode == 401 || statusCode == 403 || statusCode == 404)
		{
			// - 401 is the traditional unauthorized response (but amazon doesn't appear to use it)
			// - 403 seems to be what amazon uses for auth failures
			// - 404 is what we get if the bucket has been deleted
			//
			// A 404 is likely our first indicator that our acount has been deleted.
			// Because the bucket gets deleted right away,
			// even though our authentication sticks around for a few hours.
			
			[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			
			// Use a longer delay here.
			// We want time to check on the status of our account.
			
			delay = 30; // seconds
		}
		else
		{
			DDLogWarn(@"Received unknown statusCode from S3: %ld", (long)statusCode);
			
			// The operation failed for some unknown reason.
			//
			// This may indicate that the server is overloaded,
			// and doing some kind of rate limiting.
			//
			// So we execute exponential backoff algorithm.
			
			delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		}
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	
	// Request succeeded !
	//
	// Start polling for staging response.
	
	[operation.ephemeralInfo s3_didSucceed];
	
	ZDCPollContext *pollContext = [[ZDCPollContext alloc] init];
	
	pollContext.taskContext = context;
	pollContext.eTag = [response eTag];
	
	[self startPollWithContext:pollContext pipeline:pipeline];
}

- (void)deleteLeafPollDidComplete:(ZDCPollContext *)pollContext withStatus:(NSDictionary *)pollStatus
{
	DDLogAutoTrace();
	
	ZDCTaskContext *context = pollContext.taskContext;
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	/**
	 * pollStatus dictionary format:
	 * {
	 *   "status": <http style status code>
	 *   "ext": {
	 *     "code": <4th-a specific error code>,
	 *     "msg" : <human readable string>
	 *   }
	 *   "info": {
	 *     "fileID": <string>,
	 *     "eTag": <string>,
	 *     "ts": <integer>
	 *   }
	 * }
	**/
	
	NSInteger statusCode = [self statusCodeFromPollStatus:pollStatus];
	
	/**
	 * Known possibilities for:
	 * - delete-leaf
	 *
	 * 200 (OK)
	 *
	 * 400 (Bad request)
	 *   - unknown_user_owner
	 *   - unknown_user_caller
	 *   - staging_path_invalid
	 *
	 * 401 (Unauthorized)
	 *   - unauthorized_missing_dst_write_permission
	 *
	 * 404 (Not found)
	 *   - precondition_dst_unavailable
	 *
	 * 412 (Precondition failed)
	 *   - precondition_dst_eTag_mismatch
	 *   - precondition_not_orphan
	**/
	
	if (statusCode != 200)
	{
		// For a 400 result:
		//
		//   Our request was bad ?!?
		//   This likely indicates some kind of programming error.
		//   Nothing we can do here (at runtime) except skip the operation.
		//
		// 401 : Permissions problem.
		//       This should mean non-recoverable (i.e. bad auth0_id)
		//
		// 403 : Forbidden.
		//       This is also a permissions problem, but may be recoverable by doing a pull.
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Operation succeeded !
	
	NSDate *lastModified = nil;
	
	NSDictionary *status_info = pollStatus[@"info"];
	if ([status_info isKindOfClass:[NSDictionary class]])
	{
		lastModified = [self dateFromJavascriptTimestamp:status_info[@"ts"]];
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Mark operation as complete
		
		NSString *extName = [self extNameForContext:context];
		
		[[transaction ext:extName] completeOperationWithUUID:context.operationUUID];
		
		// Delete corresponding ZDCCloudNode's from database.
		
		ZDCCloudNode *cloudNode = nil;
		if (operation.cloudNodeID)
		{
			cloudNode = [transaction objectForKey:operation.cloudNodeID inCollection:kZDCCollection_CloudNodes];
		}
		if (!cloudNode)
		{
			cloudNode =
			  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: operation.cloudLocator.cloudPath
			                                                            bucket: operation.cloudLocator.bucket
			                                                            region: operation.cloudLocator.region
			                                                       localUserID: operation.localUserID
		   	                                                    transaction: transaction];
		}
		
		if (cloudNode)
		{
			NSMutableArray *cloudNodeIDs = [NSMutableArray arrayWithCapacity:1];
			[cloudNodeIDs addObject:cloudNode.uuid];
			
			[[ZDCCloudNodeManager sharedInstance] recursiveEnumerateCloudNodesWithParent: cloudNode
			                                                                 transaction: transaction
			                                                                  usingBlock:
			^(ZDCCloudNode *cloudNode, BOOL *stop)
			{
				[cloudNodeIDs addObject:cloudNode.uuid];
			}];
			
			[transaction removeObjectsForKeys:cloudNodeIDs inCollection:kZDCCollection_CloudNodes];
		}
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:YES];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark DeleteNode
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareDeleteNodeOperation:(ZDCCloudOperation *)operation
                       forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_DeleteNode, @"Invalid operation type");
	
	// Create context with boilerplate values
	
	ZDCTaskContext *context = [[ZDCTaskContext alloc] initWithOperation:operation];
	
	// Sanity checks
	
	if (operation.cloudLocator == nil
	 || operation.cloudLocator.region == AWSRegion_Invalid
	 || operation.cloudLocator.bucket == nil
	 || operation.cloudLocator.cloudPath == nil)
	{
		DDLogWarn(@"Skipping delete-node operation: invalid op.cloudLocator: %@", operation.cloudLocator);
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Set needed context information
	
	[[self roConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Snapshot current pullState.
		// We use this during conflict resolution to determine if a pull had any effect.
		
		ZDCChangeList *pullInfo =
		  [transaction objectForKey:operation.localUserID inCollection:kZDCCollection_PullState];
		
		operation.ephemeralInfo.lastChangeToken = pullInfo.latestChangeID_local;
	}];
	
	// The file content should already be in the operation
	
	NSData *fileData = operation.deleteNodeJSON;
	
	if (fileData)
	{
		context.sha256Hash = [AWSPayload signatureForPayload:fileData];
		
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's don't support data tasks !
		//
		// So we write the data to a temporary location on disk, in order to use a file task.
		
		NSString *fileName = [operation.uuid UUIDString];
		
		NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
		NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:fileName isDirectory:NO];
		
		NSError *error = nil;
		[fileData writeToURL:tempFileURL options:0 error:&error];
		
		if (error)
		{
			DDLogError(@"Error writing operation.data (%@): %@", tempFileURL.path, error);
		}
		
		context.uploadFileURL = tempFileURL;
		context.deleteUploadFileURL = YES;
		
		[self startDeleteNodeOperation:operation withContext:context];
	
	#else // macOS
		
		context.uploadData = fileData;
		
		[self startDeleteNodeOperation:operation withContext:context];
		
	#endif
	}
	else
	{
		DDLogWarn(@"Missing operation data: %@", operation.cloudLocator.cloudPath);
		
		[self skipOperationWithContext:context];
	}
}

- (void)startDeleteNodeOperation:(ZDCCloudOperation *)operation withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_DeleteNode, @"Invalid operation type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self deleteNodeTaskDidComplete:nil inSession:nil withError:error context:context];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// Calculate staging path
		
		NSString *requestID = [self requestIDForOperation:operation];
		NSString *stagingPath = [self stagingPathForOperation:operation withContext:context];
		
		// Fire off request
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request putObject: stagingPath
		              inBucket: operation.cloudLocator.bucket
		                region: operation.cloudLocator.region
		      outUrlComponents: &urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session
		               payloadSig: context.sha256Hash];
	
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request zdcDescription]);
	#endif
		
		NSURLSessionUploadTask *task = nil;
	#if TARGET_OS_IPHONE
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: context.uploadFileURL
		                             progress: nil
		                    completionHandler: nil];
		
	#else // macOS
		
		task = [session uploadTaskWithRequest: request
		                             fromData: context.uploadData
		                             progress: nil
		                    completionHandler: nil];
		
	#endif
		
		NSProgress *progress = [session uploadProgressForTask:task];
		context.progress = progress;
		if (progress) {
			[owner.progressManager setUploadProgress:progress forOperation:operation];
		}
		
		[self stashContext:context];
		[owner.networkTools addRecentRequestID:requestID forUser:context.localUserID];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self deleteNodeTaskDidComplete: task
			                      inSession: session.session
			                      withError: [self cancelledError]
			                        context: context];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)deleteNodeTaskDidComplete:(NSURLSessionTask *)task
                        inSession:(NSURLSession *)session
                        withError:(NSError *)error
                          context:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	
	[self unstashContext:context];
	
	NSURLResponse *response = task.response;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	// Known status codes:
	//
	// 200 - Success : OK
	// 404 - Bucket not found (account has been deleted)
	//
	// NOTE: This is a response directly from AWS S3 - NOT from Storm4 server.
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	if (error)
	{
		// Request failed due to network error.
		// Not error from the server.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely, the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200)
	{
		// Request failed due to AWS S3 issue.
		// This is rather abnormal, and generally only occurs under specific conditions.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			NSDictionary *errorInfo = @{
				@"system": @"PushManager",
				@"subsystem": @"PUT S3",
				@"statusCode": @(statusCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		
		NSTimeInterval delay;
		
		if (statusCode == 401 || statusCode == 403 || statusCode == 404)
		{
			// - 401 is the traditional unauthorized response (but amazon doesn't appear to use it)
			// - 403 seems to be what amazon uses for auth failures
			// - 404 is what we get if the bucket has been deleted
			//
			// A 404 is likely our first indicator that our acount has been deleted.
			// Because the bucket gets deleted right away,
			// even though our authentication sticks around for a few hours.
			
			[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			
			// Use a longer delay here.
			// We want time to check on the status of our account.
			
			delay = 30; // seconds
		}
		else
		{
			DDLogWarn(@"Received unknown statusCode from S3: %ld", (long)statusCode);
			
			// The operation failed for some unknown reason.
			//
			// This may indicate that the server is overloaded,
			// and doing some kind of rate limiting.
			//
			// So we execute exponential backoff algorithm.
			
			delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		}
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	
	// Request succeeded !
	//
	// Start polling for staging response.
	
	[operation.ephemeralInfo s3_didSucceed];
	
	ZDCPollContext *pollContext = [[ZDCPollContext alloc] init];
	
	pollContext.taskContext = context;
	pollContext.eTag = [response eTag];
	
	[self startPollWithContext:pollContext pipeline:pipeline];
}

- (void)deleteNodePollDidComplete:(ZDCPollContext *)pollContext withStatus:(NSDictionary *)pollStatus
{
	DDLogAutoTrace();
	
	ZDCTaskContext *context = pollContext.taskContext;
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	/**
	 * pollStatus dictionary format:
	 * {
	 *   "status": <http style status code>
	 *   "ext": {
	 *     "code": <4th-a specific error code>,
	 *     "msg" : <human readable string>
	 *   }
	 *   "info": {
	 *     "ts": <integer>
	 *   }
	 * }
	**/
	
	NSInteger statusCode = [self statusCodeFromPollStatus:pollStatus];
	
	/**
	 * Known possibilities for:
	 * - delete-node
	 *
	 * 200 (OK)
	 *
	 * 205 (Reset content)
	 *
	 * 400 (Bad request)
	 *   - unknown_user_owner
	 *   - unknown_user_caller
	 *   - staging_path_invalid
	 *   - staging_file_invalid_json
	 *   - staging_file_invalid_content
	 *
	 * 401 (Unauthorized)
	 *   - unauthorized_missing_dst_write_permission
	 *
	 * 404 (Not found)
	 *   - precondition_dst_unavailable
	 *
	 * 412 (Precondition failed)
	 *   - precondition_dst_eTag_mismatch
	 *   - precondition_not_orphan
	**/
	
	// For a 205 result:
	//
	//   The server could only delete a portion of the node hierarchy.
	//   This is because other nodes were inserted that we didn't know about.
	//   So we just need to do a full pull, and grab the new content.
	//
	// For a 404 result:
	//
	//   One of the following occurred:
	//   - the server couldn't delete the file because its parent has been deleted
	//   - the server couldn't delete the file because it doesn't exist
	//
	//   Either of these can be considered "success" for this delete operation.
	
	if (statusCode != 200 &&
	    statusCode != 205 &&
	    statusCode != 404  )
	{
		// For a 400 result:
		//
		//   Our request was bad ?!?
		//   This likely indicates some kind of programming error.
		//   Nothing we can do here (at runtime) except skip the operation.
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Operation succeeded !
	
	if (statusCode == 205)
	{
		// The server could only delete a portion of the node hierarchy.
		// This is because other nodes were inserted that we didn't know about.
		// So we need to do a full pull, and grab the new content.
		//
		// PartialDelete: Step 1 of 2:
		
		ZDCCloud *ext = [owner.databaseManager cloudExtForUser:context.localUserID app:context.zAppID];
		
		[ext suspend];
		[self incrementSuspendCountForLocalUserID:context.localUserID zAppID:context.zAppID];
	}
	
	NSDate *lastModified = nil;
	
	NSDictionary *status_info = pollStatus[@"info"];
	if ([status_info isKindOfClass:[NSDictionary class]])
	{
		lastModified = [self dateFromJavascriptTimestamp:status_info[@"ts"]];
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Mark operation as complete
		
		NSString *extName = [self extNameForContext:context];
		
		[[transaction ext:extName] completeOperationWithUUID:context.operationUUID];
		
		// Delete corresponding ZDCCloudNode's from database.
		
		ZDCCloudNode *cloudNode = nil;
		if (operation.cloudNodeID)
		{
			cloudNode = [transaction objectForKey:operation.cloudNodeID inCollection:kZDCCollection_CloudNodes];
		}
		if (!cloudNode)
		{
			cloudNode =
			  [[ZDCCloudNodeManager sharedInstance] findCloudNodeWithCloudPath: operation.cloudLocator.cloudPath
			                                                            bucket: operation.cloudLocator.bucket
			                                                            region: operation.cloudLocator.region
			                                                       localUserID: operation.localUserID
		   	                                                    transaction: transaction];
		}
		
		if (cloudNode)
		{
			NSMutableArray *cloudNodeIDs = [NSMutableArray array];
			[cloudNodeIDs addObject:cloudNode.uuid];
			
			[[ZDCCloudNodeManager sharedInstance] recursiveEnumerateCloudNodesWithParent: cloudNode
			                                                                 transaction: transaction
			                                                                  usingBlock:
			^(ZDCCloudNode *cloudNode, BOOL *stop)
			{
				[cloudNodeIDs addObject:cloudNode.uuid];
			}];
			
			[transaction removeObjectsForKeys:cloudNodeIDs inCollection:kZDCCollection_CloudNodes];
		}
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:YES];
		
		if (statusCode == 205)
		{
			// The server could only delete a portion of the node hierarchy.
			// This is because other nodes were inserted that we didn't know about.
			// So we need to do a full pull, and grab the new content.
			
			// PartialDelete: Step 2 of 2:
			[self forceFullPullForLocalUserID:context.localUserID zAppID:context.zAppID];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Poll
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startPollWithContext:(ZDCPollContext *)pollContext pipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSParameterAssert(pollContext != nil);
	NSParameterAssert(pipeline != nil);
	
	ZDCTaskContext *context = pollContext.taskContext;
	
	// Associate the pollContext with the operation.
	// This lets us know to keep trying to the poll operation, instead of the staging operation.
	
	ZDCCloudOperation *operation = (ZDCCloudOperation *)[pipeline operationWithUUID:context.operationUUID];
	operation.ephemeralInfo.pollContext = pollContext;
	
	// Edge case check:
	// If the operation was deleted (unceremoniously by rogue code) then the operation could be nil here.
	// We need to guard against this, as it would cause a crash in the code below.
	
	if (operation == nil)
	{
		[self skipOperationWithContext:context];
		return;
	}
	
	// Start the polling process.
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self pollDidComplete:nil inSession:nil withError:error context:pollContext responseObject:nil];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
		
		AWSRegion region = operation.cloudLocator.region;
		NSString *stage = userInfo.stage;
		if (!stage)
		{
		#ifdef AWS_STAGE // See PrefixHeader.pch
			stage = AWS_STAGE;
		#else
			stage = @"prod";
		#endif
		}
		
		NSString *path = [NSString stringWithFormat:@"/poll-request/%@", [self requestIDForOperation:operation]];
		
		NSURLComponents *urlComponents = [owner.webManager apiGatewayForRegion:region stage:stage path:path];
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];
		request.HTTPMethod = @"GET";
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's don't really support data tasks.
		//
		// So we have to download the tiny response to a file instead.
		
		NSURLSessionDownloadTask *task =
		  [session downloadTaskWithRequest: request
		                          progress: nil
		                       destination: nil
							  completionHandler: nil];
		
	#else
		
		__block NSURLSessionDataTask *task = nil;
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			[self pollDidComplete: task
			            inSession: session.session
			            withError: error
			              context: pollContext
			       responseObject: responseObject];
		}];
		
	#endif
		
		[self stashContext:pollContext];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self pollDidComplete: task
			            inSession: session.session
			            withError: [self cancelledError]
			              context: pollContext
			       responseObject: nil];
		}
		else
		{
		#if TARGET_OS_IPHONE
			[owner.sessionManager associateContext:pollContext withTask:task inSession:session.session];
		#else
			// When SessionManager gets called for the completion of a dataTask,
			// it's not given the `responseObject`, which we need in this case.
			// So we're handling the completion manually.
		#endif
			
			[task resume];
		}
	}];
}

- (void)pollDidComplete:(NSURLSessionTask *)task
              inSession:(NSURLSession *)session
              withError:(nullable NSError *)error
                context:(ZDCPollContext *)pollContext
         responseObject:(id)responseObject
{
	DDLogAutoTrace();
	
	[self unstashContext:pollContext];
	
	NSURLResponse *response = task.response;
	ZDCTaskContext *context = pollContext.taskContext;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	NSInteger httpStatusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	// Known status codes:
	//
	// 200 - Success : underlying status was fetched from redis
	
	if (error || httpStatusCode != 200)
	{
		NSTimeInterval delay;
		
		if (error)
		{
			// Request failed due to network error.
			//
			// Most likely, the pipeline has already been suspended.
			// This is courtesy of the AppDelegate, which does this when Reachability goes down.
			// And the pipeline will be automatically resumed once we reconnect to the Internet.
			//
			// So we can simply hand the operation back to the pipeline.
			// To be extra cautious (thread timing considerations), we do so after a short delay.
			
			delay = 2.0;
		}
		else
		{
			// Request failed due to unknown server error.
			//
			// We expect the server to return some kind of status to us within the JSON response.
			// Even if the server doesn't know about the request, it would return a 200 response,
			// with a JSON payload that would indicate as much.
			
			NSInteger successiveFailCount = [operation.ephemeralInfo polling_didFail];
			
			delay = [self pollingBackoffForFailCount:successiveFailCount];
		}
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	
	NSDictionary *stagingStatus = nil;
	NSInteger stagingStatusCode = 0;
	
	if ([responseObject isKindOfClass:[NSDictionary class]])
	{
		stagingStatus = (NSDictionary *)responseObject;
		
		id value = stagingStatus[@"status"];
		
		if ([value isKindOfClass:[NSNumber class]])
			stagingStatusCode = [(NSNumber *)value integerValue];
		else if ([value isKindOfClass:[NSString class]])
			stagingStatusCode = [(NSString *)value integerValue];
	}
	
	if (stagingStatusCode == 0)
	{
		// The server hasn't processed the staging file yet.
		
		NSUInteger pollFailCount_total = [operation.ephemeralInfo polling_didFail];
		
		// The pollFailCount is never reset !
		//
		// So if the server keeps crashing on the same file,
		// then the pollFailCount will just keep getting bigger and bigger.
		//
		// We need to watch out for this,
		// because if when we invoke `startTouchWithContext:` there's no delay.
		//
		// In the past this bug meant that we would execute exponential delay...
		// until the pollFailCount reached X.
		// And then we would just send touch commands to the server as fast as possible.
		
		NSUInteger pollingModulus = [self pollingModulus];
		
		BOOL pollFailCount_isLoop;
		NSUInteger pollFailCount_modulus;
		
		if (pollFailCount_total < pollingModulus)
		{
			pollFailCount_isLoop = NO;
			pollFailCount_modulus = pollFailCount_total;
			
			DDLogInfo(@"pollFailCount: %lu", (unsigned long)pollFailCount_total);
		}
		else
		{
			pollFailCount_isLoop = YES;
			pollFailCount_modulus = pollFailCount_total % pollingModulus;
			
			DDLogInfo(@"pollFailCount: %lu => %lu",
			          (unsigned long)pollFailCount_total,
			          (unsigned long)pollFailCount_modulus);
		}
		
		if (!pollFailCount_isLoop || pollFailCount_modulus != 0)
		{
			// Keep polling...
			//
			// Note: Even though we use the modulus technique to continually push a new `touch` command to the server,
			// we continue to force longer delays for polling. If the server is crashing, then there's no reason to
			// decrease our wait time.
			
			NSTimeInterval delay = [self pollingBackoffForFailCount:pollFailCount_total]; // <- Yup (see comment above)
			NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
			NSString *ctx = NSStringFromClass([self class]);
			
			[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
			[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
			return;
		}
		else
		{
			// The server may have "dropped" the staging/touch file.
			// This could happen if the redis server was restarted.
			// Or it could be a bug in the server.
			//
			// Either way, our solution is to issue a "touch" request for our uploaded staging file.
			
			ZDCTouchContext *touchContext = [[ZDCTouchContext alloc] init];
			touchContext.pollContext = pollContext;
			
			[self startTouchWithContext:touchContext pipeline:pipeline];
			return;
		}
	}
	
	// We got a non-zero response from the poll.
	// Which means we're done polling !
	
	[operation.ephemeralInfo polling_didSucceed];
	
	if (![pollContext atomicMarkCompleted])
	{
		// Already processed (poll request vs push notification)
		return;
	}
	
	operation.ephemeralInfo.pollContext = nil;
	
	switch(operation.type)
	{
		case ZDCCloudOperationType_Put:
		{
			[self putPollDidComplete:pollContext withStatus:stagingStatus];
			break;
		}
		case ZDCCloudOperationType_Move:
		{
			[self movePollDidComplete:pollContext withStatus:stagingStatus];
			break;
		}
		case ZDCCloudOperationType_DeleteLeaf:
		{
			[self deleteLeafPollDidComplete:pollContext withStatus:stagingStatus];
			break;
		}
		case ZDCCloudOperationType_DeleteNode:
		{
			[self deleteNodePollDidComplete:pollContext withStatus:stagingStatus];
			break;
		}
		case ZDCCloudOperationType_CopyLeaf:
		{
		//	[self copyLeafPollDidComplete:pollContext withStatus:stagingStatus];
			break;
		}
		default :
		{
			DDLogWarn(@"Unhandled poll response !");
			break;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Touch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startTouchWithContext:(ZDCTouchContext *)touchContext pipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSParameterAssert(touchContext != nil);
	NSParameterAssert(pipeline != nil);
	
	ZDCTaskContext *context = touchContext.pollContext.taskContext;
	
	// Associate the pollContext with the operation.
	// This lets us know to keep trying to the poll operation, instead of the staging operation.
	
	ZDCCloudOperation *operation = (ZDCCloudOperation *)[pipeline operationWithUUID:context.operationUUID];
	operation.ephemeralInfo.touchContext = touchContext;
	
	// Edge case check:
	// If the operation was deleted (unceremoniously by rogue code) then the operation could be nil here.
	// We need to guard against this, as it would cause a crash in the code below.
	
	if (operation == nil)
	{
		[self skipOperationWithContext:context];
		return;
	}
	
	// Start the polling process.
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self touchDidComplete:nil inSession:nil withError:error context:touchContext];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// Calculate staging path
		
		BOOL isMultipart = (operation.multipartInfo != nil);
		
		NSString *stagingPath =
		  [self stagingPathForOperation: operation
		                    withContext: context
		                      multipart: isMultipart
		                          touch: YES];
		
		// Fire off request
		
		NSURLComponents *urlComponents = nil;
		NSMutableURLRequest *request =
		  [S3Request putObject: stagingPath
		              inBucket: operation.cloudLocator.bucket
		                region: operation.cloudLocator.region
		      outUrlComponents: &urlComponents];
		
		[AWSSignature signRequest: request
		               withRegion: operation.cloudLocator.region
		                  service: AWSService_S3
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session];
		
	#if DEBUG && robbie_hanson
		DDLogDonut(@"%@", [request s4Description]);
	#endif
		
		NSURLSessionTask *task = nil;
	#if TARGET_OS_IPHONE
		
		// Background NSURLSession's do NOT support dataTask's.
		// So we have to fake it by instead creating an uploadTask with an empty file.
		//
		// It's goofy, but this is the hoop that Apple is making us jump through.
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: [ZDCDirectoryManager emptyUploadFileURL]
		                             progress: nil
		                    completionHandler: nil];
		
	#else
		
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler: nil];
		
	#endif
		
		[self stashContext:touchContext];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self touchDidComplete: task
			             inSession: session.session
			             withError: [self cancelledError]
			               context: touchContext];
		}
		else
		{
			[owner.sessionManager associateContext:touchContext withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)touchDidComplete:(NSURLSessionTask *)task
               inSession:(NSURLSession *)session
               withError:(NSError *)error
                 context:(ZDCTouchContext *)touchContext
{
	DDLogAutoTrace();
	
	[self unstashContext:touchContext];
	
	ZDCTaskContext *context = touchContext.pollContext.taskContext;
	NSURLResponse *response = task.response;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	// Known status codes:
	//
	// 200 - Success
	
	if (error)
	{
		// Request failed due to network error.
		// Not error from the server.
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely, the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200)
	{
		// Request failed due to AWS S3 issue.
		// This is rather abnormal, and generally only occurs under specific conditions.
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			NSDictionary *errorInfo = @{
				@"system": @"PushManager",
				@"subsystem": @"PUT S3",
				@"statusCode": @(statusCode)
			};
			
			[self failOperationWithContext:context errorInfo:errorInfo stopSyncingNode:YES];
			return;
		}
		
		NSTimeInterval delay;
		
		if (statusCode == 401 || statusCode == 403 || statusCode == 404)
		{
			// - 401 is the traditional unauthorized response (but amazon doesn't appear to use it)
			// - 403 seems to be what amazon uses for auth failures
			// - 404 is what we get if the bucket has been deleted
			//
			// A 404 is likely our first indicator that our acount has been deleted.
			// Because the bucket gets deleted right away,
			// even though our authentication sticks around for a few hours.
			
			[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			
			// Use a longer delay here.
			// We want time to check on the status of our account.
			
			delay = 30; // seconds
		}
		else
		{
			DDLogWarn(@"Received unknown statusCode from S3: %ld", (long)statusCode);
			
			// The operation failed for some unknown reason.
			//
			// This may indicate that the server is overloaded,
			// and doing some kind of rate limiting.
			//
			// So we execute exponential backoff algorithm.
			
			delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		}
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}

	// Request succeeded !
	//
	// Go back to polling for staging response.
	
	[operation.ephemeralInfo s3_didSucceed];
	operation.ephemeralInfo.touchContext = nil;
	
	[self startPollWithContext:touchContext.pollContext pipeline:pipeline];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Avatar
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareAvatarOperation:(ZDCCloudOperation *)operation
                   forPipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Avatar, @"Invalid operation type");
	
	// Create context with boilerplate values
	
	ZDCTaskContext *context = [[ZDCTaskContext alloc] initWithOperation:operation];
	
	// Sanity checks
	
	if (operation.avatar_auth0ID == nil)
	{
		DDLogWarn(@"Skipping AVATAR operation: nil auth0ID");
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Loop through the queued operations in order to achieve the following:
	//
	// #1: We're going to be uploading the most recently set user avatar.
	//     But there may be a bunch of queued operations.
	//     If so, we can safely delete all those matching operations when this one finishes.
	//
	// #2: Each matching operation has <oldETag, newETag> tuple.
	//     From this we can determine what the client thinks is the oldETag currently on the server.
	//     This value needs to be correct, or it will be rejected by the server.
	
	__block NSMutableSet<NSUUID *> *matchingOpUUIDs = nil;
	__block NSString *eTag_cloud    = operation.avatar_oldETag;
	__block NSString *eTag_previous = operation.avatar_oldETag;
	__block NSString *eTag_current  = operation.avatar_newETag;
	
	[pipeline enumerateOperationsUsingBlock:
		^(YapDatabaseCloudCoreOperation *opGeneric, NSUInteger graphIdx, BOOL *stop)
	{
		__unsafe_unretained ZDCCloudOperation *op = (ZDCCloudOperation *)opGeneric;
		
		if (op.type == ZDCCloudOperationType_Avatar &&
		    [op.avatar_auth0ID isEqual:operation.avatar_auth0ID] &&
		   ![op.uuid isEqual:operation.uuid])
		{
			if (!matchingOpUUIDs) {
				matchingOpUUIDs = [NSMutableSet set];
			}
			
			[matchingOpUUIDs addObject:op.uuid];
			
			if (YDB_IsEqualOrBothNil(op.avatar_oldETag, eTag_current))
			{
				// Found a continuous change:
				// A => B => C
				
				eTag_previous = eTag_current;
				eTag_current = op.avatar_newETag;
			}
			else
			{
				// Found a breaking change:
				// A => F! => G
				
				eTag_cloud    = op.avatar_oldETag;
				eTag_previous = op.avatar_oldETag;
				eTag_current  = op.avatar_newETag;
			}
		}
	}];
	
	context.matchingOpUUIDs = matchingOpUUIDs;
	context.eTag = eTag_cloud;
	
	void (^continueWithAvatarData)(NSData *_Nullable) =
	^(NSData *_Nullable avatarData){ @autoreleasepool {
		
		if (avatarData == nil)
		{
			[self startAvatarOperation:operation withContext:context];
		}
		else
		{
			context.sha256Hash = [AWSPayload signatureForPayload:avatarData];
			
			// Convert avatarData into JSON request
			
			NSString *contentType = [self mimeTypeByGuessingFromData:avatarData];
			
			NSDictionary *jsonDict = @{
				@"avatar"       : [avatarData base64EncodedStringWithOptions:0],
				@"content-type" : (contentType ?: @"image/png")
			};
			
			NSError *jsonError = nil;
			NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&jsonError];
			
			if (jsonError)
			{
				// Non-recoverable error
				[self skipOperationWithContext:context];
				return;
			}
		
			if (jsonData.length > (1024 * 1024 * 10))
			{
				DDLogError(@"Avatar image is too big !");
				
				// Non-recoverable error
				[self skipOperationWithContext:context];
				return;
			}
		
		#if TARGET_OS_IPHONE
	
			// Background NSURLSession's don't support data tasks !
			//
			// So we write the data to a temporary location on disk, in order to use a file task.
	
			NSString *fileName = [operation.uuid UUIDString];
	
			NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
			NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:fileName isDirectory:NO];
	
			NSError *error = nil;
			[jsonData writeToURL:tempFileURL options:0 error:&error];
		
			if (error)
			{
				DDLogError(@"Error writing operation.data (%@): %@", tempFileURL.path, error);
			}
		
			context.uploadFileURL = tempFileURL;
			context.deleteUploadFileURL = YES;
		
			[self startAvatarOperation:operation withContext:context];
		
		#else // macOS
	
			context.uploadData = jsonData;
	
			[self startAvatarOperation:operation withContext:context];
	
		#endif
		}
	}};
	
	__block ZDCLocalUser *localUser = nil;
	[self.roConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		localUser = [transaction objectForKey:operation.localUserID inCollection:kZDCCollection_Users];
	}];
	
	ZDCCryptoFile *cryptoFile = nil;
	if (localUser.isLocal)
	{
		ZDCDiskExport *export =
		  [owner.diskManager userAvatar: localUser
		                     forAuth0ID: operation.avatar_auth0ID];
		
		cryptoFile = export.cryptoFile;
	}
	
	if (cryptoFile)
	{
		[ZDCFileConversion decryptCryptoFileIntoMemory: cryptoFile
		                               completionQueue: concurrentQueue
		                               completionBlock:^(NSData *cleartext, NSError *error)
		{
			continueWithAvatarData(cleartext);
		}];
	}
	else
	{
		continueWithAvatarData(nil);
	}
}

- (void)startAvatarOperation:(ZDCCloudOperation *)operation
                 withContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	NSAssert(operation.type == ZDCCloudOperationType_Avatar, @"Invalid operation type");
	
	[owner.awsCredentialsManager getAWSCredentialsForUser: context.localUserID
	                                      completionQueue: concurrentQueue
	                                      completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
	{
		if (error)
		{
			if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
			{
				// Auth0 is just rate limiting us.
				// Normal path will automatically execute exponential backoff.
			}
			else
			{
				// Auth0 is indicating our account may have been removed.
				[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
			}
			
			[self avatarTaskDidComplete:nil inSession:nil withError:error context:context];
			return;
		}
		
		ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:context.localUserID];
		ZDCSessionUserInfo *userInfo = sessionInfo.userInfo;
	#if TARGET_OS_IPHONE
		AFURLSessionManager *session = sessionInfo.backgroundSession;
	#else
		AFURLSessionManager *session = sessionInfo.session;
	#endif
		
		// Calculate staging path
		
		NSString *social_userID;
		
		NSArray *comps = [operation.avatar_auth0ID componentsSeparatedByString:@"|"];
		if (comps.count == 2)
		{
			// "<provider>|<userID>"
			
			social_userID = comps[1];
		}
		
		AWSRegion region = userInfo.region;
		NSString *stage = userInfo.stage;
		
		NSString *path = [NSString stringWithFormat:@"/users/avatar/%@", social_userID];
		
		NSURLComponents *urlComponents = [owner.webManager apiGatewayForRegion:region stage:stage path:path];
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[urlComponents URL]];

	#if TARGET_OS_IPHONE
		BOOL hasBody = (context.uploadFileURL != nil);
	#else
		BOOL hasBody = (context.uploadData != nil);
	#endif
		
		if (hasBody)
		{
			request.HTTPMethod = @"POST";
			[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
 		}
		else
		{
			request.HTTPMethod = @"DELETE";
		}

		if (context.eTag) {
			[request setValue:context.eTag forHTTPHeaderField:@"If-Match"];
		} else {
			[request setValue:@"*" forHTTPHeaderField:@"If-None-Match"];
		}
		
		[AWSSignature signRequest: request
		               withRegion: region
		                  service: AWSService_APIGateway
		              accessKeyID: auth.aws_accessKeyID
		                   secret: auth.aws_secret
		                  session: auth.aws_session
		               payloadSig: context.sha256Hash];
		
		NSURLSessionUploadTask *task = nil;
	#if TARGET_OS_IPHONE
		
		task = [session uploadTaskWithRequest: request
		                             fromFile: context.uploadFileURL
		                             progress: nil
		                    completionHandler: nil];
		
	#else // macOS
		
		task = [session uploadTaskWithRequest: request
		                             fromData: context.uploadData
		                             progress: nil
		                    completionHandler: nil];
	#endif
		
		NSProgress *progress = [session uploadProgressForTask:task];
		context.progress = progress;
		if (progress) {
			[owner.progressManager setUploadProgress:progress forOperation:operation];
		}
		
		[self stashContext:context];
		
		if (operation.ephemeralInfo.abortRequested)
		{
			operation.ephemeralInfo.abortRequested = NO;
			[self avatarTaskDidComplete: task
			                  inSession: session.session
			                  withError: [self cancelledError]
			                    context: context];
		}
		else
		{
			[owner.sessionManager associateContext:context withTask:task inSession:session.session];
			[task resume];
		}
	}];
}

- (void)avatarTaskDidComplete:(NSURLSessionTask *)task
                    inSession:(NSURLSession *)session
                    withError:(NSError *)error
                      context:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	
	[self unstashContext:context];
	
	NSURLResponse *response = task.response;
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForContext:context];
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	NSInteger statusCode = response.httpStatusCode;
	
	if (response && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	/**
	 * Known statusCode's:
	 *
	 * - 200 : OK
	 * - 400 : Bad request
	 * - 401 : Unauthorized
	 * - 404 : User not found
	 * - 409 : Conflict
	 * - 423 : Locked
	**/
	
	if (error)
	{
		// Request failed due to client-side error.
		// Not error from the server.
		//
		// This could be:
		// - network error (e.g. lost internet connection)
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// If this was a network error (due to loss of Internet connection),
		// then most likely the pipeline has already been suspended.
		// This is courtesy of the AppDelegate, which does this when Reachability goes down.
		// And the pipeline will be automatically resumed once we reconnect to the Internet.
		//
		// So we can simply hand the operation back to the pipeline.
		// To be extra cautious (thread timing considerations), we do so after a short delay.
		
		NSTimeInterval retryDelay = 2.0;
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:retryDelay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode == 423)
	{
		// Request failed due to the server being busy (unable to acquire lock).
		// This is rather abnormal, but can occur under heavy loads.
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
		
		// Increment the failCount for the operation, so we can do exponential backoff.
		
		NSUInteger successiveFailCount = [operation.ephemeralInfo s3_didFailWithStatusCode:@(statusCode)];
		DDLogInfo(@"successiveFailCount: %lu", (unsigned long)successiveFailCount);
		
		if (successiveFailCount > 10)
		{
			// Infinite loop prevention.
			
			[self skipOperationWithContext:context];
			return;
		}
		
		NSTimeInterval delay = [owner.networkTools exponentialBackoffForFailCount:successiveFailCount];
		
		NSDate *holdDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		NSString *ctx = NSStringFromClass([self class]);
		
		[pipeline setHoldDate:holdDate forOperationWithUUID:context.operationUUID context:ctx];
		[pipeline setStatusAsPendingForOperationWithUUID:context.operationUUID];
		return;
	}
	else if (statusCode != 200)
	{
		// This is an unrecoverable error
		
		[self skipOperationWithContext:context];
		return;
	}
	
	// Operation succeeded
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Mark operation as complete
		
		NSString *extName = [self extNameForContext:context];
		
		[[transaction ext:extName] completeOperationWithUUID:context.operationUUID];
		
		// Remove redundant operations (if needed)
		
		if (context.matchingOpUUIDs)
		{
			[[transaction ext:extName] skipOperationsPassingTest:
			 ^BOOL (YapDatabaseCloudCorePipeline *pipeline,
					  YapDatabaseCloudCoreOperation *op, NSUInteger graphIdx, BOOL *stop)
			{
				if ([context.matchingOpUUIDs containsObject:op.uuid])
				{
					return YES;
				}
				
				return NO;
			}];
		}
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:YES];
	}];
}

/**
 * Credit: https://stackoverflow.com/a/27679591/43522
 */
- (NSString *)mimeTypeByGuessingFromData:(NSData *)data
{
	char bytes[12] = {0};
	[data getBytes:&bytes length:12];
	
	const char bmp[2] = {'B', 'M'};
	const char gif[3] = {'G', 'I', 'F'};
	const char jpg[3] = {0xff, 0xd8, 0xff};
	const char psd[4] = {'8', 'B', 'P', 'S'};
	const char iff[4] = {'F', 'O', 'R', 'M'};
	const char webp[4] = {'R', 'I', 'F', 'F'};
	const char ico[4] = {0x00, 0x00, 0x01, 0x00};
	const char tif_ii[4] = {'I','I', 0x2A, 0x00};
	const char tif_mm[4] = {'M','M', 0x00, 0x2A};
	const char png[8] = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
	const char jp2[12] = {0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a};
	
	
	if (!memcmp(bytes, bmp, 2)) {
		return @"image/x-ms-bmp";
	} else if (!memcmp(bytes, gif, 3)) {
		return @"image/gif";
	} else if (!memcmp(bytes, jpg, 3)) {
		return @"image/jpeg";
	} else if (!memcmp(bytes, psd, 4)) {
		return @"image/psd";
	} else if (!memcmp(bytes, iff, 4)) {
		return @"image/iff";
	} else if (!memcmp(bytes, webp, 4)) {
		return @"image/webp";
	} else if (!memcmp(bytes, ico, 4)) {
		return @"image/vnd.microsoft.icon";
	} else if (!memcmp(bytes, tif_ii, 4) || !memcmp(bytes, tif_mm, 4)) {
		return @"image/tiff";
	} else if (!memcmp(bytes, png, 8)) {
		return @"image/png";
	} else if (!memcmp(bytes, jp2, 12)) {
		return @"image/jp2";
	}
	
	return @"application/octet-stream"; // default type
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Stream Tools
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)resolveAsyncNodeDataForOperation:(ZDCCloudOperation *)op
{
	ZDCCloudOperation_AsyncData *asyncData = op.ephemeralInfo.asyncData;
	NSParameterAssert(asyncData != nil);
	
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForOperation:op];
	NSDate *distantFuture = [NSDate distantFuture];
	
	NSUInteger pendingCount = 0;
	
	{ // 1 of 3
		
		ZDCData *nodeData = asyncData.nodeData;
		
		if (nodeData.promise)
		{
			pendingCount++;
			NSString *ctx = @"nodeData.promise";
			[pipeline setHoldDate:distantFuture forOperationWithUUID:op.uuid context:ctx];
	
			[nodeData.promise pushCompletionQueue: concurrentQueue
			                      completionBlock:^(ZDCData * _Nullable nodeData)
			{
				if (nodeData == nil) {
					nodeData = [[ZDCData alloc] initWithData:[NSData data]];
				}
	
				op.ephemeralInfo.asyncData.nodeData = nodeData;
				[pipeline setHoldDate:nil forOperationWithUUID:op.uuid context:ctx];
			}];
		}
	}
	
	{ // 2 of 3
		
		ZDCData *nodeMetadata = asyncData.nodeMetadata;
		
		if (nodeMetadata.cleartextFileURL || nodeMetadata.cryptoFile)
		{
			pendingCount++;
			NSString *ctx = nodeMetadata.cleartextFileURL
			  ? @"nodeMetadata.cleartextFileURL"
			  : @"nodeMetadata.cryptoFile";
			[pipeline setHoldDate:distantFuture forOperationWithUUID:op.uuid context:ctx];
	
			[self extractCleartextData: nodeMetadata
			           completionQueue: concurrentQueue
			           completionBlock:^(NSData *data, NSError *error)
			{
				if (data == nil) {
					data = [NSData data];
				}
				
				op.ephemeralInfo.asyncData.rawMetadata = data;
				op.ephemeralInfo.asyncData.nodeMetadata = nil;
				[pipeline setHoldDate:nil forOperationWithUUID:op.uuid context:ctx];
			}];
		}
		else if (nodeMetadata.promise)
		{
			pendingCount++;
			NSString *ctx = @"nodeMetadata.promise";
			[pipeline setHoldDate:distantFuture forOperationWithUUID:op.uuid context:ctx];
	
			[nodeMetadata.promise pushCompletionQueue: concurrentQueue
			                          completionBlock:^(ZDCData *nodeMetadata)
			{
				if (nodeMetadata == nil) {
					nodeMetadata = [[ZDCData alloc] initWithData:[NSData data]];
				}
	
				op.ephemeralInfo.asyncData.nodeMetadata = nodeMetadata;
				[pipeline setHoldDate:nil forOperationWithUUID:op.uuid context:ctx];
			}];
		}
	}
	
	{ // 3 of 3
		
		ZDCData *nodeThumbnail = asyncData.nodeThumbnail;
		
		if (nodeThumbnail.cleartextFileURL || nodeThumbnail.cryptoFile)
		{
			pendingCount++;
			NSString *ctx = nodeThumbnail.cleartextFileURL
			  ? @"nodeThumbnail.cleartextFileURL"
			  : @"nodeThumbnail.cryptoFile";
			[pipeline setHoldDate:distantFuture forOperationWithUUID:op.uuid context:ctx];
	
			[self extractCleartextData: nodeThumbnail
			           completionQueue: concurrentQueue
			           completionBlock:^(NSData *data, NSError *error)
			{
				if (data == nil) {
					data = [NSData data];
				}
	
				op.ephemeralInfo.asyncData.rawThumbnail = data;
				op.ephemeralInfo.asyncData.nodeThumbnail = nil;
				[pipeline setHoldDate:nil forOperationWithUUID:op.uuid context:ctx];
			}];
		}
		else if (nodeThumbnail.promise)
		{
			pendingCount++;
			NSString *ctx = @"nodeThumbnail.promise";
			[pipeline setHoldDate:distantFuture forOperationWithUUID:op.uuid context:ctx];
	
			[nodeThumbnail.promise pushCompletionQueue: concurrentQueue
			                           completionBlock:^(ZDCData *nodeThumbnail)
			{
				if (nodeThumbnail == nil) {
					nodeThumbnail = [[ZDCData alloc] initWithData:[NSData data]];
				}
	
				op.ephemeralInfo.asyncData.nodeThumbnail = nodeThumbnail;
				[pipeline setHoldDate:nil forOperationWithUUID:op.uuid context:ctx];
			}];
		}
	}
	
	NSAssert(pendingCount > 0, @"No async operations to resolve !");
}

- (void)extractCleartextData:(ZDCData *)nodeData
             completionQueue:(dispatch_queue_t)completionQueue
             completionBlock:(void (^)(NSData *_Nullable, NSError *_Nullable))completionBlock
{
	NSInputStream *inputStream = nil;
	NSOutputStream *outputStream = [NSOutputStream outputStreamToMemory];
	
	if (nodeData.cleartextFileURL)
	{
		inputStream = [NSInputStream inputStreamWithURL:nodeData.cleartextFileURL];
	}
	else if (nodeData.cryptoFile)
	{
		if (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
		{
			CacheFile2CleartextInputStream *stream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: nodeData.cryptoFile.fileURL
			                                                 encryptionKey: nodeData.cryptoFile.encryptionKey];
			
			stream.retainToken = nodeData.cryptoFile.retainToken;
			inputStream = stream;
		}
		else
		{
			CloudFile2CleartextInputStream *stream =
			  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: nodeData.cryptoFile.fileURL
			                                                 encryptionKey: nodeData.cryptoFile.encryptionKey];
			
			stream.retainToken = nodeData.cryptoFile.retainToken;
			inputStream = stream;
		}
	}
	else
	{
		NSAssert(NO, @"Invoked with invalid parameter");
	}
	
	[self pipeStreamFromInput: inputStream
	                 toOutput: outputStream
	          completionQueue: completionQueue
	          completionBlock:^(NSString *sha256Hash, NSError *error)
	{
		if (error) {
			completionBlock(nil, error);
		}
		else {
			NSData *data = [outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
			completionBlock(data, nil);
		}
	}];
}

/**
 * The delegate gave us a ZDCCryptoFile in CloudFile format.
 * So, if all the following are true, then we can upload directly from the file:
 *
 * - the cryptoFile.encryptionKey matches the node.encryptionKey
 * - the cryptoFile's metadata section matches the operation's metadata
 * - the cryptoFile's thumbnail section matches the operation's thumbnail
 *
 * We can save a bunch of energy if these conditions are true.
 * On macOS this mostly just means a bunch of decryption & re-encryption.
 * But on iOS it means we also get to skip re-writing the file to disk.
 */
- (void)compareMetadata:(nullable NSData *)inMetadata
              thumbnail:(nullable NSData *)inThumbnail
               toStream:(CloudFile2CleartextInputStream *)stream
        completionQueue:(dispatch_queue_t)completionQueue
        completionBlock:(void (^)(BOOL match, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSParameterAssert(stream != nil);
	NSParameterAssert(completionQueue != nil);
	NSParameterAssert(completionBlock != nil);
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		NSData *fileMetadata = nil;
		NSData *fileThumbnail = nil;
		NSError *error = nil;
		[CloudFile2CleartextInputStream decryptCloudFileStream: stream
		                                                header: nil
		                                           rawMetadata: &fileMetadata
		                                          rawThumbnail: &fileThumbnail
		                                                 error: &error];
		
		BOOL match = NO;
		if (!error)
		{
			NSData *opMetadata = inMetadata ?: [NSData data];
			NSData *opThumbnail = inThumbnail ?: [NSData data];
			
			if (fileMetadata == nil) fileMetadata = [NSData data];
			if (fileThumbnail == nil) fileThumbnail = [NSData data];
			
			match = ([opMetadata isEqualToData:fileMetadata])
			     && ([opThumbnail isEqualToData:fileThumbnail]);
		}
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(match, error);
		}});
	}});
}

/**
 * On iOS, we often have to write a file to disk, because we need to upload sing a background NSURLSession.
 * But background NSULRSession's on iOS don't support stream-based tasks - only file-based tasks.
 */
- (void)writeStreamToDisk:(NSInputStream *)inputStream
          completionQueue:(dispatch_queue_t)completionQueue
          completionBlock:(void (^)(NSURL *fileURL, NSString *sha256Hash, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	NSString *randomFileName = [[NSUUID UUID] UUIDString];
	
	NSURL *tempDirURL = [ZDCDirectoryManager tempDirectoryURL];
	NSURL *outFileURL = [tempDirURL URLByAppendingPathComponent:randomFileName isDirectory:NO];
	
	NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:outFileURL append:NO];
	
	[self pipeStreamFromInput: inputStream
	                 toOutput: outputStream
	          completionQueue: completionQueue
	          completionBlock:^(NSString *sha256Hash, NSError *error)
	{
		if (error)
			completionBlock(nil, nil, error);
		else
			completionBlock(outFileURL, sha256Hash, nil);
	}];
}

/**
 * This method will automatically open both streams for you.
 */
- (void)pipeStreamFromInput:(NSInputStream *)inputStream
                   toOutput:(NSOutputStream *)outputStream
            completionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSString *sha256Hash, NSError *error))completionBlock
{
	NSParameterAssert(inputStream != nil);
	NSParameterAssert(outputStream != nil);
	NSParameterAssert(completionQueue != nil);
	NSParameterAssert(completionBlock != nil);
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		NSString *sha256HashInLowercase = nil;
		NSError *error = nil;
		
		NSInteger totalBytesRead = 0;
		BOOL doneReading = NO;
		
		size_t bufferMallocSize = (1024 * 1024 * 1);
		void *buffer = malloc(bufferMallocSize);
		
		const int hashLength = CC_SHA256_DIGEST_LENGTH;
		uint8_t hashBytes[hashLength];
		NSData *hashData = nil;
		
		CC_SHA256_CTX ctx;
		CC_SHA256_Init(&ctx);
		
		[inputStream open];
		[outputStream open];
		
		error = inputStream.streamError;
		if (error) goto done;
		
		error = outputStream.streamError;
		if (error) goto done;
		
		do
		{
			NSInteger bytesRead = 0;
			NSUInteger loopBytesWritten = 0;
			
			// Read the next chunk
			
			bytesRead = [inputStream read:buffer maxLength:bufferMallocSize];
			
			if (bytesRead < 0)
			{
				// Error reading
				DDLogError(@"inputStream.error: %@", outputStream.streamError);
				
				error = inputStream.streamError;
				if (error == nil) {
					error = [self errorWithDescription:@"Error reading inputStream"];
				}
				
				goto done;
			}
			
			totalBytesRead += bytesRead;
			
			CC_SHA256_Update(&ctx, (const void *)buffer, (CC_LONG)bytesRead);
			
			while (loopBytesWritten < bytesRead)
			{
				NSInteger bytesWritten =
				  [outputStream write:(buffer + loopBytesWritten)
				            maxLength:(bytesRead - loopBytesWritten)];
				
				if (bytesWritten <= 0)
				{
					// Error writing
					DDLogError(@"outputStream.error: %@", outputStream.streamError);
					
					error = outputStream.streamError;
					if (error == nil) {
						error = [self errorWithDescription:@"Error reading inputStream"];
					}
					
					goto done;
				}
				else
				{
					// Update totals and continue
					
					loopBytesWritten += bytesWritten;
				}
			}
			
			doneReading = (bytesRead == 0);
			
		} while (!doneReading);
		
	done:
		
		CC_SHA256_Final(hashBytes, &ctx);
		
		hashData = [NSData dataWithBytesNoCopy:(void *)hashBytes length:hashLength freeWhenDone:NO];
		sha256HashInLowercase = [hashData lowercaseHexString];
		
		[inputStream close];
		[outputStream close];
		
		if (buffer) {
			free(buffer);
		}
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			
			if (error)
				completionBlock(nil, error);
			else
				completionBlock(sha256HashInLowercase, nil);
		}});
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Multipart Tools
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Checks to see if we need to use multipart for the given operation.
 */
- (BOOL)checkNeedsMultipart:(ZDCTaskContext *)context
                    forNode:(ZDCNode *)node
                   withData:(ZDCData *)nodeData
                   metadata:(nullable NSData *)rawMetadata
                  thumbnail:(nullable NSData *)rawThumbnail
{
	DDLogAutoTrace();
	
	uint64_t cloudFileSize = 0;
	Cleartext2CloudFileInputStream *cloudStream = nil;
	
	if (nodeData.data || nodeData.cleartextFileURL)
	{
		uint64_t clearFileSize = 0;
		
		if (nodeData.data)
		{
			clearFileSize = nodeData.data.length;
		}
		else
		{
			NSURL *fileURL = nodeData.cleartextFileURL;
			
			NSNumber *number = nil;
			if ([fileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
			{
				clearFileSize = [number unsignedLongLongValue];
			}
		}
		
		if ((clearFileSize + rawMetadata.length + rawThumbnail.length) >= multipart_minCloudFileSize)
		{
			// Looks like we want to use multipart.
			// Calculate the exact cloudFileSize.
			
			if (nodeData.data)
			{
				cloudStream =
				  [[Cleartext2CloudFileInputStream alloc] initWithCleartextData: nodeData.data
				                                                  encryptionKey: node.encryptionKey];
			}
			else
			{
				cloudStream =
				  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: nodeData.cleartextFileURL
				                                                     encryptionKey: node.encryptionKey];
			}
			
			cloudStream.rawMetadata = rawMetadata;
			cloudStream.rawThumbnail = rawThumbnail;
			
			[cloudStream open];
			
			cloudFileSize = [cloudStream.encryptedFileSize unsignedLongLongValue];
		}
	}
	else if (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile)
	{
		NSURL *fileURL = nodeData.cryptoFile.fileURL;
		uint64_t maxClearFileSize = 0;
		
		NSNumber *number = nil;
		if ([fileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			maxClearFileSize = [number unsignedLongLongValue];
		}
		
		if ((maxClearFileSize + rawMetadata.length + rawThumbnail.length) >= multipart_minCloudFileSize)
		{
			// Looks like we want to use multipart.
			// Calculate the exact cloudFileSize.
			
			CloudFile2CleartextInputStream *clearStream =
			  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: nodeData.cryptoFile.fileURL
			                                                 encryptionKey: nodeData.cryptoFile.encryptionKey];
			
			[clearStream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
			
			cloudStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
			                                                        encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = rawMetadata;
			cloudStream.rawThumbnail = rawThumbnail;
			
			[cloudStream open];
			
			cloudFileSize = [cloudStream.encryptedFileSize unsignedLongLongValue];
		}
	}
	else if (nodeData.cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
	{
		NSURL *fileURL = nodeData.cryptoFile.fileURL;
		uint64_t cacheFileSize = 0;
		
		NSNumber *number = nil;
		if ([fileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cacheFileSize = [number unsignedLongLongValue];
		}
		
		if ((cacheFileSize + rawMetadata.length + rawThumbnail.length) >= multipart_minCloudFileSize)
		{
			// Looks like we want to use multipart.
			// Calculate the exact cloudFileSize.
			
			CacheFile2CleartextInputStream *clearStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: fileURL
			                                                 encryptionKey: nodeData.cryptoFile.encryptionKey];
			
			cloudStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
			                                                        encryptionKey: node.encryptionKey];
			
			cloudStream.rawMetadata = rawMetadata;
			cloudStream.rawThumbnail = rawThumbnail;
			
			[cloudStream open];
			
			cloudFileSize = [cloudStream.encryptedFileSize unsignedLongLongValue];
		}
	}
	
	if (cloudFileSize < multipart_minCloudFileSize)
	{
		return NO;
	}
	
	// Calculate stagingPath
	//
	// This needs to remain constant for all related multipart operations.
	
	ZDCCloudOperation *operation = [self operationForContext:context];
	operation.ephemeralInfo.multipartData = nodeData;
	
	NSString *stagingPath =
	  [self stagingPathForOperation: operation
	                    withContext: context
	                      multipart: YES
	                          touch: NO];
	
	// Calculate chunkSize.
	// That is, how big should each part be in the multipart uploads.
	//
	// AWS has some restrictions here we need to be aware of.
	//
	// - each part (excluding the last) must be >= 5 MiB
	// - there can be at most 10,000 parts
	
	uint64_t chunkSize = multipart_minPartSize;
	
	NSUInteger partsCount = (NSUInteger)(cloudFileSize / chunkSize);
	if (cloudFileSize % chunkSize != 0) { partsCount++; }
	
	while (partsCount > 10000)
	{
		chunkSize += (1024 * 1024 * 1);
		
		partsCount = (NSUInteger)(cloudFileSize / chunkSize);
		if (cloudFileSize % chunkSize != 0) { partsCount++; }
	}
	
	// Pre-calculate checksums:
	//
	// - For each chunk we're going to upload
	// - For the entire cloudFile
	
	__block NSProgress *checksumProgress = nil;
	__block NSString *fullChecksum = nil;
	
	NSMutableDictionary<NSNumber*, NSString*> *chunkChecksums =
	  [NSMutableDictionary dictionaryWithCapacity:partsCount];
	
	void (^ChecksumCompletion)(NSError *) = ^(NSError *error){
	
		if (error)
		{
			// Unknown error occurred.
			
			[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
			
			// Just restart the entire operation.
			// This will kick us back to preparePutOperation:forPipeline:
			
			[[self pipelineForContext:context] setStatusAsPendingForOperationWithUUID:context.operationUUID];
			return;
		}
		else
		{
			NSProgress *existing = [owner.progressManager uploadProgressForOperationUUID:context.operationUUID];
			if ([existing isKindOfClass:[ZDCProgress class]])
			{
				// Note: we ALWAYS set second parameter to `NO`,
				// because this task was just a prep task, and shouldn't increment `baseCompletedUnitCount`.
				//
				[(ZDCProgress *)existing removeChild:checksumProgress andIncrementBaseUnitCount:NO];
			}
		}
		
		ZDCCloudOperation_MultipartInfo *multipartInfo = [[ZDCCloudOperation_MultipartInfo alloc] init];
		
		multipartInfo.stagingPath = stagingPath;
		multipartInfo.sha256Hash = fullChecksum;
		
		multipartInfo.rawMetadata = rawMetadata;
		multipartInfo.rawThumbnail = rawThumbnail;
		
		multipartInfo.cloudFileSize = cloudFileSize;
		multipartInfo.chunkSize = chunkSize;
		
		multipartInfo.checksums = chunkChecksums;
		
		[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			NSString *extName = [self extNameForContext:context];
			ZDCCloudTransaction *ext = [transaction ext:extName];
			
			ZDCCloudOperation *op = (ZDCCloudOperation *)
			  [ext operationWithUUID:context.operationUUID inPipeline:context.pipeline];
			
			op = [op copy];
			op.multipartInfo = multipartInfo;
			
			[ext modifyOperation:op];
			
		} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
			
			[[self pipelineForContext:context] setStatusAsPendingForOperationWithUUID:context.operationUUID];
		}];
	};
	
	dispatch_queue_t callbackQueue = dispatch_queue_create("ZDCPushManager.multipart", DISPATCH_QUEUE_SERIAL);
	
	ZDCFileChecksumInstruction *chunkInstruction = nil;
	ZDCFileChecksumInstruction *fullInstruction = nil;
	
	__block NSUInteger pending = 2;
	
	chunkInstruction = [[ZDCFileChecksumInstruction alloc] init];
	chunkInstruction.algorithm = kHASH_Algorithm_SHA256;
	chunkInstruction.chunkSize = @(chunkSize);
	chunkInstruction.callbackQueue = callbackQueue;
	chunkInstruction.callbackBlock = ^(NSData *hash, uint64_t chunkIndex, BOOL done, NSError *error) {
		
		if (hash)
		{
			chunkChecksums[@(chunkIndex)] = [hash lowercaseHexString];
		}
		
		if (done && (--pending == 0))
		{
			ChecksumCompletion(error);
		}
	};
	
	fullInstruction = [[ZDCFileChecksumInstruction alloc] init];
	fullInstruction.algorithm = kHASH_Algorithm_SHA256;
	fullInstruction.callbackQueue = callbackQueue;
	fullInstruction.callbackBlock = ^(NSData *hash, uint64_t chunkIndex, BOOL done, NSError *error) {
		
		if (hash)
		{
			fullChecksum = [hash lowercaseHexString];
		}
		
		if (done && (--pending == 0))
		{
			ChecksumCompletion(error);
		}
	};
	
	NSArray<ZDCFileChecksumInstruction *> *instructions = @[chunkInstruction, fullInstruction];
	
	NSError *paramError = nil;
	checksumProgress =
	  [ZDCFileChecksum checksumFileStream: cloudStream
	                       withStreamSize: cloudFileSize
	                         instructions: instructions
	                                error: &paramError];
	
	if (paramError) {
		DDLogError(@"ZDCFileChecksum paramError: %@", paramError);
	}
	
	if (checksumProgress)
	{
		[checksumProgress setUserInfoObject: @(ZDCChildProgressType_MultipartPrep)
		                             forKey: ZDCChildProgressTypeKey];
		
		ZDCProgress *multipartProgress = [[ZDCProgress alloc] init];
		multipartProgress.totalUnitCount = checksumProgress.totalUnitCount;
		[multipartProgress addChild:checksumProgress withPendingUnitCount:checksumProgress.totalUnitCount];
		
		NSString *description = NSLocalizedString(@"Preparing multipart upload...", nil);
		[multipartProgress setUserInfoObject:description forKey:ZDCLocalizedDescriptionKey];
		
		[owner.progressManager setUploadProgress:multipartProgress forOperation:operation];
	}
	
	return YES;
}

- (ZDCTaskContext *)nextTaskForMultipartOperation:(ZDCCloudOperation *)operation
{
	DDLogAutoTrace();
	
	ZDCCloudOperation_MultipartInfo *multipartInfo = operation.multipartInfo;
	
	__block ZDCTaskContext *next = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		if (multipartTasks == nil) {
			multipartTasks = [[NSMutableDictionary alloc] init];
		}
		
		NSMutableDictionary<id, ZDCTaskContext *> *tasks = multipartTasks[operation.uuid];
		
		if (multipartInfo.uploadID == nil)
		{
			if (tasks[key_tasks_initiate] == nil)
			{
				next = [[ZDCTaskContext alloc] initWithOperation:operation];
				next.multipart_initiate = YES;
			}
		}
		else if (multipartInfo.needsAbort)
		{
			if (tasks[key_tasks_abort] == nil)
			{
				next = [[ZDCTaskContext alloc] initWithOperation:operation];
				next.multipart_abort = YES;
			}
		}
		else
		{
			BOOL foundNextPart = NO;
			
			NSUInteger numParts = multipartInfo.numberOfParts;
			NSUInteger nextPart = 0;
			
			for (NSUInteger i = 0; i < numParts; i++)
			{
				// Is this part completed already ?
				
				NSString *eTag = multipartInfo.eTags[@(i)];
				if (eTag) {
					continue;
				}
				
				// Is this part in flight ?
				
				ZDCTaskContext *context = tasks[@(i)];
				if (context) {
					continue;
				}
				
				// Found it!
				
				nextPart = i;
				foundNextPart = YES;
				
				break;
			}
			
			if (foundNextPart)
			{
				// We found the next task.
				// But is there bandwidth for it ?
				
				if (tasks.count < multipart_maxUploadCount)
				{
					next = [[ZDCTaskContext alloc] initWithOperation:operation];
					next.multipart_index = nextPart;
				}
			}
			else
			{
				// We may be ready to complete the multipart upload.
				// But we have to complete all the part uploads first.
				
				if (tasks.count == 0)
				{
					if (tasks[key_tasks_complete] == nil)
					{
						next = [[ZDCTaskContext alloc] initWithOperation:operation];
						next.multipart_complete = YES;
					}
				}
			}
		}
		
		if (next)
		{
			if (tasks == nil) {
				tasks = multipartTasks[operation.uuid] =
				  [[NSMutableDictionary alloc] initWithCapacity:multipart_maxUploadCount];
			}
			
			if (next.multipart_initiate) {
				tasks[key_tasks_initiate] = next;
			}
			else if (next.multipart_complete) {
				tasks[key_tasks_complete] = next;
			}
			else if (next.multipart_abort) {
				tasks[key_tasks_abort] = next;
			}
			else {
				tasks[@(next.multipart_index)] = next;
			}
		}
	}});
	
	return next;
}

- (void)removeTaskForMultipartOperation:(ZDCTaskContext *)context didSucceed:(BOOL)success
{
	DDLogAutoTrace();
	
	ZDCCloudOperation *operation = [self operationForContext:context];
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		NSMutableDictionary<id, ZDCTaskContext *> *tasks = multipartTasks[operation.uuid];
		if (tasks)
		{
			if (context.multipart_initiate) {
				tasks[key_tasks_initiate] = nil;
			}
			else if (context.multipart_complete) {
				tasks[key_tasks_complete] = nil;
			}
			else if (context.multipart_abort) {
				tasks[key_tasks_abort] = nil;
			}
			else {
				tasks[@(context.multipart_index)] = nil;
			}
			
			if (tasks.count == 0) {
				multipartTasks[operation.nodeID] = nil;
			}
		}
		
		NSProgress *progress = [owner.progressManager uploadProgressForOperationUUID:operation.uuid];
		if ([progress isKindOfClass:[ZDCProgress class]])
		{
			[(ZDCProgress *)progress removeChild:context.progress andIncrementBaseUnitCount:success];
		}
	}});
}

#if TARGET_OS_IPHONE
/**
 * Called if a background upload for a multipart operation is being restored.
 */
- (void)restoreInProgressMultipartContext:(ZDCTaskContext *)context
{
	DDLogAutoTrace();
	
	ZDCCloudOperation *operation = [self operationForContext:context];
	ZDCCloudOperation_MultipartInfo *multipartInfo = operation.multipartInfo;
	
	if (multipartInfo == nil)
	{
		DDLogWarn(@"ignoring - called with non-multipart context");
		return;
	}
	if (context.progress == nil)
	{
		DDLogWarn(@"ignoring - called with nil context.progress");
		return;
	}
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		if (multipartTasks == nil) {
			multipartTasks = [[NSMutableDictionary alloc] init];
		}
		
		NSMutableDictionary<id, ZDCTaskContext *> *tasks = multipartTasks[operation.uuid];
		
		if (tasks == nil) {
			tasks = multipartTasks[operation.uuid] =
			  [[NSMutableDictionary alloc] initWithCapacity:multipart_maxUploadCount];
		}
		
		if (context.multipart_initiate)
			tasks[key_tasks_initiate] = context;
		else if (context.multipart_complete)
			tasks[key_tasks_complete] = context;
		else if (context.multipart_abort)
			tasks[key_tasks_abort] = context;
		else
			tasks[@(context.multipart_index)] = context;
	}});
	
	[self refreshProgressForMultipartOperation:operation];
}
#endif

- (void)refreshProgressForMultipartOperation:(ZDCCloudOperation *)operation
{
	DDLogAutoTrace();
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
		
		NSMutableDictionary<id, ZDCTaskContext *> *tasks = multipartTasks[operation.uuid];
		if (tasks == nil) {
			return; // from block
		}
		
		ZDCProgress *progress = nil;
		
		NSProgress *existing = [owner.progressManager uploadProgressForOperationUUID:operation.uuid];
		if ([existing isKindOfClass:[ZDCProgress class]])
		{
			progress = (ZDCProgress *)existing;
		}
		else
		{
			progress = [[ZDCProgress alloc] init];
			[owner.progressManager setUploadProgress:progress forOperation:operation];
		}
		
		ZDCCloudOperation_MultipartInfo *multipartInfo = operation.multipartInfo;
		
		uint64_t normalPartSize = multipartInfo.chunkSize;
		uint64_t lastPartSize  = (multipartInfo.cloudFileSize % multipartInfo.chunkSize);
		
		if (lastPartSize == 0)
			lastPartSize = normalPartSize;
		
		NSUInteger lastPart = multipartInfo.numberOfParts - 1;
		
		NSUInteger completedUnitCount = 0;
		
		for (NSNumber *part in multipartInfo.eTags)
		{
			if ([part unsignedIntegerValue] == lastPart)
				completedUnitCount += lastPartSize;
			else
				completedUnitCount += normalPartSize;
		}
		
		progress.totalUnitCount = multipartInfo.cloudFileSize;
		progress.baseCompletedUnitCount = completedUnitCount;
		
		NSString *description = nil;
		NSMutableArray<NSNumber *> *parts = nil;
		
		for (id key in tasks)
		{
			int64_t unitCount = 0;
			
			if ([key isKindOfClass:[NSString class]])
			{
				if ([(NSString *)key isEqualToString:key_tasks_initiate])
				{
					description = NSLocalizedString(@"Initiating multipart upload...", nil);
				}
				else if ([(NSString *)key isEqualToString:key_tasks_complete])
				{
					description = NSLocalizedString(@"Completing multipart upload...", nil);
				}
				else if ([(NSString *)key isEqualToString:key_tasks_abort])
				{
					description = NSLocalizedString(@"Cancelling multipart upload...", nil);
				}
			}
			else if ([key isKindOfClass:[NSNumber class]])
			{
				NSUInteger part = [(NSNumber *)key unsignedIntegerValue];
				
				if (part == lastPart)
					unitCount = lastPartSize;
				else
					unitCount = normalPartSize;
				
				if (parts == nil)
					parts = [NSMutableArray arrayWithCapacity:multipart_maxUploadCount];
				
				[parts addObject:key];
			}
			
			ZDCTaskContext *context = tasks[key];
			if (context.progress && unitCount > 0)
			{
				[progress addChild:context.progress withPendingUnitCount:unitCount];
			}
		}
		
		if (!description && parts.count > 0)
		{
			if (parts.count == 1)
			{
				// convert from base-zero to base-1 for user readability
				int part_num = [parts[0] intValue] + 1;
				
				NSString *format = NSLocalizedString(@"Uploading part %d of %d", nil);
				description = [NSString stringWithFormat:format, part_num, (int)multipartInfo.numberOfParts];
			}
			else
			{
				// convert from base-zero to base-1 for user readability
				int part_num_a = [parts[0] intValue] + 1;
				int part_num_b = [parts[1] intValue] + 1;
				
				if (part_num_a > part_num_b) {
					int temp = part_num_a;
					part_num_a = part_num_b;
					part_num_b = temp;
				}
				
				NSString *format = NSLocalizedString(@"Uploading parts %d & %d of %d", nil);
				description = [NSString stringWithFormat:format, part_num_a, part_num_b, (int)multipartInfo.numberOfParts];
			}
		}
		
		if (description)
		{
			[progress setUserInfoObject:description forKey:ZDCLocalizedDescriptionKey];
		}
	}});
}

- (void)abortMultipartOperation:(ZDCCloudOperation *)operation
{
	DDLogAutoTrace();
	
	__block BOOL opModified = NO;
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSString *extName = [self extNameForOperation:operation];
		ZDCCloudTransaction *ext = [transaction ext:extName];
		
		ZDCCloudOperation *op = (ZDCCloudOperation *)
		  [ext operationWithUUID:operation.uuid inPipeline:operation.pipeline];
		
		if ([operation.multipartInfo.uploadID isEqualToString:op.multipartInfo.uploadID]
		 && [operation.multipartInfo.stagingPath isEqualToString:op.multipartInfo.stagingPath]
		 && operation.multipartInfo.needsAbort == NO)
		{
			op = [op copy];
			op.multipartInfo.needsAbort = YES;
			
			[ext modifyOperation:op];
			opModified = YES;
		}
		
	} completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) completionBlock:^{
		
		if (opModified) {
			[[self pipelineForOperation:operation] setStatusAsPendingForOperationWithUUID:operation.uuid];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Conflict Resolution Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fixMissingKeysForNodeID:(NSString *)nodeID operation:(ZDCCloudOperation *)operation
{
	DDLogAutoTrace();
	
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForOperation:operation];
	
	NSDate *distantFuture = [NSDate distantFuture];
	NSUUID *opUUID = operation.uuid;
	NSString *ctx = @"fix-missing-keys";
	
	[pipeline setHoldDate:distantFuture forOperationWithUUID:opUUID context:ctx];
	[pipeline setStatusAsPendingForOperationWithUUID:opUUID];
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
		ZDCNode *node = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		if (node)
		{
			[owner.cryptoTools fixMissingKeysForNode:node transaction:transaction];
		}
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[pipeline setHoldDate:nil forOperationWithUUID:opUUID context:ctx];
	}];
}

- (void)fetchMissingUsers:(NSArray<NSString*> *)missingUserIDs forOperation:(ZDCCloudOperation *)operation
{
	DDLogAutoTrace();
	
	YapDatabaseCloudCorePipeline *pipeline = [self pipelineForOperation:operation];
	
	ZDCRemoteUserManager *remoteUserManager = owner.remoteUserManager;
	
	NSDate *distantFuture = [NSDate distantFuture];
	NSUUID *opUUID = operation.uuid;
	NSString *ctx = @"fetch-missing-user";
	
	for (NSString *userID in missingUserIDs)
	{
		[pipeline setHoldDate:distantFuture forOperationWithUUID:opUUID context:ctx];
		
		[remoteUserManager createRemoteUserWithID: userID
		                              requesterID: operation.localUserID
		                          completionQueue: concurrentQueue
		                          completionBlock:^(ZDCUser *remoteUser, NSError *error)
		{
			[pipeline setHoldDate:nil forOperationWithUUID:opUUID context:ctx];
		}];
	}
	
	[pipeline setStatusAsPendingForOperationWithUUID:opUUID];
}

- (void)retryOperationWithContext:(ZDCTaskContext *)context
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(context != nil);
#else
	if (context == nil) {
		DDLogError(@"retryOperationWithContext: context is nil !");
		return;
	}
#endif
	
	ZDCCloudOperation *op = [self operationForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	[[self pipelineForOperation:op] setStatusAsPendingForOperationWithUUID:op.uuid];
}

- (void)skipOperationWithContext:(ZDCTaskContext *)context
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(context != nil);
#else
	if (context == nil) {
		DDLogError(@"skipOperationWithContext: context is nil !");
		return;
	}
#endif
	
	NSString *extName = [self extNameForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:extName] skipOperationWithUUID:context.operationUUID];
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
	}];
}

- (void)failOperationWithContext:(ZDCTaskContext *)context
                       errorInfo:(NSDictionary *)errorInfo
                 stopSyncingNode:(BOOL)stopSyncingNode
{
	DDLogInfo(@"Failing operation with info: %@", errorInfo);
	
	NSString *extName = [self extNameForContext:context];
	
	// Cleanup (if needed)
#if TARGET_OS_IPHONE
	if (context.uploadFileURL && context.deleteUploadFileURL)
	{
		[[NSFileManager defaultManager] removeItemAtURL:context.uploadFileURL error:nil];
	}
#endif
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:extName] skipOperationWithUUID:context.operationUUID];
		
		// Todo...
		
	//	ZDCNode *node = [transaction objectForKey:op.nodeID inCollection:kS4Collection_Nodes];
	//	node = [node copy];
	//
	//	node.syncErrorInfo = errorInfo;
	//	if (stopSyncingNode) {
	//		node.doNotSync = S4DoNotSync_SetAutomatically_True;
	//	}
	//
	//	[transaction setObject:node forKey:node.uuid inCollection:kS4Collection_Nodes];
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.progressManager removeUploadProgressForOperationUUID:context.operationUUID withSuccess:NO];
	}];
}

- (void)forceFullPullForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID
{
	DDLogAutoTrace();
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:localUserID inCollection:kZDCCollection_PullState];
		
	} completionQueue:concurrentQueue completionBlock:^{
		
		[owner.pullManager pullRemoteChangesForLocalUserID:localUserID zAppID:zAppID];
	}];
}

#pragma clang diagnostic pop

@end
