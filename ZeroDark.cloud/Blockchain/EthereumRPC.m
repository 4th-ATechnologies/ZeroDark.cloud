/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "EthereumRPC.h"

#import "ZDCAsyncCompletionDispatch.h"
#import "ZDCUserPrivate.h"

#import "NSData+AWSUtilities.h"
#import "NSData+S4.h"
#import "NSString+S4.h"

#define ETHEREUM_CONTRACT_VERSION 3

#if (ETHEREUM_CONTRACT_VERSION == 2)
static NSString *const CONTRACT_ADDRESS_V2 = @"0xF8CadBCaDBeaC3B5192ba29DF5007746054102a4";
#elif (ETHEREUM_CONTRACT_VERSION == 3)
static NSString *const CONTRACT_ADDRESS_V3 = @"0x997715D0eb47A50D7521ed0D2D023624a4333F9A";
#endif

static NSString *const EMPTY_MERKLE_TREE_ROOT = @"0000000000000000000000000000000000000000000000000000000000000000";

@implementation EthereumRPC

static ZDCAsyncCompletionDispatch *pendingRequests;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		pendingRequests = [[ZDCAsyncCompletionDispatch alloc] init];
	});
}

+ (void)fetchMerkleTreeRootForUserID:(NSString *)inUserID
                     completionQueue:(dispatch_queue_t)inCompletionQueue
                     completionBlock:(void (^)(NSError *error, NSString *merkleTreeRoot))inCompletionBlock
{
#ifndef NS_BLOCK_ASSERTIONS
	NSParameterAssert(inUserID != nil);
	NSParameterAssert(inCompletionBlock != nil);
#else
	if (inCompletionBlock == nil) return;
#endif
	
	// Sanity checks
	
	if (![ZDCUser isUserID:inUserID])
	{
		dispatch_async(inCompletionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			
			if (inCompletionBlock) {
				inCompletionBlock(nil, nil);
			}
		}});
		return;
	}
	
	NSString *userID = [inUserID copy]; // mutable string protection
	
	// Network request consolidation
	
	NSUInteger requestCount =
		[pendingRequests pushCompletionQueue: inCompletionQueue
		                     completionBlock: inCompletionBlock
		                              forKey: userID];
	
	if (requestCount > 1)
	{
		// There's a previous request currently in-flight.
		// The <completionQueue, completionBlock> have been added to the existing request's list.
		return;
	}

	void (^completionBlock)(NSError*, NSString*) = ^(NSError *error, NSString *merkleTreeRoot) {
		
		if ([merkleTreeRoot isEqualToString:EMPTY_MERKLE_TREE_ROOT]) {
			merkleTreeRoot = nil;
		}
		
		NSArray<dispatch_queue_t> * completionQueues = nil;
		NSArray<id>               * completionBlocks = nil;
		[pendingRequests popCompletionQueues: &completionQueues
		                    completionBlocks: &completionBlocks
		                              forKey: userID];
		
		for (NSUInteger i = 0; i < completionBlocks.count; i++)
		{
			dispatch_queue_t completionQueue = completionQueues[i];
			void (^completionBlock)(NSError*, NSString*) = completionBlocks[i];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock(error, merkleTreeRoot);
			}});
		}
	};
	
	// Send network request
	
	NSString *userIDHex = [[NSData dataFromZBase32String:userID] lowercaseHexString];
	
#if (ETHEREUM_CONTRACT_VERSION == 3)
	[self v3_fetchMerkleTreeRootForUserIDHex:userIDHex completionBlock:completionBlock];
#elif (ETHEREUM_CONTRACT_VERSION == 2)
	[self v2_fetchMerkleTreeRootForUserIDHex:userIDHex completionBlock:completionBlock];
#else
	#error ETHEREUM_CONTRACT_VERSION has invalid version number !
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark v2
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if (ETHEREUM_CONTRACT_VERSION == 2)

