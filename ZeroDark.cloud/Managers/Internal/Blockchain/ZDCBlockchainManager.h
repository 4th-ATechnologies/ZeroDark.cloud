#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BlockchainErrorCode) {
	BlockchainErrorCode_NoBlockchainEntry,
	BlockchainErrorCode_NetworkError,
	BlockchainErrorCode_MissingMerkleTreeFile,
	BlockchainErrorCode_MerkleTreeTampering,
	BlockchainErrorCode_PubKeyTampering,
	
};

@interface ZDCBlockchainManager : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Undocumented - must now be rewritten
 */
/*
- (void)fetchBlockchainRootForUserID:(NSString *)remoteUserID
                         requesterID:(NSString *)localUserID
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(NSString *merkleTreeRoot, NSError *error))completionBlock;
*/

/**
 * New version
 */
- (void)fetchBlockchainInfoForUserID:(NSString *)remoteUserID
                         requesterID:(NSString *)localUserID
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(NSError *error))completionBlock;

@end

NS_ASSUME_NONNULL_END
