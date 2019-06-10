/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCDownloadManagerPrivate.h"

#import "Auth0Utilities.h"
#import "S3Request.h"
#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCDownloadContext.h"
#import "ZDCLogging.h"
#import "ZDCProgress.h"
#import "ZDCNodePrivate.h"
#import "ZDCProgressManagerPrivate.h"
#import "ZDCNetworkTools.h"
#import "ZeroDarkCloudPrivate.h"

#import "NSError+Auth0API.h"
#import "NSError+ZeroDark.h"
#import "NSDate+ZeroDark.h"

#import "NSMutableURLRequest+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"

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

static NSUInteger const kMaxFailCount = 8;


/**
 * ZDCDownloadTicket is the class we pass back to the user.
 * This is the private API for internal use.
 */
@interface ZDCDownloadTicket ()

- (instancetype)initWithOwner:(ZDCDownloadManager *)owner
                       nodeID:(NSString *)nodeID
                   components:(ZDCNodeMetaComponents)compoents
                      options:(ZDCDownloadOptions *)options
              completionBlock:(id)completionBlock;

- (instancetype)initWithOwner:(ZDCDownloadManager *)owner
                       nodeID:(NSString *)nodeID
                      options:(ZDCDownloadOptions *)options
              completionBlock:(id)completionBlock;

- (instancetype)initWithOwner:(ZDCDownloadManager *)owner
                       userID:(NSString *)userID
                      auth0ID:(NSString *)auth0ID
                      options:(ZDCDownloadOptions *)options
              completionQueue:(dispatch_queue_t)completionQueue
              completionBlock:(id)completionBlock;

@property (nonatomic, assign, readonly) BOOL isUser;
@property (nonatomic, assign, readonly) BOOL isMeta;

@property (nonatomic, strong, readonly) NSString *userID;
@property (nonatomic, strong, readonly) NSString *auth0ID;

@property (nonatomic, strong, readonly) NSString *nodeID;
@property (nonatomic, assign, readonly) ZDCNodeMetaComponents components;

@property (nonatomic, strong, readonly) ZDCDownloadOptions *options;
@property (nonatomic, strong, readonly) dispatch_queue_t completionQueue;
@property (nonatomic, strong, readonly) id completionBlock;

@property (nonatomic, strong, readwrite) NSProgress *progress;

@property (atomic, assign, readwrite) BOOL isIgnored;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For any given download, there may be multiple tickets.
 * That is, multiple parts of the application may request the same download at approximately the same time.
 * These requests get consolidated into a single NSURLSessionTask,
 * and we use an instance of ZDCDownloadRef to track the outstanding tickets.
 *
 * This allows the requester_1 to cancel a ticket.
 * And we'll know that requester_2 is still waiting for the results, so we know to NOT cancel the task.
 */
@interface ZDCDownloadRef : NSObject

@property (nonatomic, readonly) NSMutableArray<ZDCDownloadTicket*> *tickets;

@property (nonatomic, weak, readwrite) ZDCDownloadTicket *dependency;

@property (nonatomic, weak, readwrite) NSURLSessionTask *task;
@property (nonatomic, assign, readwrite) BOOL isBackground;

@end

@implementation ZDCDownloadRef

@synthesize tickets = tickets;
@synthesize dependency;
@synthesize task;
@synthesize isBackground;

- (instancetype)init
{
	if ((self = [super init]))
	{
		tickets = [[NSMutableArray alloc] init];
	}
	return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDownloadManager
{
	__weak ZeroDarkCloud *owner;
	
	dispatch_queue_t downloadQueue;
	NSMutableDictionary<NSString*, ZDCDownloadRef*> *downloadDict; // only access/modify within downloadQueue
	
	NSCache<NSString*, NSData*> *resumeCache_background;
	NSCache<NSString*, NSData*> *resumeCache_foreground;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.downloadManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
		
		downloadQueue = dispatch_queue_create("ZDCDownloadManager", DISPATCH_QUEUE_SERIAL);
		downloadDict = [[NSMutableDictionary alloc] init];
		
		resumeCache_background = [[NSCache alloc] init];
		resumeCache_foreground = [[NSCache alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Keys
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)downloadMetaKeyForNodeID:(NSString *)nodeID components:(ZDCNodeMetaComponents)components
{
	// Format(s):
	// - nodeID : UUID (hexadecimal) e.g.: 68753A44-4D6F-1226-9C60-0050E4C00067
	
	return [NSString stringWithFormat:@"%@|%d", nodeID, (int)components];
}

- (NSString *)downloadKeyForUserID:(NSString *)userID auth0ID:(NSString *)auth0ID
{
	// Format(s)
	// - userID  : 32 chars (zBase32) e.g.: z55tqmfr9kix1p1gntotqpwkacpuoyno
	// - auth0ID : <provider_name>|<provider_specific_id>
	
	return [NSString stringWithFormat:@"%@|%@", userID, auth0ID];
}

- (NSString *)resumeKeyForRequest:(NSURLRequest *)request
{
	// Motivation:
	// - The URL for a given nodeID may change over time
	// - The eTag may change over time
	// - Requests for different components will result in different ranges
	//
	// Thus our best bet is really to base the key of the actual URL + HTTP headers.
	
	NSString *url = request.URL.path;
	NSString *eTag = [request valueForHTTPHeaderField:@"If-Match"];
	NSString *range = [request valueForHTTPHeaderField:@"Range"];
	
	if (eTag == nil) { eTag = @"none"; }
	if (!range) { range = @"none"; }
	
	return [NSString stringWithFormat:@"%@|%@|%@", url, eTag, range];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateDatabaseWithCloudDataInfo:(ZDCCloudDataInfo *)info
                              forNodeID:(NSString *)nodeID
                        completionQueue:(dispatch_queue_t)completionQueue
                        completionBlock:(dispatch_block_t)completionBlock
{
	__weak ZeroDarkCloud *owner = self->owner;
	
	YapDatabaseConnection *rwConnection = owner.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCNode *updatedNode = [transaction objectForKey:nodeID inCollection:kZDCCollection_Nodes];
		if (updatedNode == nil) return; // from block
			
		updatedNode = [updatedNode copy];
		updatedNode.cloudDataInfo = info;
		
		BOOL notifyDelegate = NO;
		
		if (!updatedNode.lastModified_data || [updatedNode.lastModified_data isBefore:info.lastModified])
		{
			updatedNode.eTag_data = info.eTag;
			updatedNode.lastModified_data = info.lastModified;
			
			notifyDelegate = YES;
		}
		
		[transaction setObject:updatedNode forKey:nodeID inCollection:kZDCCollection_Nodes];
		
		if (notifyDelegate)
		{
			ZDCTreesystemPath *path =
			  [[ZDCNodeManager sharedInstance] pathForNode:updatedNode transaction:transaction];
			
			[owner.delegate didDiscoverModifiedNode: updatedNode
			                             withChange: ZDCNodeChange_Data
			                                 atPath: path
			                            transaction: transaction];
		}
			
	} completionQueue:completionQueue completionBlock:completionBlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Header
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal method - all metadata downloads require the header.
 */
- (ZDCDownloadTicket *)downloadNodeHeader:(ZDCNode *)node
                                  options:(ZDCDownloadOptions *)options
                   preFetchedCloudLocator:(ZDCCloudLocator *)preFetchedCloudLocator
                          completionQueue:(nullable dispatch_queue_t)completionQueue
                          completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock
{
	DDLogAutoTrace();
	
	ZDCCloudDataInfo *upToDateHeader = nil;
	if ([node.cloudDataInfo.eTag isEqual:node.eTag_data])
	{
		upToDateHeader = node.cloudDataInfo;
	}
	
	if (upToDateHeader)
	{
		// Nothing to download - we already have the header
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(upToDateHeader, nil, nil, nil);
			}});
		}
		return [[ZDCDownloadTicket alloc] init];
	}
	
	NSString *const downloadKey = [self downloadMetaKeyForNodeID:node.uuid components:ZDCNodeMetaComponents_Header];
	
	__block ZDCDownloadTicket *existingTicket = nil;
	__block ZDCDownloadTicket *ticket = nil;
	
	__block NSProgress *existingProgress = nil;
	__block ZDCProgress *progress = nil;
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		
		if (options.completionTag && ref)
		{
			for (ZDCDownloadTicket *ticket in ref.tickets)
			{
				if ([ticket.options.completionTag isEqualToString:options.completionTag])
				{
					existingTicket = ticket;
					break;
				}
			}
		}
		
		if (existingTicket == nil)
		{
			ticket = [[ZDCDownloadTicket alloc] initWithOwner: self
			                                           nodeID: node.uuid
			                                       components: ZDCNodeMetaComponents_Header
			                                          options: options
			                                  completionBlock: completionBlock];
			
			progress = [[ZDCProgress alloc] init];
			
			[owner.progressManager setMetaDownloadProgress: progress
			                                     forNodeID: node.uuid
			                                    components: ZDCNodeMetaComponents_Header
			                                   localUserID: node.localUserID
			                              existingProgress: &existingProgress
			                               completionQueue: completionQueue
			                               completionBlock: completionBlock];
		
			if (existingProgress) {
				ticket.progress = existingProgress;
			}
			else {
				ticket.progress = progress;
			}
		
			if (!ref) {
				ref = downloadDict[downloadKey] = [[ZDCDownloadRef alloc] init];
			}
			[ref.tickets addObject:ticket];
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (existingTicket)
	{
		// Download already in progress.
		// Request is a duplicate (as per completionTag).
		return existingTicket;
	}
	if (existingProgress)
	{
		// Download already in progress.
		// Request added to listeners.
		return ticket;
	}
	
	__weak typeof(self) weakSelf = self;
	void (^continuation)(ZDCCloudLocator *) = ^(ZDCCloudLocator *cloudLocator){ @autoreleasepool {
		
		[weakSelf _downloadNodeHeader: node
		             withCloudLocator: cloudLocator
		                     progress: progress
		                      options: options
		                    failCount: 0];
	}};
	
	if (preFetchedCloudLocator)
	{
		continuation(preFetchedCloudLocator);
	}
	else
	{
		dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
		// Deadlock warning:
		//
		// We may currently be inside a transaction.
		// As in, this method was invoked from inside a transaction.
		// So it's not safe to perform a synchronous read using the public roDatabaseConnection here.
		// We can either use our own dedicated databaseConnection, or simply perform it using an async transaction.
		//
		__block ZDCCloudLocator *cloudLocator = nil;
		[owner.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
	
			cloudLocator =
			  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
			                                              fileExtension: kZDCCloudFileExtension_Data
			                                                transaction: transaction];
	
		} completionQueue:concurrentQueue completionBlock:^{
		
			continuation(cloudLocator);
		}];
	}
	
	return ticket;
}