+ (void)v2_fetchMerkleTreeRootForUserIDHex:(NSString *)userIDHex
                           completionBlock:(void (^)(NSError *error, NSString *merkleTreeRoot))completionBlock
{
	NSParameterAssert(userIDHex != nil);
	NSParameterAssert(completionBlock != nil);
	
	NSData *transactionData = [self v2_transactionDataForUserIDHex:userIDHex];
	
	NSString *transactionStr = [transactionData hexString];
	if (![transactionStr hasPrefix:@"0x"] && ![transactionStr hasPrefix:@"0X"]) {
		transactionStr = [@"0x" stringByAppendingString:transactionStr];
	}
	
	NSArray *eth_call_params = @[
		@{
			@"to"   : CONTRACT_ADDRESS_V2,
			@"data" : transactionStr
		},
		@"latest"
	];
	
	NSDictionary *body_json = @{
		@"jsonrpc" : @"2.0",
		@"method"  : @"eth_call",
		@"id"      : @(1),
		@"params"  : eth_call_params,
	};
	
	[self sendRequestWithBody: body_json
	          completionBlock:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		NSString *merkleTreeRoot = nil;
		if (data)
		{
			id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([obj isKindOfClass:[NSDictionary class]])
			{
				NSDictionary *dict = (NSDictionary *)obj;
				
				NSString *result = dict[@"result"];
				if ([result isKindOfClass:[NSString class]])
				{
					NSData *resultData = [NSData dataFromHexString:result];
					if (resultData)
					{
						merkleTreeRoot = [self v2_merkleTreeRootFromResponse:resultData];
					}
				}
			}
		}
		
		completionBlock(error, merkleTreeRoot);
	}];
}

+ (NSData *)v2_transactionDataForUserIDHex:(NSString *)userIDHex
{
	// Data Layout:
	//
	// - First 4 bytes : Function signature
	// - Next 32 bytes : bytes20 (aligned left) : userID
	// - Next 32 bytes : uint8   (aligned left) : hashTypeID
	//

	NSMutableData *data = [NSMutableData dataWithCapacity:(8+32+32)];

	{
		NSString *functionSig = [self v2_functionSig];
		NSData *functionSigData = [NSData dataFromHexString:functionSig];

		[data appendData:functionSigData];
	}
	{
		NSData *nameData = [NSData dataFromHexString:userIDHex];
		NSAssert(nameData.length == 20, @"Invalid userIDHex");

		[data appendData:nameData]; // 20 bytes (160 bits)
		[data increaseLengthBy:12]; // 12 bytes
	}
	{
		// Since we're sending hashTypeID == 0,
		// we just need 32 bytes of zero.

		[data increaseLengthBy:32];
	}

	return data;
}

+ (NSString *)v2_functionSig
{
	// The function identifier is generated via:
	// `<functionName>(<param_type_1>,...)`
	//
	// For example:
	// `getMerkleTreeRoot(bytes20,uint8)`
	//
	// The function signature is generated via
	// hex(keccak256(utf8(<function_id>))).substring(0, 8)

	// S4 doesn't support KECCAK, so we're hard-coding this for now.
	return @"4326e22b";
}

+ (NSString *)v2_merkleTreeRootFromResponse:(NSData *)data
{
	// The response value is of type `bytes`,
	// which is a dynamically sized element.
	//
	// Data Layout:
	// - 32 bytes : Offset (of where dynamic value is stored)
	// - 32 bytes : Length of `bytes`
	// -  X bytes : Actual value
	//
	// This looks goofy and wasteful when there's only a single value,
	// but makes a little more sense when there's several parameter values being passed.

	NSString *merkleTreeRoot = nil;

	uint32_t global_offset = 0;
	uint32_t bytes_length = 0;

	// First we extract the offset.
	// We expect this to be:
	// - base16 (hex) : 0x20
	// - base10 (dec) : 32

	{
		uint32_t section_offset = (32 /*bytes*/ - (32 /*bits*/ / 8 /*bits per byte*/));
		uint32_t local_offset = global_offset + section_offset;

		// Safety Note:
		// The `extractUInt32AtOffset::` method checks for out-of-bounds issues, and returns 0 if detected.
		uint32_t data_offset = [data extractUInt32AtOffset:local_offset andConvertFromNetworkOrder:YES];

		global_offset += data_offset;
	}
	{
		uint32_t section_offset = (32 /*bytes*/ - (32 /*bits*/ / 8 /*bits per byte*/));
		uint32_t local_offset = global_offset + section_offset;

		// Safety Note:
		// The `extractUInt32AtOffset::` method checks for out-of-bounds issues, and returns 0 if detected.
		bytes_length = [data extractUInt32AtOffset:local_offset andConvertFromNetworkOrder:YES];

		global_offset += 32;
	}

	NSRange range = (NSRange){
		.location = global_offset,
		.length   = bytes_length
	};

	if (data.length >= NSMaxRange(range))
	{
		NSData *value = [data subdataWithRange:range];
		merkleTreeRoot = [value hexString];
	}
	
	return merkleTreeRoot;
}

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark v3
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if (ETHEREUM_CONTRACT_VERSION == 3)

