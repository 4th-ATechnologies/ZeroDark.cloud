/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCSymmetricKey.h"
#import "ZDCObjectSubclass.h"

static int const kS4SymmetricKey_CurrentVersion = 0;

static NSString *const k_version     = @"version";
static NSString *const k_uuid        = @"uuid";
static NSString *const k_keyJSON     = @"keyJSON";


@interface ZDCSymmetricKey ()
@property (atomic, strong, readwrite) NSDictionary *cachedKeyDict;
@end

@implementation ZDCSymmetricKey

@synthesize uuid = uuid;
@synthesize keyJSON = keyJSON;

@synthesize cachedKeyDict = _cachedKeyDict_atomic_property_must_use_selfDot_syntax;

@dynamic keyDict;


static BOOL S4MakeSymmetricKey(Cipher_Algorithm keyAlgorithm,
                               S4KeyContextRef  storageKeyCtx,
                               NSString**       keyStringOut,
                               NSString**       keyIDOut)
{
	BOOL success = NO;
	S4Err     err = kS4Err_NoErr;
	
	NSString* symKey = nil;
	NSString* keyID = nil;
	
	S4KeyContextRef symCtx = kInvalidS4KeyContextRef;
	
	uint8_t*    keyData = NULL;
	size_t      keyDataLen = 0;
	char*       keyIDStr = NULL;
	
	uint8_t         keyBytes[32];
	
	size_t cipherSizeInBits = 0;
	size_t cipherSizeInBytes = 0;
	
	// create the new storage key
	
	err = Cipher_GetKeySize(keyAlgorithm, &cipherSizeInBits); CKERR;
	cipherSizeInBytes = cipherSizeInBits / 8;
	ASSERTERR((cipherSizeInBytes != 0) && (cipherSizeInBytes <= sizeof(keyBytes)), kS4Err_BadParams);
	
	err = RNG_GetBytes(keyBytes, cipherSizeInBytes); CKERR;
	err = S4Key_NewSymmetric(keyAlgorithm, keyBytes, &symCtx ); CKERR;
	err = S4Key_GetAllocatedProperty(symCtx, kS4KeyProp_KeyIDString, NULL, (void **)&keyIDStr, NULL); CKERR;
	keyID = [NSString stringWithUTF8String:keyIDStr];
	
	err = S4Key_SerializeToS4Key(symCtx, storageKeyCtx, &keyData, &keyDataLen); CKERR;
	symKey = [[NSString alloc] initWithBytesNoCopy: keyData
	                                        length: keyDataLen
	                                      encoding: NSUTF8StringEncoding
	                                  freeWhenDone: YES];
	
	if (keyStringOut) *keyStringOut = symKey;
   if (keyIDOut) *keyIDOut = keyID;
	
	success = YES;
    
done:
    
    ZERO(keyBytes, sizeof(keyBytes));
    
    if(keyIDStr)
        XFREE(keyIDStr);
    
    if(S4KeyContextRefIsValid(symCtx))
          S4Key_Free(symCtx);
    
    return success;
}

static BOOL importEncodedSymmetricKey(NSString  * keyStringIn,
                                NSString  * passCodeIn,
                                NSString ** locatorOut )
{
    BOOL            success = NO;
    S4Err           err = kS4Err_NoErr;

    S4KeyContextRef symCtx      =  kInvalidS4KeyContextRef;
    S4KeyContextRef *importCtx = NULL;
    size_t          keyCount = 0;
    
     err = S4Key_DeserializeKeys((uint8_t*)keyStringIn.UTF8String, keyStringIn.length, &keyCount, &importCtx ); CKERR;
    ASSERTERR(keyCount == 1,  kS4Err_SelfTestFailed);
    
    err = S4Key_DecryptFromPassPhrase(importCtx[0],(uint8_t*) passCodeIn.UTF8String, passCodeIn.length, &symCtx); CKERR;
  
    // check that it is a sym key
    ASSERTERR(symCtx->type == kS4KeyType_Symmetric ,  kS4Err_BadParams);
 

    success =  YES;
    
done:
    
    if(S4KeyContextRefIsValid(symCtx))
        S4Key_Free(symCtx);
    
   
    return success;
}

