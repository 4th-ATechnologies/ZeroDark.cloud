/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCBlockchainProof.h"

static NSString *const k_merkleTreeRoot = @"merkleTreeRoot";
static NSString *const k_blockNumber    = @"blockNumber";
static NSString *const k_pubKey         = @"pubKey";
static NSString *const k_keyID          = @"keyID";


@implementation ZDCBlockchainProof

@synthesize merkleTreeRoot = _merkleTreeRoot;
@synthesize blockNumber = _blockNumber;
@synthesize merkleTreeFile_pubKey = _pubKey;
@synthesize merkleTreeFile_keyID = _keyID;

- (instancetype)initWithMerkleTreeRoot:(NSString *)merkleTreeRoot
									blockNumber:(NSUInteger)blockNumber
                                pubKey:(NSString *)pubKey
                                 keyID:(NSString *)keyID
{
	if ((self = [super init]))
	{
		_merkleTreeRoot = [merkleTreeRoot copy];
		_blockNumber = blockNumber;
		_pubKey = [pubKey copy];
		_keyID = [keyID copy];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		_merkleTreeRoot = [decoder decodeObjectOfClass:[NSString class] forKey:k_merkleTreeRoot];
		_blockNumber = (NSUInteger)[decoder decodeInt64ForKey:k_blockNumber];
		_pubKey = [decoder decodeObjectOfClass:[NSString class] forKey:k_pubKey];
		_keyID = [decoder decodeObjectOfClass:[NSString class] forKey:k_keyID];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_merkleTreeRoot forKey:k_merkleTreeRoot];
	[coder encodeInt64:(int64_t)_blockNumber forKey:k_blockNumber];
	[coder encodeObject:_pubKey forKey:k_pubKey];
	[coder encodeObject:_keyID forKey:k_keyID];
}

- (id)copyWithZone:(NSZone *)zone
{
	return self; // immutable
}

@end
