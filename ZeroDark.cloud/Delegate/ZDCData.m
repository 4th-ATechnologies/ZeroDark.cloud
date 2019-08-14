/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCData.h"

#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCDataPromisePrivate.h"

#import <stdatomic.h>

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 */
@implementation ZDCData

@synthesize data = data;
@synthesize cleartextFileURL = cleartextFileURL;
@synthesize cryptoFile = cryptoFile;
@synthesize promise = promise;

- (instancetype)init
{
	return [self initWithData:[NSData data]];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 */
- (instancetype)initWithData:(NSData *)inData
{
	if ((self = [super init]))
	{
		data = [inData copy];
	}
	return self;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 */
- (instancetype)initWithCleartextFileURL:(NSURL *)inCleartextFileURL
{
	if ((self = [super init]))
	{
		cleartextFileURL = inCleartextFileURL;
	}
	return self;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)inCryptoFile
{
	if ((self = [super init]))
	{
		cryptoFile = inCryptoFile;
	}
	return self;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 */
- (instancetype)initWithPromise:(ZDCDataPromise *)inPromise
{
	if ((self = [super init]))
	{
		promise = inPromise;
	}
	return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 * https://apis.zerodark.cloud/Classes/ZDCDataPromise.html
 */
@implementation ZDCDataPromise {
	
	dispatch_queue_t queue;
	
	BOOL completed;
	ZDCData *result;
	
	NSMutableArray<dispatch_queue_t> *completionQueues;
	NSMutableArray<id>               *completionBlocks;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		queue = dispatch_queue_create("ZDCDataPromise", DISPATCH_QUEUE_SERIAL);
		
		completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
		completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
	}
	return self;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 * https://apis.zerodark.cloud/Classes/ZDCDataPromise.html
 */
- (void)fulfill:(ZDCData *)inResult
{
	if (inResult == nil) {
		[self reject];
		return;
	}
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		if (self->completed) return;
		self->completed = YES;
		self->result = inResult;
		
		[self popListeners];
	}});
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCData.html
 * https://apis.zerodark.cloud/Classes/ZDCDataPromise.html
 */
- (void)reject
{
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		if (self->completed) return;
		self->completed = YES;
		self->result = nil;
		
		[self popListeners];
	}});
}

- (void)pushCompletionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(ZDCData * _Nullable))completionBlock
{
	if (completionBlock == nil) return;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	
		[self->completionQueues addObject:completionQueue ?: dispatch_get_main_queue()];
		[self->completionBlocks addObject:completionBlock];
		
		if (self->completed)
		{
			[self popListeners];
		}
	}});
}

- (void)popListeners
{
	__strong ZDCData *theResult = result;
	
	NSUInteger const count = completionBlocks.count;
	for (NSUInteger i = 0; i < count; i++)
	{
		dispatch_queue_t completionQueue = completionQueues[i];
		void (^completionBlock)(ZDCData *) = completionBlocks[i];
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(theResult);
		}});
	}
	
	[completionQueues removeAllObjects];
	[completionBlocks removeAllObjects];
}

@end