/**
 * Performs the actual download logic including:
 * - retry with exponential backoff
 * - decryption
 * - updating node in database (as needed)
 * - popping completionBlock(s) from ProgressManager
 */
- (void)_downloadNodeHeader:(ZDCNode *)node
           withCloudLocator:(nullable ZDCCloudLocator *)cloudLocator
                   progress:(ZDCProgress *)progress
                    options:(ZDCDownloadOptions *)options
                  failCount:(NSUInteger)failCount
{
	DDLogAutoTrace();
	
	NSString *nodeID = node.uuid;
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__weak typeof(self) weakSelf = self;
	
	void (^failBlock)(NSError *) = ^(NSError *error) { @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeMetaDownloadFailed: nodeID
		                        components: ZDCNodeMetaComponents_Header
		                             error: error];
	}};
	
	if (cloudLocator == nil)
	{
		NSString *msg = @"Invalid parameter: node is misconfigured - unable to determine cloud URL";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		failBlock(error);
		return;
	}
	
	ZDCDownloadContext *context =
	  [[ZDCDownloadContext alloc] initWithLocalUserID: node.localUserID
	                                           nodeID: node.uuid
	                                           isMeta: YES
	                                       components: ZDCNodeMetaComponents_Header
	                                          options: options];
	
	context.ephemeralInfo.node = node;
	context.ephemeralInfo.cloudLocator = cloudLocator;
	context.ephemeralInfo.progress = progress;
	context.ephemeralInfo.failCount = failCount;
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		AWSCredentialsManager *awsCredentialsManager = nil;
		{ // scoping
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf)
			{
				awsCredentialsManager = strongSelf->owner.awsCredentialsManager;
			}
		}
		
		[awsCredentialsManager getAWSCredentialsForUser: node.localUserID
		                                completionQueue: concurrentQueue
		                                completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use normal flow to execute exponential backoff.
					
					[weakSelf _downloadNodeHeaderTaskDidComplete: nil
					                                 withContext: context
					                                       error: error
					                                responseData: nil];
				}
				else
				{
					failBlock(error);
				}
			}
			else
			{
				[weakSelf _downloadNodeHeader: node
				                  withContext: context
				                         auth: auth];
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

- (void)_downloadNodeHeader:(ZDCNode *)node
                withContext:(ZDCDownloadContext *)context
                       auth:(ZDCLocalUserAuth *)auth
{
#if TARGET_OS_IPHONE
	BOOL canBackground = context.options.canDownloadWhileInBackground;
#else
	BOOL canBackground = NO;
#endif
	
	ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:node.localUserID];
#if TARGET_OS_IPHONE
	AFURLSessionManager *session =
	  canBackground ? sessionInfo.backgroundSession : sessionInfo.foregroundSession;
#else
	AFURLSessionManager *session = sessionInfo.session;
#endif

	ZDCCloudLocator *cloudLocator = context.ephemeralInfo.cloudLocator;
	
	NSMutableURLRequest *request =
	  [S3Request getObject: cloudLocator.cloudPath.path
	              inBucket: cloudLocator.bucket
	                region: cloudLocator.region
	      outUrlComponents: nil];
	
	NSRange byteRange = (NSRange){
		.location = 0,
		.length = sizeof(ZDCCloudFileHeader) // <- 64 bytes
	};

	[request setHTTPRange:byteRange];

	[AWSSignature signRequest: request
	               withRegion: cloudLocator.region
	                  service: AWSService_S3
	              accessKeyID: auth.aws_accessKeyID
	                   secret: auth.aws_secret
	                  session: auth.aws_session];

	__block NSURLSessionTask *task = nil;
	if (canBackground)
	{
		// Background NSURLSession's don't really support data tasks.
		// So we have to download the tiny response to a file instead.
		
		task = [session downloadTaskWithRequest: request
		                               progress: nil
		                            destination: nil
		                      completionHandler: nil];
				
		[owner.sessionManager associateContext:context withTask:task inSession:session.session];
	}
	else
	{
		// The header download is so tiny, it's not worth the effort to use a download task.
		// The data will arrive in only a few TCP packets anyway.
		
		__weak typeof(self) weakSelf = self;
		task = [session dataTaskWithRequest: request
		                     uploadProgress: nil
		                   downloadProgress: nil
		                  completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
		{
			NSData *responseData = nil;
			
			if (!error && ![responseObject isKindOfClass:[NSData class]])
			{
				error = [NSError errorWithClass: [ZDCDownloadManager class]
				                           code: 2000
				                    description: @"Unexpected result from server"];
			}
			else
			{
				responseData = (NSData *)responseObject;
			}
			
			[weakSelf _downloadNodeHeaderTaskDidComplete: task
			                                 withContext: context
			                                       error: error
			                                responseData: responseData];
		}];
	}
	
	NSProgress *taskProgress = [session downloadProgressForTask:task];
	if (taskProgress)
	{
		[context.ephemeralInfo.progress addChild:taskProgress withPendingUnitCount:byteRange.length];
	}
	
	__block BOOL shouldStartTask = YES;
	
	NSString *const downloadKey = [self downloadMetaKeyForNodeID:context.nodeID components:context.components];
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		if (ref && ref.tickets.count > 0)
		{
			shouldStartTask = YES;
			ref.task = task;
			ref.isBackground = canBackground;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldStartTask)
	{
		[task resume];
	}
}

