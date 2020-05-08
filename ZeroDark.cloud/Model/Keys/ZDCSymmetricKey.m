/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCSymmetricKeyPrivate.h"
#import "ZDCObjectSubclass.h"

#import "NSError+S4.h"
#import "NSString+ZeroDark.h"


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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Initializers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (nullable instancetype)createWithAlgorithm:(Cipher_Algorithm)algorithm
                                  storageKey:(S4KeyContextRef)storageKeyCtx
                                       error:(NSError *_Nullable *_Nullable)outError
{
	S4Err err = kS4Err_NoErr;
		
	size_t cipherSizeInBits = 0;
	size_t cipherSizeInBytes = 0;
	
	uint8_t keyBytes[32];
	
	S4KeyContextRef symCtx = kInvalidS4KeyContextRef;
	
	uint8_t * keyData = NULL;
	size_t    keyDataLen = 0;
	
	NSString *keyJSON = nil;
	
	ZDCSymmetricKey *result = nil;
	NSError *error = nil;
	
	ASSERTERR(S4KeyContextRefIsValid(storageKeyCtx), kS4Err_BadParams);
	
	err = Cipher_GetKeySize(algorithm, &cipherSizeInBits); CKERR;
	cipherSizeInBytes = cipherSizeInBits / 8;
	ASSERTERR((cipherSizeInBytes != 0) && (cipherSizeInBytes <= sizeof(keyBytes)), kS4Err_BadParams);
	
	err = RNG_GetBytes(keyBytes, cipherSizeInBytes); CKERR;
	err = S4Key_NewSymmetric(algorithm, keyBytes, &symCtx); CKERR;
	
	err = S4Key_SerializeToS4Key(symCtx, storageKeyCtx, &keyData, &keyDataLen); CKERR;
	keyJSON = [[NSString alloc] initWithBytesNoCopy: keyData
	                                         length: keyDataLen
	                                       encoding: NSUTF8StringEncoding
	                                   freeWhenDone: YES];
	
	result = [[ZDCSymmetricKey alloc] initWithKeyJSON:keyJSON];
		 
done:
	
	ZERO(keyBytes, sizeof(keyBytes));
	
	if (S4KeyContextRefIsValid(symCtx)) {
		S4Key_Free(symCtx);
	}
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (outError) *outError = error;
	return result;
}

+ (nullable instancetype)createWithS4Key:(S4KeyContextRef)symCtx
                              storageKey:(S4KeyContextRef)storageKeyCtx
	                                error:(NSError *_Nullable *_Nullable)outError
{
	S4Err err = kS4Err_NoErr;
	
	uint8_t * keyData = NULL;
	size_t    keyDataLen = 0;
	
	NSString *keyJSON = nil;
	
	ZDCSymmetricKey *result = nil;
	NSError *error = nil;
	
	ASSERTERR(symCtx->type == kS4KeyType_Symmetric, kS4Err_BadParams);
	ASSERTERR(S4KeyContextRefIsValid(symCtx), kS4Err_BadParams);
	
	err = S4Key_SerializeToS4Key(symCtx, storageKeyCtx, &keyData, &keyDataLen); CKERR;
	keyJSON = [[NSString alloc] initWithBytesNoCopy: keyData
	                                         length: keyDataLen
	                                       encoding: NSUTF8StringEncoding
	                                   freeWhenDone: YES];
	
	result = [[ZDCSymmetricKey alloc] initWithKeyJSON:keyJSON];
	
done:
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (outError) *outError = error;
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithKeyJSON:(NSString *)inKeyJSON
{
	if ((self = [super init]))
	{
		uuid = [[NSUUID UUID] UUIDString];
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
