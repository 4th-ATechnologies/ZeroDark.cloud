//
//  ZDCAccessCode.m
//  ZeroDarkCloud
//
//  Created by vinnie on 3/12/19.
//

#import "ZDCAccessCode.h"
#import "ZeroDarkCloudPrivate.h"
#import "AWSURL.h"

// Categories
#import "NSError+ZeroDark.h"
#import "NSError+S4.h"
#import "NSString+ZeroDark.h"
#import "NSData+ZeroDark.h"
#import "NSData+S4.h"
#import "NSArray+S4.h"

#if TARGET_OS_IPHONE
#import "UIColor+Crayola.h"
#else
#import "NSColor+Crayola.h"
#endif

static const uint colorCount = 11;

/*
 
 The encoded  accessKey data string  we feed to QRcodes looks like the following
 
 storm4://clone2/b3o8qh8gy4fzfiwrrho3wd9dtjypryue/ADgBIPklYzgqIKb3LQslam0ge1GJFyYeOK61HeDXVVelBzUn6ULgS006iinH5kkMF%2FGEdgAC7zM%3D/DkJwTwiF3p%2FXvyiLTVFqUnXKDccMeu6SSMtWqYqcdqpkpTQJM3J%2BCwlXs5jKZZQiSHBeO0pnFh5Bv38Bcb7PLh3dhqiexClxFcakTnUT5fyxmVLmKHAfUajlSh99ySGrH%2BbFeg%3D%3D
 
 scheme : storm4
 path : clone2 / <userID> / base64(pbkdf2-wrapped-encrypting-key) / base64(encryptedAccessKeyData)
 
 the decoded pbkdf2-wrapped-encrypting-key is of the form:
 ---
 <totalLen (2b) >
 <version (1) >
 <encrypted key len (1)>
 <PBKDF2 encrypting key (32b) >
 <mac (8b) >
 <salt (8b) ><
 rounds (4b)>
 --
 
 the decoded access key  is encrypted to the pbkdf2-wrapped-encrypting-key
 using the S4Crypto CBC_EncryptPAD - the ciphertext version of this looks like
 
 <IV (32b)>
 <xxHash32 checksum (4b)
 <padded data -- typically 64 bytes)
 
 the decrypted data is typically 33 bytes.  where
 <algorithm ( kCipher_Algorithm_2FISH256 (1b) >
 < access key (32 bytes)
 
 
 */

NSString *const kZDCSplitKeyProp_ShareNum  = @"shareNum";

@implementation ZDCAccessCode

static NSString *const kEncyptedAccessKey_Key = @"encyptedAccessKey";