- (void)_downloadNodeHeaderTaskDidComplete:(nullable NSURLSessionTask *)task
                               withContext:(ZDCDownloadContext *)context
                                     error:(nullable NSError *)error
                              responseData:(nullable NSData *)responseData
{
	DDLogAutoTrace();
	
	NSString *nodeID = context.nodeID;
	
	__weak typeof(self) weakSelf = self;
	
	void (^failBlock)(NSError *) = ^(NSError *error) { @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeMetaDownloadFailed: nodeID
		                        components: ZDCNodeMetaComponents_Header
		                             error: error];
	}};
	
	void (^successBlock)(ZDCCloudDataInfo*) = ^(ZDCCloudDataInfo *info) { @autoreleasepool {
		
		// Executing within concurrentQueue here
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeMetaDownloadSucceeded: nodeID
		                           components: ZDCNodeMetaComponents_Header
		                               header: info
		                             metadata: nil
		                            thumbnail: nil];
	}};
	
	NSURLResponse *urlResponse = task.response;
	NSInteger statusCode = [urlResponse httpStatusCode];
	
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
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		NSUInteger newFailCount = context.ephemeralInfo.failCount + 1;
		
		if (newFailCount > kMaxFailCount)
		{
			if (error == nil) {
				error = [NSError errorWithClass:[self class] code:503 description:@"Exceeded max retries"];
			}
			
			failBlock(error);
			return;
		}
		else
		{
			[self _downloadNodeHeader: context.ephemeralInfo.node
			         withCloudLocator: context.ephemeralInfo.cloudLocator
			                 progress: context.ephemeralInfo.progress
			                  options: context.options
			                failCount: newFailCount];
		}
		
		return;
	}
	else if (statusCode == 401) // Unauthorized
	{
		// Authentication failed.
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		// We need to alert the user (so they can re-auth with valid credentials).
		//
		[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
		
		NSError *error =
		  [NSError errorWithClass:[self class] code:statusCode description:@"Unauthorized"];
		
		failBlock(error);
		return;
	}
	else if ((statusCode != 200) && (statusCode != 206) && (statusCode != 304))
	{
		// Download failed for some other reason - possibly unknown
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		// One would think AWS would return a 404 for files that no longer exist.
		// But one would be wrong !
		//
		// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
		
		if ((statusCode != 403) && (statusCode != 404))
		{
			DDLogError(@"AWS S3 returned unknown status code: %ld", (long)statusCode);
		}
		
		NSError *error =
		  [NSError errorWithClass:[self class] code:statusCode description:@"HTTP status code"];
		
		failBlock(error);
		return;
	}
	
	// We're currently executing on the AFNetworking session queue.
	// And decryption is comparatively slow.
	// So let's do it on a different queue.
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{ @autoreleasepool {
		
		ZDCNode *node = context.ephemeralInfo.node;
		
		ZDCCloudFileHeader header;
		bzero(&header, sizeof(header));
		
		NSError *error = nil;
		[CloudFile2CleartextInputStream decryptCloudFileData: responseData
		                                   withEncryptionKey: node.encryptionKey
		                                              header: &header
		                                         rawMetadata: nil
		                                        rawThumbnail: nil
		                                               error: &error];
		if (error)
		{
			failBlock(error);
			return;
		}
		
		NSString *eTag = [urlResponse eTag] ?: @"";
		NSDate *lastModified = [urlResponse lastModified] ?: [NSDate date];
		
		ZDCCloudDataInfo *info =
		  [[ZDCCloudDataInfo alloc] initWithCloudFileHeader: header
		                                               eTag: eTag
		                                       lastModified: lastModified];
		
		[weakSelf updateDatabaseWithCloudDataInfo: info
		                                forNodeID: nodeID
		                          completionQueue: concurrentQueue
		                          completionBlock:
		^{
			successBlock(info);
		}];
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Meta
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (ZDCDownloadTicket *)downloadNodeMeta:(ZDCNode *)node
                             components:(ZDCNodeMetaComponents)components
                                options:(nullable ZDCDownloadOptions *)inOptions
                        completionQueue:(nullable dispatch_queue_t)completionQueue
                        completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock
{
	DDLogAutoTrace();
	
	if (!node.isImmutable) {
		node = [node immutableCopy];
	}
	
	ZDCDownloadOptions *options = [inOptions copy];
	if (options == nil)
	{
		options = [[ZDCDownloadOptions alloc] init];
		options.cacheToDiskManager = YES;
	}
	
	if (components == 0)
	{
		NSString *msg = @"Invalid parameter: components specify nothing";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(nil, nil, nil, error);
			}});
		}
		return [[ZDCDownloadTicket alloc] init];
	}
	
	// Cleanup the components so they make sense.
	// Here's how the file is laid out in the cloud:
	//
	// | header | metadata | thumbnail | data |
	//
	// We always need the header, because it tells us:
	// - how big the metadata section is (may be zero, meaning section not present)
	// - how big the thumbnail section is (may be zero, meaning section not present)
	// - how big the data section is
	//
	// Careful:
	//   Failure to ignore spurious flags in the bitfield would cause coalescing to fail.
	
	ZDCNodeMetaComponents inComponents = components;
	
	components = ZDCNodeMetaComponents_Header;
	if (inComponents & ZDCNodeMetaComponents_Metadata) {
		components |= ZDCNodeMetaComponents_Metadata;
	}
	if (inComponents & ZDCNodeMetaComponents_Thumbnail) {
		components |= ZDCNodeMetaComponents_Thumbnail;
	}
	
	if (components == ZDCNodeMetaComponents_Header) // Shortcut - only requesting header
	{
		return [self downloadNodeHeader: node
		                        options: options
		         preFetchedCloudLocator: nil
		                completionQueue: completionQueue
		                completionBlock: completionBlock];
	}
	
	BOOL requestingMetadata = (components & ZDCNodeMetaComponents_Metadata) != 0;
	BOOL requestingThumbnail = (components & ZDCNodeMetaComponents_Thumbnail) != 0;
	
	if (!requestingMetadata || !requestingThumbnail)
	{
		// Are we currently downloading both ?
		// If so we can just piggyback off that.
		
		NSString *const piggybackKey = [self downloadMetaKeyForNodeID:node.uuid components:ZDCNodeMetaComponents_All];
		
		__block ZDCDownloadTicket *piggybackTicket = nil;
		
		dispatch_sync(downloadQueue, ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			ZDCDownloadRef *ref = downloadDict[piggybackKey];
			
			if (options.completionTag && ref)
			{
				for (ZDCDownloadTicket *ticket in ref.tickets)
				{
					if ([ticket.options.completionTag isEqualToString:options.completionTag])
					{
						piggybackTicket = ticket;
						break;
					}
				}
			}
			
			if (piggybackTicket == nil)
			{
				NSProgress *piggybackProgress =
				  [owner.progressManager metaDownloadProgressForNodeID: node.uuid
				                                            components: @(ZDCNodeMetaComponents_All)
				                                       completionQueue: completionQueue
				                                       completionBlock: completionBlock];
				if (piggybackProgress)
				{
					piggybackTicket = [[ZDCDownloadTicket alloc] initWithOwner: self
					                                                    nodeID: node.uuid
					                                                components: ZDCNodeMetaComponents_All
					                                                   options: options
					                                           completionBlock: completionBlock];
					
					piggybackTicket.progress = piggybackProgress;
		
					if (!ref) {
						ref = downloadDict[piggybackKey] = [[ZDCDownloadRef alloc] init];
					}
		
					[ref.tickets addObject:piggybackTicket];
				}
			}
			
		#pragma clang diagnostic pop
		}});
		
		if (piggybackTicket)
		{
			// Download already in progress (for a slightly different request).
			return piggybackTicket;
		}
	}
	
	// Check for existing progress
	
	NSString *const downloadKey = [self downloadMetaKeyForNodeID:node.uuid components:components];
	
	__block ZDCDownloadTicket *existingTicket = nil;
	__block ZDCDownloadTicket *ticket = nil;
	
	__block NSProgress *existingProgress = nil;
	__block ZDCProgress *progress = nil;
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		
		if (options.completionTag && ref)
		{
			for (ZDCDownloadTicket *ticket in ref.tickets)
			{
				if ([ticket.options.completionTag isEqualToString:options.completionTag])
				{
					existingTicket = ticket;
					break;
				}
			}
		}
		
		if (existingTicket == nil)
		{
			ticket = [[ZDCDownloadTicket alloc] initWithOwner: self
			                                           nodeID: node.uuid
			                                       components: components
			                                          options: options
			                                  completionBlock: completionBlock];
			
			progress = [[ZDCProgress alloc] init];
			
			[owner.progressManager setMetaDownloadProgress: progress
			                                     forNodeID: node.uuid
			                                    components: components
			                                   localUserID: node.localUserID
			                              existingProgress: &existingProgress
			                               completionQueue: completionQueue
			                               completionBlock: completionBlock];
	
			if (existingProgress) {
				ticket.progress = existingProgress;
			}
			else {
				ticket.progress = progress;
			}
	
			if (!ref) {
				ref = downloadDict[downloadKey] = [[ZDCDownloadRef alloc] init];
			}
			[ref.tickets addObject:ticket];
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (existingTicket)
	{
		// Download already in progress.
		// Request is a duplicate (as per completionTag).
		return existingTicket;
	}
	if (existingProgress)
	{
		// Download already in progress.
		// Request added to listeners.
		return ticket;
	}
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	__weak typeof(self) weakSelf = self;
	
	// Deadlock warning:
	//
	// We may currently be inside a transaction.
	// As in, this method was invoked from inside a transaction.
	// So it's not safe to perform a synchronous read using the public roDatabaseConnection here.
	// We can either use our own dedicated databaseConnection, or simply perform it using an async transaction.
	//
	__block ZDCCloudLocator *cloudLocator = nil;
	[owner.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		cloudLocator =
		  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
		                                              fileExtension: kZDCCloudFileExtension_Data
		                                                transaction: transaction];
		
	} completionQueue:concurrentQueue completionBlock:^{
	
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		ZDCDownloadTicket *dependency =
		  [strongSelf downloadNodeHeader: node
		                        options: options
		         preFetchedCloudLocator: cloudLocator
		                completionQueue: concurrentQueue
		                completionBlock:^(ZDCCloudDataInfo *header, NSData *ignore1, NSData *ignore2, NSError *error)
		{
			if (error)
			{
				[weakSelf nodeMetaDownloadFailed: node.uuid
				                      components: components
				                           error: error];
			}
			else
			{
				[weakSelf _downloadNodeMeta: node
				                 components: components
				           withCloudLocator: cloudLocator
				                     header: header
				                   progress: progress
				                    options: options
				                  failCount: 0];
			}
		}];
		
		dispatch_sync(strongSelf->downloadQueue, ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			ZDCDownloadRef *ref = downloadDict[downloadKey];
			if (ref) {
				ref.dependency = dependency;
			}
			
		#pragma clang diagnostic pop
		}});
	}];
	
	return ticket;
}

