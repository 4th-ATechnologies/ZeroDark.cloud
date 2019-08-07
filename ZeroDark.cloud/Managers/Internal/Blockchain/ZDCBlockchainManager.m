#import "ZDCBlockchainManagerPrivate.h"

#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

#import "ZDCLogging.h"
#import "ZDCPublicKey.h"

#import "ZDCUser.h"


#import "EthereumRPC.h"

// Categories
#import "NSArray+S4.h"
#import "NSData+S4.h"
//#import "NSData+Utilities.h"
#import "NSError+S4.h"
#import "NSString+S4.h"
#import "NSURLResponse+ZeroDark.h"

// Libraries
#import <stdatomic.h>
//#import <S4/s4.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int ddLogLevel = DDLogLevelInfo;
#elif DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

#ifdef DDLogError
#define CKERROR                                                                     \
if(error) {                                                                       \
DDLogError(@"ERROR %@ %@:%d", error.localizedDescription, THIS_FILE, __LINE__); \
goto done;                                                                      \
}
#else
#define CKERROR \
if (error) {  \
goto done;  \
}
#endif

 
@implementation ZDCBlockchainManager
{
    __weak ZeroDarkCloud         *owner;
}


- (instancetype)init
{
    return nil; // To access this class use: ZeroDarkCloud.directoryManager (or use class methods)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
    if ((self = [super init]))
    {
        owner = inOwner;
    }
    return self;
}

- (NSError *)errorWithDescription:(NSString *)description
{
    NSDictionary *userInfo = nil;
    if (description)
        userInfo = @{ NSLocalizedDescriptionKey: description };
    
    NSString *domain = NSStringFromClass([self class]);
    return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

- (void)_fetchMerkleTreeFile:(NSString *)root
                 requesterID:(NSString *)requesterID
             completionQueue:(dispatch_queue_t)completionQueue
             completionBlock:(void (^)(NSDictionary * info, NSError *error))completionBlock
{
	DDLogAutoTrace();
	
	void (^InvokeCompletionBlock)(NSDictionary*, NSError*) = ^(NSDictionary *info, NSError *error){
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(info, error);
			}});
		}
	};
	
	if (!root)
	{
		InvokeCompletionBlock(nil, [self errorWithDescription:@"Bad parameter: root is nil"]);
		return;
	}
	
	if (!requesterID)
	{
		InvokeCompletionBlock(nil, [self errorWithDescription:@"Bad parameter: requesterID is nil"]);
		return;
	}
	
	[owner.restManager fetchMerkleTreeFile: root
	                      requesterID: requesterID
	                  completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                  completionBlock:
	^(NSURLResponse *urlResponse, id responseObject, NSError *error)
	{
		NSInteger statusCode = [urlResponse httpStatusCode];
		NSDictionary *jsonDict = nil;
		
		if (statusCode != 200)
		{
			error = [self errorWithDescription:@"Bad Status response"];
		}
		else if (!error)
		{
			if ([responseObject isKindOfClass:[NSData class]])
			{
				jsonDict = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:&error];
			}
			else if ([responseObject isKindOfClass:[NSDictionary class]])
			{
				jsonDict = (NSDictionary *)responseObject;
			}
		}
		
		InvokeCompletionBlock(jsonDict, error);
	}];
}



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

    /* verify we support the hash*/
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

    /* paramater check the dictionary */
    item = [treeDict objectForKey:@"values"];
    if(![item isKindOfClass:[NSArray class]])
    {
        error =  [self errorWithDescription:@"Bad parameter: merkle tree values not NSArray "];
        CKERROR;
    }
    values = (NSArray*) item;

    /* check merkle tree */
    for(id obj in values )
    {
        NSDictionary *info = nil;

        if([obj isKindOfClass:[NSString class]])
        {
            NSData* data=  [obj dataUsingEncoding:NSUTF8StringEncoding];
            if (data)
                info = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if(error)break;

            /* check if there is a key tha matches our pubkey */
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

    /* check merkle tree against root hash */
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

};


#pragma mark - public entry point

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

	[EthereumRPC fetchMerkleTreeRootForUserID:remoteUserID
							  completionQueue:bgQueue
							  completionBlock:^(NSError *error, NSString *merkleTreeRoot) {

		  if (error || merkleTreeRoot.length == 0)
		  {
			  InvokeCompletionBlock(nil, error);
			  return;
		  }


		  [self _fetchMerkleTreeFile: merkleTreeRoot
						 requesterID: localUserID
					 completionQueue: bgQueue
					 completionBlock:
		   ^(NSDictionary *treeDict, NSError *error)
		   {
			   if (error)
			   {
				   InvokeCompletionBlock(nil, error );
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

- (void)updateBlockChainRoot:(NSString *)blockchainTransaction
				   forUserID:(NSString *)userID
			 completionQueue:(nullable dispatch_queue_t)completionQueue
			 completionBlock:(nullable dispatch_block_t)completionBlock
{

	[owner.databaseManager.rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCUser* user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		if (user)
		{
			user = user.copy;
			user.blockchainTransaction  = blockchainTransaction;

			[transaction setObject:user
							forKey:user.uuid
					  inCollection:kZDCCollection_Users];

		}
	}
		completionQueue:completionQueue
		completionBlock:completionBlock];

}

@end
