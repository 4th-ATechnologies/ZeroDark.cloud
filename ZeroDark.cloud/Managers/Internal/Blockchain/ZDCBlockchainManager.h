#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCBlockchainManager : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (void)fetchBlockchainRootForUserID:(NSString *)remoteUserID
						 requesterID:(NSString *)localUserID
					 completionQueue:(nullable dispatch_queue_t)completionQueue
					 completionBlock:(void (^)(NSString *merkleTreeRoot, NSError *error))completionBlock;

- (void)updateBlockChainRoot:(NSString *)blockchainTransaction
				   forUserID:(NSString *)userID
			  completionQueue:(nullable dispatch_queue_t)completionQueue
			 completionBlock:(nullable dispatch_block_t)completionBlock;

@end

NS_ASSUME_NONNULL_END