+ (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

+ (BOOL)isValidCodeString:(NSString *)codeString
					 forUserID:(NSString *)userIDIn
{
	BOOL isValid = NO;
	
	if ([codeString isKindOfClass:[NSString class]])
	{
		NSURL* url = [NSURL URLWithString:codeString];
		NSString* userID = nil;
		
		if ([self parseCloneCodeURL: url
									userID: &userID
							cloneKeyData: nil
					encryptedCloneData: nil
									 error: nil])
		{
			isValid = YES;
			if (userIDIn) {
				isValid = [userID isEqualToString:userIDIn];
			}
		}
	}
	
	return isValid;
}

+ (BOOL)isValidShareString:(NSString *)shareString
					  forUserID:(NSString *)userIDIn
{
	BOOL isValid = NO;
	
	if ([shareString isKindOfClass:[NSString class]])
	{
		NSURL* url = [NSURL URLWithString:shareString];
		NSString* userID = nil;
		
		if ([self parseShareCodeURL: url
									userID: &userID
						  shareCodeData: nil
									 error: nil])
		{
			isValid = YES;
			if (userIDIn) {
				isValid = [userID isEqualToString:userIDIn];
			}
		}
	}
	
	return isValid;
}

+ (BOOL)parseShareCodeURL:(NSURL*)url
						 userID:(NSString **)userIDOut
				shareCodeData:(NSString **)shareCodeDataOut
						  error:(NSError **)errorOut
{
	NSError*   error = nil;
	BOOL isValid = NO;
	
	if ([url.scheme isEqualToString:@"storm4"]
		 &&  [url.host isEqualToString:@"share" ])
	{
		NSArray* parts = [url.resourceSpecifier componentsSeparatedByString:@"/"];
		
		if(parts.count == 5)
		{
			NSString* userID = parts[3];
			NSString* shareCodeData = [parts[4] stringByRemovingPercentEncoding];
			
			if(userIDOut) *userIDOut = userID;
			if(shareCodeDataOut) *shareCodeDataOut = shareCodeData;
			isValid = YES;
		}
	}
	
	if(!isValid) {
		error  = [NSError errorWithClass:[self class] code:0 description:@"Invalid access key"];
	}
	
	if (errorOut) *errorOut = error;
	return isValid;
	
}



+ (BOOL)parseCloneCodeURL:(NSURL*)url
						 userID:(NSString **)userIDOut
				 cloneKeyData:(NSString **)cloneKeyDataOut
		 encryptedCloneData:(NSString **)encryptedCloneDataOut
						  error:(NSError **)errorOut
{
	NSError*   error = nil;
	BOOL isValid = NO;
	
	if ([url.scheme isEqualToString:@"storm4"]
		 &&  [url.host isEqualToString:@"clone2" ])
	{
		NSArray* parts = [url.resourceSpecifier componentsSeparatedByString:@"/"];
		
		if(parts.count == 6)
		{
			NSString* userID = parts[3];
			NSString* cloneKeyData = [parts[4] stringByRemovingPercentEncoding];
			NSString* encryptedCloneData = [parts[5] stringByRemovingPercentEncoding];
			
			if(userIDOut) *userIDOut = userID;
			if(cloneKeyDataOut) *cloneKeyDataOut = cloneKeyData;
			if(encryptedCloneDataOut) *encryptedCloneDataOut = encryptedCloneData;
			isValid = YES;
		}
	}
	
	
	if(!isValid) {
		error  = [NSError errorWithClass:[self class] code:0 description:@"Invalid access key"];
	}
	
	if (errorOut) *errorOut = error;
	return isValid;
}

+ (NSData*)accessKeyDataFromString:(NSString *)codeString
							 withPasscode:(NSString *)passcode
										salt:(NSData*)salt
									  error:(NSError *_Nullable *_Nullable) outError
{
	NSError* 	error = nil;
	S4Err		err = kS4Err_NoErr;
	
	NSData *	accessKeyData = nil;
	
	S4KeyContextRef * pkKeyCtx = NULL;
	S4KeyContextRef   cloneKeyCtx = NULL;
	
	uint8_t*			normalizedPassCode = NULL;
	size_t     		normalizedPassCodeLen = 0;

	if ([codeString isKindOfClass:[NSString class]])
	{
		NSString* userID             = nil;
		NSString* cloneKeyString     = nil;
		NSString* encryptedCloneData = nil;
		
		NSURL* url = [NSURL URLWithString:codeString];
		
		if ([self parseCloneCodeURL: url
									userID: &userID
							cloneKeyData: &cloneKeyString
					encryptedCloneData: &encryptedCloneData
									 error: &error])
		{
			// unpack the PBKDF Blob
			{
				NSData*        pkData = NULL;
				uint8_t*       pbBlock   = NULL;
				size_t         pbBlockLen = 0;
				uint8_t*       p;
				uint16_t       lenVal = 0;
				uint8_t			version = 0;
				
				// <totalLen> <version>
				
				pkData = [[NSData alloc] initWithBase64EncodedString:cloneKeyString options:0];
				p = pbBlock = (uint8_t*) pkData.bytes;
				pbBlockLen = pkData.length;
				
				lenVal = S4_Load16(&p);
				ASSERTERR(lenVal == pkData.length,  kS4Err_CorruptData);
				
				version = S4_Load8(&p);
				if(version == 1)  //  version 1 codes
				{
					NSData* encrypted  = NULL;
					NSData* mac  = NULL;
					NSData* salt = NULL;
					uint32_t rounds;
					size_t keyCount = 0;
					//  <version = 1> <Len>encrypted <8 mac> <8 salt><4 rounds>
					
					lenVal = S4_Load8(&p);
					encrypted   = [[NSData alloc] initWithBytes:p length:lenVal ];
					S4_SkipBytes(lenVal, &p);
					
					mac   = [[NSData alloc] initWithBytes:p length:kS4KeyESK_HashBytes ];
					S4_SkipBytes(kS4KeyESK_HashBytes, &p);
					
					salt   = [[NSData alloc] initWithBytes:p length:kS4KeyPBKDF2_SaltBytes ];
					S4_SkipBytes(kS4KeyPBKDF2_SaltBytes, &p);
					
					rounds = S4_Load32(&p);
					
					// check for internal error here
					ASSERTERR(p - pbBlock == pbBlockLen,  kS4Err_CorruptData);
					
					NSDictionary* jsonDict = @{
														@"version" 	:@(1),
														@"encoding"	:@"pbkdf2-Twofish-256",
														@"keySuite"	:@"Twofish-256",
														@"salt"		:[salt base64EncodedStringWithOptions:0],
														@"rounds"	:@(rounds),
														@"mac"		:[mac base64EncodedStringWithOptions:0],
														@"encrypted":[encrypted base64EncodedStringWithOptions:0]
														};
					// rebuild the pb block
					NSData* pbData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
					
					err = S4Key_DeserializeKeys((uint8_t*)pbData.bytes, pbData.length, &keyCount, &pkKeyCtx); CKERR;
					ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
					
					err = S4Key_DecryptFromPassPhrase(pkKeyCtx[0],
																 (uint8_t*)passcode.UTF8String,
																 passcode.UTF8LengthInBytes,
																 &cloneKeyCtx); CKERR;
					
				}
				else if(version == 2)  //  version 2 codes
				{
					Cipher_Algorithm	encodingAlgorithm = kCipher_Algorithm_Invalid;
					NSString* 		encodingAlgorString = NULL;
					size_t  keySizeInBits = 0;
					size_t  keySizeInBytes = 0;
					size_t 	keyCount = 0;
					
					NSData* encrypted = NULL;
					NSData* iv  		= NULL;
					NSData* esk  		= NULL;
					NSData* mac  		= NULL;
					
					size_t	 p2kParamsLen = 0;
					NSString* p2kParams	= NULL;
					
					encodingAlgorithm = S4_Load8(&p);
					
					err = Cipher_GetKeySize(encodingAlgorithm, &keySizeInBits); CKERR;
					keySizeInBytes = keySizeInBits / 8;
					
					switch (encodingAlgorithm) {
						case kCipher_Algorithm_AES128:
							encodingAlgorString = @"AES-128";
							break;
							
						case kCipher_Algorithm_2FISH256:
							encodingAlgorString = @"Twofish-256";
							break;
							
						default:
							RETERR(kS4Err_BadCipherNumber);
							break;
					}
					
					encrypted   = [[NSData alloc] initWithBytes:p length:keySizeInBytes ];
					S4_SkipBytes(keySizeInBytes, &p);
					
					iv   = [[NSData alloc] initWithBytes:p length:keySizeInBytes ];
					S4_SkipBytes(keySizeInBytes, &p);
					
					esk   = [[NSData alloc] initWithBytes:p length:keySizeInBytes ];
					S4_SkipBytes(keySizeInBytes, &p);
					
					mac   = [[NSData alloc] initWithBytes:p length:kS4KeyESK_HashBytes ];
					S4_SkipBytes(kS4KeyESK_HashBytes, &p);
					
					p2kParamsLen = S4_Load8(&p);
					p2kParams = [[NSString alloc] initWithBytes:p length:p2kParamsLen encoding:NSUTF8StringEncoding];
					S4_SkipBytes(p2kParamsLen, &p);
					
					// check for internal error here
					ASSERTERR(p - pbBlock == pbBlockLen,  kS4Err_CorruptData);
					
					NSDictionary* jsonDict = @{
														@"version" 			:@(1),
														@"encoding"			:@"p2k",
														@"encodedObject"	:encodingAlgorString,
														@"encrypted"		:[encrypted base64EncodedStringWithOptions:0],
														@"esk"				:[esk base64EncodedStringWithOptions:0],
														@"iv"					:[iv base64EncodedStringWithOptions:0],
														@"keySuite"			:encodingAlgorString,
														@"mac"				:[mac base64EncodedStringWithOptions:0],
														@"p2k-params"		: p2kParams
														};
					// rebuild the pb block
					NSData* pbData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
					
					err = S4Key_DeserializeKeys((uint8_t*)pbData.bytes, pbData.length, &keyCount, &pkKeyCtx); CKERR;
					ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
					
					err = HASH_NormalizePassPhrase((uint8_t*) passcode.UTF8String, passcode.UTF8LengthInBytes,
															 salt.bytes, salt.length,
															 &normalizedPassCode, &normalizedPassCodeLen); CKERR;

					err = S4Key_DecryptFromPassCode(pkKeyCtx[0],
															  normalizedPassCode, normalizedPassCodeLen,
															  &cloneKeyCtx); CKERR;
				}
			}
			
			// unpack and decrypt the clone data
			{
				NSData* codeData = [[NSData alloc] initWithBase64EncodedString:encryptedCloneData
																						 options:0];
				
				accessKeyData = [self decryptedAccessKey:codeData
														 withS4Key:cloneKeyCtx
															  error:&error];
			}
		}
	}
	
done:
	
	if(pkKeyCtx)
	{
		if(S4KeyContextRefIsValid(pkKeyCtx[0]))
		{
			S4Key_Free(pkKeyCtx[0]);
		}
		XFREE(pkKeyCtx);
	}
	
	if(normalizedPassCode)
	{
		XFREE(normalizedPassCode);
		normalizedPassCode = NULL;
	}

	if(S4KeyContextRefIsValid(cloneKeyCtx))
		S4Key_Free(cloneKeyCtx);
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(outError)
		*outError = error;
	
	return accessKeyData;
}


static uint32_t xor32 (uint32_t in32, void *keydata)
{
	uint8_t* p = keydata;
	uint32_t result = S4_Load32(&p);
	result ^= in32;
	return result;
}

+ (NSData *)decryptedAccessKey:(NSData*)dataIn
							withS4Key:(S4KeyContextRef)keyCtx
								 error:(NSError **)errorOut
{
	NSData*     accessKeyData = NULL;
	S4Err       err = kS4Err_NoErr;
	NSError*     error = NULL;
	
	S4KeyType           keyType;
	Cipher_Algorithm     algor;
	
	uint8_t      keyData[128] = {0};
	size_t      keyLen = 0;
	
	uint8_t     *IV = NULL;
	uint8_t     *CT = NULL;
	size_t      CTLen = 0;
	
	uint8_t     *PT = NULL;
	size_t      PTLen = 0;
	
	uint32_t    checkSum = 0;
	uint32_t    checkSum1 = 0;
	
	NSParameterAssert(dataIn != nil);
	
	// must have keyContext
	if(!S4KeyContextRefIsValid(keyCtx))
	{
		RETERR(kS4Err_BadParams);
	}
	
	err = S4Key_GetProperty(keyCtx, kS4KeyProp_KeyType, NULL, &keyType, sizeof(keyType), NULL ); CKERR;
	err = S4Key_GetProperty(keyCtx, kS4KeyProp_KeySuite, NULL, &algor, sizeof(algor), NULL ); CKERR;
	
	if(algor != kCipher_Algorithm_2FISH256
		|| keyType != kS4KeyType_Symmetric)
	{
		RETERR(kS4Err_FeatureNotAvailable);
	}
	
	err = S4Key_GetProperty(keyCtx, kS4KeyProp_KeyData, NULL, &keyData , sizeof(keyData), &keyLen ); CKERR;
	
	IV = (uint8_t*) dataIn.bytes;
	
	uint8_t* p = (uint8_t*) dataIn.bytes + keyLen;
	checkSum = S4_Load32(&p);
	
	CT =  p;
	CTLen = dataIn.length - keyLen - sizeof(uint32_t);
	
	err = CBC_DecryptPAD(algor, keyData, IV, CT, CTLen,  &PT,  &PTLen); CKERR;
	
	err = HASH_DO(kHASH_Algorithm_xxHash32, PT, PTLen, (uint8_t*) &checkSum1, sizeof(checkSum1) ); CKERR;
	checkSum1  = xor32(checkSum1,keyData);
	
	if(checkSum != checkSum1)
		RETERR(kS4Err_CorruptData);
	
	if(PT[0] != kCipher_Algorithm_2FISH256)
		RETERR(kS4Err_CorruptData);
	
	accessKeyData = [NSData allocSecureDataWithLength:32];
	COPY(PT+1, accessKeyData.bytes, 32);
	
	
done:
	
	if(PT) {
		ZERO(PT, PTLen);
		XFREE(PT);
		PT = NULL;
	}
	
	if(IsS4Err(err))
	{
		error = [NSError errorWithS4Error:err];
	}
	
	if(errorOut)
	{
		*errorOut = error;
	}
	
	return accessKeyData;
}

+ (NSData *)encryptedAccessKey:(NSData*)dataIn
							withS4Key:(S4KeyContextRef)keyCtx
								 error:(NSError **)errorOut
{
	
	NSMutableData*    accessKeyData = NULL;
	S4Err       err = kS4Err_NoErr;
	NSError*     error = NULL;
	
	S4KeyType           keyType;
	Cipher_Algorithm     algor;
	
	uint8_t      keyData[128] = {0};
	size_t      keyLen = 0;
	
	uint8_t     IV[128] = {0};
	uint8_t     *CT = NULL;
	size_t      CTLen = 0;
	
	uint32_t    checkSum = 0;
	uint8_t     checkSumBytes[4]= {0};
	
	NSParameterAssert(dataIn != nil);
	
	// must have keyContext
	if(!S4KeyContextRefIsValid(keyCtx))
	{
		RETERR(kS4Err_BadParams);
	}
	
	err = S4Key_GetProperty(keyCtx, kS4KeyProp_KeyType, NULL, &keyType, sizeof(keyType), NULL ); CKERR;
	err = S4Key_GetProperty(keyCtx, kS4KeyProp_KeySuite, NULL, &algor, sizeof(algor), NULL ); CKERR;
	
	if(algor != kCipher_Algorithm_2FISH256
		|| keyType != kS4KeyType_Symmetric)
	{
		RETERR(kS4Err_FeatureNotAvailable);
	}
	
	err = S4Key_GetProperty(keyCtx, kS4KeyProp_KeyData, NULL, &keyData , sizeof(keyData), &keyLen ); CKERR;
	
	err = RNG_GetBytes(IV,keyLen); CKERR;
	
	err = HASH_DO(kHASH_Algorithm_xxHash32, dataIn.bytes, dataIn.length,
					  (uint8_t*) &checkSum, sizeof(checkSum) ); CKERR;
	
	checkSum  = xor32(checkSum,keyData);
	uint8_t* p = checkSumBytes;
	S4_Store32(checkSum, &p);
	
	err = CBC_EncryptPAD(algor, keyData, IV, dataIn.bytes, dataIn.length,  &CT,  &CTLen); CKERR;
	
	accessKeyData = [NSMutableData dataWithBytes:IV length:keyLen];
	[accessKeyData appendData: [NSData dataWithBytes:checkSumBytes length:sizeof(checkSumBytes)]];
	[accessKeyData appendData: [NSData dataWithBytesNoCopy:CT length:CTLen freeWhenDone:YES]];
	
done:
	
	ZERO(keyData, sizeof(keyData));
	
	if(IsS4Err(err))
	{
		error = [NSError errorWithS4Error:err];
	}
	
	if(errorOut)
	{
		*errorOut = error;
	}
	
	return accessKeyData;
}



+ (NSString* _Nullable)splitKeyStringFromData:(NSData*)accessKeyData
											 totalShares:(NSUInteger)totalShares
												threshold:(NSUInteger)threshold
								 additionalProperties:(NSDictionary<NSString *, NSObject *> *_Nullable)additionalProperties
													shares:(NSDictionary<NSString *, NSString *>*_Nullable *_Nullable) outShares
													 error:(NSError *_Nullable *_Nullable) outError
{
	
	__block NSError*  	error = NULL;
	__block S4Err   		err = kS4Err_NoErr;
	NSString*				splitKeyString = NULL;
	
	NSDictionary* 				splitKeyDict = NULL;
	S4KeyContextRef     		newCloneKeyCtx = kInvalidS4KeyContextRef;
	
	NSData*             		encryptedAccessKeyData   = NULL;
	NSArray* 					rndArray = NULL;
	S4KeyContextRef*			sharesCtx = NULL;            // array of shares kNumShares of the key
	NSMutableDictionary*		sharesDict = NULL;
	__block NSMutableDictionary  *shareNumDict = NULL;
	
	uint8_t     *splitData = NULL;
	size_t      splitLen = 0;
	
	time_t		 startTime = [[NSDate date] timeIntervalSince1970];
	
	NSParameterAssert(accessKeyData != nil);
	
	// prepend the algotithm type to to the accessKeyData
	NSMutableData* accessKeyBlob = [NSMutableData dataWithCapacity:accessKeyData.length + 1];
	uint8_t  algor = kCipher_Algorithm_2FISH256;
	[accessKeyBlob appendBytes:&algor length:1];
	[accessKeyBlob appendData: accessKeyData];
	
	// create an encyption key for this data
	err = S4Key_NewKey(kCipher_Algorithm_2FISH256, &newCloneKeyCtx); CKERR;
	
	encryptedAccessKeyData = [self encryptedAccessKey:accessKeyBlob
														 withS4Key:newCloneKeyCtx
															  error:&error];
	if(error) goto done;
	
	// set key create time
	err = S4Key_SetProperty(newCloneKeyCtx,
									kS4KeyProp_StartDate, S4KeyPropertyType_Time,
									&startTime, sizeof(time_t)); CKERR;
	
	err = S4Key_SetProperty(newCloneKeyCtx,
									[kEncyptedAccessKey_Key cStringUsingEncoding:NSUTF8StringEncoding],
									S4KeyPropertyType_Binary,
									(void*) encryptedAccessKeyData.bytes,
									encryptedAccessKeyData.length); CKERR;
	
	[additionalProperties enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSObject * obj, BOOL * stop) {
		
		if([obj isKindOfClass:[NSString class]])
		{
			NSString* string = (NSString*)obj;
			
			err = S4Key_SetProperty(newCloneKeyCtx,
											[key cStringUsingEncoding:NSUTF8StringEncoding],
											S4KeyPropertyType_UTF8String,
											(void*) string.UTF8String,
											string.UTF8LengthInBytes);
			if(IsS4Err(err))
				*stop = YES;
			
		}
		else if([obj isKindOfClass:[NSData class]])
		{
			NSData* data = (NSData*)obj;
			err = S4Key_SetProperty(newCloneKeyCtx,
											[key cStringUsingEncoding:NSUTF8StringEncoding],
											S4KeyPropertyType_Binary,
											(void*) data.bytes,
											data.length);
		}
		else if([obj isKindOfClass:[NSDate class]])
		{
			NSDate* date = (NSDate*)obj;
			time_t unixTime = [date timeIntervalSince1970];
			
			err = S4Key_SetProperty(newCloneKeyCtx,
											[key cStringUsingEncoding:NSUTF8StringEncoding],
											S4KeyPropertyType_Time,
											&unixTime, sizeof(time_t));
		}
		else if([obj isKindOfClass:[NSNumber class]])
		{
			NSNumber* number = (NSNumber*)obj;
			uint num = number.unsignedIntValue;
			
			err = S4Key_SetProperty(newCloneKeyCtx,
											[key cStringUsingEncoding:NSUTF8StringEncoding],
											S4KeyPropertyType_Numeric,
											&num, sizeof(num));
		}
		else
		{
			error =  [self errorWithDescription:@"Invalid Parameter for additionalProperties"];
		}
		
		if(IsS4Err(err) || error)
			*stop = YES;
		
	}];
	
	if(error) goto done;
	
	// split the key into shares and produce a shared key string
	// and a set of S4KeyContextRefs for each share
	err = S4Key_SerializeToShares(newCloneKeyCtx,
											(uint32_t)totalShares,
											(uint32_t) threshold,
											&sharesCtx ,
											&splitData, &splitLen); CKERR;
	
	splitKeyDict =  [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:splitData
																								  length:splitLen]
																	options:0
																	  error:&error] ;
	if(error) goto done;
	
	// create an array of sharenums
	shareNumDict = [NSMutableDictionary dictionaryWithCapacity:totalShares];
	rndArray =  [[NSArray arc4RandomArrayWithCount:colorCount] subarrayWithRange:NSMakeRange(0, totalShares)];
	
	sharesDict = [NSMutableDictionary dictionaryWithCapacity:totalShares];
	for(int i = 0; i < totalShares; i++)
	{
		S4KeyContextRef shareCtx = sharesCtx[i];
		
		uint8_t	*shareData = nil;
		size_t	shareDataLen = 0;
		uint8_t	shareID [kS4ShareInfo_HashBytes];
		
		err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareID,
										NULL,(void**)&shareID, sizeof(shareID), NULL);
		
		NSString* shareIDString = [[NSData dataWithBytes:shareID length:sizeof(shareID)]
											base64EncodedStringWithOptions:0];
		
		NSNumber* shareNum = [rndArray objectAtIndex:i];
		uint shareNumInt =  shareNum.unsignedIntValue;
		
		err = S4Key_SetProperty(shareCtx,
										[kZDCSplitKeyProp_ShareNum cStringUsingEncoding:NSUTF8StringEncoding],
										S4KeyPropertyType_Numeric,
										&shareNumInt, sizeof(shareNumInt));
		
		
		err = S4Key_SerializeSharePart(shareCtx,
												 &shareData, &shareDataLen); CKERR;
		
		NSString* value = [[NSString alloc]
								 initWithData:[NSData dataWithBytesNoCopy:shareData length:shareDataLen freeWhenDone:YES] encoding:NSUTF8StringEncoding];
		
		[sharesDict setObject:value forKey:shareIDString];
		[shareNumDict setObject:shareNum forKey:shareIDString];
	}
	
	
	// update the accessKeyString with a table of shareNumDict
	{
		NSMutableDictionary* updatedDict =  [NSMutableDictionary dictionaryWithDictionary:splitKeyDict];
		
		[updatedDict setObject:shareNumDict forKey:kZDCSplitKeyProp_ShareNum];
		
		NSData* splitKeyData = [NSJSONSerialization dataWithJSONObject:updatedDict
																				 options:0
																					error:&error];
		if(error) goto done;
		
		splitKeyString = [[NSString alloc] initWithData:splitKeyData
															encoding:NSUTF8StringEncoding];
	}
	
