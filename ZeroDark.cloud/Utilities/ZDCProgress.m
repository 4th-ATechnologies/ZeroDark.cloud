#import "ZDCProgress.h"

/* extern */ NSString *const ZDCLocalizedDescriptionKey = @"ZDCLocalizedDescription";
/* extern */ NSString *const ZDCChildProgressTypeKey    = @"ZDCChildProgressType";


@interface ZDCProgressChildInfo : NSObject {
@public
	NSProgress *progress;
	BOOL dynamicPendingUnitCount;
	int64_t pendingUnitCount;
	int64_t totalUnitCount;
	int64_t completedUnitCount;
}
@end

@implementation ZDCProgressChildInfo
@end

#pragma mark -

@implementation ZDCProgress {
@private
	
	dispatch_queue_t _queue;
	NSMutableDictionary<NSNumber *, ZDCProgressChildInfo *> *_children;
	
	int64_t _baseTotalUnitCount;
	int64_t _baseCompletedUnitCount;
}

@dynamic baseTotalUnitCount;
@dynamic baseCompletedUnitCount;

- (instancetype)init
{
	if ((self = [super init]))
	{
		_queue = dispatch_queue_create("ZDCProgress", DISPATCH_QUEUE_SERIAL);
		_children = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	for (ZDCProgressChildInfo *info in [_children objectEnumerator])
	{
		[self stopMonitoringChild:info->progress];
	}
}

- (int64_t)baseTotalUnitCount
{
	__block int64_t value = 0;
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		value = _baseTotalUnitCount;
		
	#pragma clang diagnostic pop
	}});
	
	return value;
}

- (void)setBaseTotalUnitCount:(int64_t)value
{
	__block BOOL didChange = NO;
	
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_baseTotalUnitCount != value)
		{
			_baseTotalUnitCount = value;
			didChange = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (didChange) {
		[self updateCompletedUnitCount:nil];
	}
}

- (int64_t)baseCompletedUnitCount
{
	__block int64_t value = 0;
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		value = _baseCompletedUnitCount;
		
	#pragma clang diagnostic pop
	}});
	
	return value;
}

- (void)setBaseCompletedUnitCount:(int64_t)value
{
	__block BOOL didChange = NO;
	
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_baseCompletedUnitCount != value)
		{
			_baseCompletedUnitCount = value;
			didChange = YES;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (didChange) {
		[self updateCompletedUnitCount:nil];
	}
}

/**
 * See header file for description.
 */
- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)inPendingUnitCount
{
	if (child == nil) return;
	
	__block BOOL didAddChild = NO;
	__block BOOL didUpdateChild = NO;
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSNumber *key = [NSNumber numberWithLong:(long)child];
		
		ZDCProgressChildInfo *info = _children[key];
		if (info == nil)
		{
			info = [[ZDCProgressChildInfo alloc] init];
			info->progress = child;
			
			_children[key] = info;
			didAddChild = YES;
		}
		
		if (inPendingUnitCount > 0)
		{
			if (info->dynamicPendingUnitCount || info->pendingUnitCount != inPendingUnitCount)
			{
				info->dynamicPendingUnitCount = NO;
				info->pendingUnitCount = inPendingUnitCount;
				didUpdateChild = YES;
			}
		}
		else // if (inPendingUnitCount <= 0) // Using a dynamicPendingUnitCount
		{
			if (!info->dynamicPendingUnitCount)
			{
				info->dynamicPendingUnitCount = YES;
				info->pendingUnitCount = child.totalUnitCount;
				didUpdateChild = YES;
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (didAddChild) {
		[self startMonitoringChild:child];
	}
	if (didAddChild || didUpdateChild) {
		[self updateCompletedUnitCount:child];
	}
}

/**
 * See header file for description.
 */
- (void)removeChild:(NSProgress *)child andIncrementBaseUnitCount:(BOOL)success
{
	if (child == nil) return;
	
	__block BOOL didRemoveChild = NO;
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSNumber *key = [NSNumber numberWithLong:(long)child];
		
		ZDCProgressChildInfo *info = _children[key];
		if (info)
		{
			_children[key] = nil;
			didRemoveChild = YES;
			
			if (success)
			{
				if (info->dynamicPendingUnitCount) {
					_baseTotalUnitCount += info->pendingUnitCount;
				}
				_baseCompletedUnitCount += info->pendingUnitCount;
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (didRemoveChild)
	{
		[self stopMonitoringChild:child];
		[self updateCompletedUnitCount:nil];
	}
}

/**
 * See header file for description.
 */
- (void)removeAllChildrenAndIncrementBaseUnitCount:(BOOL)success
{
	__block NSMutableArray<NSProgress *> *children;
	
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		const NSUInteger childCount = _children.count;
		if (childCount > 0)
		{
			children = [NSMutableArray arrayWithCapacity:_children.count];
		
			for (ZDCProgressChildInfo *info in [_children objectEnumerator])
			{
				if (success)
				{
					if (info->dynamicPendingUnitCount) {
						_baseTotalUnitCount += info->pendingUnitCount;
					}
					_baseCompletedUnitCount += info->pendingUnitCount;
				}
		
				[children addObject:info->progress];
			}
			
			[_children removeAllObjects];
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (children.count > 0)
	{
		for (NSProgress *child in children) {
			[self stopMonitoringChild:child];
		}
		[self updateCompletedUnitCount:nil];
	}
}

/**
 * See header file for description.
 */
- (NSProgress *)childProgressWithType:(ZDCChildProgressType)type
{
	__block NSProgress *matchingChildProgress = nil;
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (ZDCProgressChildInfo *info in [_children objectEnumerator])
		{
			NSProgress *childProgress = info->progress;
			NSNumber *childProgressType = childProgress.userInfo[ZDCChildProgressTypeKey];
			
			if (childProgressType && [childProgressType isKindOfClass:[NSNumber class]])
			{
				if (childProgressType.integerValue == type)
				{
					matchingChildProgress = childProgress;
					break;
				}
			}
		}
		
	#pragma clang diagnostic pop
	}});
	
	return matchingChildProgress;
}

- (void)startMonitoringChild:(NSProgress *)child
{
	[child addObserver: self
	        forKeyPath: NSStringFromSelector(@selector(fractionCompleted))
	           options: 0
	           context: NULL];
}

- (void)stopMonitoringChild:(NSProgress *)child
{
	[child removeObserver: self
	           forKeyPath: NSStringFromSelector(@selector(fractionCompleted))];
}

- (void)updateCompletedUnitCount:(NSProgress *)changedProgress
{
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		int64_t totalUnitCount = _baseTotalUnitCount;
		int64_t completedUnitCount = _baseCompletedUnitCount;
		
		for (ZDCProgressChildInfo *info in [_children objectEnumerator])
		{
			// Update values only if changed.
			// There's a cost to querying for this information (atomic getters).
			//
			if (info->progress == changedProgress)
			{
				info->totalUnitCount = info->progress.totalUnitCount;
				info->completedUnitCount = info->progress.completedUnitCount;
				
				if (info->dynamicPendingUnitCount) {
					info->pendingUnitCount = info->totalUnitCount;
				}
			}
			
			if (info->dynamicPendingUnitCount)
			{
				totalUnitCount += info->pendingUnitCount;
			}
			
			if (info->totalUnitCount > 0) // division by zero guard
			{
				double fractionCompleted = (double)info->completedUnitCount / (double)info->totalUnitCount;
				
				if (fractionCompleted > 1.0)
					fractionCompleted = 1.0;
				
				completedUnitCount += (int64_t)(info->pendingUnitCount * fractionCompleted);
			}
		}
		
		if (self.totalUnitCount != totalUnitCount) {
			self.totalUnitCount = totalUnitCount;
		}
		if (self.completedUnitCount != completedUnitCount) {
			self.completedUnitCount = completedUnitCount;
		}
		
	#pragma clang diagnostic pop
	}});
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
	if ([object isKindOfClass:[NSProgress class]])
	{
		NSProgress *progress = (NSProgress *)object;
		
		[self updateCompletedUnitCount:progress];
	}
}

- (void)cancel
{
	dispatch_sync(_queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		for (ZDCProgressChildInfo *info in [_children objectEnumerator])
		{
			[info->progress cancel];
		}
		
	#pragma clang diagnostic pop
	}});
}

@end