- (void)_downloadNodeMeta:(ZDCNode *)node
               components:(ZDCNodeMetaComponents)components
         withCloudLocator:(ZDCCloudLocator *)cloudLocator
                   header:(ZDCCloudDataInfo *)header
                 progress:(ZDCProgress *)progress
                  options:(ZDCDownloadOptions *)options
                failCount:(NSUInteger)failCount
{
	DDLogAutoTrace();
	
	NSString *nodeID = node.uuid;
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__weak typeof(self) weakSelf = self;
	
	void (^failBlock)(NSError *) = ^(NSError *error) { @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeMetaDownloadFailed: nodeID
		                        components: components
		                             error: error];
	}};
	
	void (^successBlock)(void) = ^(){ @autoreleasepool {
		
		// Success here (within the context of this method),
		// means there wasn't anything to download.
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeMetaDownloadSucceeded: nodeID
		                           components: components
		                               header: header
		                             metadata: nil
		                            thumbnail: nil];
	}};
	
	BOOL hasCloudData = NO;
	
	const BOOL requestingMetadata = (components & ZDCNodeMetaComponents_Metadata) != 0;
	const BOOL requestingThumbnail = (components & ZDCNodeMetaComponents_Thumbnail) != 0;
	
	if (requestingMetadata && (header.metadataSize > 0)) {
		hasCloudData = YES;
	}
	if (requestingThumbnail && (header.thumbnailSize > 0)) {
		hasCloudData = YES;
	}
	
	if (!hasCloudData)
	{
		// This isn't an error.
		// But there's nothing for us to download.
		
		successBlock();
		return;
	}
	
	const size_t headerSize = sizeof(ZDCCloudFileHeader);
	
	NSUInteger byteOffset_data_start = 0;
	NSUInteger byteOffset_data_end = 0;
	
	if (requestingMetadata)
	{
		byteOffset_data_start = headerSize;
		byteOffset_data_end = byteOffset_data_start + header.metadataSize;
		
		if (requestingThumbnail) {
			byteOffset_data_end += header.thumbnailSize;
		}
	}
	else
	{
		byteOffset_data_start = headerSize + header.metadataSize;
		byteOffset_data_end = byteOffset_data_start + header.thumbnailSize;
	}
	
	// In order to decrypt the data, we need to follow the following rules:
	//
	// #1. The data must start on a tweak block boundry.
	//     These start every kZDCNode_TweakBlockSizeInBytes (== 1024) bytes.
	//     So our request must be evenly divisible by 1024.
	//
	// #2. The data length must be evenly divisible by encryptionKey.length bytes.
	//     This is because we're going to use a (tweakable) block cipher,
	//     which means we have to decrypt in blocks.
	//     And each block == encryptionKey.length bytes (usually for Threefish-512).
	
	NSUInteger byteOffset_request_start = 0;
	NSUInteger byteOffset_request_end = 0;
	
	NSUInteger tweakBlockIndex = (NSUInteger)(byteOffset_data_start / kZDCNode_TweakBlockSizeInBytes);
	byteOffset_request_start = tweakBlockIndex * kZDCNode_TweakBlockSizeInBytes;
	
	NSUInteger cipherBlockIndex = (NSUInteger)(byteOffset_data_end / node.encryptionKey.length);
	if ((byteOffset_data_end % node.encryptionKey.length) != 0) {
		cipherBlockIndex++;
	}
	byteOffset_request_end = cipherBlockIndex * kZDCNode_TweakBlockSizeInBytes;
	
	if (byteOffset_request_start == 0)
	{
		// We already have the header, so we don't need to download it again
		byteOffset_request_start = headerSize;
	}
	
	ZDCDownloadContext *context =
	  [[ZDCDownloadContext alloc] initWithLocalUserID: node.localUserID
	                                           nodeID: node.uuid
	                                           isMeta: YES
	                                       components: components
	                                          options: options];
	
	context.header = header;
	context.range_data = (NSRange){
		.location = byteOffset_data_start,
		.length = byteOffset_data_end - byteOffset_data_start
	};
	context.range_request = (NSRange){
		.location = byteOffset_request_start,
		.length = byteOffset_request_end - byteOffset_request_start
	};
	
	context.ephemeralInfo.node = node;
	context.ephemeralInfo.cloudLocator = cloudLocator;
	context.ephemeralInfo.progress = progress;
	context.ephemeralInfo.failCount = failCount;
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		AWSCredentialsManager *awsCredentialsManager = nil;
		{ // scoping
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf)
			{
				awsCredentialsManager = strongSelf->owner.awsCredentialsManager;
			}
		}
		
		[awsCredentialsManager getAWSCredentialsForUser: node.localUserID
		                                completionQueue: concurrentQueue
		                                completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use normal flow to execute exponential backoff.
					
					[weakSelf _downloadNodeMetaTaskDidComplete: nil
					                               withContext: context
					                                     error: error
					                              responseData: nil];
				}
				else
				{
					failBlock(error);
				}
			}
			else
			{
				[weakSelf _downloadNodeMeta: node
				                withContext: context
				                       auth: auth];
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

- (void)_downloadNodeMeta:(ZDCNode *)node
              withContext:(ZDCDownloadContext *)context
                     auth:(ZDCLocalUserAuth *)auth
{
	DDLogAutoTrace();
	
#if TARGET_OS_IPHONE
	BOOL canBackground = context.options.canDownloadWhileInBackground;
#else
	BOOL canBackground = NO;
#endif
	
	ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:node.localUserID];
#if TARGET_OS_IPHONE
	AFURLSessionManager *session =
	  canBackground ? sessionInfo.backgroundSession : sessionInfo.foregroundSession;
#else
	AFURLSessionManager *session = sessionInfo.session;
#endif
	
	ZDCCloudLocator *cloudLocator = context.ephemeralInfo.cloudLocator;
	
	NSMutableURLRequest *request =
	  [S3Request getObject: cloudLocator.cloudPath.path
	              inBucket: cloudLocator.bucket
	                region: cloudLocator.region
	      outUrlComponents: nil];
	
	[request setHTTPRange:context.range_request];
	[request setValue:context.header.eTag forHTTPHeaderField:@"If-Match"];
	
	[AWSSignature signRequest: request
	               withRegion: cloudLocator.region
	                  service: AWSService_S3
	              accessKeyID: auth.aws_accessKeyID
	                   secret: auth.aws_secret
	                  session: auth.aws_session];
	
	NSString *const resumeKey = [self resumeKeyForRequest:request];
	
	__block NSURLSessionDownloadTask *task = nil;
	if (canBackground)
	{
		// Background NSURLSession's don't really support data tasks.
		// So we have to download the tiny response to a file instead.
		
		NSCache<NSString*, NSData*> *resumeCache = resumeCache_background;
		
		NSData *resumeData = [resumeCache objectForKey:resumeKey];
		if (resumeData) {
			[resumeCache removeObjectForKey:resumeKey];
		}
		
		if (resumeData)
		{
			task = [session downloadTaskWithResumeData: resumeData
			                                  progress: nil
			                               destination: nil
			                         completionHandler: nil];
		}
		
		if (!task)
		{
			task = [session downloadTaskWithRequest: request
			                               progress: nil
			                            destination: nil
			                      completionHandler: nil];
		}
		
		[owner.sessionManager associateContext:context withTask:task inSession:session.session];
	}
	else
	{
		NSCache<NSString*, NSData*> *resumeCache = resumeCache_foreground;
		
		NSData *resumeData = [resumeCache objectForKey:resumeKey];
		if (resumeData) {
			[resumeCache removeObjectForKey:resumeKey];
		}
		
		NSURL *dstFileURL = [owner.directoryManager generateDownloadURL];
		NSURL* (^destinationHandler)(NSURL*, NSURLResponse*) =
			^(NSURL *targetPath, NSURLResponse *response)
		{
			return dstFileURL;
		};
		
		__weak typeof(self) weakSelf = self;
		void (^completionHandler)(NSURLResponse*, NSURL*, NSError*) =
			^(NSURLResponse *response, NSURL *downloadedFileURL, NSError *error)
		{
			NSData *responseData = nil;
			if (downloadedFileURL)
			{
				responseData = [NSData dataWithContentsOfURL:downloadedFileURL];
				[[NSFileManager defaultManager] removeItemAtURL:downloadedFileURL error:nil];
				
				if (responseData == nil) {
					error = [NSError errorWithClass: [ZDCDownloadManager class]
														code: 2001
											  description: @"Downloaded file disappeared before we could read it"];
				}
			}
			
			[weakSelf _downloadNodeMetaTaskDidComplete: task
			                               withContext: context
			                                     error: error
			                              responseData: responseData];
		};
		
		if (resumeData)
		{
			task = [session downloadTaskWithResumeData: resumeData
			                                  progress: nil
			                               destination: destinationHandler
			                         completionHandler: completionHandler];
		}
		
		if (!task)
		{
			task = [session downloadTaskWithRequest: request
			                               progress: nil
			                            destination: destinationHandler
			                      completionHandler: completionHandler];
		}
	}
	
	NSProgress *taskProgress = [session downloadProgressForTask:task];
	if (taskProgress)
	{
		[context.ephemeralInfo.progress addChild:taskProgress withPendingUnitCount:context.range_request.length];
	}
	
	NSString *downloadKey = [self downloadMetaKeyForNodeID:context.nodeID components:context.components];
	
	__block BOOL shouldStartTask = YES;
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		if (ref && ref.tickets.count > 0)
		{
			shouldStartTask = YES;
			ref.task = task;
			ref.isBackground = canBackground;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldStartTask)
	{
		[task resume];
	}
}

- (void)_downloadNodeMetaTaskDidComplete:(nullable NSURLSessionDownloadTask *)task
                             withContext:(ZDCDownloadContext *)context
                                   error:(nullable NSError *)error
                            responseData:(nullable NSData *)responseData
{
	DDLogAutoTrace();
	
	__weak typeof(self) weakSelf = self;
	
	void (^failBlock)(NSError *) =
		^(NSError *error) { @autoreleasepool
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeMetaDownloadFailed: context.nodeID
		                        components: context.components
		                             error: error];
	}};
	
	void (^successBlock)(NSData*, NSData*) =
	  ^(NSData *metadata, NSData *thumbnail) { @autoreleasepool
	{
		// Executing within concurrentQueue here
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf maybeCacheNodeThumbnail:thumbnail withContext:context];
		
		[strongSelf nodeMetaDownloadSucceeded: context.nodeID
		                           components: context.components
		                               header: context.header
		                             metadata: metadata
		                            thumbnail: thumbnail];
	}};
	
	NSURLResponse *urlResponse = task.response;
	NSInteger statusCode = [urlResponse httpStatusCode];
	
	if (urlResponse && error)
	{
		error = nil; // we only care about non-server-response errors
	}
	
	// Known status codes:
	//
	// - 200 : OK
	// - 206 : Partial Content     - due to Range header
	// - 403 : Forbidden
	// - 412 : Precondition Failed - due to If-None-Match header
	// - 503 : Slow Down           - we're being throttled
	
	if (error || (statusCode == 503))
	{
		// Try request again (using exponential backoff)
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		NSUInteger newFailCount = context.ephemeralInfo.failCount + 1;
		
		if (newFailCount > kMaxFailCount)
		{
			if (error == nil) {
				error = [NSError errorWithClass:[self class] code:503 description:@"Exceeded max retries"];
			}
			
			failBlock(error);
			return;
		}
		else
		{
			[self _downloadNodeMeta: context.ephemeralInfo.node
			             components: context.components
			       withCloudLocator: context.ephemeralInfo.cloudLocator
			                 header: context.header
			               progress: context.ephemeralInfo.progress
			                options: context.options
			              failCount: newFailCount];
		}
		
		return;
	}
	else if (statusCode == 401) // Unauthorized
	{
		// Authentication failed.
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		// We need to alert the user (so they can re-auth with valid credentials).
		//
		[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
		
		NSError *error =
		  [NSError errorWithClass:[self class] code:statusCode description:@"Unauthorized"];
		
		failBlock(error);
		return;
	}
	else if ((statusCode != 200) && (statusCode != 206) && (statusCode != 304))
	{
		// Download failed for some other reason - possibly unknown
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		// One would think AWS would return a 404 for files that no longer exist.
		// But one would be wrong !
		//
		// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
		
		if ((statusCode != 403) && (statusCode != 404) && (statusCode != 412))
		{
			DDLogError(@"AWS S3 returned unknown status code: %ld", (long)statusCode);
		}
		
		NSError *error =
		  [NSError errorWithClass:[self class] code:statusCode description:@"HTTP status code"];
		
		failBlock(error);
		return;
	}
	
	// We're currently executing on the AFNetworking session queue.
	// And decryption is comparatively slow.
	// So let's do it on a different queue.
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{ @autoreleasepool {
	
		ZDCNode *node = context.ephemeralInfo.node;
		ZDCCloudDataInfo *header = context.header;
		
		const size_t headerSize = sizeof(ZDCCloudFileHeader);
		
		const BOOL requestingMetadata = (context.components & ZDCNodeMetaComponents_Metadata) != 0;
		const BOOL requestingThumbnail = (context.components & ZDCNodeMetaComponents_Thumbnail) != 0;
		
		NSError *error = nil;
		NSData *metadata = nil;
		NSData *thumbnail = nil;
		
		if (context.range_request.location == headerSize)
		{
			// We downloaded from the very beginning of the file - excluding the header
			// since we already had it. Now we need to decypt it.
			// And to do so requires that we start at a "tweak block" boundry.
			// In this case, that's the beginning of the file.
			// So we need to prepend the encrypted header.
			
			NSData *prefix =
			  [Cleartext2CloudFileInputStream encryptCloudFileHeader: header.rawHeader
			                                       withEncryptionKey: node.encryptionKey
			                                                   error: &error];
			if (error) {
				failBlock(error);
				return;
			}
			
			NSMutableData *encryptedData =
			  [NSMutableData dataWithCapacity:(prefix.length + responseData.length)];
			[encryptedData appendData:prefix];
			[encryptedData appendData:responseData];
			
			[CloudFile2CleartextInputStream decryptCloudFileData: encryptedData
			                                   withEncryptionKey: node.encryptionKey
			                                              header: nil
			                                         rawMetadata: &metadata
			                                        rawThumbnail: &thumbnail
			                                               error: &error];
			if (error) {
				failBlock(error);
				return;
			}
		}
		else
		{
			// We downloaded from somewhere in the middle of the file.
			// So we're decrypting from some offset.
			
			NSData *decryptedData =
			  [CloudFile2CleartextInputStream decryptCloudFileBlocks: responseData
			                                          withByteOffset: context.range_request.location
			                                           encryptionKey: node.encryptionKey
			                                                   error: &error];
			if (error) {
				failBlock(error);
				return;
			}
			
			if (requestingMetadata && (header.metadataSize > 0))
			{
				NSRange range = (NSRange){
					.location = (headerSize + header.metadataSize)
					          - context.range_request.location,
					.length = context.header.metadataSize
				};
				
				metadata = [decryptedData subdataWithRange:range];
			}
			if (requestingThumbnail && (header.thumbnailSize > 0))
			{
				NSRange range = (NSRange){
					.location = (headerSize + header.metadataSize + header.thumbnailSize)
					          - context.range_request.location,
					.length = header.thumbnailSize
				};
				
				thumbnail = [decryptedData subdataWithRange:range];
			}
		}
	
		successBlock(metadata, thumbnail);
	}});
}