done:
	
	if(sharesCtx)
	{
		for(int i = 0; i < totalShares; i++)
		{
			if(S4KeyContextRefIsValid(sharesCtx[i]))
				S4Key_Free(sharesCtx[i]);
		}
		XFREE(sharesCtx);
	}
	
	if(splitData)
		XFREE(splitData);
	
	if(S4KeyContextRefIsValid(newCloneKeyCtx))
		S4Key_Free(newCloneKeyCtx);
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(error)
	{
		sharesDict = NULL;
	}
	
	if(outShares)
		*outShares = sharesDict;
	
	if(outError)
		*outError = error;
	
	return splitKeyString;
	
}

// decode the QRcode string to json data blob


+(NSData* _Nullable)dataFromShareDataString:(NSString*)shareString
												  error:(NSError **)errorOut
{
	NSError*   	error = nil;
	S4Err   		err = kS4Err_NoErr;
	NSData*		shareData = nil;
	
	NSURL* 		url = [NSURL URLWithString:shareString];
	NSString*	shareCodeString = nil;
	
	if (![self parseShareCodeURL:url
								 userID:nil
						shareCodeData:&shareCodeString
								  error:&error]) goto done;
	
	// unpack the  Blob
	{
		NSData* shareCodeData = nil;
		shareCodeData = [[NSData alloc] initWithBase64EncodedString:shareCodeString options:0];
		
		uint8_t*       pbBlock   = NULL;
		size_t         pbBlockLen = 0;
		uint8_t*       p;
		uint16_t       lenVal = 0;
		
		uint8_t 		version;
		NSData*		shareID  = NULL;
		NSData*		shareOwner = NULL;
		uint8_t		threshold;                              /* Number of shares needed to combine */
		uint8_t		xCoordinate;                            /* X coordinate of share  AKA the share index */
		uint16_t		shareNum;
		
		NSData*		sharePartData = NULL;
		
		p = pbBlock = (uint8_t*) shareCodeData.bytes;
		pbBlockLen = shareCodeData.length;
		
		lenVal = S4_Load16(&p);
		ASSERTERR(lenVal == shareCodeData.length,  kS4Err_CorruptData);
		
		// support only version 1 codes/
		version = S4_Load8(&p);
		ASSERTERR(version == 1,  kS4Err_CorruptData);
		
		shareID   = [[NSData alloc] initWithBytes:p length:kS4ShareInfo_HashBytes ];
		S4_SkipBytes(kS4ShareInfo_HashBytes, &p);
		
		shareOwner   = [[NSData alloc] initWithBytes:p length:kS4ShareInfo_HashBytes ];
		S4_SkipBytes(kS4ShareInfo_HashBytes, &p);
		
		xCoordinate = S4_Load8(&p);
		threshold = S4_Load8(&p);
		shareNum	= S4_Load16(&p);
		
		lenVal = S4_Load8(&p);
		sharePartData   = [[NSData alloc] initWithBytes:p length:lenVal ];
		S4_SkipBytes(lenVal, &p);
		
		// check for internal error here
		ASSERTERR(p - pbBlock == pbBlockLen,  kS4Err_CorruptData);
		
		NSDictionary* jsonDict = @{
											@"version" : @(1),
											@"keySuite": @"Shamir",
											@"shareOwner": [shareOwner base64EncodedStringWithOptions:0],
											@"shareID": [shareID base64EncodedStringWithOptions:0],
											@"threshold": @(threshold),
											@"index": @(xCoordinate),
											kZDCSplitKeyProp_ShareNum: @(shareNum),
											@"encrypted":  [sharePartData base64EncodedStringWithOptions:0],
											};
		
		shareData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
	}
	
done:
	
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(errorOut)
		*errorOut = error;
	
	return shareData;
}


