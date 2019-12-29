/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCProgressManagerPrivate.h"

#import "ZDCConstants.h"
#import "ZDCCloudOperation.h"
#import "ZDCNode.h"
#import "ZDCLogging.h"
#import "ZDCProgress.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

/* extern */ NSString *const ZDCProgressListChangedNotification = @"ZDCProgressListChangedNotification";
/* extern */ NSString *const kZDCProgressManagerChanges = @"changes";

/* extern */ NSString *const ZDCProgressTypeKey = @"ZDCProgressType";
/* extern */ NSString *const ZDCNodeMetaComponentsKey = @"ZDCNodeMetaComponents";

/* private*/ NSString *kProgress_UserInfo_ZDCNetworkSpeedInfo = @"ZDCNetworkSpeedInfo";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCProgressManagerChanges ()

@property (nonatomic, assign, readwrite) ZDCProgressType progressType;
@property (nonatomic, copy,   readwrite) NSString *localUserID;
@property (nonatomic, copy,   readwrite) NSString *nodeID;
@property (nonatomic, assign, readwrite) ZDCNodeMetaComponents metaComponents;
@property (nonatomic, strong, readwrite, nullable) NSUUID *operationUUID;
@property (nonatomic, assign, readwrite) BOOL isDataUpload;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCProgressItem : NSObject

@property (nonatomic, copy, readwrite) NSString *nodeID;
@property (nonatomic, copy, readwrite) NSString *localUserID;

@property (nonatomic, assign, readwrite) BOOL isDataUpload;

@property (nonatomic, strong, readwrite) NSProgress *progress;

@property (nonatomic, strong, readwrite) NSMutableArray *completionQueues;
@property (nonatomic, strong, readwrite) NSMutableArray *completionBlocks;

@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *parents; // for file imports

@end

@implementation ZDCProgressItem
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCNetworkSpeedInfo : NSObject

@property (nonatomic, assign, readwrite) int64_t last_totalUnitCount;
@property (nonatomic, assign, readwrite) int64_t last_completedUnitCount;
@property (nonatomic, assign, readwrite) int64_t last_bytesPerSecond;
@property (nonatomic, assign, readwrite) BOOL    last_bytesPerSecondValid;
@property (nonatomic, strong, readwrite) NSDate *last_date;
@property (nonatomic, assign, readwrite) uint64_t sampleCount_positive;
@property (nonatomic, assign, readwrite) uint64_t sampleCount_neutral;

@end

@implementation ZDCNetworkSpeedInfo

