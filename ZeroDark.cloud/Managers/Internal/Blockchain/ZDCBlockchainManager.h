#import "ZeroDarkCloud.h"

#import "ZDCBlockchainProof.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents the nature of the error that occurred when attempting to fetch the blockchain proof.
 */
typedef NS_ENUM(NSInteger, BlockchainErrorCode) {
	/**
	 * The user doesn't have an entry in the blockchain yet.
	 * This is common for new users, as it may take a few days for the transaction to get mined.
	 */
	BlockchainErrorCode_NoBlockchainEntry,
	
	/**
	 * A network error occurred, possibly because of an Internet disconnection.
	 */
	BlockchainErrorCode_NetworkError,
	
	/**
	 * The blockchain contains a merkleTreeRoot value,
	 * but the corresponding merkleTree file appears to be missing from the server.
	 */
	BlockchainErrorCode_MissingMerkleTreeFile,
	
	/**
	 * The blockchain contains a merkleTreeRoot value,
	 * and we successfully downloaded the merkleTree file.
	 * However, the merkleTree file appears to be corrupt, likely due to tampering.
	 */
	BlockchainErrorCode_MerkleTreeTampering
};

/**
 * The BlockchainManager provides the functionality to fetch blockchain proofs of publicKeys.
 */
@interface ZDCBlockchainManager : NSObject

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Attempts to fetch the blockchain proof for the given user's public key.
 *
 * @important This method does NOT compare the proof with the user's local ZDCPublicKey value.
 *            It just performs the network operations to fetch the information.
 */
- (void)fetchBlockchainProofForUserID:(NSString *)userID
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(ZDCBlockchainProof *_Nullable proof, NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