// USe this to export a share remotely
+ (NSData* _Nullable)exportableShareDataFromShare:(NSString*)shareIn
												  localUserID:(NSString*)localUserID
														  error:(NSError *_Nullable *_Nullable) outError
{
	NSError*  	error = NULL;
	
	NSParameterAssert(shareIn != nil);
	NSParameterAssert(localUserID != nil);
	
	NSData* 		shareData 	= NULL;
	NSDictionary * shareDict 	= NULL;
	
	NSArray* keysToExport = @[@"version",
										@"keySuite",
										@"shareID",
										@"shareOwner",
										@"index",
										@"threshold",
										@"encrypted",
										kZDCSplitKeyProp_ShareNum];

	shareDict =  [NSJSONSerialization JSONObjectWithData:
							[shareIn dataUsingEncoding:NSUTF8StringEncoding]
																	 options:0
																		error:&error] ;
	if(error) goto done;
	
	shareDict = 	[shareDict dictionaryWithValuesForKeys:keysToExport];
	
	{
		NSMutableDictionary * dict = [NSMutableDictionary dictionaryWithDictionary:shareDict];
		[dict setObject: localUserID forKey:kZDCCloudRcrd_UserID];
		shareDict = dict;
	}
	
	shareData = [NSJSONSerialization dataWithJSONObject:shareDict
																		 options:0
																			error:&error];
	
done:
	
	if(outError)
		*outError = error;
	
	return shareData;

}