@synthesize last_totalUnitCount;
@synthesize last_completedUnitCount;
@synthesize last_bytesPerSecond;
@synthesize last_bytesPerSecondValid;
@synthesize last_date;
@synthesize sampleCount_positive;
@synthesize sampleCount_neutral;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCProgressManager
{
	__weak ZeroDarkCloud *zdc;
	
	dispatch_queue_t queue;
	void *IsOnQueueKey;
	
	dispatch_queue_t timerQueue;
	dispatch_source_t timer;
	NSMutableArray<NSProgress *> *monitoring;
	
	NSMutableDictionary<NSString *, ZDCProgressItem *> * metaDownloadDict;
	NSMutableDictionary<NSString *, ZDCProgressItem *> * dataDownloadDict;
	NSMutableDictionary<NSUUID   *, ZDCProgressItem *> * uploadDict;
	NSMutableDictionary<NSString *, ZDCProgressItem *> * importDict;
	
	NSMutableArray<NSString *> *downloadOrder;
	NSMutableArray<NSString *> *importOrder;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.progressManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
		
		queue = dispatch_queue_create("ZDCProgressManager", DISPATCH_QUEUE_SERIAL);
		 
		IsOnQueueKey = &IsOnQueueKey;
		dispatch_queue_set_specific(queue, IsOnQueueKey, IsOnQueueKey, NULL);
		
		timerQueue = dispatch_queue_create("ZDCProgressManager-Timer", DISPATCH_QUEUE_SERIAL);
		monitoring = [[NSMutableArray alloc] init];
		
		metaDownloadDict = [[NSMutableDictionary alloc] init];
		dataDownloadDict = [[NSMutableDictionary alloc] init];
		uploadDict       = [[NSMutableDictionary alloc] init];
		importDict       = [[NSMutableDictionary alloc] init];
		
		downloadOrder = [[NSMutableArray alloc] init];
		importOrder   = [[NSMutableArray alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)postProgressListChangedNotification:(ZDCProgressManagerChanges *)changes
{
	NSDictionary *userInfo = @{ kZDCProgressManagerChanges : changes };
	
	dispatch_block_t block = ^{
		
		[[NSNotificationCenter defaultCenter] postNotificationName: ZDCProgressListChangedNotification
		                                                    object: self
		                                                  userInfo: userInfo];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Monitoring
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startMonitoringProgress:(NSProgress *)progress
{
	if (progress == nil) return;
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Invoked on incorrect queue");
	
	NSUInteger index = [monitoring indexOfObjectIdenticalTo:progress];
	if (index == NSNotFound)
	{
		/* This was the original idea.
		 * However, it didn't work very well due to throughput accuracy issues.
		 * It ended up being far more accurate to simply use a timer, and check a few times per second.
		 *
		[progress addObserver:self
					  forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
						  options:0
						  context:NULL];
		*/
		
		[monitoring addObject:progress];
		if (monitoring.count == 1)
		{
			[self startTimer];
		}
	}
}

- (void)stopMonitoringProgress:(NSProgress *)progress
{
	if (progress == nil) return;
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Invoked on incorrect queue");
	
	NSUInteger index = [monitoring indexOfObjectIdenticalTo:progress];
	if (index != NSNotFound)
	{
		/* See comment in `startMonitoringProgress:`
		 *
		[progress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
		*/
		
		[monitoring removeObjectAtIndex:index];
		if (monitoring.count == 0)
		{
			[self stopTimer];
		}
	}
}

/**
 * We use the timer to ensure regular calculation updates.
 * Otherwise, we're only updating the calculation when bytes go across the network.
 * But if the network connection slows to a halt, we want our calculations to continue updating.
**/
- (void)startTimer
{
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Invoked on incorrect queue");
	
	if (timer == NULL)
	{
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
		
		__weak typeof(self) weakSelf = self;
		dispatch_source_set_event_handler(timer, ^{
			
			[weakSelf timerFire];
		});
		
		NSTimeInterval fireIntervalInSeconds = 0.5; // seconds
		
		dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (uint64_t)(fireIntervalInSeconds * NSEC_PER_SEC));
		
		uint64_t interval = (uint64_t)(fireIntervalInSeconds * NSEC_PER_SEC);
		uint64_t leeway = (uint64_t)(0.1 * NSEC_PER_SEC);
		
		dispatch_source_set_timer(timer, start, interval, leeway);
		dispatch_resume(timer);
	}
}

- (void)stopTimer
{
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Invoked on incorrect queue");
	
	if (timer)
	{
		timer = NULL;
	}
}

- (void)timerFire
{
	__block NSArray<NSProgress *> *_monitoring = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		_monitoring = [monitoring copy];
		
	#pragma clang diagnostic pop
	}});
	
	for (NSProgress *progress in _monitoring)
	{
		[self observeValueForKeyPath:nil ofObject:progress change:nil context:NULL];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
	NSAssert([object isKindOfClass:[NSProgress class]], @"Bad object");
	
	NSProgress *progress = (NSProgress *)object;
	
	int64_t current_totalUnitCount = progress.totalUnitCount;
	int64_t current_completedUnitCount = progress.completedUnitCount;
	NSDate *current_date = [NSDate date];
	
	if ((current_totalUnitCount > 0) && (current_completedUnitCount >= current_totalUnitCount))
	{
		// Progress is >= 100%
		// So there's no need to keep monitoring the throughput.
		
		[progress setUserInfoObject:nil forKey:kProgress_UserInfo_ZDCNetworkSpeedInfo];
		[progress setUserInfoObject:nil forKey:NSProgressThroughputKey];
		[progress setUserInfoObject:nil forKey:NSProgressEstimatedTimeRemainingKey];
		
		dispatch_async(queue, ^{ @autoreleasepool { // we're currently on the timerQueue
			[self stopMonitoringProgress:progress];
		}});
		return;
	}
	
	ZDCNetworkSpeedInfo *nsi = progress.userInfo[kProgress_UserInfo_ZDCNetworkSpeedInfo];
	
	if (nsi == nil)
	{
		nsi = [[ZDCNetworkSpeedInfo alloc] init];
		nsi.last_totalUnitCount = current_totalUnitCount;
		nsi.last_completedUnitCount = current_completedUnitCount;
		
		[progress setUserInfoObject:nsi forKey:kProgress_UserInfo_ZDCNetworkSpeedInfo];
	}
	else
	{
		NSTimeInterval secondsDiff = 0;
		if (nsi.last_date)
		{
			secondsDiff = [current_date timeIntervalSinceDate:nsi.last_date];
		}
		
		int64_t bytesDiff = current_completedUnitCount - nsi.last_completedUnitCount;
		
		if (nsi.last_date == nil ||                            // first sample
		    secondsDiff < 0      ||                            // sanity check
		    bytesDiff < 0        ||                            // sanity check
		    nsi.last_totalUnitCount != current_totalUnitCount) // sanity check
		{
			nsi.last_totalUnitCount = current_totalUnitCount;
			nsi.last_completedUnitCount = current_completedUnitCount;
			nsi.last_bytesPerSecond = 0;
			nsi.last_bytesPerSecondValid = NO;
			nsi.last_date = current_date;
			nsi.sampleCount_positive = 0;
			nsi.sampleCount_neutral = 0;
			
			[progress setUserInfoObject:nil forKey:NSProgressThroughputKey];
			[progress setUserInfoObject:nil forKey:NSProgressEstimatedTimeRemainingKey];
		}
		else
		{
			int64_t current_bytesPerSecond = (int64_t)(bytesDiff / secondsDiff);
			int64_t last_bytesPerSecond =
				nsi.last_bytesPerSecondValid ? nsi.last_bytesPerSecond : current_bytesPerSecond;
			
			// Using exponential moving average
			//
			// averageSpeed = SMOOTHING_FACTOR * lastSpeed + (1-SMOOTHING_FACTOR) * averageSpeed;
			//
			// A higher SMOOTHING_FACTOR discounts older observations faster.
			// So we start with a higher SMOOTHING_FACTOR, and decrease it as we get more samples.
			
			double smoothing_factor;
			if (nsi.sampleCount_positive < 8)
				smoothing_factor = 0.05;
			else if (nsi.sampleCount_positive < 16)
				smoothing_factor = 0.03;
			else
				smoothing_factor = 0.001;
			
			double bytesPerSecond =
			    (smoothing_factor * current_bytesPerSecond)
			  + ((1.0 - smoothing_factor) * last_bytesPerSecond);
			
			nsi.last_completedUnitCount = current_completedUnitCount;
			nsi.last_bytesPerSecond = (int64_t)bytesPerSecond;
			nsi.last_bytesPerSecondValid = YES;
			nsi.last_date = current_date;
			
			if (bytesDiff > 0)
			{
				nsi.sampleCount_positive++;
				nsi.sampleCount_neutral = 0;
			}
			else
			{
				nsi.sampleCount_neutral++;
				if ((nsi.sampleCount_neutral > 6) && (nsi.sampleCount_positive > 0)) {
					nsi.sampleCount_positive = 0;
				}
			}
			
			if (bytesPerSecond > 0)
			{
				int64_t bytesRemaining = current_totalUnitCount - current_completedUnitCount;
				NSTimeInterval timeRemaining = (double)bytesRemaining / (double)bytesPerSecond;
				
				[progress setUserInfoObject:@((int64_t)bytesPerSecond) forKey:NSProgressThroughputKey];
				[progress setUserInfoObject:@(timeRemaining)           forKey:NSProgressEstimatedTimeRemainingKey];
			}
			else
			{
				[progress setUserInfoObject:nil forKey:NSProgressThroughputKey];
				[progress setUserInfoObject:nil forKey:NSProgressEstimatedTimeRemainingKey];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads - General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allDownloadingNodeIDs
{
	__block NSSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableSet<NSString *> *_nodeIDs = nil;
		
		NSArray<NSString*> *metaKeys = [metaDownloadDict allKeys];
		if (metaKeys.count > 0)
		{
			_nodeIDs = [NSMutableSet setWithCapacity:metaKeys.count];
			
			for (NSString *metaKey in metaKeys)
			{
				NSString *nodeID = nil;
				[self getNodeID:&nodeID components:NULL fromMetaKey:metaKey];
				
				[_nodeIDs addObject:nodeID];
			}
		}
		
		NSArray<NSString *> *dataKeys = [dataDownloadDict allKeys];
		if (dataKeys.count > 0)
		{
			if (_nodeIDs) {
				[_nodeIDs addObjectsFromArray:dataKeys];
			}
			else {
				nodeIDs = [NSSet setWithArray:dataKeys];
			}
		}
		
		if (_nodeIDs) {
			nodeIDs = _nodeIDs;
		}
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allDownloadingNodeIDs:(NSString *)localUserID
{
	__block NSMutableSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[metaDownloadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSString *metaKey, ZDCProgressItem *item, BOOL *stop)
		{
			if ([localUserID isEqualToString:item.localUserID])
			{
				if (nodeIDs == nil) {
					nodeIDs = [NSMutableSet set];
				}
				
				NSString *nodeID = nil;
				[self getNodeID:&nodeID components:nil fromMetaKey:metaKey];
				
				[nodeIDs addObject:nodeID];
			}
		}];
		
		[dataDownloadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSString *nodeID, ZDCProgressItem *item, BOOL *stop)
		{
			if ([localUserID isEqualToString:item.localUserID])
			{
				if (nodeIDs == nil) {
					nodeIDs = [NSMutableSet set];
				}
				
				[nodeIDs addObject:nodeID];
			}
		}];
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)downloadProgressForNodeID:(NSString *)nodeID
{
	if (nodeID == nil) return nil;
	
	__block NSProgress *progress = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = dataDownloadDict[nodeID];
		if (item) {
			progress = item.progress;
			return; // from block
		}
		
		NSArray<NSString *> *metaKeys = [self prioritizedMetaKeysForNodeID:nodeID];
		for (NSString *metaKey in metaKeys)
		{
			item = metaDownloadDict[metaKey];
			if (item) {
				progress = item.progress;
				return; // from block
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return progress;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads - Meta
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standardized key creation for 'metaDownloadDict'.
 */
- (NSString *)metaKeyForNodeID:(NSString *)nodeID components:(ZDCNodeMetaComponents)components
{
	return [NSString stringWithFormat:@"%@|%d", nodeID, (int)components];
}

/**
 * Standardized extraction for keys in 'metaDownloadDict'.
 */
- (void)getNodeID:(NSString *_Nullable *)outNodeID
       components:(ZDCNodeMetaComponents *_Nullable)outComponents
      fromMetaKey:(NSString *)key
{
	NSArray<NSString*> *split = [key componentsSeparatedByString:@"|"];
	
	if (outNodeID && (split.count > 0))
	{
		*outNodeID = split[0];
	}
	if (outComponents && (split.count > 1))
	{
		NSString *str = split[1];
		*outComponents = (ZDCNodeMetaComponents)[str integerValue];
	}
}

- (NSArray<NSString *> *)prioritizedMetaKeysForNodeID:(NSString *)nodeID
{
	return @[
		[self metaKeyForNodeID:nodeID components:(ZDCNodeMetaComponents_All)],
		[self metaKeyForNodeID:nodeID components:(ZDCNodeMetaComponents_Header | ZDCNodeMetaComponents_Thumbnail)],
		[self metaKeyForNodeID:nodeID components:(ZDCNodeMetaComponents_Header | ZDCNodeMetaComponents_Metadata)],
		[self metaKeyForNodeID:nodeID components:(ZDCNodeMetaComponents_Header)],
	];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allMetaDownloadingNodeIDs
{
	__block NSMutableSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSArray<NSString*> *metaKeys = [metaDownloadDict allKeys];
		if (metaKeys.count > 0)
		{
			nodeIDs = [NSMutableSet setWithCapacity:metaKeys.count];
			
			for (NSString *metaKey in metaKeys)
			{
				NSString *nodeID = nil;
				[self getNodeID:&nodeID components:NULL fromMetaKey:metaKey];
				
				[nodeIDs addObject:nodeID];
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allMetaDownloadingNodeIDs:(NSString *)localUserID
{
	__block NSMutableSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[metaDownloadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSString *metaKey, ZDCProgressItem *item, BOOL *stop)
		{
			if ([localUserID isEqualToString:item.localUserID])
			{
				if (nodeIDs == nil) {
					nodeIDs = [NSMutableSet set];
				}
				
				NSString *nodeID = nil;
				[self getNodeID:&nodeID components:nil fromMetaKey:metaKey];
				
				[nodeIDs addObject:nodeID];
			}
		}];
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 *
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
{
	return [self metaDownloadProgressForNodeID: nodeID
	                                components: nil
	                           completionQueue: nil
	                           completionBlock: nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
                                            components:(nullable NSNumber *)components
{
	return [self metaDownloadProgressForNodeID: nodeID
	                                components: components
	                           completionQueue: nil
	                           completionBlock: nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
                                       completionQueue:(nullable dispatch_queue_t)completionQueue
                                       completionBlock:(nullable NodeMetaDownloadCompletionBlock)completionBlock
{
	return [self metaDownloadProgressForNodeID: nodeID
	                                components: nil
	                           completionQueue: completionQueue
	                           completionBlock: completionBlock];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)metaDownloadProgressForNodeID:(NSString *)nodeID
                                            components:(nullable NSNumber *)components
                                       completionQueue:(nullable dispatch_queue_t)completionQueue
                                       completionBlock:(nullable NodeMetaDownloadCompletionBlock)completionBlock
{
	if (nodeID == nil) return nil;
	
	__block NSProgress *progress = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSArray<NSString *> *metaKeys = nil;
		if (components) {
			metaKeys = @[ [self metaKeyForNodeID:nodeID components:[components unsignedIntegerValue]] ];
		}
		else {
			metaKeys = [self prioritizedMetaKeysForNodeID:nodeID];
		}
		
		for (NSString *metaKey in metaKeys)
		{
			ZDCProgressItem *item = metaDownloadDict[metaKey];
			if (item)
			{
				progress = item.progress;
		
				if (completionBlock)
				{
					if (!item.completionBlocks) {
						item.completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
						item.completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
					}
		
					[item.completionQueues addObject:(completionQueue ?: dispatch_get_main_queue())];
					[item.completionBlocks addObject:completionBlock];
				}
				
				break;
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return progress;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (BOOL)addMetaDownloadListenerForNodeID:(NSString *)nodeID
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock
{
	NSProgress *progress =
	  [self metaDownloadProgressForNodeID: nodeID
	                           components: nil
	                      completionQueue: completionQueue
	                      completionBlock: completionBlock];
	
	return (progress != nil);
}

/**
 *
 */
- (BOOL)addMetaDownloadListenerForNodeID:(NSString *)nodeID
                              components:(nullable NSNumber *)components
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock
{
	NSProgress *progress =
	  [self metaDownloadProgressForNodeID: nodeID
	                           components: components
	                      completionQueue: completionQueue
	                      completionBlock: completionBlock];
	
	return (progress != nil);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (BOOL)setMetaDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                     components:(ZDCNodeMetaComponents)components
                    localUserID:(NSString *)localUserID
{
	return [self setMetaDownloadProgress: progress
	                           forNodeID: nodeID
	                          components: components
	                         localUserID: localUserID
	                    existingProgress: nil
	                     completionQueue: nil
	                     completionBlock: nil];
}

/**
 * Used by DownloadManager.
 * Provides an atomic get-or-set operation.
 */
- (BOOL)setMetaDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                     components:(ZDCNodeMetaComponents)components
                    localUserID:(NSString *)localUserID
               existingProgress:(NSProgress *_Nullable *_Nullable)outExistingProgress
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable NodeMetaDownloadCompletionBlock)completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(progress    != nil);
	NSParameterAssert(nodeID      != nil);
	NSParameterAssert(components  != 0);
	NSParameterAssert(localUserID != nil);
#else
	if (progress    == nil) return NO;
	if (nodeID      == nil) return NO;
	if (components  == 0)   return NO;
	if (localUserID == nil) return NO;
#endif
	
	[progress setUserInfoObject:@(ZDCProgressType_MetaDownload) forKey:ZDCProgressTypeKey];
	[progress setUserInfoObject:@(components) forKey:ZDCNodeMetaComponentsKey];
	
	__block BOOL shouldPostNotification = NO;
	__block NSProgress *existingProgress = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSString *const metaKey = [self metaKeyForNodeID:nodeID components:components];
		
		ZDCProgressItem *item = metaDownloadDict[metaKey];
		if (item)
		{
			existingProgress = item.progress;
		}
		else // if (item == nil)
		{
			item = [[ZDCProgressItem alloc] init];
			item.nodeID = nodeID;
			item.localUserID = localUserID;
			item.progress = progress;
			
			if (progress.kind == nil) {
				progress.kind = NSProgressKindFile;
				
				if (@available(macOS 10.13, iOS 11, *))
				{
					if (progress.fileOperationKind == nil) {
						progress.fileOperationKind = NSProgressFileOperationKindDownloading;
					}
				}
			}
			[self startMonitoringProgress:progress];
			
			metaDownloadDict[metaKey] = item;
			shouldPostNotification = YES;
		}
		
		if (completionBlock)
		{
			if (!item.completionBlocks) {
				item.completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
				item.completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
			}
			
			[item.completionQueues addObject:(completionQueue ?: dispatch_get_main_queue())];
			[item.completionBlocks addObject:completionBlock];
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldPostNotification)
	{
		ZDCProgressManagerChanges *changes = [[ZDCProgressManagerChanges alloc] init];
		
		changes.progressType   = ZDCProgressType_MetaDownload;
		changes.localUserID    = localUserID;
		changes.nodeID         = nodeID;
		changes.metaComponents = components;
		
		[self postProgressListChangedNotification:changes];
	}
	
	if (outExistingProgress) *outExistingProgress = existingProgress;
	return shouldPostNotification;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (void)removeMetaDownloadListenerForNodeID:(NSString *)nodeID
                                 components:(ZDCNodeMetaComponents)components
                            completionBlock:(NodeMetaDownloadCompletionBlock)completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(nodeID     != nil);
	NSParameterAssert(components != 0);
#else
	if (nodeID     == nil) return;
	if (components == 0)   return;
#endif
	if (completionBlock == nil) return; // not assert worthy - just ignore
	
	NSString *const metaKey = [self metaKeyForNodeID:nodeID components:components];
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = metaDownloadDict[metaKey];
		if (item)
		{
			NSUInteger idx = [item.completionBlocks indexOfObjectIdenticalTo:completionBlock];
			if (idx != NSNotFound)
			{
				[item.completionQueues removeObjectAtIndex:idx];
				[item.completionBlocks removeObjectAtIndex:idx];
			}
		}
		
	#pragma clang diagnostic pop
	}});
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (void)removeMetaDownloadProgressForNodeID:(NSString *)nodeID
                                 components:(ZDCNodeMetaComponents)components
                                 withHeader:(nullable ZDCCloudDataInfo *)header
                                   metadata:(nullable NSData *)metadata
                                  thumbnail:(nullable NSData *)thumbnail
                                      error:(nullable NSError *)error
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(nodeID     != nil);
	NSParameterAssert(components != 0);
#else
	if (nodeID     == nil) return;
	if (components == 0)   return;
#endif
	
	__block BOOL shouldPostNotification = NO;
	__block NSString *localUserID = nil;
	__block NSArray *completionQueues = nil;
	__block NSArray *completionBlocks = nil;
	
	NSString *const metaKey = [self metaKeyForNodeID:nodeID components:components];
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = metaDownloadDict[metaKey];
		if (item)
		{
			localUserID = item.localUserID;
			completionQueues = item.completionQueues;
			completionBlocks = item.completionBlocks;
			
			[self stopMonitoringProgress:item.progress];
			
			metaDownloadDict[metaKey] = nil;
			shouldPostNotification = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	const NSUInteger count = completionBlocks.count;
	for (NSUInteger i = 0; i < count; i++)
	{
		dispatch_queue_t completionQueue = completionQueues[i];
		NodeMetaDownloadCompletionBlock completionBlock = completionBlocks[i];
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(header, metadata, thumbnail, error);
		}});
	}
	
	if (shouldPostNotification)
	{
		ZDCProgressManagerChanges *changes = [[ZDCProgressManagerChanges alloc] init];
		
		changes.progressType   = ZDCProgressType_MetaDownload;
		changes.localUserID    = localUserID;
		changes.nodeID         = nodeID;
		changes.metaComponents = components;
		
		[self postProgressListChangedNotification:changes];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads - Meta
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allDataDownloadingNodeIDs
{
	__block NSSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSArray<NSString *> *dataKeys = [dataDownloadDict allKeys];
		if (dataKeys.count > 0)
		{
			nodeIDs = [NSSet setWithArray:dataKeys];
		}
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allDataDownloadingNodeIDs:(NSString *)localUserID
{
	__block NSMutableSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[dataDownloadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSString *nodeID, ZDCProgressItem *item, BOOL *stop)
		{
			if ([localUserID isEqualToString:item.localUserID])
			{
				if (nodeIDs == nil) {
					nodeIDs = [NSMutableSet set];
				}
				
				[nodeIDs addObject:nodeID];
			}
		}];
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)dataDownloadProgressForNodeID:(NSString *)nodeID
{
	return [self dataDownloadProgressForNodeID:nodeID completionQueue:nil completionBlock:nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)dataDownloadProgressForNodeID:(NSString *)nodeID
                                       completionQueue:(nullable dispatch_queue_t)completionQueue
                                       completionBlock:(nullable NodeDataDownloadCompletionBlock)completionBlock
{
	if (nodeID == nil) return nil;
	
	__block NSProgress *progress = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = dataDownloadDict[nodeID];
		if (item)
		{
			progress = item.progress;
	
			if (completionBlock)
			{
				if (!item.completionBlocks) {
					item.completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
					item.completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
				}
	
				[item.completionQueues addObject:(completionQueue ?: dispatch_get_main_queue())];
				[item.completionBlocks addObject:completionBlock];
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return progress;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (BOOL)addDataDownloadListenerForNodeID:(NSString *)nodeID
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(NodeDataDownloadCompletionBlock)completionBlock
{
	NSProgress *progress =
	  [self dataDownloadProgressForNodeID: nodeID
	                      completionQueue: completionQueue
	                      completionBlock: completionBlock];
	
	return (progress != nil);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (BOOL)setDataDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                    localUserID:(NSString *)localUserID
{
	return [self setDataDownloadProgress: progress
	                           forNodeID: nodeID
	                         localUserID: localUserID
	                    existingProgress: nil
	                     completionQueue: nil
	                     completionBlock: nil];
}

/**
 * Used by DownloadManager.
 * Provides an atomic get-or-set operation.
 */
- (BOOL)setDataDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                    localUserID:(NSString *)localUserID
               existingProgress:(NSProgress *_Nullable *_Nullable)outExistingProgress
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable NodeDataDownloadCompletionBlock)completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(progress    != nil);
	NSParameterAssert(nodeID      != nil);
	NSParameterAssert(localUserID != nil);
#else
	if (progress    == nil) return NO;
	if (nodeID      == nil) return NO;
	if (localUserID == nil) return NO;
#endif
	
	[progress setUserInfoObject:@(ZDCProgressType_DataDownload) forKey:ZDCProgressTypeKey];
	
	__block BOOL shouldPostNotification = NO;
	__block NSProgress *existingProgress = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = dataDownloadDict[nodeID];
		if (item)
		{
			existingProgress = item.progress;
		}
		else // if (item == nil)
		{
			item = [[ZDCProgressItem alloc] init];
			item.nodeID = nodeID;
			item.localUserID = localUserID;
			item.progress = progress;
			
			if (progress.kind == nil) {
				progress.kind = NSProgressKindFile;
				
				if (@available(macOS 10.13, iOS 11, *))
				{
					if (progress.fileOperationKind == nil) {
						progress.fileOperationKind = NSProgressFileOperationKindDownloading;
					}
				}
			}
			[self startMonitoringProgress:progress];
			
			dataDownloadDict[nodeID] = item;
			shouldPostNotification = YES;
		}
		
		if (completionBlock)
		{
			if (!item.completionBlocks) {
				item.completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
				item.completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
			}
			
			[item.completionQueues addObject:(completionQueue ?: dispatch_get_main_queue())];
			[item.completionBlocks addObject:completionBlock];
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldPostNotification)
	{
		ZDCProgressManagerChanges *changes = [[ZDCProgressManagerChanges alloc] init];
		
		changes.progressType = ZDCProgressType_DataDownload;
		changes.localUserID  = localUserID;
		changes.nodeID       = nodeID;
		
		[self postProgressListChangedNotification:changes];
	}
	
	if (outExistingProgress) *outExistingProgress = existingProgress;
	return shouldPostNotification;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (void)removeDataDownloadListenerForNodeID:(NSString *)nodeID
                            completionBlock:(NodeDataDownloadCompletionBlock)completionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(nodeID != nil);
#else
	if (nodeID == nil) return;
#endif
	if (completionBlock == nil) return; // not assert worthy - just ignore
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = dataDownloadDict[nodeID];
		if (item)
		{
			NSUInteger idx = [item.completionBlocks indexOfObjectIdenticalTo:completionBlock];
			if (idx != NSNotFound)
			{
				[item.completionQueues removeObjectAtIndex:idx];
				[item.completionBlocks removeObjectAtIndex:idx];
			}
		}
		
	#pragma clang diagnostic pop
	}});
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (void)removeDataDownloadProgressForNodeID:(NSString *)nodeID
                                 withHeader:(nullable ZDCCloudDataInfo *)header
                                 cryptoFile:(nullable ZDCCryptoFile *)cryptoFile
                                      error:(nullable NSError *)error
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(nodeID != nil);
#else
	if (nodeID == nil) return;
#endif
	
	__block BOOL shouldPostNotification = NO;
	__block NSString *localUserID = nil;
	__block NSArray *completionQueues = nil;
	__block NSArray *completionBlocks = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = dataDownloadDict[nodeID];
		if (item)
		{
			localUserID = item.localUserID;
			completionQueues = item.completionQueues;
			completionBlocks = item.completionBlocks;
			
			[self stopMonitoringProgress:item.progress];
			
			dataDownloadDict[nodeID] = nil;
			shouldPostNotification = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	const NSUInteger count = completionBlocks.count;
	for (NSUInteger i = 0; i < count; i++)
	{
		dispatch_queue_t completionQueue = completionQueues[i];
		NodeDataDownloadCompletionBlock completionBlock = completionBlocks[i];
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(header, cryptoFile, error);
		}});
	}
	
	if (shouldPostNotification)
	{
		ZDCProgressManagerChanges *changes = [[ZDCProgressManagerChanges alloc] init];
		
		changes.progressType = ZDCProgressType_DataDownload;
		changes.localUserID  = localUserID;
		changes.nodeID       = nodeID;
		
		[self postProgressListChangedNotification:changes];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Uploads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSUUID *> *)allUploadingOperationUUIDs
{
	__block NSSet<NSUUID *> *operationUUIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		operationUUIDs = [NSSet setWithArray:[uploadDict allKeys]];
		
	#pragma clang diagnostic pop
	}});
	
	return operationUUIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSUUID *> *)allUploadingOperationUUIDs:(NSString *)localUserID
{
	__block NSMutableSet<NSUUID *> *operationUUIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[uploadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSUUID *operationUUID, ZDCProgressItem *item, BOOL *stop)
		{
			if ([localUserID isEqualToString:item.localUserID])
			{
				if (operationUUIDs == nil)
					operationUUIDs = [NSMutableSet set];
				
				[operationUUIDs addObject:operationUUID];
			}
		}];
		
	#pragma clang diagnostic pop
	}});
	
	return operationUUIDs ?: [NSSet set];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (NSSet<NSString *> *)allUploadingNodeIDs
{
	__block NSMutableSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		nodeIDs = [NSMutableSet set];
		
		[uploadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSUUID *operationUUID, ZDCProgressItem *item, BOOL *stop)
		{
			if (item.nodeID != nil) // might be nil for "delete-node:if-orphan" operations
			{
				[nodeIDs addObject:item.nodeID];
			}
		}];
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs ?: [NSSet set];
}

/**
 * Returns the list of nodeIDs that currently have associated uploads.
**/
- (NSSet<NSString *> *)allUploadingNodeIDs:(NSString *)localUserID
{
	__block NSMutableSet<NSString *> *nodeIDs = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[uploadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSUUID *operationUUID, ZDCProgressItem *item, BOOL *stop)
		{
			if ([localUserID isEqualToString:item.localUserID] &&
			    item.nodeID != nil) // might be nil for "delete-node:if-orphan" operations
			{
				if (nodeIDs == nil)
					nodeIDs = [NSMutableSet set];
				
				[nodeIDs addObject:item.nodeID];
			}
		}];
		
	#pragma clang diagnostic pop
	}});
	
	return nodeIDs;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)uploadProgressForOperationUUID:(NSUUID *)operationID
{
	return [self uploadProgressForOperationUUID:operationID completionQueue:nil completionBlock:nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)uploadProgressForOperationUUID:(NSUUID *)operationUUID
                                        completionQueue:(nullable dispatch_queue_t)completionQueue
                                        completionBlock:(nullable UploadCompletionBlock)completionBlock
{
	if (!operationUUID) return nil;
	
	__block NSProgress *progress = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = uploadDict[operationUUID];
		if (item)
		{
			progress = item.progress;
			
			if (completionBlock)
			{
				if (item.completionBlocks == nil) {
					item.completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
					item.completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
				}
				
				[item.completionQueues addObject:(completionQueue ?: dispatch_get_main_queue())];
				[item.completionBlocks addObject:completionBlock];
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return progress;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)dataUploadProgressForNodeID:(NSString *)nodeID
{
	return [self dataUploadProgressForNodeID:nodeID completionQueue:nil completionBlock:nil];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (nullable NSProgress *)dataUploadProgressForNodeID:(NSString *)nodeID
                                     completionQueue:(nullable dispatch_queue_t)completionQueue
                                     completionBlock:(nullable UploadCompletionBlock)completionBlock
{
	if (!nodeID) return nil;
	
	__block NSProgress *progress = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		__block ZDCProgressItem *matchingItem = nil;
		
		[uploadDict enumerateKeysAndObjectsUsingBlock:
		  ^(NSUUID *operationUUID, ZDCProgressItem *item, BOOL *stop)
		{
			if ([item.nodeID isEqualToString:nodeID] && item.isDataUpload)
			{
				matchingItem = item;
				*stop = YES;
			}
		}];
		
		if (matchingItem)
		{
			progress = matchingItem.progress;
			
			if (completionBlock)
			{
				if (matchingItem.completionBlocks == nil) {
					matchingItem.completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
					matchingItem.completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
				}
				
				[matchingItem.completionQueues addObject:(completionQueue ?: dispatch_get_main_queue())];
				[matchingItem.completionBlocks addObject:completionBlock];
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return progress;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCProgressManager.html
 */
- (BOOL)setUploadProgress:(NSProgress *)progress
             forOperation:(ZDCCloudOperation *)operation
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(progress  != nil);
	NSParameterAssert(operation != nil);
#else
	if (progress  == nil) return NO;
	if (operation == nil) return NO;
#endif
	
	[progress setUserInfoObject:@(ZDCProgressType_Upload) forKey:ZDCProgressTypeKey];
	
	__block BOOL shouldPostNotification = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = uploadDict[operation.uuid];
		if (item == nil)
		{
			item = [[ZDCProgressItem alloc] init];
			item.nodeID = operation.nodeID;
			item.localUserID = operation.localUserID;
			item.isDataUpload = operation.isPutNodeDataOperation;
			item.progress = progress;
			
			if (progress.kind == nil) {
				progress.kind = NSProgressKindFile;
				
				// Uncomment me when Apple gets their head out of their arse,
				// and adds `NSProgressFileOperationKindUploading`.
				//
			//	if (@available(macOS 10.X, iOS Y, *))
			//	{
			//		if (progress.fileOperationKind == nil) {
			//			progress.fileOperationKind = NSProgressFileOperationKindUploading; // Type doesn't exist !
			//		}
			//	}
			}
			[self startMonitoringProgress:progress];
			
			uploadDict[operation.uuid] = item;
			shouldPostNotification = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (shouldPostNotification)
	{
		ZDCProgressManagerChanges *changes = [[ZDCProgressManagerChanges alloc] init];
		
		changes.progressType  = ZDCProgressType_Upload;
		changes.localUserID   = operation.localUserID;
		changes.nodeID        = operation.nodeID;
		changes.operationUUID = operation.uuid;
		changes.isDataUpload  = operation.isPutNodeDataOperation;
		
		[self postProgressListChangedNotification:changes];
	}
	
	return shouldPostNotification;
}

- (void)removeUploadProgressForOperationUUID:(NSUUID *)operationUUID withSuccess:(BOOL)success
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(operationUUID != nil);
#else
	if (operationUUID == nil) return;
#endif
	
	__block BOOL shouldPostNotification = NO;
	__block NSString *nodeID = nil;
	__block NSString *localUserID = nil;
	__block BOOL isDataUpload = NO;
	__block NSArray *completionQueues = nil;
	__block NSArray *completionBlocks = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCProgressItem *item = uploadDict[operationUUID];
		if (item)
		{
			nodeID = item.nodeID;
			localUserID = item.localUserID;
			isDataUpload = item.isDataUpload;
			completionQueues = item.completionQueues;
			completionBlocks = item.completionBlocks;
			
			[self stopMonitoringProgress:item.progress];
			
			uploadDict[operationUUID] = nil;
			shouldPostNotification = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	const NSUInteger count = completionBlocks.count;
	for (NSUInteger i = 0; i < count; i++)
	{
		dispatch_queue_t completionQueue = completionQueues[i];
		UploadCompletionBlock completionBlock = completionBlocks[i];
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(success);
		}});
	}
	
	if (shouldPostNotification)
	{
		ZDCProgressManagerChanges *changes = [[ZDCProgressManagerChanges alloc] init];
		
		changes.progressType  = ZDCProgressType_Upload;
		changes.localUserID   = localUserID;
		changes.nodeID        = nodeID;
		changes.operationUUID = operationUUID;
		changes.isDataUpload  = isDataUpload;
		
		[self postProgressListChangedNotification:changes];
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCProgressManagerChanges

@synthesize progressType;
@synthesize localUserID;
@synthesize nodeID;
@synthesize metaComponents;
@synthesize operationUUID;
@synthesize isDataUpload;

@end
