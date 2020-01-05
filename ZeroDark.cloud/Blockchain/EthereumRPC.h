/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates code to query the blockchain for information.
 */
@interface EthereumRPC : NSObject

/**
 * Queries the blockchain for the given user's value, which is a merkleTreeRoot.
 * 
 * Detailed information about the smart contract can be found here:
 * https://zerodarkcloud.readthedocs.io/en/latest/overview/ethereum/
 */
+  (void)fetchMerkleTreeRootForUserID:(NSString *)userID
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSError *error, NSString *merkleTreeRoot))completionBlock;

@end

NS_ASSUME_NONNULL_END
