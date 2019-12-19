/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCPublicKey.h"

#import "ZDCObjectSubclass.h"
#import "ZDCConstants.h"

// Categories
#import "NSData+AWSUtilities.h"
#import "NSError+S4.h"
#import "NSString+ZeroDark.h"

static int const kCurrentVersion = 0;

static NSString *const k_version      = @"version";
static NSString *const k_uuid         = @"uuid";
static NSString *const k_userID       = @"userUUID";
static NSString *const k_privKeyJSON  = @"privKeyJSON";
static NSString *const k_pubKeyJSON   = @"k_pubKeyJSON";


@interface ZDCPublicKey ()
@property (nonatomic, copy, readwrite) NSString * pubKeyJSON;
@property (nonatomic, copy, readwrite, nullable) NSString * privKeyJSON;

@property (atomic, strong, readwrite) NSDictionary *cachedKeyDict;
@end

@implementation ZDCPublicKey

@synthesize uuid = uuid;
@synthesize userID = userID;
@synthesize pubKeyJSON = pubKeyJSON;
@synthesize privKeyJSON = privKeyJSON;

@synthesize cachedKeyDict = _cachedKeyDict_atomic_property_must_use_selfDot_syntax;

@dynamic keyDict;
@dynamic pubKey;
@dynamic keyID;
//@dynamic eTag;

static BOOL MakeSigningKey(Cipher_Algorithm    keyAlgorithm,
                           NSString          * userID, // optional
                           S4KeyContextRef     storageKeyCtx,
                           NSString         ** pubKeyStringOut,
                           NSString         ** privkeyStringOut,
                           NSString         ** keyIDOut)
{
	BOOL success = NO;
	S4Err err = kS4Err_NoErr;
	
	NSString* privKey = nil;
	NSString* pubKey = nil;
	NSString* keyID = nil;
	
	S4KeyContextRef pubCtx = kInvalidS4KeyContextRef;
	uint8_t* privKeyData = NULL;
	uint8_t* pubKeyData = NULL;
   size_t keyDataLen = 0;
   char* keyIDStr = NULL;
	
	time_t startTime = [[NSDate date] timeIntervalSince1970];
	
	// create a pub/priv key pair.
	err = S4Key_NewPublicKey(keyAlgorithm, &pubCtx); CKERR;
	
	err = S4Key_GetAllocatedProperty(pubCtx, kS4KeyProp_KeyIDString, NULL, (void**)&keyIDStr, NULL); CKERR;
	keyID = [NSString stringWithUTF8String:keyIDStr];
	
	if (userID)
	{
		// Add userID to key as signable property
		err = S4Key_SetPropertyExtended(pubCtx,
		                                kZDCCloudRcrd_UserID.UTF8String,
		                                S4KeyPropertyType_UTF8String,
		                                S4KeyPropertyExtended_Signable,
		                        (void *)userID.UTF8String,
		                                userID.UTF8LengthInBytes); CKERR;
	}
	
	// set key create time
	err = S4Key_SetProperty(pubCtx, kS4KeyProp_StartDate, S4KeyPropertyType_Time, &startTime, sizeof(time_t)); CKERR;
	
//	if (expireDate)
//	{
//		time_t expireTime = [expireDate timeIntervalSince1970];
//		err = SCKeySetProperty(ecKey, kSCKeyProp_ExpireDate, SCKeyPropertyType_Time, &expireTime, sizeof(time_t)); CKERR;
//	}
    
	err = S4Key_SerializeToS4Key(pubCtx, storageKeyCtx, &privKeyData, &keyDataLen); CKERR;
	privKey = [[NSString alloc] initWithBytesNoCopy:privKeyData
	                                         length:keyDataLen
	                                       encoding:NSUTF8StringEncoding
	                                   freeWhenDone:YES];
	
	err = S4Key_SerializePubKey(pubCtx, &pubKeyData, &keyDataLen); CKERR;
	pubKey = [[NSString alloc] initWithBytesNoCopy:pubKeyData
	                                        length:keyDataLen
	                                      encoding:NSUTF8StringEncoding
	                                  freeWhenDone:YES];
	
	success = YES;
	
done:
	
	if (S4KeyContextRefIsValid(pubCtx)) {
		S4Key_Free(pubCtx);
	}
	
	if(privkeyStringOut) *privkeyStringOut = privKey;
	if(pubKeyStringOut) *pubKeyStringOut = pubKey;
	if(keyIDOut) *keyIDOut = keyID;
	
	return success;
}

/**
 * See header file for description.
 */
+ (instancetype)privateKeyWithOwner:(NSString *)userID
                         storageKey:(S4KeyContextRef)storageKey
                          algorithm:(Cipher_Algorithm)algorithm

