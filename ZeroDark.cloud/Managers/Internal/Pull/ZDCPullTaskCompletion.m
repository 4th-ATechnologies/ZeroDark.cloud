/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPullTaskCompletion.h"

#import <YapDatabase/YapDatabaseAtomic.h>
#import <libkern/OSAtomic.h>
#import <os/lock.h>
#import <stdatomic.h>

@implementation ZDCPullTaskMultiCompletion {

	void (^incrementPendingCount)(uint);
}

@synthesize wrapper = wrapper;

- (instancetype)initWithPendingCount:(uint)inPendingCount
                 taskCompletionBlock:(ZDCPullTaskSingleCompletion)taskCompletionBlock
                finalCompletionBlock:(ZDCPullTaskCompletion)finalCompletionBlock
{
	if ((self = [super init]))
	{
		__block atomic_uint pendingCount = inPendingCount;
		
		__block YAPUnfairLock lock = YAP_UNFAIR_LOCK_INIT;
		__block ZDCPullTaskResult *cumulativeResult = nil;
		
		wrapper = ^(YapDatabaseReadWriteTransaction *transaction, ZDCPullTaskResult *result){ @autoreleasepool {
			
			uint remaining = atomic_fetch_sub(&pendingCount, 1) - 1;
			
			YAPUnfairLockLock(&lock);
			@try {
				
				if ((cumulativeResult == nil) || (result.pullResult != ZDCPullResult_Success))
				{
					cumulativeResult = result;
				}
			}
			@finally {
				YAPUnfairLockUnlock(&lock);
			}
			
			if (taskCompletionBlock) {
				taskCompletionBlock(transaction, result, remaining);
			}
			if (remaining == 0) {
				finalCompletionBlock(transaction, cumulativeResult);
			}
		}};
		
		incrementPendingCount = ^(uint increment){
			
			atomic_fetch_add(&pendingCount, increment);
		};
	}
	return self;
}

- (void)incrementPendingCount:(uint)increment
{
	incrementPendingCount(increment);
}

@end