// Use this to create a QRcode
+ (NSString* _Nullable) shareDataStringFromShare:(NSString*)shareIn
												 localUserID:(NSString*)localUserID
														 error:(NSError *_Nullable *_Nullable) outError
{
	__block NSError*  	error = NULL;
	__block S4Err   		err = kS4Err_NoErr;
	
	NSString* shareDataString = nil;
	
	S4KeyContextRef *	encodedCtx =  nil;
	S4KeyContextRef 	shareCtx	 	= nil;
	size_t          	keyCount 	= 0;
	
	S4KeyType  			keyType		= kS4KeyType_Invalid;
	uint8_t				shareID 		[kS4ShareInfo_HashBytes];
	uint8_t				shareOwner	[kS4ShareInfo_HashBytes];
	
	uint32_t         	threshold;     	/* Number of shares needed to combine */
	uint32_t				xCoordinate; 		/* X coordinate of share  AKA the share index */
	uint32_t				shareNum;
	
	void*          	sharePartData[64];
	size_t          	sharePartLen = 0;
	
	
	NSParameterAssert(shareIn != nil);
	NSParameterAssert(localUserID != nil);
	
	// decode the share
	err = S4Key_DeserializeKeys((uint8_t*)shareIn.UTF8String,
										 shareIn.UTF8LengthInBytes,
										 &keyCount, &encodedCtx); CKERR;
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
	
	shareCtx = encodedCtx[0];
	
	// type check it
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_KeyType,
									NULL, &keyType, sizeof(keyType), NULL ); CKERR;
	
	if(keyType != kS4KeyType_Share)
		RETERR(kS4Err_BadParams);
	
	// get the needed properties
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareID,
									NULL,(void**)&shareID, sizeof(shareID), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareOwner,
									NULL,(void**)&shareOwner, sizeof(shareOwner), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareIndex,
									NULL,(void**)&xCoordinate, sizeof(xCoordinate), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareThreshold,
									NULL,(void**)&threshold, sizeof(threshold), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, [kZDCSplitKeyProp_ShareNum cStringUsingEncoding:NSUTF8StringEncoding],
									NULL,(void**)&shareNum, sizeof(shareNum), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_KeyData,
									NULL, &sharePartData , sizeof(sharePartData), &sharePartLen ); CKERR;
	
	// create the datablock
	{
		// <totalLen> <version> <Len>encrypted <8 mac> <8 salt><4 rounds>
		
		NSData*             pbBlockData = NULL;
		
		uint8_t*            pbBlock   = NULL;
		size_t              pbBlockLen = 0;
		uint8_t*            p;
		
		uint8_t					version = 1;
		
		pbBlockLen = 2			// pbBlockLen
		+ 1						// version
		+ sizeof(shareID)		// sharedID
		+ sizeof(shareOwner)	// share Owner
		+  1						// xCoordinate as byte
		+  1						// threshold as byte
		+  2						// shareNum as word (11 bits)
		+  1						// sharePartLen
		+  sharePartLen;
		
		pbBlock = XMALLOC(pbBlockLen);
		p = pbBlock;
		
		S4_Store16(pbBlockLen,&p);
		S4_Store8(version,&p);
		
		S4_StoreArray((uint8_t*)shareID, sizeof(shareID), &p);
		S4_StoreArray((uint8_t*)shareOwner, sizeof(shareOwner), &p);
		S4_Store8(xCoordinate,&p);
		S4_Store8(threshold,&p);
		S4_Store16(shareNum,&p);
		
		S4_Store8(sharePartLen,&p);
		S4_StoreArray((uint8_t*)sharePartData, sharePartLen, &p);
		
		// check for internal error here
		ASSERTERR(p - pbBlock == pbBlockLen,  kS4Err_BufferTooSmall);
		
		pbBlockData = [[NSData alloc] initWithBytesNoCopy:pbBlock length:pbBlockLen freeWhenDone:YES];
		
		shareDataString = [NSString stringWithFormat:@"%@://%@/%@/%@",@"storm4", @"share",
								 localUserID,
								 [AWSURL urlEncodePathComponent: [pbBlockData base64EncodedStringWithOptions:0]]
								 ];
	}
	
done:
	
	if(encodedCtx)
	{
		if(S4KeyContextRefIsValid(encodedCtx[0]))
		{
			S4Key_Free(encodedCtx[0]);
		}
		XFREE(encodedCtx);
	}
	
	ZERO(sharePartData, sharePartLen);
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(outError)
		*outError = error;
	
	return shareDataString;
}



