/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface EthereumRPC : NSObject

+  (void)fetchMerkleTreeRootForUserID:(NSString *)userID
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSError *error, NSString *merkleTreeRoot))completionBlock;

@end

NS_ASSUME_NONNULL_END
