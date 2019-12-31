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
 * If the user's public key has been verified on the blockchain,
 * this class encompasses information about the proof.
 */
@interface ZDCBlockchainProof : NSObject <NSSecureCoding, NSCopying>

/**
 * The merkleTreeRoot value is stored on the blockchain (i.e. within the smart contract).
 *
 * This value is a reference to a merkleTreeFile that can be fetched from the server.
 * For example, if the merkleTreeRoot value is
 * "cd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1",
 * then you could fetch the corresponding JSON file at
 * https://blockchain.storm4.cloud/cd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1.json
 *
 * The RestManager has an API to fetch this file for you, given a merkleTreeRoot value:
 * `-[ZDCRestManager fetchMerkleTreeFile:completionQueue:completionBlock:]`
 *
 * The merkleTreeFile is a JSON file that allows you to independently verify the public key information.
 * You can use the ZDCMerkleTree class to parse & validate this file.
 */
@property (nonatomic, readonly) NSString *merkleTreeRoot;

/**
 * The smart contract is coded such that, when a user's merkleTreeRoot is stored in the contract,
 * it also records the blockNumber at which the proof was submitted.
 *
 * This information can be used to determine when the user's publicKey proof was posted to the blockchain.
 */
@property (nonatomic, readonly) NSUInteger blockNumber;

/**
 * Stores the pubKey value that was recorded in the merkleTreeFile.
 */
@property (nonatomic, readonly) NSString *merkleTreeFile_pubKey;

/**
 * Stores the keyID value that was recorded in the merkleTreeFile.
 */
@property (nonatomic, readonly) NSString *merkleTreeFile_keyID;

@end

NS_ASSUME_NONNULL_END