+ (NSString*)accessKeyStringFromData:(NSData*)accessKeyData
								withPasscode:(NSString * _Nullable)passcode
								p2kAlgorithm:(P2K_Algorithm)p2kAlgorithm
										userID:(NSString* __nonnull)userID
										  salt:(NSData* _Nullable)salt
										 error:(NSError *_Nullable *_Nullable) outError
{
	
	NSError* 			error = NULL;
	S4Err 	 			err = kS4Err_NoErr;
	NSMutableData* 	accessKeyBlob = NULL;
	S4KeyContextRef 	newCloneKeyCtx = kInvalidS4KeyContextRef;
	Cipher_Algorithm	encodingAlgorithm = kCipher_Algorithm_Invalid;
	
	NSString* 		accessKeyString = NULL;
	NSData*    		encryptedAccessKeyData   = NULL;
	NSData*     	cloneKeyData = NULL;
	
	void*      		keyData = NULL;
	size_t      	keyDataLen = 0;
	
	uint8_t*			normalizedPassCode = NULL;
	size_t     		normalizedPassCodeLen = 0;

	NSParameterAssert(accessKeyData != nil);
	
	switch (accessKeyData.length) {
		case 128 / 8:
			encodingAlgorithm = kCipher_Algorithm_AES128;
			break;
			
		case 256 /8:
			encodingAlgorithm = kCipher_Algorithm_2FISH256;
			break;
			
		default:
			break;
	}
	
	NSParameterAssert(encodingAlgorithm != kCipher_Algorithm_Invalid);
	
	// create an encyption key for this data
	err = S4Key_NewKey(encodingAlgorithm, &newCloneKeyCtx); CKERR;
	
	// prepend the algotithm type to to the accessKeyData
	accessKeyBlob = [NSMutableData dataWithCapacity:accessKeyData.length + 1];
	uint8_t  algor = (uint8_t) encodingAlgorithm;
	[accessKeyBlob appendBytes:&algor length:1];
	[accessKeyBlob appendData: accessKeyData];
	
	//NOTE:  we need to use the depricated API to support storm4 compatibility
	/*
	 revist this when we port this back to storm4 and create a version 2 access string.
	 that uses the new S4Key_SerializeToPassCode API instead.
	 */
	
	if(p2kAlgorithm == kP2K_Algorithm_PBKDF2)
	{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		err = S4Key_SerializeToPassPhrase(newCloneKeyCtx,
													 (uint8_t*)passcode.UTF8String, passcode.UTF8LengthInBytes,
													 (void*)&keyData, &keyDataLen); CKERR;
#pragma clang diagnostic pop
		// pack the PBKDF Blob
		{
			
			NSDictionary* pkDict
			= [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:keyData length:keyDataLen]
														 options:0 error:&error];
			if(!error)
			{
				uint8_t*            pbBlock   = NULL;
				size_t              pbBlockLen = 0;
				uint8_t*            p;
				
				// <totalLen> <version> <Len>encrypted <8 mac> <8 salt><4 rounds>
				
				// pack the PBKDF Blob
				
				NSData* encrypted = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"encrypted"] options:0];
				NSData* mac = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"mac"] options:0];
				NSData* salt = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"salt"] options:0];
				uint32_t rounds = [[pkDict objectForKey: @"rounds"] unsignedIntValue ];
				uint8_t version =  1;
				
				ASSERTERR(mac.length == kS4KeyESK_HashBytes,  kS4Err_BufferTooSmall);
				ASSERTERR(salt.length == kS4KeyPBKDF2_SaltBytes,  kS4Err_BufferTooSmall);
				
				pbBlockLen = 2 + 1 +
				+ 1 + encrypted.length
				+ kS4KeyESK_HashBytes
				+ kS4KeyPBKDF2_SaltBytes
				+ 4;
				
				pbBlock = XMALLOC(pbBlockLen);
				p = pbBlock;
				
				S4_Store16(pbBlockLen,&p);
				
				S4_Store8(version,&p);
				
				S4_Store8(encrypted.length,&p);
				S4_StoreArray((uint8_t*)encrypted.bytes, encrypted.length, &p);
				
				S4_StoreArray((uint8_t*)mac.bytes, kS4KeyESK_HashBytes, &p);
				
				S4_StoreArray((uint8_t*)salt.bytes, kS4KeyPBKDF2_SaltBytes, &p);
				
				S4_Store32(rounds,&p);
				
				// check for internal error here
				ASSERTERR(p - pbBlock == pbBlockLen,  kS4Err_BufferTooSmall);
				
				cloneKeyData = [[NSData alloc] initWithBytesNoCopy:pbBlock length:pbBlockLen freeWhenDone:YES];
				
			}
		}
	}
	else
	{
		err = HASH_NormalizePassPhrase((uint8_t*) passcode.UTF8String, passcode.UTF8LengthInBytes,
												 salt.bytes, salt.length,
												 &normalizedPassCode, &normalizedPassCodeLen); CKERR;

		err = S4Key_SerializeToPassCode(newCloneKeyCtx,
												  normalizedPassCode, normalizedPassCodeLen,
												  p2kAlgorithm,
												  (void*)&keyData, &keyDataLen); CKERR;
		
			// pack the passcode Blob
		{
			NSDictionary* pkDict =
			[NSJSONSerialization JSONObjectWithData: [NSData dataWithBytes:keyData length:keyDataLen]
													  options:0
														 error:&error];
			if(!error)
			{
				uint8_t*            pbBlock   = NULL;
				size_t              pbBlockLen = 0;
				uint8_t*            p;
				
				// <totalLen> <version> <<alg> encrypted <iv> <esk> <8 mac>
				
				NSData* encrypted = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"encrypted"] options:0];
				NSData* iv = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"iv"] options:0];
				NSData* esk = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"esk"] options:0];
				NSData* mac = [[NSData alloc] initWithBase64EncodedString: [pkDict objectForKey: @"mac"] options:0];
				NSString* p2kParams = [pkDict objectForKey: @"p2k-params"];
				
				uint8_t version =  2;
				uint8_t  algor = (uint8_t) encodingAlgorithm;
				
				ASSERTERR(mac.length == kS4KeyESK_HashBytes,  kS4Err_BufferTooSmall);
				
				pbBlockLen = 2 + 1 +		// <totalLen> <version>
				+ 1							// algor = 1 or 4 (	AES128, 2FISH256)
				+ encrypted.length
				+ iv.length
				+ esk.length
				+ mac.length
				+ 1 + p2kParams.length;  // <len b> <p2kParams>
				
				pbBlock = XMALLOC(pbBlockLen);
				p = pbBlock;
				
				S4_Store16(pbBlockLen,&p);	// <totalLen>
				S4_Store8(version,&p);		// <2>
				S4_Store8(algor,&p);			// algor = 1 or 4 (	AES128, 2FISH256)
				S4_StoreArray((uint8_t*)encrypted.bytes, encrypted.length, &p);
				S4_StoreArray((uint8_t*)iv.bytes, iv.length, &p);
				S4_StoreArray((uint8_t*)esk.bytes, esk.length, &p);
				S4_StoreArray((uint8_t*)mac.bytes, mac.length, &p);
				
				S4_Store8(p2kParams.UTF8LengthInBytes,&p);		// <length of p2kParams byte>
				S4_StoreArray((uint8_t*)p2kParams.UTF8String, p2kParams.UTF8LengthInBytes, &p);
				
				// check for internal error here
				ASSERTERR(p - pbBlock == pbBlockLen,  kS4Err_BufferTooSmall);
				
				cloneKeyData = [[NSData alloc] initWithBytesNoCopy:pbBlock length:pbBlockLen freeWhenDone:YES];
			}
		}
		
		
	}
	
	encryptedAccessKeyData = [self encryptedAccessKey:accessKeyBlob
														 withS4Key:newCloneKeyCtx
															  error:&error];
	
	accessKeyString = [NSString stringWithFormat:@"%@://%@/%@/%@/%@",@"storm4", @"clone2",
							 userID,
							 [AWSURL urlEncodePathComponent: [cloneKeyData base64EncodedStringWithOptions:0]] ,
							 [AWSURL urlEncodePathComponent: [encryptedAccessKeyData base64EncodedStringWithOptions:0]]
							 ];
	
done:
	
	if(keyData)
	{
		ZERO(keyData, keyDataLen);
		XFREE(keyData);
	}
	
	if(normalizedPassCode)
	{
		XFREE(normalizedPassCode);
		normalizedPassCode = NULL;
	}
	
	if(S4KeyContextRefIsValid(newCloneKeyCtx))
		S4Key_Free(newCloneKeyCtx);
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(outError)
		*outError = error;
	
	
	return accessKeyString;
}

+ (NSString* _Nullable)decryptShareWithShareCodeEntry:(NSString*)entry
													 decryptionKey:(NSData*) decryptionKey
																error:(NSError *_Nullable *_Nullable) outError
{
	__block NSError*  	error = NULL;
	__block S4Err   		err = kS4Err_NoErr;
	NSString*				share = nil;
	
	Cipher_Algorithm		algorithm = kCipher_Algorithm_Invalid;
	uint8_t     			*IV = NULL;
	uint8_t     			*CT = NULL;
	size_t      			CTLen = 0;
	uint32_t  				checkSum = 0;
	
	uint8_t     			*PT = NULL;
	size_t     				 PTLen = 0;
	
	size_t  keySizeInBits = 0;
	size_t  keySizeInBytes = 0;
	uint32_t checkSum1 = 0;
	
	NSParameterAssert(entry != nil);
	NSParameterAssert(decryptionKey != nil);
	
	// param checking
	NSData* data = [[NSData alloc] initWithBase64EncodedString:entry options:0];
	if(!data)
		RETERR(kS4Err_BadParams);
	
	// get the parts of the blob
	
	uint8_t* p = (uint8_t*) data.bytes;
	algorithm = S4_Load8(&p);
	err = Cipher_GetKeySize(algorithm, &keySizeInBits); CKERR;
	keySizeInBytes = keySizeInBits / 8;
	if(keySizeInBytes != decryptionKey.length)
		RETERR(kS4Err_BadParams);
	
	IV = (uint8_t*) p;
	S4_SkipBytes(decryptionKey.length, &p);
	checkSum = S4_Load32(&p);
	CT =  (uint8_t*) p;
	CTLen = data.length - (p - (uint8_t*)data.bytes);
	
	err = CBC_DecryptPAD(algorithm, (void*)decryptionKey.bytes, IV, CT, CTLen,  &PT,  &PTLen);
	if(IsS4Err(err)) goto done;
	
	err = HASH_DO(kHASH_Algorithm_xxHash32, PT, PTLen, (uint8_t*) &checkSum1, sizeof(checkSum1) );
	if(IsS4Err(err)) goto done;
	
	checkSum1  = xor32(checkSum1,PT);
	
	if(checkSum != checkSum1)
		RETERR(kS4Err_CorruptData);
	
	{
		uint8_t				xCoordinate;                            /* X coordinate of share  AKA the share index */
		uint8_t				threshold;                              /* Number of shares needed to combine */
		NSData				*shareID  	= nil;
		NSData				*shareOwner  = nil;
		NSData 				*sharePartData 	= nil;
		size_t          	sharePartLen = 0;
		
		p = PT;
		xCoordinate = S4_Load8(&p);
		threshold = S4_Load8(&p);
		shareID   = [[NSData alloc] initWithBytes:p length:kS4ShareInfo_HashBytes ];
		S4_SkipBytes(kS4ShareInfo_HashBytes, &p);
		shareOwner   = [[NSData alloc] initWithBytes:p length:kS4ShareInfo_HashBytes ];
		S4_SkipBytes(kS4ShareInfo_HashBytes, &p);
		sharePartLen = S4_Load8(&p);
		sharePartData   = [[NSData alloc] initWithBytes:p length:sharePartLen ];
		S4_SkipBytes(sharePartLen, &p);
		
		// check for internal error here
		ASSERTERR(p - PT == PTLen,  kS4Err_CorruptData);
		
		NSDictionary* jsonDict = @{
											@"version" : @(1),
											@"keySuite": @"Shamir",
											@"shareOwner": [shareOwner base64EncodedStringWithOptions:0],
											@"shareID": [shareID base64EncodedStringWithOptions:0],
											@"threshold": @(threshold),
											@"index": @(xCoordinate),
											@"encrypted":  [sharePartData base64EncodedStringWithOptions:0],
											};
		
		NSData* shareData = [NSJSONSerialization dataWithJSONObject:jsonDict
																			 options:0
																				error:&error];
		if(error)
			goto done;
		
		share = [[NSString alloc] initWithData:shareData
												encoding:NSUTF8StringEncoding];
		
	}
	
done:
	
	if(PT) {
		ZERO(PT, PTLen);
		XFREE(PT);
		PT = NULL;
	}
	
	if(IsS4Err(err))
	{
		error = [NSError errorWithS4Error:err];
	}
	
	if(outError)
	{
		*outError = error;
	}
	
	return share;
}



