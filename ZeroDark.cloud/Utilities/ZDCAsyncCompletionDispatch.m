/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCAsyncCompletionDispatch.h"

@interface ZDCAsyncCompletionItem : NSObject {
@public
	
	NSMutableArray<dispatch_queue_t> * completionQueues;
	NSMutableArray<id>               * completionBlocks;
}
@end

@implementation ZDCAsyncCompletionItem

- (instancetype)init
{
	if ((self = [super init]))
	{
		completionQueues = [[NSMutableArray alloc] initWithCapacity:1];
		completionBlocks = [[NSMutableArray alloc] initWithCapacity:1];
	}
	return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCAsyncCompletionDispatch {
@private
	
	dispatch_queue_t queue;
	NSMutableDictionary<NSString *, ZDCAsyncCompletionItem *> *dict;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		queue = dispatch_queue_create("ZDCAsyncCompletionDispatch", DISPATCH_QUEUE_SERIAL);
		
		dict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (NSUInteger)pushCompletionQueue:(dispatch_queue_t)completionQueue
                  completionBlock:(id)completionBlock
                           forKey:(NSString *)key
{
	if (!completionBlock || !key)
		return 0;
	
	if (completionQueue == nil)
		completionQueue = dispatch_get_main_queue();
	
	__block NSUInteger count = 0;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		ZDCAsyncCompletionItem *item = dict[key];
		if (item == nil)
		{
			item = dict[key] = [[ZDCAsyncCompletionItem alloc] init];
		}
		
		[item->completionQueues addObject:completionQueue];
		[item->completionBlocks addObject:completionBlock];
		
		count = [item->completionBlocks count];
		
	#pragma clang diagnostic pop
	}});
	
	return count;
}

- (void)popCompletionQueues:(NSArray<dispatch_queue_t> **)completionQueuesPtr
           completionBlocks:(NSArray<id> **)completionBlocksPtr
                     forKey:(NSString *)key
{
	if (!key)
		return;
	
	__block ZDCAsyncCompletionItem *item = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		item = dict[key];
		if (item)
		{
			dict[key] = nil;
		}
		
	#pragma clang diagnostic pop
	}});
	
	if (completionQueuesPtr) *completionQueuesPtr = item ? item->completionQueues : nil;
	if (completionBlocksPtr) *completionBlocksPtr = item ? item->completionBlocks : nil;
}

@end
