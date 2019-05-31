#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDCBlockchainManager : NSObject

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