- (void)maybeCacheNodeThumbnail:(nullable NSData *)thumbnail
                    withContext:(ZDCDownloadContext *)context
{
	NSParameterAssert(context != nil);
	
	__block BOOL shouldCache = context.options.cacheToDiskManager;
	__block BOOL shouldSave = context.options.savePersistentlyToDiskManager;
	
	if (!shouldSave)
	{
		NSString *const downloadKey = [self downloadMetaKeyForNodeID:context.nodeID components:context.components];
		
		dispatch_sync(downloadQueue, ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			ZDCDownloadRef *ref = downloadDict[downloadKey];
			for (ZDCDownloadTicket *ticket in ref.tickets)
			{
				if (!shouldCache && ticket.options.cacheToDiskManager) {
					shouldCache = YES;
				}
				if (!shouldSave && ticket.options.savePersistentlyToDiskManager) {
					shouldSave = YES;
				}
			}
			
		#pragma clang diagnostic pop
		}});
	}
	
	if (shouldCache || shouldSave)
	{
		ZDCDiskImport *import = nil;
		if (thumbnail) {
			import = [[ZDCDiskImport alloc] initWithCleartextData:thumbnail];
		} else {
			import = [[ZDCDiskImport alloc] init];
		}
		import.storePersistently = shouldSave;
		import.eTag = context.header.eTag;
		
		[owner.diskManager importNodeThumbnail: import
		                               forNode: context.ephemeralInfo.node
		                                 error: nil];
	}
}

- (void)nodeMetaDownloadFailed:(NSString *)nodeID
                    components:(ZDCNodeMetaComponents)components
                         error:(NSError *)error
{
	NSString *const downloadKey = [self downloadMetaKeyForNodeID:nodeID components:components];
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		downloadDict[downloadKey] = nil;
		[owner.progressManager removeMetaDownloadProgressForNodeID: nodeID
		                                                components: components
		                                                withHeader: nil
		                                                  metadata: nil
		                                                 thumbnail: nil
		                                                     error: error];
	#pragma clang diagnostic pop
	}});
}

- (void)nodeMetaDownloadSucceeded:(NSString *)nodeID
                       components:(ZDCNodeMetaComponents)components
                           header:(ZDCCloudDataInfo *)header
                         metadata:(nullable NSData *)metadata
                        thumbnail:(nullable NSData *)thumbnail
{
	NSString *const downloadKey = [self downloadMetaKeyForNodeID:nodeID components:components];
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		downloadDict[downloadKey] = nil;
		[owner.progressManager removeMetaDownloadProgressForNodeID: nodeID
		                                                components: components
		                                                withHeader: header
		                                                  metadata: metadata
		                                                 thumbnail: thumbnail
		                                                     error: nil];
	#pragma clang diagnostic pop
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (ZDCDownloadTicket *)downloadNodeData:(ZDCNode *)node
                                options:(nullable ZDCDownloadOptions *)inOptions
                        completionQueue:(nullable dispatch_queue_t)completionQueue
                        completionBlock:(NodeDataDownloadCompletionBlock)completionBlock
{
	DDLogAutoTrace();
	
	if (!node.isImmutable) {
		node = [node immutableCopy];
	}
	
	ZDCDownloadOptions *options = [inOptions copy];
	if (options == nil)
	{
		options = [[ZDCDownloadOptions alloc] init];
	}
	
	if (node == nil)
	{
		NSString *msg = @"Invalid parameter: node doesn't exist in the database";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(nil, nil, error);
			}});
		}
		return [[ZDCDownloadTicket alloc] init];
	}
	
	NSString *const downloadKey = node.uuid;
	
	__block ZDCDownloadTicket *existingTicket = nil;
	__block ZDCDownloadTicket *ticket = nil;
	
	__block NSProgress *existingProgress = nil;
	__block ZDCProgress *progress = nil;
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		
		if (options.completionTag && ref)
		{
			for (ZDCDownloadTicket *ticket in ref.tickets)
			{
				if ([ticket.options.completionTag isEqualToString:options.completionTag])
				{
					existingTicket = ticket;
					break;
				}
			}
		}
		
		if (existingTicket == nil)
		{
			ticket = [[ZDCDownloadTicket alloc] initWithOwner: self
			                                           nodeID: node.uuid
			                                          options: options
			                                  completionBlock: completionBlock];
			
			progress = [[ZDCProgress alloc] init];
		
			[owner.progressManager setDataDownloadProgress: progress
			                                     forNodeID: node.uuid
			                                   localUserID: node.localUserID
			                              existingProgress: &existingProgress
			                               completionQueue: completionQueue
			                               completionBlock: completionBlock];
	
			if (existingProgress) {
				ticket.progress = existingProgress;
			}
			else {
				ticket.progress = progress;
			}
	
			if (!ref) {
				ref = downloadDict[downloadKey] = [[ZDCDownloadRef alloc] init];
			}
			[ref.tickets addObject:ticket];
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (existingTicket)
	{
		// Download already in progress.
		// Request is a duplicate (as per completionTag).
		return existingTicket;
	}
	if (existingProgress)
	{
		// Download already in progress.
		// Request added to listeners.
		return ticket;
	}
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	__weak typeof(self) weakSelf = self;
	__block ZDCCloudLocator *cloudLocator = nil;
	
	// Deadlock warning:
	//
	// We may currently be inside a transaction.
	// As in, this method was invoked from inside a transaction.
	// So it's not safe to perform a synchronous read using the public roDatabaseConnection here.
	// We can either use our own dedicated databaseConnection, or simply perform it using an async transaction.
	//
	[owner.databaseManager.roDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		cloudLocator =
		  [[ZDCCloudPathManager sharedInstance] cloudLocatorForNode: node
		                                              fileExtension: kZDCCloudFileExtension_Data
		                                                transaction: transaction];
		
	} completionQueue:concurrentQueue completionBlock:^{
	
		[weakSelf _downloadNodeData: node
		           withCloudLocator: cloudLocator
		                   progress: progress
		                    options: options
		                  failCount: 0];
	}];
	
	return ticket;
}

/**
 * Performs the actual download logic including:
 * - retry with exponential backoff
 * - decryption
 * - updating node in database (as needed)
 * - popping completionBlock(s) from ProgressManager
 */