+ (NSString* _Nullable)shareCodeEntryFromShare:(NSString*)shareIn
												 algorithm:(Cipher_Algorithm)algorithm
											 encyptionKey:(NSData*_Nullable *_Nullable) encyptionKeyOut
													  error:(NSError *_Nullable *_Nullable) outError
{
	__block NSError*  	error = NULL;
	__block S4Err   		err = kS4Err_NoErr;
	
	NSData* encryptionKey = NULL;
	size_t  keySizeInBits = 0;
	size_t  keySizeInBytes = 0;
	
	S4KeyContextRef *	encodedCtx =  nil;
	S4KeyContextRef 	shareCtx	 	= nil;
	size_t          	keyCount 	= 0;
	
	S4KeyType  			keyType		= kS4KeyType_Invalid;
	
	NSMutableData*    accessKeyData = NULL;
	uint32_t				xCoordinate;                            /* X coordinate of share  AKA the share index */
	uint32_t				threshold;                              /* Number of shares needed to combine */
	uint8_t				shareID 		[kS4ShareInfo_HashBytes];
	uint8_t				shareOwner	[kS4ShareInfo_HashBytes];
	uint8_t          	sharePartData[64];
	size_t          	sharePartLen = 0;
	
	uint8_t     keyData[128] = {0};
	uint8_t     IV[128] = {0};
	
	uint8_t     *CT = NULL;
	size_t      CTLen = 0;
	uint32_t    checkSum = 0;
	uint8_t     checkSumBytes[4]= {0};
	uint8_t     algorithmBytes[1]= {0};
	
	NSParameterAssert(shareIn != nil);
	
	NSParameterAssert (  (algorithm == kCipher_Algorithm_AES128)
							 || (algorithm == kCipher_Algorithm_AES192)
							 || (algorithm == kCipher_Algorithm_AES256)
							 || (algorithm == kCipher_Algorithm_2FISH256));
	
	// decode the share
	err = S4Key_DeserializeKeys((uint8_t*)shareIn.UTF8String,
										 shareIn.UTF8LengthInBytes,
										 &keyCount, &encodedCtx); CKERR;
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
	
	shareCtx = encodedCtx[0];
	
	// type check it
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_KeyType,
									NULL, &keyType, sizeof(keyType), NULL ); CKERR;
	
	if(keyType != kS4KeyType_Share)
		RETERR(kS4Err_BadParams);
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareIndex,
									NULL,(void**)&xCoordinate, sizeof(xCoordinate), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareThreshold,
									NULL,(void**)&threshold, sizeof(threshold), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareID,
									NULL,(void**)&shareID, sizeof(shareID), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_ShareOwner,
									NULL,(void**)&shareOwner, sizeof(shareOwner), NULL);  CKERR;
	
	err = S4Key_GetProperty(shareCtx, kS4KeyProp_KeyData,
									NULL, &sharePartData , sizeof(sharePartData), &sharePartLen ); CKERR;
	
	uint8_t* p = keyData;
	S4_Store8(xCoordinate,&p);
	S4_Store8(threshold,&p);
	S4_StoreArray((uint8_t*)shareID, sizeof(shareID), &p);
	S4_StoreArray((uint8_t*)shareOwner, sizeof(shareOwner), &p);
	S4_Store8(sharePartLen,&p);
	S4_StoreArray((uint8_t*)sharePartData, sharePartLen, &p);
	
	// create an encyption key for this data
	err = Cipher_GetKeySize(algorithm, &keySizeInBits); CKERR;
	keySizeInBytes = keySizeInBits / 8;
	encryptionKey = [NSData allocSecureDataWithLength:keySizeInBytes];
	err = RNG_GetBytes((void*)encryptionKey.bytes, keySizeInBytes); CKERR;
	err = RNG_GetBytes(IV,keySizeInBytes); CKERR;
	
	err = HASH_DO(kHASH_Algorithm_xxHash32, keyData, p-keyData,
					  (uint8_t*) &checkSum, sizeof(checkSum) ); CKERR;
	
	checkSum  = xor32(checkSum,keyData);
	uint8_t* csb = checkSumBytes;
	S4_Store32(checkSum, &csb);
	
	err = CBC_EncryptPAD(algorithm, (void*)encryptionKey.bytes, IV, keyData, p-keyData,  &CT,  &CTLen); CKERR;
	
	p = (uint8_t*) &algorithmBytes;
	S4_Store8(algorithm, &p);
	
	accessKeyData = [NSMutableData dataWithBytes:&algorithmBytes length:sizeof(algorithmBytes)];
	[accessKeyData appendData: [NSData dataWithBytes:IV length:keySizeInBytes]];
	[accessKeyData appendData: [NSData dataWithBytes:checkSumBytes length:sizeof(checkSumBytes)]];
	[accessKeyData appendData: [NSData dataWithBytesNoCopy:CT length:CTLen freeWhenDone:YES]];
	
	if(encyptionKeyOut)
		*encyptionKeyOut = encryptionKey;
	
done:
	
	ZERO(keyData, sizeof(keyData));
	
	if(encodedCtx)
	{
		if(S4KeyContextRefIsValid(encodedCtx[0]))
		{
			S4Key_Free(encodedCtx[0]);
		}
		XFREE(encodedCtx);
	}
	
	ZERO(sharePartData, sharePartLen);
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(outError)
		*outError = error;
	
	if(accessKeyData)
		return [accessKeyData base64EncodedStringWithOptions:0];
	else
		return nil;
}