{
	NSString *pubKeyString = nil;
	NSString *privKeyString = nil;
    
	if (MakeSigningKey(algorithm, userID, storageKey, &pubKeyString, &privKeyString, NULL))
	{
		return [[ZDCPublicKey alloc] initWithUserID: userID
		                                 pubKeyJSON: pubKeyString
		                                privKeyJSON: privKeyString];
	}
	else
	{
		return nil;
	}
}

/**
 * The S4Crypto library expects serialized JSON keys to be in a certain order.
 * This method corrects the order.
 */
+ (NSString *)s4PropertyStringFromDictionary:(NSDictionary *)dictionaryIn
{
	NSMutableDictionary	*newDict = [NSMutableDictionary dictionaryWithDictionary:dictionaryIn];
	NSString* string = nil;

	NSString* keySuite = [dictionaryIn objectForKey:@"keySuite"];

	if(keySuite)
	{
		[newDict removeObjectForKey:@"keySuite"];
	}


	NSData *JSONData = [NSJSONSerialization dataWithJSONObject:newDict options:0 error:nil];
	if(JSONData)
		string = [[NSString alloc] initWithData:JSONData encoding:NSUTF8StringEncoding];

	if(string.length)
	{
		NSMutableString* newString = [NSMutableString stringWithString:string];

		NSRange startRange = [string rangeOfString:@"{"];
		 if (startRange.location != NSNotFound)
		 {
			 if(keySuite)
				 [newString insertString: [NSString stringWithFormat:@"\"keySuite\":\"%@\", ", keySuite]
								 atIndex:startRange.location + startRange.length];
		 }
		string = newString;
	}

	return string;
}

/**
 * See header file for description.
 */
- (instancetype)initWithUserID:(NSString *)inUserID
                    pubKeyJSON:(NSString *)inPubKeyJSON
{
	return [self initWithUserID: inUserID
	                 pubKeyJSON: inPubKeyJSON
	                privKeyJSON: nil];
}

/**
 * See header file for description.
 */
- (instancetype)initWithUserID:(NSString *)inUserID
                    pubKeyJSON:(NSString *)inPubKeyJSON
                   privKeyJSON:(NSString *)inPrivKeyJSON
{
	NSParameterAssert(inUserID != nil);
	NSParameterAssert(inPubKeyJSON != nil);
	
	NSParameterAssert([inPubKeyJSON isKindOfClass:[NSString class]]); // did you accidentally pass a dictionary ?
	if (inPrivKeyJSON) {
		NSParameterAssert([inPrivKeyJSON isKindOfClass:[NSString class]]); // did you accidentally pass a dictionary ?
	}
	
	if ((self = [super init]))
	{
		// IMPORTANT:
		//
		// The `uuid` MUST be a randomly generated value.
		// It MUST NOT be the keyID value.
		//
		// In other words: (uuid != JSON.keyID) <= REQUIRED
		//
		// Why ?
		// Because there's a simple denial-of-service attack.
		// A user simply needs to upload a fake '.pubKey' file to their account,
		// which has the same keyID as some other user.
		// Now, the user simply needs to communicate with other users which will:
		// - cause them to download the .pubKey for the rogue user
		// - insert it into their database, and thus replacing the pubKey for the target (of the DOS attack)
		// - and now a bunch of users have an invalid pubKey for the target
		//
		// Even worse, the attacker could simply communicate with the target.
		// The same thing would happen, but the target would end up replacing their own private key !
		//
		uuid = [[NSUUID UUID] UUIDString];
		//
		// Do NOT change this code.
		// Read the giant comment block above first.
		
		userID      = [inUserID copy];
		pubKeyJSON  = [inPubKeyJSON copy];
		privKeyJSON = [inPrivKeyJSON copy];
	}
	return self;
}

/**
 * See header file for description.
 */
- (id)initWithUserID:(NSString *)inUserID
          pubKeyDict:(NSDictionary *)inPubKeyDict
         privKeyDict:(nullable NSDictionary *)inPrivKeyDict
{
	NSString *inPubKeyJSON = [[self class] s4PropertyStringFromDictionary:inPubKeyDict];
	NSString *inPrivKeyJSON = nil;
	if (inPrivKeyDict) {
		inPrivKeyJSON = [[self class] s4PropertyStringFromDictionary:inPrivKeyDict];
	}
	
	return [self initWithUserID:inUserID
                     pubKeyJSON:inPubKeyJSON
                    privKeyJSON:inPrivKeyJSON];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Version History:
 *
 * // Goes here ...
**/

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
	//	int version = [decoder decodeIntForKey:k_version];
		
		uuid        = [decoder decodeObjectForKey:k_uuid];
		userID      = [decoder decodeObjectForKey:k_userID];
		pubKeyJSON  = [decoder decodeObjectForKey:k_pubKeyJSON];
		privKeyJSON = [decoder decodeObjectForKey:k_privKeyJSON];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
   [coder encodeObject:uuid        forKey:k_uuid];
	[coder encodeObject:userID      forKey:k_userID];
	[coder encodeObject:pubKeyJSON  forKey:k_pubKeyJSON];
	[coder encodeObject:privKeyJSON forKey:k_privKeyJSON];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCPublicKey *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]

	copy->uuid = uuid;
	copy->userID = userID;
	copy->pubKeyJSON = pubKeyJSON;
	copy->privKeyJSON = privKeyJSON;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides ZDCObject.
 * Allows us to specify our atomic cachedX properties as ignored (for immutability purposes).