- (void)_downloadNodeData:(ZDCNode *)node
         withCloudLocator:(nullable ZDCCloudLocator *)cloudLocator
                 progress:(ZDCProgress *)progress
                  options:(ZDCDownloadOptions *)options
                failCount:(NSUInteger)failCount
{
	DDLogAutoTrace();
	
	NSString *const nodeID = node.uuid;
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__weak typeof(self) weakSelf = self;
	
	void (^failBlock)(NSError *) = ^(NSError *error) { @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeDataDownloadFailed:nodeID error:error];
	}};
	
	if (cloudLocator == nil)
	{
		NSString *msg = @"Invalid parameter: node is misconfigured - unable to determine cloud URL";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		failBlock(error);
		return;
	}
	
	ZDCDownloadContext *context =
	  [[ZDCDownloadContext alloc] initWithLocalUserID: node.localUserID
	                                           nodeID: node.uuid
	                                           isMeta: NO
	                                       components: ZDCNodeMetaComponents_All
	                                          options: options];
	
	context.ephemeralInfo.node = node;
	context.ephemeralInfo.cloudLocator = cloudLocator;
	context.ephemeralInfo.progress = progress;
	context.ephemeralInfo.failCount = failCount;
	
	dispatch_block_t requestBlock = ^{ @autoreleasepool {
		
		AWSCredentialsManager *awsCredentialsManager = nil;
		{ // scoping
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf)
			{
				awsCredentialsManager = strongSelf->owner.awsCredentialsManager;
			}
		}
		
		[awsCredentialsManager getAWSCredentialsForUser: node.localUserID
		                                completionQueue: concurrentQueue
		                                completionBlock:^(ZDCLocalUserAuth *auth, NSError *error)
		{
			if (error)
			{
				if ([error.auth0API_error isEqualToString:kAuth0Error_RateLimit])
				{
					// Auth0 is rate limiting us.
					// Use normal flow to execute exponential backoff.
					
					[weakSelf _downloadNodeDataTaskDidComplete: nil
					                               withContext: context
					                                     error: error
					                         downloadedFileURL: nil];
				}
				else
				{
					failBlock(error);
				}
			}
			else
			{
				[weakSelf _downloadNodeData: node
				                withContext: context
				                       auth: auth];
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

- (void)_downloadNodeData:(ZDCNode *)node
              withContext:(ZDCDownloadContext *)context
                     auth:(ZDCLocalUserAuth *)auth
{
	DDLogAutoTrace();
	
#if TARGET_OS_IPHONE
	BOOL canBackground = context.options.canDownloadWhileInBackground;
#else
	BOOL canBackground = NO;
#endif
	
	ZDCSessionInfo *sessionInfo = [owner.sessionManager sessionInfoForUserID:node.localUserID];
#if TARGET_OS_IPHONE
	AFURLSessionManager *session =
	  canBackground ? sessionInfo.backgroundSession : sessionInfo.foregroundSession;
#else
	AFURLSessionManager *session = sessionInfo.session;
#endif
	
	ZDCCloudLocator *cloudLocator = context.ephemeralInfo.cloudLocator;
	
	NSMutableURLRequest *request =
	  [S3Request getObject: cloudLocator.cloudPath.path
	              inBucket: cloudLocator.bucket
	                region: cloudLocator.region
	      outUrlComponents: nil];

	[AWSSignature signRequest: request
	               withRegion: cloudLocator.region
	                  service: AWSService_S3
	              accessKeyID: auth.aws_accessKeyID
	                   secret: auth.aws_secret
	                  session: auth.aws_session];

	NSString *const resumeKey = [self resumeKeyForRequest:request];
	
	__block NSURLSessionDownloadTask *task = nil;
	if (canBackground)
	{
		// Background NSURLSession.
		// Need to use delegate based approach.
		
		NSCache<NSString*, NSData*> *resumeCache = resumeCache_background;
		
		NSData *resumeData = [resumeCache objectForKey:resumeKey];
		if (resumeData) {
			[resumeCache removeObjectForKey:resumeKey];
		}
		
		if (resumeData)
		{
			task = [session downloadTaskWithResumeData: resumeData
			                                  progress: nil
			                               destination: nil
			                         completionHandler: nil];
		}
		
		if (!task)
		{
			task = [session downloadTaskWithRequest: request
			                               progress: nil
			                            destination: nil
			                      completionHandler: nil];
		}
		
		[owner.sessionManager associateContext:context withTask:task inSession:session.session];
	}
	else
	{
		NSCache<NSString*, NSData*> *resumeCache = resumeCache_foreground;
		
		NSData *resumeData = [resumeCache objectForKey:resumeKey];
		if (resumeData) {
			[resumeCache removeObjectForKey:resumeKey];
		}
		
		NSURL *dstFileURL = [owner.directoryManager generateDownloadURL];
		NSURL* (^destinationHandler)(NSURL*, NSURLResponse*) =
			^(NSURL *targetPath, NSURLResponse *response)
		{
			return dstFileURL;
		};
		
		__weak typeof(self) weakSelf = self;
		void (^completionHandler)(NSURLResponse*, NSURL*, NSError*) =
			^(NSURLResponse *response, NSURL *downloadedFileURL, NSError *error)
		{
			[weakSelf _downloadNodeDataTaskDidComplete: task
			                               withContext: context
			                                     error: error
			                         downloadedFileURL: downloadedFileURL];
		};
		
		if (resumeData)
		{
			task = [session downloadTaskWithResumeData: resumeData
			                                  progress: nil
			                               destination: destinationHandler
			                         completionHandler: completionHandler];
		}
		
		if (!task)
		{
			task = [session downloadTaskWithRequest: request
				                            progress: nil
				                         destination: destinationHandler
			                      completionHandler: completionHandler];
		}
	}

	NSProgress *taskProgress = [session downloadProgressForTask:task];
	if (taskProgress)
	{
		[context.ephemeralInfo.progress addChild: taskProgress
		                    withPendingUnitCount: 0/* < dynamic: use child.totalUnitCount */];
	}

	NSString *const downloadKey = context.nodeID;
	__block BOOL shouldStartTask = YES;
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		if (ref && ref.tickets.count > 0)
		{
			shouldStartTask = YES;
			ref.task = task;
			ref.isBackground = canBackground;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldStartTask)
	{
		[task resume];
	}
}

- (void)_downloadNodeDataTaskDidComplete:(nullable NSURLSessionDownloadTask *)task
                             withContext:(ZDCDownloadContext *)context
                                   error:(nullable NSError *)error
                       downloadedFileURL:(nullable NSURL *)downloadedFileURL
{
	DDLogAutoTrace();
	
	NSString *const nodeID = context.nodeID;
	
	__weak typeof(self) weakSelf = self;
	
	void (^failBlock)(NSError *) = ^(NSError *error) { @autoreleasepool {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf nodeDataDownloadFailed:nodeID error:error];
	}};
	
	void (^successBlock)(ZDCCloudDataInfo*, ZDCCryptoFile*) =
	  ^(ZDCCloudDataInfo *info, ZDCCryptoFile *cryptoFile) { @autoreleasepool
	{
		// Executing within concurrentQueue here
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		cryptoFile = [strongSelf maybeCacheNodeData:cryptoFile withContext:context eTag:info.eTag];
		
		[strongSelf nodeDataDownloadSucceeded:nodeID header:info cryptoFile:cryptoFile];
	}};
	
	NSURLResponse *urlResponse = task.response;
	NSInteger statusCode = [urlResponse httpStatusCode];
	
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
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		NSUInteger newFailCount = context.ephemeralInfo.failCount + 1;
		
		if (newFailCount > kMaxFailCount)
		{
			if (error == nil) {
				error = [NSError errorWithClass:[self class] code:503 description:@"Exceeded max retries"];
			}
			
			failBlock(error);
			return;
		}
		else
		{
			[context.ephemeralInfo.progress removeAllChildrenAndIncrementBaseUnitCount:NO];
			
			[self _downloadNodeData: context.ephemeralInfo.node
			       withCloudLocator: context.ephemeralInfo.cloudLocator
			               progress: context.ephemeralInfo.progress
			                options: context.options
			              failCount: newFailCount];
		}
		
		return;
	}
	else if (statusCode == 401) // Unauthorized
	{
		// Authentication failed.
		//
		// We need to alert the user (so they can re-auth with valid credentials).
		
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		[owner.networkTools handleAuthFailureForUser:context.localUserID withError:error];
		
		NSError *error =
		  [NSError errorWithClass:[self class] code:statusCode description:@"Unauthorized"];
		
		failBlock(error);
		return;
	}
	else if ((statusCode != 200) && (statusCode != 206) && (statusCode != 304))
	{
		if (context.ephemeralInfo.progress == nil) {
			// Download failed in between app launches - ignore
			return;
		}
		
		// One would think AWS would return a 404 for files that no longer exist.
		// But one would be wrong !
		//
		// If the keyPath doesn't exist in the bucket, then S3 returns a 403 !
		
		if ((statusCode != 403) && (statusCode != 404))
		{
			DDLogError(@"AWS S3 returned unknown status code: %ld", (long)statusCode);
		}
		
		NSError *error =
		  [NSError errorWithClass:[self class] code:statusCode description:@"HTTP status code"];
		
		failBlock(error);
		return;
	}
	
	// We're currently executing on the AFNetworking session queue.
	// And decryption is comparatively slow.
	// So let's do it on a different queue.
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{ @autoreleasepool {
	
		ZDCNode *node = context.ephemeralInfo.node;
	
		ZDCCloudFileHeader header;
		bzero(&header, sizeof(header));
	
		NSError *decryptionError = nil;
		[CloudFile2CleartextInputStream decryptCloudFileURL: downloadedFileURL
		                                  withEncryptionKey: node.encryptionKey
		                                             header: &header
		                                        rawMetadata: nil
		                                       rawThumbnail: nil
		                                              error: &decryptionError];
		if (decryptionError)
		{
			failBlock(decryptionError);
			return;
		}
	
		NSString *eTag = [urlResponse eTag] ?: @"";
		NSDate *lastModified = [urlResponse lastModified] ?: [NSDate date];
	
		ZDCCloudDataInfo *info =
		  [[ZDCCloudDataInfo alloc] initWithCloudFileHeader: header
		                                               eTag: eTag
		                                       lastModified: lastModified];
	
		ZDCCryptoFile *cryptoFile =
		  [[ZDCCryptoFile alloc] initWithFileURL: downloadedFileURL
		                              fileFormat: ZDCCryptoFileFormat_CloudFile
		                           encryptionKey: node.encryptionKey
		                             retainToken: nil];
		
		[weakSelf updateDatabaseWithCloudDataInfo: info
		                                forNodeID: nodeID
		                          completionQueue: concurrentQueue
		                          completionBlock:
		^{
			successBlock(info, cryptoFile);
		}];
	}});
}

- (ZDCCryptoFile *)maybeCacheNodeData:(ZDCCryptoFile *)cryptoFile
                          withContext:(ZDCDownloadContext *)context
                                 eTag:(NSString *)eTag
{
	NSParameterAssert(cryptoFile != nil);
	NSParameterAssert(context != nil);
	
	__block BOOL shouldCache = context.options.cacheToDiskManager;
	__block BOOL shouldSave = context.options.savePersistentlyToDiskManager;
	
	if (!shouldSave)
	{
		NSString *const downloadKey = context.nodeID;
		
		dispatch_sync(downloadQueue, ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			ZDCDownloadRef *ref = downloadDict[downloadKey];
			for (ZDCDownloadTicket *ticket in ref.tickets)
			{
				if (!shouldCache && ticket.options.cacheToDiskManager) {
					shouldCache = YES;
				}
				if (!shouldSave && ticket.options.savePersistentlyToDiskManager) {
					shouldSave = YES;
				}
			}
			
		#pragma clang diagnostic pop
		}});
	}
	
	ZDCCryptoFile *result = nil;
	if (shouldCache || shouldSave)
	{
		ZDCDiskImport *import = [[ZDCDiskImport alloc] initWithCryptoFile:cryptoFile];
		import.storePersistently = shouldSave;
		import.eTag = eTag;
		
		result = [owner.diskManager importNodeData: import
		                                   forNode: context.ephemeralInfo.node
		                                     error: nil];
	}
	
	return (result ?: cryptoFile);
}

- (void)nodeDataDownloadFailed:(NSString *)nodeID error:(NSError *)error
{
	NSString *const downloadKey = [nodeID copy];
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		downloadDict[downloadKey] = nil;
		[owner.progressManager removeDataDownloadProgressForNodeID: nodeID
		                                                withHeader: nil
		                                                cryptoFile: nil
		                                                     error: error];
		
	#pragma clang diagnostic pop
	}});
}

- (void)nodeDataDownloadSucceeded:(NSString *)nodeID
                           header:(ZDCCloudDataInfo *)header
                       cryptoFile:(ZDCCryptoFile *)cryptoFile
{
	NSString *const downloadKey = [nodeID copy];
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
		downloadDict[downloadKey] = nil;
		[owner.progressManager removeDataDownloadProgressForNodeID: nodeID
		                                                withHeader: header
		                                                cryptoFile: cryptoFile
		                                                     error: nil];
		
	#pragma clang diagnostic pop
	}});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Avatar
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for documentation.
 */