+ (NSData* _Nullable )accessKeyDataFromSplit:(NSString *)splitKey
											 withShares:(NSArray<NSString *>*)shares
													error:(NSError *_Nullable *_Nullable) outError
{
	__block NSError*  	error = NULL;
	__block S4Err   		err = kS4Err_NoErr;
	NSData*    			accessKeyData = NULL;
	
	NSParameterAssert(splitKey != nil);
	NSParameterAssert(shares != nil);
	
	S4KeyContextRef *	encodedCtx =  NULL;
	size_t          	keyCount = 0;
	S4KeyContextRef*	sharesCtx = NULL;            // array of shares kNumShares of the key
	size_t          	shareCount = 0;
	
	S4KeyContextRef	recoveredKey =  kInvalidS4KeyContextRef;
	
	NSString* shareString = [NSString stringWithFormat:@"[ %@ ]", [shares componentsJoinedByString:@","]];
	
	// deserialise the split
	err = S4Key_DeserializeKeys((uint8_t*)splitKey.UTF8String, splitKey.UTF8LengthInBytes,
										 &keyCount, &encodedCtx ); CKERR;
	ASSERTERR(keyCount == 1,  kS4Err_SelfTestFailed);
	
	// deserialise the shares
	err = S4Key_DeserializeKeys((uint8_t*)shareString.UTF8String, shareString.UTF8LengthInBytes,
										 &shareCount, &sharesCtx ); CKERR;
	ASSERTERR(shareCount == shares.count ,  kS4Err_SelfTestFailed);
	
	// attempt to recombine the keys
	err = S4Key_RecoverKeyFromShares( encodedCtx[0],
												sharesCtx, (uint32_t)shareCount,
												&recoveredKey); CKERR;
	
	// get the keydata
	{
		void   * eakData = NULL;
		size_t   eakDataLen = 0;
		NSData*  eak = NULL;
		
		err = S4Key_GetAllocatedProperty(recoveredKey, [kEncyptedAccessKey_Key cStringUsingEncoding:NSUTF8StringEncoding],
													NULL, &eakData, &eakDataLen); CKERR;
		
		eak =  [[NSData alloc] initWithBytesNoCopy:eakData
														length:eakDataLen
												freeWhenDone:YES];
		
		NSData* codeData = [[NSData alloc]
								  initWithBase64EncodedString:[[NSString alloc]
																		 initWithData:eak encoding:NSUTF8StringEncoding]
								  options:0];
		
		accessKeyData = [self decryptedAccessKey: codeData
												 withS4Key:recoveredKey
													  error:&error];
	}
	
done:
	
	if(encodedCtx)
	{
		if(S4KeyContextRefIsValid(encodedCtx[0]))
		{
			S4Key_Free(encodedCtx[0]);
		}
		XFREE(encodedCtx);
	}
	
	if(sharesCtx)
	{
		for(int i = 0; i < shareCount; i++)
		{
			if(S4KeyContextRefIsValid(sharesCtx[i]))
			{
				S4Key_Free(sharesCtx[i]);
			}
		}
		XFREE(sharesCtx);
	}
	
	if(recoveredKey)
		S4Key_Free(recoveredKey);;
	
	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if(outError)
		*outError = error;
	
	return accessKeyData;
	
}

/* debug  tool*/
+(BOOL)compareEncodedShareString:(NSString*)encodedString
					  shareDictString:(NSString*)shareDictString
							localUserID:(NSString *)localUserID
									error:(NSError *_Nullable *_Nullable) outError

{
	
	NSError*  	error = NULL;
	BOOL success = NO;
	NSData* splitData = NULL;
	NSDictionary*  splitKeyDict2;
	NSDictionary*  splitKeyDict1;
	
	NSArray* keysToCompare = @[@"version",
										@"keySuite",
										@"shareID",
										@"shareOwner",
										@"index",
										@"threshold",
										@"encrypted",
										kZDCSplitKeyProp_ShareNum];
	
	splitKeyDict1 =  [NSJSONSerialization JSONObjectWithData:
												[shareDictString dataUsingEncoding:NSUTF8StringEncoding]
																						 options:0
																							error:&error] ;
	
	if(error) goto done;
	
	splitKeyDict1 = 	[splitKeyDict1 dictionaryWithValuesForKeys:keysToCompare];
	
	
	if(![ZDCAccessCode isValidShareString:encodedString
										 forUserID:localUserID])
	{
		error =  [self errorWithDescription:@"isValidShareString failed"];
	}
	if(error) goto done;
	
	 splitData = [ZDCAccessCode dataFromShareDataString:encodedString
																		  error:&error];
	if(error) goto done;
	
 	splitKeyDict2 =  [NSJSONSerialization JSONObjectWithData:splitData
																						 options:0
																							error:&error] ;
	if(error) goto done;
	
	splitKeyDict2 = 	[splitKeyDict2 dictionaryWithValuesForKeys:keysToCompare];
	
	// compare the keys
	
	if(![splitKeyDict1 isEqual:splitKeyDict2])
	{
		error =  [self errorWithDescription:@"compareEncodedShareString failed compare"];
	}
	
	if(error) goto done;
	
	success = YES;
	
done:
	if(outError)
		*outError = error;
	
	return success;
}

+ (NSString*) stringFromShareNum:(NSNumber*)shareNum
{
	NSString* 	color = NULL;
	
	NSParameterAssert(shareNum != nil);
	
	NSArray* colorArray = [NSLocalizedString(@"White,Black,Grey,Yellow,Red,Blue,Green,Brown,Pink,Orange,Purple",
														  @"White,Black,Grey,Yellow,Red,Blue,Green,Brown,Pink,Orange,Purple")  componentsSeparatedByString:@","];
	
	NSParameterAssert(colorCount == colorArray.count);
	NSParameterAssert(shareNum.unsignedIntValue < colorArray.count);
	
	color = [colorArray objectAtIndex:shareNum.unsignedIntValue];
	
	return color;
}


+(void) attributedStringFromShareNum:(NSNumber*)shareNum
										string:(NSAttributedString**)outString
									  bgColor:(OSColor**)outbgColor
{
	NSParameterAssert(shareNum != nil);
	
	NSArray* colorArray = [NSLocalizedString(@"White,Black,Grey,Yellow,Red,Blue,Green,Brown,Pink,Orange,Purple",
														  @"White,Black,Grey,Yellow,Red,Blue,Green,Brown,Pink,Orange,Purple")  componentsSeparatedByString:@","];
	NSParameterAssert(shareNum.unsignedIntValue < colorArray.count);
	NSString* 	colorText = [colorArray objectAtIndex:shareNum.unsignedIntValue];
	
	NSArray* fgColorArray = @[OSColor.whiteColor,
									  OSColor.blackColor,
									  OSColor.grayColor,
									  OSColor.yellowColor,
									  OSColor.redColor,
									  OSColor.blueColor,
									  OSColor.crayolaGreenColor,
									  OSColor.brownColor,
									  OSColor.crayolaPiggyPinkColor,
									  OSColor.crayolaOrangeColor,
									  OSColor.crayolaGrapeColor
									  ];
	
	NSArray* bgColorArray = @[OSColor.blackColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.blackColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.blackColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor];
	
	
	if(outString)
		*outString = [[NSAttributedString alloc] initWithString:colorText
																	attributes:  @{
							 NSForegroundColorAttributeName:  [fgColorArray objectAtIndex:shareNum.unsignedIntValue],
							 }];
	
	if(outbgColor)
		*outbgColor = [bgColorArray objectAtIndex:shareNum.unsignedIntValue];
}

+( NSAttributedString*) attributedStringFromShareNum:(NSNumber*)shareNum
{
	NSString* 	color = NULL;

	NSParameterAssert(shareNum != nil);
	
	NSArray* colorArray = [NSLocalizedString(@"White,Black,Grey,Yellow,Red,Blue,Green,Brown,Pink,Orange,Purple",
														  @"White,Black,Grey,Yellow,Red,Blue,Green,Brown,Pink,Orange,Purple")  componentsSeparatedByString:@","];
	NSParameterAssert(shareNum.unsignedIntValue < colorArray.count);
	color = [colorArray objectAtIndex:shareNum.unsignedIntValue];
	
	
	color = [NSString stringWithFormat:@" %@ ", color ];

	NSArray* fgColorArray = @[OSColor.whiteColor,
									  OSColor.blackColor,
									  OSColor.grayColor,
									  OSColor.yellowColor,
									  OSColor.redColor,
									  OSColor.blueColor,
									  OSColor.greenColor,
									  OSColor.brownColor,
									  OSColor.crayolaPiggyPinkColor,
									  OSColor.crayolaOrangeColor,
									  OSColor.crayolaPlumpPurpleColor
 									  ];
	
	
	NSArray* bgColorArray = @[OSColor.blackColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.blackColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor,
									  OSColor.blackColor,
									  OSColor.whiteColor,
									  OSColor.whiteColor];
	

	return  	[[NSAttributedString alloc] initWithString:color
														  attributes:
				 @{
					NSForegroundColorAttributeName:  [fgColorArray objectAtIndex:shareNum.unsignedIntValue],
					NSBackgroundColorAttributeName:  [bgColorArray objectAtIndex:shareNum.unsignedIntValue],
 					}];
	
	
	
}


@end
