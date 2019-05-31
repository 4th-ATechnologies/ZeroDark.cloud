#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This class helps to manage a list of <completionQueue, completionBlock> tuples
 * that need to be invoked upon the completion of some asynchronous task.
 *
 * In addition to storing the array of tuples,
 * this class provides the tools needed to atomically manage the array.
 */
@interface ZDCAsyncCompletionDispatch : NSObject

/**
 * Pushes the <completionQueue, completionBlock> tuple onto the the queue for the given key,
 * and returns the NEW count of the queue.
 *
 * Generally:
 * - if the returned count is 1, you should start the async task
 * - if the returned count is 2+, you can ignore the request, as you've already started the async task
 * - if the returned count is zero, you passed a nil key or a nil completionBlock
 */
- (NSUInteger)pushCompletionQueue:(nullable dispatch_queue_t)completionQueue
                  completionBlock:(id)completionBlock
                           forKey:(NSString *)key;

/**
 * Pops the entire queue for the given key.
 * You can now enumerate the lists, and invoke the completionBlocks with the result of the async task.
 */
- (void)popCompletionQueues:(NSArray<dispatch_queue_t> *_Nullable *_Nullable)completionQueuesPtr
           completionBlocks:(NSArray<id> *_Nullable *_Nullable)completionBlocksPtr
                     forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