- (ZDCDownloadTicket *)downloadUserAvatar:(ZDCUser *)user
                                  auth0ID:(nullable NSString *)auth0ID
                                  options:(nullable ZDCDownloadOptions *)options
                          completionQueue:(nullable dispatch_queue_t)completionQueue
                          completionBlock:(UserAvatarDownloadCompletionBlock)completionBlock
{
	DDLogAutoTrace();
	
	if (!auth0ID) {
		auth0ID = user.auth0_preferredID;
	}
	if (!auth0ID) {
		auth0ID = [Auth0Utilities firstAvailableAuth0IDFromProfiles:user.auth0_profiles];
	}
	
	NSDictionary *profile = nil;
	if (auth0ID) {
		profile = user.auth0_profiles[auth0ID];
	}
	
	NSError *error = nil;
	
	if (user == nil)
	{
		NSString *msg = @"Invalid parameter: user is nil";
		error = [NSError errorWithClass:[self class] code:400 description:msg];
	}
	else if (auth0ID == nil)
	{
		NSString *msg = @"Invalid parameter: user is missing all social profiles";
		error = [NSError errorWithClass:[self class] code:400 description:msg];
	}
	else if (profile == nil)
	{
		NSString *msg = @"Invalid parameter: user is missing profile for auth0ID";
		error = [NSError errorWithClass:[self class] code:400 description:msg];
	}
	
	if (error)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(nil, error);
			}});
		}
		return [[ZDCDownloadTicket alloc] init];
	}
	
	NSString *picture =
	  [Auth0Utilities correctPictureForAuth0ID: auth0ID
	                               profileData: profile
	                                    region: user.aws_region
	                                    bucket: user.aws_bucket];
	
	NSURL *url = nil;
	if (picture) {
		url = [NSURL URLWithString:picture];
	}
	
	if (url == nil)
	{
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(nil, nil);
			}});
		}
		return [[ZDCDownloadTicket alloc] init];
	}
	
	return [self _downloadUserAvatar: user
	                         auth0ID: auth0ID
	                         fromURL: url
	                         options: options
	                 completionQueue: completionQueue
	                 completionBlock: completionBlock];
}

/**
 * Internal method.
 * Exposed via ZDCDownloadManagerPrivate.
 */
- (ZDCDownloadTicket *)downloadUserAvatar:(NSString *)userID
                                  auth0ID:(NSString *)auth0ID
                                  fromURL:(NSURL *)url
                                  options:(nullable ZDCDownloadOptions *)inOptions
                          completionQueue:(nullable dispatch_queue_t)completionQueue
                          completionBlock:(UserAvatarDownloadCompletionBlock)completionBlock
{
	return [self _downloadUserAvatar: userID
	                         auth0ID: auth0ID
	                         fromURL: url
	                         options: inOptions
	                 completionQueue: completionQueue
	                 completionBlock: completionBlock];
}

- (ZDCDownloadTicket *)_downloadUserAvatar:(id)userOrUserID
                                   auth0ID:(NSString *)auth0ID
                                   fromURL:(NSURL *)url
                                   options:(nullable ZDCDownloadOptions *)inOptions
                           completionQueue:(nullable dispatch_queue_t)completionQueue
                           completionBlock:(UserAvatarDownloadCompletionBlock)completionBlock
{
	DDLogAutoTrace();
	
	ZDCUser *user = nil;
	NSString *userID = nil;
	
	if ([userOrUserID isKindOfClass:[ZDCUser class]])
	{
		user = (ZDCUser *)userOrUserID;
		userID = user.uuid;
	}
	else
	{
		userID = [(NSString *)userOrUserID copy]; // mutable string protection
	}
	
	auth0ID = [auth0ID copy]; // mutable string protection
	
	ZDCDownloadOptions *options = [inOptions copy];
	if (options == nil)
	{
		options = [[ZDCDownloadOptions alloc] init];
		options.cacheToDiskManager = YES;
	}
	
	NSString *downloadKey = [self downloadKeyForUserID:userID auth0ID:auth0ID];
	ZDCDownloadTicket *ticket =
	  [[ZDCDownloadTicket alloc] initWithOwner: self
	                                    userID: userID
	                                   auth0ID: auth0ID
	                                   options: options
	                           completionQueue: completionQueue
	                           completionBlock: completionBlock];
	
	__block BOOL shouldDownload = YES;
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		if (ref) {
			shouldDownload = NO;
		}
		else {
			ref = downloadDict[downloadKey] = [[ZDCDownloadRef alloc] init];
		}
		
		[ref.tickets addObject:ticket];
		
	#pragma clang diagnostic pop
	}});
	
	if (!shouldDownload) {
		return ticket;
	}
	
	NSURLSession *session = [NSURLSession sharedSession];
	
	__weak typeof(self) weakSelf = self;
	NSURLSessionDataTask *task =
	  [session dataTaskWithURL: url
				completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		NSInteger statusCode = response.httpStatusCode;
		NSString *eTag = response.eTag;
		
		if ((statusCode != 200) && data)
		{
			// data is actually an error message (in XML or JSON format)
			data = nil;
		}
		
		if (user && !error)
		{
			[strongSelf maybeCacheUserAvatar:data forUser:user withAuth0ID:auth0ID eTag:eTag];
		}
		
		[strongSelf _downloadUserAvatarDidComplete: userID
		                                   auth0ID: auth0ID
		                                  withData: data
		                                     error: error];
	}];
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		ref.task = task;
		
	#pragma clang diagnostic pop
	}});
	
	[task resume];
	return ticket;
}

- (void)_downloadUserAvatarDidComplete:(NSString *)userID
                               auth0ID:(NSString *)auth0ID
                              withData:(nullable NSData *)data
                                 error:(nullable NSError *)error
{
	NSString *downloadKey = [self downloadKeyForUserID:userID auth0ID:auth0ID];
	
	__block NSArray<ZDCDownloadTicket*> *tickets = nil;
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		if (ref)
		{
			tickets = ref.tickets;
			downloadDict[downloadKey] = nil;
		}
		
	#pragma clang diagnostic pop
	}});
	
	for (ZDCDownloadTicket *ticket in tickets)
	{
		__strong UserAvatarDownloadCompletionBlock completionBlock = ticket.completionBlock;
		if (completionBlock)
		{
			dispatch_async(ticket.completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				completionBlock(data, error);
			}});
		}
	}
}

- (void)maybeCacheUserAvatar:(nullable NSData *)data
                     forUser:(ZDCUser *)user
                 withAuth0ID:(NSString *)auth0ID
                        eTag:(NSString *)eTag
{
	NSParameterAssert(user != nil);
	NSParameterAssert(auth0ID != nil);
	
	NSString *downloadKey = [self downloadKeyForUserID:user.uuid auth0ID:auth0ID];
	
	__block BOOL shouldCache = NO;
	__block BOOL shouldSave = NO;
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		for (ZDCDownloadTicket *ticket in ref.tickets)
		{
			if (!shouldCache && ticket.options.cacheToDiskManager) {
				shouldCache = YES;
			}
			if (!shouldSave && ticket.options.savePersistentlyToDiskManager) {
				shouldSave = YES;
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldCache || shouldSave)
	{
		ZDCDiskImport *import = nil;
		if (data) {
			import = [[ZDCDiskImport alloc] initWithCleartextData:data];
		} else {
			import = [[ZDCDiskImport alloc] init];
		}
		import.storePersistently = shouldSave;
		import.eTag = eTag;
		
		[owner.diskManager importUserAvatar: import
		                            forUser: user
		                            auth0ID: auth0ID
		                              error: nil];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cancellation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)processTicketRequest:(ZDCDownloadTicket *)sender isCancellation:(BOOL)isCancellation
{
	if (sender.completionBlock)
	{
		if (sender.isMeta)
		{
			[owner.progressManager removeMetaDownloadListenerForNodeID: sender.nodeID
			                                                components: sender.components
			                                           completionBlock: sender.completionBlock];
		}
		else
		{
			[owner.progressManager removeDataDownloadListenerForNodeID: sender.nodeID
			                                           completionBlock: sender.completionBlock];
		}
	}
	
	NSString* (^downloadKeyForTicket)(ZDCDownloadTicket*) = ^(ZDCDownloadTicket *ticket){
		
		if (sender.isUser)
			return [self downloadKeyForUserID:ticket.userID auth0ID:ticket.auth0ID];
		else if (sender.isMeta)
			return [self downloadMetaKeyForNodeID:ticket.nodeID components:ticket.components];
		else
			return ticket.nodeID;
	};
	
	typedef NS_ENUM(NSInteger, ProcessTicketResult) {
		ProcessTicketResult_None,
		ProcessTicketResult_Cancelled,
		ProcessTicketResult_Ignored,
	};
	
	ProcessTicketResult (^processTicket)(ZDCDownloadTicket*, BOOL, ZDCDownloadTicket**) =
		^ProcessTicketResult (ZDCDownloadTicket *ticket, BOOL isCancellation, ZDCDownloadTicket **outDependency)
	{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		// Invoked within the downloadQueue
		
		NSString *downloadKey = downloadKeyForTicket(ticket);
		
		ZDCDownloadRef *ref = downloadDict[downloadKey];
		if (!ref) return ProcessTicketResult_None;
		
		// When a ticket is cancelled : remove from array
		// When a ticket is ignored   : remain in array
		//
		if (isCancellation) // <- refers to block parameter
		{
			[ref.tickets removeObjectIdenticalTo:sender];
		}
		
		BOOL allCancelled = (ref.tickets.count == 0);
		if (allCancelled)
		{
			NSString *resumeKey = [self resumeKeyForRequest:ref.task.originalRequest];
			
			[self cancelTask:ref.task withResumeKey:resumeKey isBackground:ref.isBackground];
			
			if (outDependency) *outDependency = ref.dependency;
			return ProcessTicketResult_Cancelled;
		}
		else
		{
			BOOL allIgnored = YES;
			for (ZDCDownloadTicket *ticket in ref.tickets)
			{
				if (!ticket.isIgnored)
				{
					allIgnored = NO;
					break;
				}
			}
			
			if (allIgnored)
			{
				ref.task.priority = NSURLSessionTaskPriorityLow;
				
				if (outDependency) *outDependency = ref.dependency;
				return ProcessTicketResult_Ignored;
			}
		}
		
		if (outDependency) *outDependency = nil;
		return ProcessTicketResult_None;
		
	#pragma clang diagnostic pop
	};
	
	dispatch_sync(downloadQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCDownloadTicket *dependency = nil;
		ProcessTicketResult result = processTicket(sender, isCancellation, &dependency);
		
		if (dependency)
		{
			// Note: We do NOT remove the listener for the dependency.
			// That listener is our code block, and we want it to get called.
			
			if (result == ProcessTicketResult_Cancelled)
			{
				processTicket(dependency, YES, nil);
			}
			else if (result == ProcessTicketResult_Ignored)
			{
				processTicket(dependency, NO, nil);
			}
		}
		
	#pragma clang diagnostic pop
	}});
}