+ (void)v3_fetchMerkleTreeRootForUserIDHex:(NSString *)userIDHex
                        completionBlock:(void (^)(NSError *error, NSString *merkleTreeRoot))completionBlock
{
	NSParameterAssert(userIDHex != nil);
	NSParameterAssert(completionBlock != nil);
	
	NSData *transactionData = [self v3_transactionDataForUserIDHex:userIDHex];
	
	NSString *transactionStr = [transactionData lowercaseHexString];
	if (![transactionStr hasPrefix:@"0x"] && ![transactionStr hasPrefix:@"0X"]) {
		transactionStr = [@"0x" stringByAppendingString:transactionStr];
	}
	
	NSArray *eth_call_params = @[
		@{
			@"to"   : CONTRACT_ADDRESS_V3,
			@"data" : transactionStr
		},
		@"latest"
	];
	
	NSDictionary *body_json = @{
		@"jsonrpc" : @"2.0",
		@"method"  : @"eth_call",
		@"id"      : @(1),
		@"params"  : eth_call_params,
	};
	
	[self sendRequestWithBody: body_json
	          completionBlock:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		NSString *merkleTreeRoot = nil;
		if (data)
		{
			id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([obj isKindOfClass:[NSDictionary class]])
			{
				NSDictionary *dict = (NSDictionary *)obj;
				
				NSString *result = dict[@"result"];
				NSDictionary * errorDict =  dict[@"error"];
	 
				if ([result isKindOfClass:[NSString class]])
				{
					NSData *resultData = [NSData dataFromHexString:result];
					if (resultData)
					{
						merkleTreeRoot = [self v3_merkleTreeRootFromResponse:resultData];
					}
				}
				else if(errorDict && [errorDict isKindOfClass:[NSDictionary class]])
				{
					NSString* errMsg =  errorDict[@"message"];
					NSInteger errCode = [errorDict[@"code"] integerValue];
					NSError* eth_Error = [self errorWithDescription:errMsg statusCode:errCode];
					error = eth_Error;
				}
				
			}
		}
		
		completionBlock(error, merkleTreeRoot);
	}];
}

+ (NSData *)v3_transactionDataForUserIDHex:(NSString *)userIDHex
{
	// Data Layout:
	//
	// - First 4 bytes : Function signature
	// - Next 32 bytes : bytes20 (aligned left) : userID
	
	NSMutableData *data = [NSMutableData dataWithCapacity:(8+32)];
	
	{
		NSString *functionSig = [self v3_functionSig];
		NSData *functionSigData = [NSData dataFromHexString:functionSig];
		
		[data appendData:functionSigData];
	}
	{
		NSData *nameData = [NSData dataFromHexString:userIDHex];
		NSAssert(nameData.length == 20, @"Invalid userIDHex");
		
		[data appendData:nameData]; // 20 bytes (160 bits)
		[data increaseLengthBy:12]; // 12 bytes
	}
	
	return data;
}

+ (NSString *)v3_functionSig
{
	// The function identifier is generated via:
	// `<functionName>(<param_type_1>,...)`
	//
	// For example:
	// `getMerkleTreeRoot(bytes20,uint8)`
	//
	// The function signature is generated via
	// hex(keccak256(utf8(<function_id>))).substring(0, 8)
	
	// getMerkleTreeRoot : 0xee94c797
	// getBlockNumber    : 0x47378145
	// getUserInfo       : 0x829a34c6
	
	// S4 doesn't support KECCAK, so we're hard-coding this for now.
	
	return @"0xee94c797";
}

+ (NSString *)v3_merkleTreeRootFromResponse:(NSData *)data
{
	// The response value is of type `bytes32`.
	//
	// Data Layout:
	// - 32 bytes : Actual value
	
	NSString *merkleTreeRoot = nil;
	
	if (data.length == 32)
	{
		merkleTreeRoot = [data lowercaseHexString];
	}
	
	return merkleTreeRoot;
}

#endif
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark HTTPS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)sendRequestWithBody:(NSDictionary *)body_json
            completionBlock:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionBlock
{
	NSError *error = nil;
	NSData *body_data = [NSJSONSerialization dataWithJSONObject:body_json options:0 error:&error];
	
	if (error)
	{
		// Internal method: non-async completionBlock supported
		completionBlock(nil, nil, error);
		return;
	}
	
	NSString *const accessToken = @"94cbbe9f44574c19af2335390473a778";
	NSString *const urlStr = [NSString stringWithFormat:@"https://mainnet.infura.io/v3/%@", accessToken];
	
	NSURL *url = [NSURL URLWithString:urlStr];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:body_data];
	
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
	
	NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:completionBlock];
	[task resume];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description)
		userInfo = @{ NSLocalizedDescriptionKey: description };
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

+ (NSError *)errorWithDescription:(NSString *)description statusCode:(NSUInteger)statusCode
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:statusCode userInfo:userInfo];
}

@end