**/
+ (NSMutableSet<NSString *> *)monitoredProperties
{
	NSMutableSet<NSString *> *result = [super monitoredProperties];
	[result removeObject:NSStringFromSelector(@selector(cachedKeyDict))];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark KeyDict Values
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)keyDict
{
	// Note: We MUST use atomic getter & setter (to be thread-safe)
	
	NSDictionary *keyDict = self.cachedKeyDict;
	if (keyDict == nil)
	{
		NSData *jsonData = [pubKeyJSON dataUsingEncoding:NSUTF8StringEncoding];
		keyDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
		
		if (keyDict) {
			self.cachedKeyDict = keyDict;
		}
	}
	
	return keyDict;
}

- (nullable NSString *)pubKey
{
	id value = self.keyDict[@"pubKey"]; // We forget to export `kS4KeyProp_PubKey` in S4
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	} else {
		return nil;
	}
}

- (nullable NSString *)keyID
{
	id value = self.keyDict[@(kS4KeyProp_KeyID)];
	if ([value isKindOfClass:[NSString class]]) {
		return (NSString *)value;
	} else {
		return nil;
	}
}

/*
- (NSString *)eTag
{
	NSString* keyID = self.keyID;
	NSData* data = [[keyID dataUsingEncoding:NSUTF8StringEncoding] base64EncodedDataWithOptions:0];
	
	return data.lowercaseHexString;
}
*/

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utility functions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isPrivateKey
{
	return (privKeyJSON != nil);
}

- (BOOL)isValidPubKey
{
	// This method is deprecated
	// Use `checkKeyValidityWithError:` instead.
	
	return [self checkKeyValidityWithError:nil];
}

- (BOOL)checkKeyValidityWithError:(NSError **)errorOut
{
	S4Err    err = kS4Err_NoErr;
	NSError *error = nil;
	
	size_t keyCount = 0;
	S4KeyContextRef *pubKeyCtxs = NULL;

	// Attempt to create an S4KeyContextRef from the JSON
	err = S4Key_DeserializeKeys((uint8_t *)self.pubKeyJSON.UTF8String,
	                                       self.pubKeyJSON.UTF8LengthInBytes,
	                                       &keyCount,
	                                       &pubKeyCtxs); CKERR;
	
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);

done:

	if (pubKeyCtxs)
	{
		for (size_t i = 0; i < keyCount; i++)
		{
			S4Key_Free(pubKeyCtxs[i]);
		}
		XFREE(pubKeyCtxs);
	}

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if(errorOut) *errorOut = error;
	return (IsntS4Err(err) && error == nil);
}

- (NSData *)encryptSymKey:(NSData *)cloudKeyIn
                    error:(NSError **)errorOut
{
	NSData *dataOut = nil;
	NSError *error = nil;
	S4Err err = kS4Err_NoErr;
	
	size_t keyCount = 0;
	S4KeyContextRef *pubKeyCtxs = NULL;
	S4KeyContextRef cloudKeyCtx = kInvalidS4KeyContextRef;
	
	uint8_t *data = NULL;
	size_t dataLen = 0;
	
	Cipher_Algorithm cloudKeyAlgor = kCipher_Algorithm_Invalid;
	
	// create a S4 key context for the  public key
	err = S4Key_DeserializeKeys((uint8_t *)self.pubKeyJSON.UTF8String,
	                            self.pubKeyJSON.UTF8LengthInBytes,
	                            &keyCount, &pubKeyCtxs); CKERR;
	
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
    
	// create a S4 key for the cloud key
	switch(cloudKeyIn.length * 8)
	{
		case 256:   cloudKeyAlgor = kCipher_Algorithm_3FISH256; break;
		case 512:   cloudKeyAlgor = kCipher_Algorithm_3FISH512; break;
		case 1024:  cloudKeyAlgor = kCipher_Algorithm_3FISH1024; break;
		default:    RETERR(kS4Err_BadParams);
	}
	err = S4Key_NewTBC(cloudKeyAlgor, cloudKeyIn.bytes, &cloudKeyCtx  ); CKERR;

	// encode the cloud key to the public key.
	err = S4Key_SerializeToS4Key(cloudKeyCtx, pubKeyCtxs[0], &data, &dataLen); CKERR;
	dataOut = [[NSData alloc]initWithBytesNoCopy:data length:dataLen freeWhenDone:YES];
    
done:
    
	if (pubKeyCtxs)
	{
		if (S4KeyContextRefIsValid(pubKeyCtxs[0]))
		{
			S4Key_Free(pubKeyCtxs[0]);
		}
		XFREE(pubKeyCtxs);
	}

	if (S4KeyContextRefIsValid(cloudKeyCtx))
	{
		S4Key_Free(cloudKeyCtx);
	}
    
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if(errorOut) *errorOut = error;
	return dataOut;
}


