#import "ZDCBlockchainManager.h"

#import "EthereumRPC.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
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
#pragma mark Undocumented Code
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
- (BOOL)checkBlockEntry:(NSDictionary*)entry
                forPubKey:(ZDCPublicKey *)pubKey
                  error:(NSError**)errorOut
{

    NSError* error = nil;
    BOOL result = NO;

    NSString* keyID = entry[@"keyID"];              // hex value
    NSString* pubKeyHash = entry[@"pubKeyHash"];    // hex value
    NSString* hashName = entry[@"description"];

    NSData *pubData = nil;
    NSData *keyIDData = nil;
    NSData *hashData = nil;

    HASH_Algorithm hashAlgor = kHASH_Algorithm_Invalid;
    HASH_ContextRef hashCtx =  kInvalidHASH_ContextRef;
    size_t  hashSize = 0;

    S4Err       err         = kS4Err_NoErr;
    uint8_t     hashBuf [512/8];   //SHA512

    NSData *pubKeyHashData = [NSData dataFromHexString:pubKeyHash];
    NSData* pubKeyKeyIDData = [[NSData alloc] initWithBase64EncodedString:pubKey.keyID options:0];

    // get the user's public key
    pubData =  [[NSData alloc] initWithBase64EncodedString: [pubKey.keyDict objectForKey:@"pubKey"] options:0];
    keyIDData = [NSData dataFromHexString:keyID];

    if(![keyIDData isEqualToData:pubKeyKeyIDData])
    {
        error =  [self errorWithDescription:@"blockchain keyID mismatch"];
    }
    CKERROR;

    if([hashName isEqualToString:@"sha512"])
    {
        hashAlgor = kHASH_Algorithm_SHA512;
    }
    else if([hashName isEqualToString:@"sha256"])
    {
         hashAlgor = kHASH_Algorithm_SHA256;
    }

    err = HASH_Init(hashAlgor, &hashCtx); CKERR;
    err = HASH_GetSize(hashCtx, &hashSize);CKERR;
    err = HASH_Update(hashCtx, pubData.bytes, pubData.length); CKERR;
    err = HASH_Final(hashCtx, hashBuf); CKERR;
    hashData = [NSData dataWithBytesNoCopy:hashBuf length:hashSize freeWhenDone:NO];

    if(![hashData isEqualToData:pubKeyHashData])
    {
        error =  [self errorWithDescription:@"blockchain hash mismatch"];
    }
    CKERROR;

    result = YES;

done:

    if(hashCtx)
        HASH_Free(hashCtx);

	 if(IsS4Err(err))
            error = [NSError errorWithS4Error:err];


    if(errorOut)
        *errorOut = error;

    return result;
}
*/

