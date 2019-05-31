/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface EthereumRPC : NSObject

+  (void)fetchMerkleTreeRootForUserID:(NSString *)userID
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSError *error, NSString *merkleTreeRoot))completionBlock;

@end

NS_ASSUME_NONNULL_END
