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
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchMerkleTreeFile:(NSString *)root
            completionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSDictionary *file, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(root != nil);
	NSParameterAssert(completionQueue != nil);
	NSParameterAssert(completionBlock != nil);
	
	void (^InvokeCompletionBlock)(NSDictionary*, NSError*) = ^(NSDictionary *file, NSError *error){
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(file, error);
		}});
	};
	
	__weak typeof(self) weakSelf = self;
	
	[zdc.restManager fetchMerkleTreeFile: root
	                     completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                     completionBlock:^(NSURLResponse *urlResponse, id responseObject, NSError *networkError)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		if (networkError)
		{
			NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_NetworkError underlyingError:networkError];
			
			InvokeCompletionBlock(nil, error);
			return;
		}
		
		NSInteger statusCode = [urlResponse httpStatusCode];
		if (statusCode != 200)
		{
			NSString *msg = [NSString stringWithFormat:@"Server returned status code %ld", (long)statusCode];
			NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_MissingMerkleTreeFile description:msg];
			
			InvokeCompletionBlock(nil, error);
			return;
		}
		
		NSDictionary *jsonDict = nil;
		if ([responseObject isKindOfClass:[NSDictionary class]])
		{
			jsonDict = (NSDictionary *)responseObject;
		}
		else if ([responseObject isKindOfClass:[NSData class]])
		{
			jsonDict = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
		}
		
		if (jsonDict)
		{
			InvokeCompletionBlock(jsonDict, nil);
		}
		else
		{
			NSString *msg = @"Server returned non-json-dictionary response";
			NSError *error = [strongSelf errorWithCode:BlockchainErrorCode_MissingMerkleTreeFile description:msg];
			
			InvokeCompletionBlock(nil, error);
		}
	}];
}

- (nullable ZDCMerkleTree *)verifyMerkleTreeFile:(NSDictionary *)file error:(NSError **)outError
{
	NSError *parseError = nil;
	ZDCMerkleTree *merkleTree = [ZDCMerkleTree parseFile:file error:&parseError];
	
	if (parseError)
	{
		// What do we do if the merkleTree file is corrupt ?
		//
		// It's possible the HTTP response returned something other than the merkleTree JSON file.
		// And it's possible the response, whatever it was, was also JSON.
		// So we're treating this like a missing merkle tree file, to be safe.
		//
		NSError *error = [self errorWithCode:BlockchainErrorCode_MissingMerkleTreeFile underlyingError:parseError];
		
		if (outError) *outError = error;
		return nil;
	}
	
	NSError *verifyError = nil;
	BOOL isVerified = [merkleTree hashAndVerify:&verifyError];
	
	if (!isVerified || verifyError)
	{
		NSError *error = [self errorWithCode:BlockchainErrorCode_MerkleTreeTampering underlyingError:verifyError];
		
		if (outError) *outError = error;
		return nil;
	}
	
	if (outError) *outError = nil;
	return merkleTree;
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
		
		[weakSelf fetchMerkleTreeFile: merkleTreeRoot
		              completionQueue: bgQueue
		              completionBlock:^(NSDictionary *merkleTreeFile, NSError *error)
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			if (error)
			{
				// The error already has BlockchainErrorCode set
				
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			ZDCMerkleTree *merkleTree = [strongSelf verifyMerkleTreeFile:merkleTreeFile error:&error];
			if (error)
			{
				// The error already has BlockchainErrorCode set
				
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
