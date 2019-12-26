/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCBlockchainProof.h"

@interface ZDCBlockchainProof ()

- (instancetype)initWithMerkleTreeRoot:(NSString *)merkleTreeRoot
                           blockNumber:(NSUInteger)blockNumber
                                pubKey:(NSString *)pubKey
                                 keyID:(NSString *)keyID;

@end