- (BOOL)updateKeyProperty:(NSString*)propertyID
                    value:(NSData*)value
               storageKey:(S4KeyContextRef)storageKey
                    error:(NSError **)errorOut
{
    BOOL success = NO;
    NSError             *error = NULL;
    S4Err               err = kS4Err_NoErr;
 
    size_t              keyCount = 0;
    S4KeyContextRef     *importCtx = NULL;
    S4KeyContextRef      privKeyCtx = kInvalidS4KeyContextRef;
    
    uint8_t*  privKeyData = NULL;
    uint8_t*  pubKeyData = NULL;
    size_t  keyDataLen = 0;

    NSString* privKeyStr = NULL;
    NSString* pubKeyStr = NULL;

    if(!self.isPrivateKey)
        RETERR(kS4Err_PubPrivKeyNotFound);
    
    if(propertyID.length == 0)
       RETERR(kS4Err_BadParams);
     
    
    // create a S4 key context for the  public key
    err = S4Key_DeserializeKeys((uint8_t*)self.privKeyJSON.UTF8String, self.privKeyJSON.length, &keyCount, &importCtx ); CKERR;
    ASSERTERR(keyCount == 1,  kS4Err_CorruptData);
    
    err = S4Key_DecryptFromS4Key(importCtx[0], storageKey, &privKeyCtx); CKERR;
    // check that it is a private key
    ASSERTERR(privKeyCtx->type == kS4KeyType_PublicKey ,  kS4Err_BadParams);
    ASSERTERR(privKeyCtx->pub.isPrivate,  kS4Err_SelfTestFailed);
  
    err = S4Key_SetPropertyExtended(privKeyCtx, propertyID.UTF8String,  S4KeyPropertyType_UTF8String ,
                                    S4KeyPropertyExtended_Signable,
                                    (void *)value.bytes, value.length ); CKERR;

	err = S4Key_SerializeToS4Key(privKeyCtx, storageKey, &privKeyData, &keyDataLen); CKERR;
	privKeyStr = [[NSString alloc] initWithBytesNoCopy: privKeyData
	                                            length: keyDataLen
	                                          encoding: NSUTF8StringEncoding
	                                      freeWhenDone: YES];
    
	err = S4Key_SerializePubKey(privKeyCtx, &pubKeyData, &keyDataLen); CKERR;
	pubKeyStr = [[NSString alloc] initWithBytesNoCopy: pubKeyData
	                                           length: keyDataLen
	                                         encoding: NSUTF8StringEncoding
	                                     freeWhenDone: YES];

	if (privKeyStr.length && pubKeyStr.length)
	{
		// Are you getting a crash here ?
		// That's because you're attempting to modify an immutable instance.
		// You need to:
		// - make a copy of the publicKey instance: pubKey = [pubKey copy]
		// - modify the copy
		// - update the database with the modified version
		//
		self.pubKeyJSON = pubKeyStr;   // don't change this code - see comment above
		self.privKeyJSON = privKeyStr; // don't change this code - see comment above
		//
		// See comment above
		self.cachedKeyDict = nil; // cached version is now outdated
		success = YES;
	}
     
 done:
    
	if (importCtx)
	{
		if (S4KeyContextRefIsValid(importCtx[0])) {
			S4Key_Free(importCtx[0]);
		}
		XFREE(importCtx);
	}

	if (IsS4Err(err))
		error = [NSError errorWithS4Error:err];
	
	if (errorOut)
		*errorOut = error;

	return success;
}

/**
 * Used when migrating a Private Key to a PublicKey.
 */
- (void)copyToPublicKey:(ZDCPublicKey *)copy
{
	copy->uuid 		  = uuid;
	copy->userID 	  = userID;
	copy->pubKeyJSON = pubKeyJSON;
}

@end