static BOOL importS4Key(S4KeyContextRef     symCtx,
                        S4KeyContextRef      storageKeyCtx,
                        NSString             ** keyStringOut,
                        NSString             ** keyIDOut  )
{
    BOOL            success = NO;
    S4Err           err = kS4Err_NoErr;
    
    NSString*       keyString = NULL;
    NSString*       keyID = NULL;
    
    if(S4KeyContextRefIsValid(symCtx))
    {
        uint8_t*    keyData = NULL;
        size_t      keyDataLen = 0;
        char*       keyIDStr = NULL;
        
        // check that it is a sym key
        ASSERTERR(symCtx->type == kS4KeyType_Symmetric ,  kS4Err_BadParams);
        
        err = S4Key_GetAllocatedProperty(symCtx, kS4KeyProp_KeyIDString, NULL, (void**)&keyIDStr, NULL); CKERR;
        keyID = [NSString stringWithUTF8String:keyIDStr];
     
        err = S4Key_SerializeToS4Key(symCtx, storageKeyCtx, &keyData, &keyDataLen); CKERR;
        keyString = [[NSString alloc]initWithBytesNoCopy:keyData length:keyDataLen encoding:NSUTF8StringEncoding freeWhenDone:YES];
  
        if(keyStringOut) *keyStringOut = keyString;
        if(keyIDOut) *keyIDOut = keyID;
        
        success =  YES;
     }
    
done:
    
    
    return success;
}




+ (instancetype)keyWithS4Key:(S4KeyContextRef)symCtx
                  storageKey:(S4KeyContextRef)storageKey
{
    ZDCSymmetricKey *key = nil;
    
    NSString *keyString = nil;
    NSString *locator = nil;
    
    if ( importS4Key(symCtx, storageKey, &keyString, &locator))
    {
          key =  [[ZDCSymmetricKey alloc] initWithUUID:locator
                                              keyJSON:keyString];
    }
        
    return key;
}

+ (id)keyWithAlgorithm:(Cipher_Algorithm)algorithm
            storageKey:(S4KeyContextRef)storageKey
{
    ZDCSymmetricKey *key = nil;
    NSString *keyString = nil;
    NSString *locator = nil;
    
    if (S4MakeSymmetricKey(algorithm, storageKey,  &keyString, &locator))
    {
        key =  [[ZDCSymmetricKey alloc] initWithUUID:locator
                                            keyJSON:keyString];
    }
    
    return key;
}


+ (id)keyWithString:(NSString *)inKeyJSON passCode:(NSString*)passCode
{
    ZDCSymmetricKey *key = nil;
    
       NSString *locator = nil;
    
    if (importEncodedSymmetricKey(inKeyJSON, passCode, &locator))
    {
        key = [[ZDCSymmetricKey alloc] initWithUUID:locator
                                           keyJSON:inKeyJSON];
    }
    
    return key;
}

- (instancetype)initWithUUID:(NSString *)inUUID
                     keyJSON:(NSString *)inKeyJSON
{
	if ((self = [super init]))
	{
		uuid = [inUUID copy];
		keyJSON = [inKeyJSON copy];
	}
	return self;
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
		uuid    = [decoder decodeObjectForKey:k_uuid];
		keyJSON = [decoder decodeObjectForKey:k_keyJSON];
   }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kS4SymmetricKey_CurrentVersion != 0) {
		[coder encodeInt:kS4SymmetricKey_CurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:uuid    forKey:k_uuid];
	[coder encodeObject:keyJSON forKey:k_keyJSON];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
    ZDCSymmetricKey *copy = [super copyWithZone:zone];
    
    copy->uuid = uuid;
    copy->keyJSON = keyJSON;
    
    return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCObject
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides ZDCObject.
 * Allows us to specify our atomic cached property as ignored (for immutability purposes).
**/
+ (NSMutableSet *)monitoredProperties
{
	NSMutableSet *result = [super monitoredProperties];
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
        NSData *jsonData = [keyJSON dataUsingEncoding:NSUTF8StringEncoding];
        keyDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
        
        self.cachedKeyDict = keyDict;
    }
    
    return keyDict;
}

@end
