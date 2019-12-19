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
@interface ZDCBlockchainProof : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic, readonly) NSString *merkleTreeRoot;

@property (nonatomic, readonly) NSUInteger blockNumber;

@property (nonatomic, readonly) NSString *merkleTreeFile_pubKey;
@property (nonatomic, readonly) NSString *merkleTreeFile_keyID;

@end

NS_ASSUME_NONNULL_END