- (void)cancelTask:(NSURLSessionTask *)task withResumeKey:(NSString *)resuemKey isBackground:(BOOL)isBackground
{
	if (task == nil) return;
	
	if (![task isKindOfClass:[NSURLSessionDownloadTask class]])
	{
		[task cancel];
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	[(NSURLSessionDownloadTask *)task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
		
		if (resumeData == nil) {
			return;
		}
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			if (isBackground)
				[strongSelf->resumeCache_background setObject:resumeData forKey:resuemKey];
			else
				[strongSelf->resumeCache_foreground setObject:resumeData forKey:resuemKey];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Background Downloads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)downloadTaskDidComplete:(NSURLSessionDownloadTask *)task
                      inSession:(NSURLSession *)session
                    withContext:(ZDCDownloadContext *)context
                          error:(NSError *)error
              downloadedFileURL:(NSURL *)downloadedFileURL
{
	DDLogAutoTrace();
	
#if TARGET_OS_IOS
	BOOL needsNotifyZeroDarkCloudDelegate = NO;
	
	__block ZDCNode *node = nil;
	__block ZDCTreesystemPath *path = nil;
	
	if (!error && !context.ephemeralInfo.node)
	{
		// We're being notified about a background download,
		// -- AND -- the background download spans multiple app launches.
		//
		// In other words:
		// - client requests download (using background session)
		// - download starts
		// - app is backgrounded
		// - app is killed
		// - download completes
		// - app is relaunched
		// - we're being asked to process the download at this point
		//
		// This means 2 things for us:
		//
		// 1. We need to fetch the node (the encryptionKey will be needed by various handlers)
		// 2. There isn't a completionBlock setup to handle the completed download,
		//    so we need to go through the ZeroDarkCloudDelegate.
		
		needsNotifyZeroDarkCloudDelegate = YES;
		
		[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			node = [transaction objectForKey:context.nodeID inCollection:kZDCCollection_Nodes];
			
			if (node) {
				path = [[ZDCNodeManager sharedInstance] pathForNode:node transaction:transaction];
			}
		}];
		
		if (!node || !path)
		{
			// Nothing much we can do here.
			
			[[NSFileManager defaultManager] removeItemAtURL:downloadedFileURL error:nil];
			return;
		}
		
		context.ephemeralInfo.node = node;
	}
#endif
	
	if (context.isMeta)
	{
		NSData *responseData = nil;
		if (downloadedFileURL)
		{
			responseData = [NSData dataWithContentsOfURL:downloadedFileURL];
			[[NSFileManager defaultManager] removeItemAtURL:downloadedFileURL error:nil];
			
			if (responseData == nil) {
				error = [NSError errorWithClass: [self class]
				                           code: 2001
				                    description: @"Downloaded file disappeared before we could read it"];
			}
		}
		
	#if TARGET_OS_IOS
		if (needsNotifyZeroDarkCloudDelegate)
		{
			[self installDelegateInvocationForMetaContext:context path:path];
		}
	#endif
		
		if (context.components == ZDCNodeMetaComponents_Header)
		{
			[self _downloadNodeHeaderTaskDidComplete: task
			                             withContext: context
			                                   error: error
			                            responseData: responseData];
		}
		else
		{
			
			[self _downloadNodeMetaTaskDidComplete: task
			                           withContext: context
			                                 error: error
			                          responseData: responseData];
		}
	}
	else
	{
	#if TARGET_OS_IOS
		if (needsNotifyZeroDarkCloudDelegate)
		{
			[self installDelegateInvocationForDataContext:context path:path];
		}
	#endif
		
		[self _downloadNodeDataTaskDidComplete: task
		                           withContext: context
		                                 error: error
		                     downloadedFileURL: downloadedFileURL];
	}
}

#if TARGET_OS_IOS
- (void)installDelegateInvocationForMetaContext:(ZDCDownloadContext *)context
                                           path:(ZDCTreesystemPath *)path
{
	DDLogAutoTrace();
	NSParameterAssert(context.isMeta);
	
	NSProgress *progress = [[NSProgress alloc] init];
	progress.totalUnitCount = 1;
	progress.completedUnitCount = 1;
	
	__weak ZeroDarkCloud *owner = self->owner;
	
	[owner.progressManager setMetaDownloadProgress: progress
	                                     forNodeID: context.nodeID
	                                    components: context.components
	                                   localUserID: context.localUserID];
	
	[owner.progressManager addMetaDownloadListenerForNodeID: context.nodeID
														 completionQueue: nil
														 completionBlock:
	^(ZDCCloudDataInfo *header, NSData *metadata, NSData *thumbnail, NSError *error)
	{
		if (error) return; // ignore
		
		id<ZeroDarkCloudDelegate> delegate = owner.delegate;
		
		if ([delegate respondsToSelector:
		      @selector(didBackgroundDownloadNodeMeta:atPath:withComponents:header:metadata:thumbnail:)])
		{
			[delegate didBackgroundDownloadNodeMeta: context.ephemeralInfo.node
			                                 atPath: path
			                         withComponents: context.components
			                                 header: header
			                               metadata: metadata
			                              thumbnail: thumbnail];
		}
	}];
}

- (void)installDelegateInvocationForDataContext:(ZDCDownloadContext *)context
                                           path:(ZDCTreesystemPath *)path
{
	DDLogAutoTrace();
	NSParameterAssert(!context.isMeta);
	
	NSProgress *progress = [[NSProgress alloc] init];
	progress.totalUnitCount = 1;
	progress.completedUnitCount = 1;
	
	__weak ZeroDarkCloud *owner = self->owner;
	
	[owner.progressManager setDataDownloadProgress: progress
	                                     forNodeID: context.nodeID
	                                   localUserID: context.localUserID];
	
	[owner.progressManager addDataDownloadListenerForNodeID: context.nodeID
	                                        completionQueue: nil
	                                        completionBlock:
	^(ZDCCloudDataInfo *header, ZDCCryptoFile *cryptoFile, NSError *error)
	{
		if (error) return; // ignore
		
		id<ZeroDarkCloudDelegate> delegate = owner.delegate;
		
		if ([delegate respondsToSelector:
		      @selector(didBackgroundDownloadNodeData:atPath:withCryptoFile:)])
		{
			[delegate didBackgroundDownloadNodeData: context.ephemeralInfo.node
			                                 atPath: path
			                         withCryptoFile: cryptoFile];
		}
	}];
}
#endif

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static NSString *const k_cacheToDisk   = @"cacheToDisk";
static NSString *const k_saveToDisk    = @"saveToDisk";
#if TARGET_OS_IPHONE
static NSString *const k_canBackground = @"canBackground";
#endif
static NSString *const k_completionTag = @"completionTag";

@implementation ZDCDownloadOptions

@synthesize cacheToDiskManager = _cacheToDisk;
@synthesize savePersistentlyToDiskManager = _saveToDisk;
#if TARGET_OS_IPHONE
@synthesize canDownloadWhileInBackground = _canBackground;
#endif
@synthesize completionTag = _completionTag;


- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		_cacheToDisk = [decoder decodeBoolForKey:k_cacheToDisk];
		_saveToDisk = [decoder decodeBoolForKey:k_saveToDisk];
	#if TARGET_OS_IPHONE
		_canBackground = [decoder decodeBoolForKey:k_canBackground];
	#endif
		_completionTag = [decoder decodeObjectForKey:k_completionTag];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeBool:_cacheToDisk forKey:k_cacheToDisk];
	[coder encodeBool:_saveToDisk  forKey:k_saveToDisk];
#if TARGET_OS_IPHONE
	[coder encodeBool:_canBackground forKey:k_canBackground];
#endif
	[coder encodeObject:_completionTag forKey:k_completionTag];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCDownloadOptions *copy = [[[self class] alloc] init];
	copy.cacheToDiskManager = _cacheToDisk;
	copy.savePersistentlyToDiskManager = _saveToDisk;
#if TARGET_OS_IPHONE
	copy.canDownloadWhileInBackground = _canBackground;
#endif
	copy.completionTag = [_completionTag copy];
	
	return copy;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDownloadTicket {
	
	__weak ZDCDownloadManager *_owner;
}

@synthesize isUser = _isUser;
@synthesize isMeta = _isMeta;

@synthesize userID = _userID;
@synthesize auth0ID = _auth0ID;

@synthesize nodeID = _nodeID;
@synthesize components = _components;

@synthesize options = _options;
@synthesize completionQueue = _completionQueue;
@synthesize completionBlock = _completionBlock;

@synthesize progress;

@synthesize isIgnored;

- (instancetype)init
{
	if ((self = [super init]))
	{
		progress = [NSProgress progressWithTotalUnitCount:0];
	}
	return self;
}

- (instancetype)initWithOwner:(ZDCDownloadManager *)owner
                       nodeID:(NSString *)nodeID
                   components:(ZDCNodeMetaComponents)components
                      options:(ZDCDownloadOptions *)options
              completionBlock:(id)completionBlock
{
	if ((self = [super init]))
	{
		_owner = owner;
		_isMeta = YES;
		_nodeID = nodeID;
		_components = components;
		_options = options;
		_completionBlock = completionBlock;
	}
	return self;
}

- (instancetype)initWithOwner:(ZDCDownloadManager *)owner
                       nodeID:(NSString *)nodeID
                      options:(ZDCDownloadOptions *)options
              completionBlock:(id)completionBlock
{
	if ((self = [super init]))
	{
		_owner = owner;
		_nodeID = nodeID;
		_options = options;
		_completionBlock = completionBlock;
	}
	return self;
}

- (instancetype)initWithOwner:(ZDCDownloadManager *)owner
                       userID:(NSString *)userID
                      auth0ID:(NSString *)auth0ID
                      options:(ZDCDownloadOptions *)options
              completionQueue:(dispatch_queue_t)completionQueue
              completionBlock:(id)completionBlock
{
	if ((self = [super init]))
	{
		_owner = owner;
		_isUser = YES;
		_userID = userID;
		_auth0ID = auth0ID;
		_options = options;
		_completionQueue = completionQueue;
		_completionBlock = completionBlock;
	}
	return self;
}

- (void)cancel
{
	[_owner processTicketRequest:self isCancellation:YES];
	_completionBlock = nil;
}

- (void)ignore
{
	self.isIgnored = YES;
	[_owner processTicketRequest:self isCancellation:NO];
	_completionBlock = nil;
}

@end
