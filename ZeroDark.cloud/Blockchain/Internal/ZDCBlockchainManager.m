#import "ZDCBlockchainManager.h"

#import "EthereumRPC.h"
#import "ZDCBlockchainProofPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZDCMerkleTree.h"
#import "ZDCPublicKey.h"
#import "ZDCUser.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSArray+S4.h"
#import "NSData+S4.h"
#import "NSError+S4.h"
#import "NSString+S4.h"
#import "NSURLResponse+ZeroDark.h"

// Libraries
#import <stdatomic.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelInfo;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

 
@implementation ZDCBlockchainManager {
	
	__weak ZeroDarkCloud *zdc;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.blockchainManager (or use class methods)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner
{
	if ((self = [super init]))
	{
		zdc = owner;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithCode:(BlockchainErrorCode)code description:(nullable NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

- (NSError *)errorWithCode:(BlockchainErrorCode)code underlyingError:(nullable NSError *)underlyingError
{
	NSDictionary *userInfo = nil;
	if (underlyingError) {
		userInfo = @{ NSUnderlyingErrorKey: underlyingError };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (void)fetchBlockchainProofForUserID:(NSString *)inUserID
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(ZDCBlockchainProof *proof, NSError *error))completionBlock
{
	NSString *userID = [inUserID copy];
	
	void (^InvokeCompletionBlock)(ZDCBlockchainProof*, NSError *) = ^(ZDCBlockchainProof *proof, NSError *error){

		if (!completionBlock) return;
		
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			completionBlock(proof, error);
		}});
	};
	
	__weak typeof(self) weakSelf = self;
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__block void (^queryBlockchain)(void);
	__block void (^fetchMerkleTreeFile)(NSString *merkleTreeRoot);
	
	queryBlockchain = ^void (){ @autoreleasepool {
		
		[EthereumRPC fetchMerkleTreeRootForUserID: userID
		                          completionQueue: bgQueue
		                          completionBlock:^(NSError *networkError, NSString *merkleTreeRoot)
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
	
			if (networkError)
			{
				NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_NetworkError underlyingError:networkError];
	
				InvokeCompletionBlock(nil, error);
				return;
			}
	
			if (merkleTreeRoot.length == 0)
			{
				NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_NoBlockchainEntry description:nil];
	
				InvokeCompletionBlock(nil, error);
				return;
			}
	
			// Next step
			fetchMerkleTreeFile(merkleTreeRoot);
		}];
	}};
	
	fetchMerkleTreeFile = ^void (NSString *merkleTreeRoot){ @autoreleasepool {
		
		ZDCRestManager *restManager = nil;
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf) {
				restManager = strongSelf->zdc.restManager;
			}
		}

		[restManager fetchMerkleTreeFile: merkleTreeRoot
		                 completionQueue: bgQueue
		                 completionBlock:^(NSURLResponse *urlResponse, ZDCMerkleTree *merkleTree, NSError *fetchError)
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			if (fetchError)
			{
				NSInteger statusCode = [urlResponse httpStatusCode];
				
				if (statusCode == 0) // network error
				{
					NSError *error =
					  [strongSelf errorWithCode:BlockchainErrorCode_NetworkError underlyingError:fetchError];
					
					InvokeCompletionBlock(nil, error);
					return;
				}
				else if (statusCode != 200) // probably a 404
				{
					NSString *msg = [NSString stringWithFormat:@"Server returned status code %ld", (long)statusCode];
					NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_MissingMerkleTreeFile description:msg];
					
					InvokeCompletionBlock(nil, error);
					return;
				}
				else // unexpected response from server
				{
					NSError *error =
					  [strongSelf errorWithCode:BlockchainErrorCode_MissingMerkleTreeFile underlyingError:fetchError];
					
					InvokeCompletionBlock(nil, error);
					return;
				}
			}
			
			NSError *verifyError = nil;
			BOOL isVerified = [merkleTree hashAndVerify:&verifyError];
			
			if (!isVerified || verifyError)
			{
				NSError *error =
				  [strongSelf errorWithCode:BlockchainErrorCode_MerkleTreeTampering underlyingError:verifyError];
				
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			if (![merkleTreeRoot isEqual:merkleTree.rootHash])
			{
				NSString *msg = @"Downloaded merkleTreeFile doesn't match merkleTreeRoot request.";
				NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_MerkleTreeTampering description:msg];
				
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			NSString *pubKey = nil;
			NSString *keyID = nil;
			
			if (![merkleTree getPubKey:&pubKey keyID:&keyID forUserID:userID])
			{
				NSString *msg = @"Downloaded merkleTreeFile doesn't contain entries for user.";
				NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_MerkleTreeTampering description:msg];
				
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			ZDCBlockchainProof *proof =
			  [[ZDCBlockchainProof alloc] initWithMerkleTreeRoot: merkleTreeRoot
			                                         blockNumber: 0
			                                              pubKey: pubKey
			                                               keyID: keyID];
			
			// Success!
			InvokeCompletionBlock(proof, nil);
		}];
	}};
	
	// Start
	queryBlockchain();
}

@end