/*
- (BOOL)verifyMerkleTree:(NSDictionary*)treeDict
                withRoot:(NSString*)rootIn
               usingHash:(NSString*)hashName
               forUserID:(NSString *)userIDIn
                pubKeyID:(NSData *)keyIDIn
                  pubKey:(NSData *)pubKeyIn
                   error:(NSError**)errorOut
{
    BOOL result = NO;
    __block NSError* error = nil;
    __block NSDictionary* matchingValueDict = nil;

    id item = nil;
    NSArray* values = nil;
    NSMutableArray* valueHashes = nil;

    // verify we support the hash
    HASH_Algorithm hashAlgor = kHASH_Algorithm_Invalid;
   if([hashName isEqualToString:@"sha512"])
    {
        hashAlgor = kHASH_Algorithm_SHA512;
    }
    else if([hashName isEqualToString:@"sha256"])
    {
        hashAlgor = kHASH_Algorithm_SHA256;
    }

    if(hashAlgor  == kHASH_Algorithm_Invalid)
    {
        error =  [self errorWithDescription:@"Bad parameter: hash algorithm not supported"];
        CKERROR;

    }

    // paramater check the dictionary
    item = [treeDict objectForKey:@"values"];
    if(![item isKindOfClass:[NSArray class]])
    {
        error =  [self errorWithDescription:@"Bad parameter: merkle tree values not NSArray "];
        CKERROR;
    }
    values = (NSArray*) item;

    // check merkle tree
    for(id obj in values )
    {
        NSDictionary *info = nil;

        if([obj isKindOfClass:[NSString class]])
        {
            NSData* data=  [obj dataUsingEncoding:NSUTF8StringEncoding];
            if (data)
                info = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if(error)break;

            // check if there is a key tha matches our pubkey
            NSString* entryUserID = info[@"userID"];
            if([userIDIn isEqualToString:entryUserID])
            {
                NSData* entryKeyID  =   [[NSData alloc]
                                         initWithBase64EncodedString:info[@"keyID"] options:0];
                NSData* entryPubKey = [[NSData alloc]
                                       initWithBase64EncodedString:info[@"pubKey"] options:0];
                
                if(![entryKeyID isEqualToData:keyIDIn])
                    error = [self errorWithDescription:@"Key ID mismatch"];
                if(error) break;
                
                if(![entryPubKey isEqualToData:pubKeyIn])
                    error = [self errorWithDescription:@"Public Key mismatch"];
                if(error) break;
                
                matchingValueDict = info;
                break;
            }
            if(!valueHashes)
                    valueHashes = NSMutableArray.array;

            NSString* value = (NSString*) obj;
            NSData* hValue = [value hashWithAlgorithm:kHASH_Algorithm_SHA256   error:&error];
             if(error)break;

            [valueHashes addObject:hValue.hexString];
      }
    }
    CKERROR;

    // check merkle tree against root hash
    {
        NSString* rootHash =  [valueHashes merkleHashWithAlgorithm:kHASH_Algorithm_SHA256
                                                             error:&error];
        CKERROR;

        if([rootIn isEqualToString:rootHash])
        {
            error =  [self errorWithDescription:@"merkle tree hash failed "];
            CKERROR;
        }
    }

    if(!matchingValueDict)
    {
        error =  [self errorWithDescription:@"Bad parameter: user not found in this tree "];
        CKERROR;
    }

      result = YES;

done:

    if(errorOut)
        *errorOut = error;

    return result;
}
*/

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Undocumented Code
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
- (void)fetchBlockchainRootForUserID:(NSString *)remoteUserID
                         requesterID:(NSString *)localUserID
                     completionQueue:(dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(NSString *merkleTreeRoot, NSError *error))completionBlock
{

	void (^InvokeCompletionBlock)(NSString*, NSError *) = ^(NSString *merkleTreeRoot, NSError *error){

		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(merkleTreeRoot, error);
			}});
		}
	};

	__block ZDCUser *targetUser = nil;
	__block ZDCPublicKey *pubKey = nil;

	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {

		targetUser = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
		pubKey = [transaction objectForKey:targetUser.publicKeyID inCollection:kZDCCollection_PublicKeys];
	}];

	//    if(targetUser.blockChainTransaction)
	//    {
	//        InvokeCompletionBlock(targetUser.blockChainTransaction, nil);
	//        return;
	//    }

	if (!pubKey)
	{
		InvokeCompletionBlock(nil, [self errorWithDescription:@"Bad parameter: no public key for user"]);
		return;
	}

	// get the user's public key data
	NSData* pubData =  [[NSData alloc] initWithBase64EncodedString: [pubKey.keyDict objectForKey:@"pubKey"] options:0];
	NSData* pubKeyKeyIDData = [[NSData alloc] initWithBase64EncodedString:pubKey.keyID options:0];

	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

	[EthereumRPC fetchMerkleTreeRootForUserID: remoteUserID
	                          completionQueue: bgQueue
	                          completionBlock:^(NSError *error, NSString *merkleTreeRoot)
	{
		if (error || merkleTreeRoot.length == 0)
		{
			InvokeCompletionBlock(nil, error);
			return;
		}
		
		[self fetchMerkleTreeFile: merkleTreeRoot
		              requesterID: localUserID
		          completionQueue: bgQueue
		          completionBlock:
		^(NSDictionary *treeDict, NSError *error)
		{
			if (error)
			{
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			[self verifyMerkleTree: treeDict
			              withRoot: merkleTreeRoot
			             usingHash: @"sha256"
			             forUserID: targetUser.uuid
			              pubKeyID: pubKeyKeyIDData
			                pubKey: pubData
			                 error: &error];

			InvokeCompletionBlock(merkleTreeRoot, error);
		}];
	}];
}
*/

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
                requesterID:(NSString *)requesterID
            completionQueue:(dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSDictionary *file, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	NSParameterAssert(root != nil);
	NSParameterAssert(requesterID != nil);
	NSParameterAssert(completionQueue != nil);
	NSParameterAssert(completionBlock != nil);
	
	void (^InvokeCompletionBlock)(NSDictionary*, NSError*) = ^(NSDictionary *file, NSError *error){
		
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(file, error);
		}});
	};
	
	__weak typeof(self) weakSelf = self;
	
	[zdc.restManager fetchMerkleTreeFile: root
	                         requesterID: requesterID
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

- (nullable NSError *)verifyMerkleTreeFile:(NSDictionary *)file
{
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchBlockchainInfoForUserID:(NSString *)remoteUserID
                         requesterID:(NSString *)localUserID
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(NSError *error))completionBlock
{
	void (^InvokeCompletionBlock)(NSString*, NSError *) = ^(NSString *merkleTreeRoot, NSError *error){

		if (!completionBlock) return;
		
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			completionBlock(error);
		}});
	};
	
	__weak typeof(self) weakSelf = self;
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	__block void (^queryBlockchain)(void);
	__block void (^fetchMerkleTreeFile)(NSString *merkleTreeRoot);
	
	queryBlockchain = ^void (){ @autoreleasepool {
		
		[EthereumRPC fetchMerkleTreeRootForUserID: remoteUserID
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
		                  requesterID: localUserID
		              completionQueue: bgQueue
		              completionBlock:^(NSDictionary *file, NSError *error)
		{
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			if (error)
			{
				// The error already has BlockchainErrorCode set
				
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			error = [strongSelf verifyMerkleTreeFile:file];
			if (error)
			{
				// The error already has BlockchainErrorCode set
				
				InvokeCompletionBlock(nil, error);
				return;
			}
			
			
		}];
	}};
	
	queryBlockchain();
}

@end
