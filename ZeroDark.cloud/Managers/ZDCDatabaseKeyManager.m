/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCDatabaseKeyManagerPrivate.h"

#import "ZDCDirectoryManager.h"
#import "ZDCLogging.h"

// Categories
#import "NSString+ZeroDark.h"
#import "NSError+ZeroDark.h"
#import "NSError+S4.h"
#import "NSData+S4.h"

// Libraries
#import <S4Crypto/S4Crypto.h>
@import LocalAuthentication;


#if DEBUG && robbie_hanson
static const int ddLogLevel = DDLogLevelVerbose | DDLogFlagTrace;
#elif DEBUG
static const int ddLogLevel = DDLogLevelWarning;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

NSString *const kPassPhraseSourceKey_keychain     = @"keychain";
NSString *const kPassPhraseSourceKey_keyboard     = @"keyboard";
NSString *const kPassPhraseSourceKey_biometric    = @"biometric";

static  NSString *const kPassPhraseHintKey        = @"passPhraseHint";
static  NSString *const kPassPhraseSourceKey      = @"passPhraseSource";

static Cipher_Algorithm  defaultKeyCipherAlgorithm	=	 kCipher_Algorithm_2FISH256;
static P2K_Algorithm  	defaultP2KAlgorithm			=	 kP2K_Algorithm_Argon2i;

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

@implementation ZDCDatabaseKeyManager
{
	__weak ZeroDarkCloud *zdc;

	S4KeyContextRef sKeyCtx;

}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.databaseKeyManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
	}
	return self;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}

	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isConfigured
{
	BOOL result = NO;

	NSURL *storageBlobURL = [self storageBlobURL];
	BOOL fileExists = [storageBlobURL checkResourceIsReachableAndReturnError:NULL];

	if(fileExists)
	{
		NSDictionary* dict = [self keysDictWithError:NULL];
		if(dict.count > 0)
			result = YES;
	}
 	return result;
}

- (BOOL)isUnlocked
{
	return S4KeyContextRefIsValid(sKeyCtx);
}

- (BOOL)usesKeychainKey
{
	__block BOOL result = NO;

	[self configureStorageKey:(defaultKeyCipherAlgorithm) error:nil];

	// test for keychain
	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSDictionary* kcDict = [dictIn objectForKey:kPassPhraseSourceKey_keychain];

	result  = kcDict && [self  hasKeychainPassphrase];

	return result;
}

- (BOOL)usesPassphrase
{
	__block BOOL result = NO;
	[self configureStorageKey:(defaultKeyCipherAlgorithm) error:nil];

	// test for keychain
	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSDictionary* kcDict = [dictIn objectForKey:kPassPhraseSourceKey_keyboard];

	result  = kcDict != nil;

	return result;
}

- (BOOL)usesBioMetrics
{
	__block BOOL result = NO;
	[self configureStorageKey:(defaultKeyCipherAlgorithm) error:nil];

	// test for keychain
	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSDictionary* kcDict = [dictIn objectForKey:kPassPhraseSourceKey_biometric];

	result  = (kcDict != NULL)  && [self  hasBioPassphrase];

	return result;
}


-(NSData*) storageKey
{
	NSData* data = NULL;

	if (S4KeyContextRefIsValid(sKeyCtx)) {

		data = [NSData allocSecureDataWithLength:sKeyCtx->sym.keylen];
		COPY(sKeyCtx->sym.symKey, data.bytes, sKeyCtx->sym.keylen);
	}

	return data;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


// initial setup storageKey and create temporary keychain password.
-(BOOL) configureStorageKey:(Cipher_Algorithm)algorithm
					  error:(NSError *_Nullable *_Nullable) outError
{
	BOOL            sucess = NO;
	S4Err           err = kS4Err_NoErr;
	NSError         *error  = NULL;
	const int       keyBytesLen =  32;
	uint8_t         keyBytes[keyBytesLen];

	if(self.isConfigured)
	{
		return YES;
	}
	// create the new storage key
	size_t keySizeInBits = 0;

	err = Cipher_GetKeySize(algorithm, &keySizeInBits); CKERR;

	NSAssert((keySizeInBits > 0) && ((keySizeInBits / 8) <= keyBytesLen), @"Mismatch: algorithm vs keySize");

	err = RNG_GetBytes(keyBytes, (keySizeInBits / 8)); CKERR;
	err = S4Key_NewSymmetric(algorithm, keyBytes, &sKeyCtx); CKERR;

	sucess = [self createKeychainEntryKeyWithError:&error];

done:

	ZERO(keyBytes, sizeof(keyBytes));

	if (outError) *outError = error;
	return sucess;
 }


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Keychain
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)keychainPassphraseIdentifier
{
	// The keychain entry is tied to 2 things:
	// - the app that created the entry
	// - the database file it's associated with
	//
	NSString *appOwner = [ZDCDirectoryManager bundleIdentifier];
	NSString *dbFilename = zdc.databasePath.lastPathComponent;
	
	return [NSString stringWithFormat:@"%@|%@.keyChainPassphrase", appOwner, dbFilename];
}


-(BOOL) createKeychainEntryKeyWithError:(NSError *_Nullable *_Nullable) outError
{
	NSError     *error = NULL;
	BOOL       success    = NO;
	Cipher_Algorithm algorithm = defaultKeyCipherAlgorithm;
	NSDictionary* blob  = NULL;

	NSData* kcPassphraseData  = [self makeKeyChainPassphraseWithAlgorithm:algorithm error:&error];

	if(kcPassphraseData)
	{
		blob = [self blobWithPassKey:kcPassphraseData
					passKeyAlgorithm:algorithm
							   error:&error]; CKERROR;

		success = [self addKeyStorageBlob:blob
						 passPhraseSource:kPassPhraseSourceKey_keychain
								 outError:&error]; CKERROR;
	}

done:
	if(error && outError)
	{
		*outError = error.copy;
	}

	return success;
}

- (BOOL)hasKeychainPassphrase
{
	BOOL sucess = NO;
	NSString *keychainPassphraseIdentifier = [self keychainPassphraseIdentifier];

	NSDictionary *query = @{
		(__bridge id)kSecAttrService          : keychainPassphraseIdentifier,
		(__bridge id)kSecReturnAttributes     : @YES,
		(__bridge id)kSecClass                : (__bridge id) kSecClassGenericPassword,
		(__bridge id)(kSecAttrSynchronizable) : (__bridge id) kSecAttrSynchronizableAny
	};

	CFTypeRef queryResult = NULL;

	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &queryResult);
	if (status == errSecSuccess)
	{
		sucess = YES;
	}
	else
	{
		if (queryResult) CFRelease(queryResult);
	}

	return sucess;
}


- (nullable NSData *)unlockUsingKeychainKeyWithError:(NSError *_Nullable *_Nullable) outError
{
	BOOL sucess     = NO;
	NSError     *error = NULL;
	Cipher_Algorithm algorithm = defaultKeyCipherAlgorithm;

	if([self usesKeychainKey])
	{
		NSData* kcPassphraseData = [self keychainPassphraseDataWithError:&error];

		if(kcPassphraseData && !error)
		{
			sucess = [self unlockStorageBlobWithPassKey:kcPassphraseData
									   passKeyAlgorithm:algorithm
									   passPhraseSource: kPassPhraseSourceKey_keychain
												  error: &error]
			&& !error;
		}
 	}
	else
	{
		error = [self errorWithDescription:@"Not encrypted to keychain"];
	}

	if(error && outError)
	{
		*outError = error.copy;
	}

	return sucess? [self storageKey]:nil;
 }

- (NSData*) keychainPassphraseDataWithError:(NSError**)errorOut

{
	NSData* kcData = nil;

	// Read the guidPassphrase from the keychain.
	NSMutableDictionary *query = @{
		(__bridge id)kSecAttrService     : [self keychainPassphraseIdentifier],
		(__bridge id)kSecAttrAccount            : @"",
		(__bridge id)kSecReturnData             : @YES,
		(__bridge id)(kSecMatchLimit)           :(__bridge id) kSecMatchLimitOne,
		(__bridge id)(kSecClass)                :(__bridge id) kSecClassGenericPassword,
		(__bridge id)(kSecAttrSynchronizable)   :(__bridge id) kSecAttrSynchronizableAny
	}.mutableCopy;

	CFTypeRef passwordData = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &passwordData);

	if (status == errSecSuccess)
	{
		kcData = (__bridge_transfer NSData *)passwordData;
	}

	if(!kcData && (status != errSecItemNotFound))
	{
		if(errorOut)
		{
			*errorOut = [self errorWithKeyOSStatus:status];
		}
	}

	return kcData;
}


- (NSData *)makeKeyChainPassphraseWithAlgorithm:(Cipher_Algorithm)passKeyAlgorithm
										  error:(NSError **)outError
{
	NSError*        error = NULL;
	S4Err        	err = kS4Err_NoErr;
	OSStatus 		status = errSecSuccess;

	//uint8_t unlockingKey[32];
	size_t  keySizeInBits = 0;
	size_t  keySizeInBytes = 0;

	NSData* kcPassphraseData = nil;
	NSDictionary *query;

	err = Cipher_GetKeySize(passKeyAlgorithm, &keySizeInBits); CKERR;
	keySizeInBytes = keySizeInBits / 8;

	kcPassphraseData = [NSData allocSecureDataWithLength:keySizeInBytes];
	err = RNG_GetBytes((void *)kcPassphraseData.bytes, keySizeInBytes); CKERR;

	// try deleting old one first
	[self deleteKeychainPassphraseWithError:NULL];

	query = @{
			  (__bridge NSString *)kSecAttrService          : [self keychainPassphraseIdentifier],
			  (__bridge NSString *)kSecAttrAccount          : @"",
			  (__bridge NSString *)kSecValueData            : kcPassphraseData,
			  (__bridge NSString *)kSecClass                :(__bridge NSString *)kSecClassGenericPassword,
			  (__bridge NSString *)kSecAttrSynchronizable   :(__bridge NSString *)kSecAttrSynchronizableAny,
			  (__bridge NSString *)kSecAttrAccessible       :(__bridge NSString *)kSecAttrAccessibleAfterFirstUnlock,
			  };

	status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	if (status != errSecSuccess)
	{
		error = [self errorWithKeyOSStatus:status];
	}

done:

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (outError) *outError = error;
	return (error == nil) ? kcPassphraseData : nil;
}


-(BOOL)  deleteKeychainPassphraseWithError:(NSError**)errorOut
{
 	BOOL success = NO;

	NSDictionary *query = @{ (__bridge id)kSecAttrService            : [self keychainPassphraseIdentifier],
							 (__bridge id)kSecAttrAccount            : @"",
							 (__bridge id)(kSecClass)                :(__bridge id) kSecClassGenericPassword,
							 (__bridge id)(kSecAttrSynchronizable)   :(__bridge id) kSecAttrSynchronizableAny
							 };

	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

	if( status == errSecSuccess )
	{
		success = YES;
	}
	else
	{
		if(errorOut)
		{
			*errorOut = [self errorWithKeyOSStatus:status];
		}
	}

	return success;
}


- (NSError *)errorWithKeyOSStatus:(OSStatus) code
{
	NSString *message = nil;
	switch (code) {
		case errSecSuccess: return nil;

		case errSecUnimplemented: {
			message = @"errSecUnimplemented";
			break;
		}
		case errSecParam: {
			message = @"errSecParam";
			break;
		}
		case errSecAllocate: {
			message = @"errSecAllocate";
			break;
		}
		case errSecNotAvailable: {
			message = @"errSecNotAvailable";
			break;
		}
		case errSecDuplicateItem: {
			message = @"errSecDuplicateItem";
			break;
		}
		case errSecItemNotFound: {
			message = @"errSecItemNotFound";
			break;
		}
		case errSecInteractionNotAllowed: {
			message = @"errSecInteractionNotAllowed";
			break;
		}
		case errSecDecode: {
			message = @"errSecDecode";
			break;
		}
		case errSecAuthFailed: {
			message = @"errSecAuthFailed";
			break;
		}
		case errSecUserCanceled: {
			message = @"errSecUserCanceled";
			break;
		}
		default: {
			message = [NSString stringWithFormat: @"errSec Code %d", (int)code];
		}
	}

	NSDictionary *userInfo = nil;
	if (message) {
		userInfo = @{ NSLocalizedDescriptionKey : message };
	}
	return [NSError errorWithDomain:NSOSStatusErrorDomain code:code userInfo:userInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark passphrase
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(BOOL) createPassPhraseKey:(NSString*)passPhrase
			 passPhraseHint:(NSString*)passPhraseHint
					  error:(NSError *_Nullable *_Nullable) outError
{

	NSError*	error = NULL;
	S4Err   	err = kS4Err_NoErr;
	BOOL       	success    = NO;

	uint8_t    *passCode = NULL;
	size_t     passCodeLen = 0;

	uint8_t     *data = NULL;
	size_t      dataLen = 0;

	err = HASH_NormalizePassPhrase((uint8_t*) passPhrase.UTF8String, passPhrase.UTF8LengthInBytes,
								   (uint8_t*) zdc.zAppID.UTF8String, zdc.zAppID.UTF8LengthInBytes,
								   &passCode, &passCodeLen); CKERR;

	err = S4Key_SerializeToPassCode(sKeyCtx,
									passCode,  passCodeLen, defaultP2KAlgorithm,
									&data, &dataLen); CKERR;
	{
		NSData* newBlobData = [NSData dataWithBytes:data length:dataLen];

		id blobData = [NSJSONSerialization JSONObjectWithData:newBlobData
													  options:0 error:&error];
		if (!error && [blobData isKindOfClass: [NSDictionary class]])
		{
			NSMutableDictionary* blobDict =
					[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)blobData];

			if(passPhraseHint.length > 0)
 				[blobDict setObject:passPhraseHint forKey:kPassPhraseHintKey];
 
			success = [self addKeyStorageBlob:blobDict
							 passPhraseSource:kPassPhraseSourceKey_keyboard
									 outError:&error]; CKERROR;
		}
	}

done:

	if(passCode)
	{
		XFREE(passCode);
		passCode = NULL;
	}

	if(data)
	{
		XFREE(data);
		data = NULL;
	}

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (outError)
		*outError = error;

	return success;
}


-(nullable NSData*) unlockUsingPassphaseKey:(NSString*)passPhrase
						  error:(NSError**)outError
{
	NSError*	error = NULL;
	S4Err   	err = kS4Err_NoErr;
	BOOL       	success    = NO;

	S4KeyContextRef     unlockingKey = kInvalidS4KeyContextRef;

	uint8_t    *passCode = NULL;
	size_t     passCodeLen = 0;

	if ([self getKeyForPassPhraseSource:kPassPhraseSourceKey_keyboard
							 keyContext:&unlockingKey
								  error:&error ])
	{
		err = HASH_NormalizePassPhrase((uint8_t*) passPhrase.UTF8String, passPhrase.UTF8LengthInBytes,
									   (uint8_t*) zdc.zAppID.UTF8String, zdc.zAppID.UTF8LengthInBytes,
									   &passCode, &passCodeLen); CKERR;

		err = S4Key_DecryptFromPassCode(unlockingKey,
										passCode, passCodeLen,
										&sKeyCtx); CKERR;

		success = YES;
	}
	else
	{
		error = [self errorWithDescription:@"Not encrypted to password"];
 	}


done:

	if(passCode)
		XFREE(passCode);

	if (S4KeyContextRefIsValid(unlockingKey))
		S4Key_Free(unlockingKey);


	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (outError)
		*outError = error;

	return success? [self storageKey]:NULL;
}

-(nullable NSString*) hintStringForPassphraseKey
{
 	NSString* 			result = NULL;
	// test for keychain
	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSDictionary* p2kDict = [dictIn objectForKey:kPassPhraseSourceKey_keyboard];

	if(p2kDict)
	{
		result = [p2kDict objectForKey:kPassPhraseHintKey];
	}

	return result;
}

-(BOOL) removePassphraseKeyWithError:(NSError *_Nullable *_Nullable) outError
{
	BOOL success    = YES;

	if(self.usesPassphrase)
	{
 		success = [self createKeychainEntryKeyWithError:outError];
 	}

	return success;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark biometric
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)bioPassphraseIdentifier
{
	// The keychain entry is tied to 2 things:
	// - the app that created the entry
	// - the database file it's associated with
	//
	NSString *appOwner = [ZDCDirectoryManager bundleIdentifier];
	NSString *dbFilename = zdc.databasePath.lastPathComponent;
	
	return [NSString stringWithFormat:@"%@|%@.biometricPassphrase", appOwner, dbFilename];
}

- (BOOL)canUseBioMetrics
{
	BOOL    result = NO;
	NSError *error = NULL;

	LAContext *context = [[LAContext alloc] init];

	// test if we can evaluate the policy, this test will tell us if Touch ID is available and enrolled
	if (context)
	{
#if TARGET_OS_IPHONE
		result = [context canEvaluatePolicy: LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
#else
		result = [context canEvaluatePolicy: LAPolicyDeviceOwnerAuthentication error:&error];
#endif

		if (result && error) result = NO;
	}

	return result;
}

 -(BOOL) createBiometricKeyWithError:(NSError *_Nullable *_Nullable) outError
{

	NSError     *error = NULL;
	BOOL       success    = NO;
	Cipher_Algorithm algorithm = defaultKeyCipherAlgorithm;
	NSDictionary* blob  = NULL;


	NSData* bioPassphraseData  = [self makeBioPassphraseWithAlgorithm:algorithm error:&error];

	if(bioPassphraseData)
	{
		blob = [self blobWithPassKey:bioPassphraseData
					passKeyAlgorithm:algorithm
							   error:&error]; CKERROR;

		success = [self addKeyStorageBlob:blob
						 passPhraseSource:kPassPhraseSourceKey_biometric
								 outError:&error]; CKERROR;
	}

done:
	if(error && outError)
	{
		*outError = error.copy;
	}

	return success;
}

- (BOOL)hasBioPassphrase
{
	BOOL sucess = NO;

	// Read the guidPassphrase from the keychain.
	NSDictionary *query = @{ (__bridge id)kSecAttrService            : [self bioPassphraseIdentifier],
							 (__bridge id)kSecAttrAccount            : @"",
							 (__bridge id)kSecReturnData             : @NO,
							 (__bridge id)(kSecMatchLimit)           :(__bridge id) kSecMatchLimitOne,
							 (__bridge id)(kSecClass)                :(__bridge id) kSecClassGenericPassword,
							 (__bridge id)(kSecAttrSynchronizable)   :(__bridge id) kSecAttrSynchronizableAny,
							 (__bridge id)kSecUseAuthenticationUI    :(__bridge id) kSecUseAuthenticationUIFail,
							 };

	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);

	if (status == errSecSuccess || status == errSecInteractionNotAllowed)   // we asked for no interaction here.
	{
		sucess = YES;
	}

	return sucess;
}

-(nullable NSData*) unlockUsingBiometricKeyWithPrompt:(NSString*)prompt
								   error:(NSError *_Nullable *_Nullable) outError
{
	BOOL sucess     = NO;
	NSError     *error = NULL;
	Cipher_Algorithm algorithm = defaultKeyCipherAlgorithm;

	NSData* bioPassphraseData = [self authenticateBioPassPhraseWithPrompt:prompt
																	error:&error];
	if(bioPassphraseData && !error)
	{
		sucess = [self unlockStorageBlobWithPassKey:bioPassphraseData
								   passKeyAlgorithm:algorithm
								   passPhraseSource: kPassPhraseSourceKey_biometric
											  error: &error]
		&& !error;
	}

	if(error && outError)
	{
		*outError = error.copy;
	}

	return sucess? [self storageKey]:NULL;
}

-(BOOL) removeBioMetricKeyWithError:(NSError *_Nullable *_Nullable) outError
{
 	BOOL                success = NO;
	NSError*            error = NULL;

	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSMutableDictionary* dict = NSMutableDictionary.dictionary;
	
	if(dictIn)
		[dict addEntriesFromDictionary:dictIn];


	if(dict.count > 1)
	{
 		[dict removeObjectForKey:kPassPhraseSourceKey_biometric];
		[self deleteBioPassphraseWithError:NULL];

		NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:NULL];

		success = [data writeToURL:self.storageBlobURL
						   options:NSDataWritingAtomic
							 error:&error];
	}
	else
	{
		error = [self errorWithDescription:@"Can not remove the last authentication method"];
	}

	if (outError) *outError = error;

	return success;
}


- (NSData *)makeBioPassphraseWithAlgorithm:(Cipher_Algorithm)passKeyAlgorithm error:(NSError **)outError
{
	NSError*    error = nil;
	S4Err       err;

	CFErrorRef  sacError = NULL;
	SecAccessControlRef sacObject = NULL;

	NSData*     bioPassphraseData = NULL;

	const int   unlockingKeyLen = 32;
	uint8_t     unlockingKey[unlockingKeyLen];

	size_t      keySizeInBits = 0;
	size_t      keySizeInBytes = 0;

	// try deleting old one first
	[self deleteBioPassphraseWithError: NULL ];

	err = Cipher_GetKeySize(passKeyAlgorithm, &keySizeInBits); CKERR;
	keySizeInBytes = keySizeInBits/ 8;

	err = RNG_GetBytes(unlockingKey, keySizeInBytes); CKERR;

	// Should the secret be invalidated when passcode is removed?
	// If not then use kSecAttrAccessibleWhenUnlocked

#if TARGET_OS_IPHONE
	{
		sacObject =
		SecAccessControlCreateWithFlags(kCFAllocatorDefault,
										kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
										kSecAccessControlTouchIDCurrentSet,
										&sacError);
	}
#else
	{
		sacObject =
		SecAccessControlCreateWithFlags(kCFAllocatorDefault,
										kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
										kSecAccessControlUserPresence,
										&sacError);
	}
#endif

	if (sacError)
	{
		if (sacObject) {
			CFRelease(sacObject);
			sacObject = NULL;
		}

		error = (__bridge NSError *)sacError;
	}
	else
	{
		bioPassphraseData = [NSData dataWithBytes:unlockingKey length:keySizeInBytes];

		NSDictionary *query = @{
								(__bridge NSString *)kSecAttrService         : [self bioPassphraseIdentifier],
								//	(__bridge NSString *)kSecAttrAccount         : @"",
								(__bridge NSString *)kSecValueData           : bioPassphraseData,
								(__bridge NSString *)kSecClass               : (__bridge id)kSecClassGenericPassword,
								(__bridge NSString *)kSecUseAuthenticationUI : @YES,
								(__bridge NSString *)kSecAttrAccessControl   : (__bridge_transfer id)sacObject
								};

		OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
		if (status != errSecSuccess)
		{
			error = [self errorWithKeyOSStatus:status];
		}
	}

done:

	ZERO(unlockingKey, sizeof(unlockingKey));

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (outError) *outError = error;
	return (error == nil) ? bioPassphraseData : nil;
}


-(BOOL)  deleteBioPassphraseWithError:(NSError**)outError
{
	BOOL success = NO;

	NSDictionary *query = @{ (__bridge id)kSecAttrService            : [self bioPassphraseIdentifier],
							 //                             (__bridge id)kSecAttrAccount            : @"",
							 (__bridge id)(kSecClass)                :(__bridge id) kSecClassGenericPassword,
							 (__bridge id)(kSecAttrSynchronizable)   :(__bridge id) kSecAttrSynchronizableAny
							 };

	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

	if( status == errSecSuccess )
	{
		success = YES;
	}
	else
	{
		if(outError)
		{
			*outError = [self errorWithKeyOSStatus:status];
		}
	}

	return success;
}

- (NSData*) authenticateBioPassPhraseWithPrompt:(NSString*)prompt
										  error:(NSError**)outError

{
	NSData* bioData = nil;

	// Read the guidPassphrase from the keychain.
	NSMutableDictionary *query = @{ (__bridge id)kSecAttrService     : [self bioPassphraseIdentifier],
									//                                    (__bridge id)kSecAttrAccount            : @"",
									(__bridge id)kSecReturnData             : @YES,
									//                                   (__bridge id)(kSecMatchLimit)           :(__bridge id) kSecMatchLimitOne,
									(__bridge id)(kSecClass)                :(__bridge id) kSecClassGenericPassword,
									(__bridge id)(kSecAttrSynchronizable)   :(__bridge id) kSecAttrSynchronizableAny
									}.mutableCopy;

	if(prompt)
	{
		[query setObject:prompt forKey: (__bridge id)kSecUseOperationPrompt];
	}

	CFTypeRef passwordData = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &passwordData);

	if (status == errSecSuccess)
	{
		bioData = (__bridge_transfer NSData *)passwordData;
	}

	if(!bioData && (status != errSecItemNotFound))
	{
		if(outError)
		{
			*outError = [self errorWithKeyOSStatus:status];
		}
	}

	return bioData;
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark p2kFile data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSURL*) storageBlobURL
{
	NSURL *url = [zdc.databasePath URLByAppendingPathExtension:@"p2k"];
	return url;
}

-(NSDictionary*) keysDictWithError:(NSError *_Nullable *_Nullable) outError
{
	NSError*        error = NULL;
	NSDictionary*   dict = NULL;

	NSURL *storageBlobURL = [self storageBlobURL];

	NSData* storageBlob = [NSData dataWithContentsOfURL:storageBlobURL
												options:0
												  error:&error];
	if(!error)
	{
		id blobData = [NSJSONSerialization JSONObjectWithData:storageBlob options:0 error:&error];

		if ([blobData isKindOfClass: [NSDictionary class]])
		{
			dict =  blobData ;
		}
		else
		{
			error = [self errorWithDescription:@"Corrupt p2k file"];
		}
	}

	if(error && outError)
	{
		*outError = error;
	}

	return dict;
}

// create storage blob dictionary entry using passKey

- (NSDictionary *)blobWithPassKey:(NSData *)passKey
				 passKeyAlgorithm:(Cipher_Algorithm)passKeyAlgorithm
							error:(NSError **)errorOut

{
	NSError*            error = NULL;
	S4Err               err = kS4Err_NoErr;

	S4KeyContextRef     sKey = kInvalidS4KeyContextRef;
	S4KeyContextRef     passKeyCtx =  kInvalidS4KeyContextRef;
	size_t              cipherSizeInBits = 0;
	size_t              cipherSizeInBytes = 0;

	NSDictionary*       blob = NULL;

	uint8_t*            keyData = NULL;
	size_t              keyDataLen = 0;

	NSData*             newBlobData= NULL;

	// must have keyContext
	if (!sKeyCtx) {
		RETERR(kS4Err_BadParams);
	}

	err = Cipher_GetKeySize(passKeyAlgorithm, &cipherSizeInBits); CKERR;
	cipherSizeInBytes = cipherSizeInBits / 8;
	ASSERTERR(passKey.length == cipherSizeInBytes, kS4Err_BadParams);

	// create a new key to encrypt the storage key to
	err = S4Key_NewSymmetric(passKeyAlgorithm, passKey.bytes, &passKeyCtx  ); CKERR;

	// Encrypt the storage key and extract metaData
	err = S4Key_SerializeToS4Key(sKeyCtx, passKeyCtx, &keyData, &keyDataLen); CKERR;

	newBlobData = [NSData dataWithBytes:keyData length:keyDataLen];

	blob = [NSJSONSerialization JSONObjectWithData:newBlobData options:0 error:&error]; CKERROR;

done:

	if (S4KeyContextRefIsValid(sKey)) {
		S4Key_Free(sKey);
	}

	if (S4KeyContextRefIsValid(passKeyCtx)) {
		S4Key_Free(passKeyCtx);
	}

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (errorOut) *errorOut = error;
	return blob;
}


// add or replace the key storage blob,
-(BOOL) addKeyStorageBlob:(NSDictionary*)newKeyBlob
		passPhraseSource:(NSString *)passPhraseSource
				 outError:(NSError *_Nullable *_Nullable) outError
{
	BOOL                success = NO;
	NSError*            error = NULL;

	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSMutableDictionary* dict = NSMutableDictionary.dictionary;

	if(dictIn)
		[dict addEntriesFromDictionary:dictIn];

	if([passPhraseSource isEqualToString:kPassPhraseSourceKey_keyboard])
	{
		[dict removeObjectForKey:kPassPhraseSourceKey_keychain];
		[self deleteKeychainPassphraseWithError:NULL];
	}
	else if([passPhraseSource isEqualToString:kPassPhraseSourceKey_keychain])
	{
		[dict removeObjectForKey:kPassPhraseSourceKey_keyboard];
	}

	[dict setObject:newKeyBlob forKey:passPhraseSource];

	NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:NULL];

	success = [data writeToURL:self.storageBlobURL
			 options:NSDataWritingAtomic
			   error:&error];

	if (outError) *outError = error;

	return success;
}


- (BOOL)unlockStorageBlobWithPassKey:(NSData *)passKey
					passKeyAlgorithm:(Cipher_Algorithm)passKeyAlgorithm
					passPhraseSource:(NSString *)passPhraseSource
							   error:(NSError **)errorOut
{
	BOOL                success = FALSE;
	S4Err               err = kS4Err_NoErr;
	NSError*            error = NULL;

	S4KeyContextRef     sKey = kInvalidS4KeyContextRef;
	S4KeyContextRef     unlockingKey = kInvalidS4KeyContextRef;
	S4KeyContextRef     passKeyCtx =  kInvalidS4KeyContextRef;
	size_t              cipherSizeInBits = 0;
	size_t              cipherSizeInBytes = 0;

	err = Cipher_GetKeySize(passKeyAlgorithm, &cipherSizeInBits); CKERR;
	cipherSizeInBytes = cipherSizeInBits / 8;
	ASSERTERR(passKey.length == cipherSizeInBytes, kS4Err_BadParams);

	err = S4Key_NewSymmetric(passKeyAlgorithm, passKey.bytes, &passKeyCtx); CKERR;

	if ([self getKeyForPassPhraseSource:passPhraseSource  keyContext:&unlockingKey error:&error ])
 	{
 		err = S4Key_DecryptFromS4Key(unlockingKey, passKeyCtx,&sKey ); CKERR;

		// sanitize the storage key
		S4Key_RemoveProperty(sKey, kPassPhraseHintKey.UTF8String);

		if (!sKeyCtx) {
			sKeyCtx = sKey;
		}

		success = YES;
 	}

done:

	if (S4KeyContextRefIsValid(unlockingKey))
		S4Key_Free(unlockingKey);

	if (passKeyCtx)
		S4Key_Free(passKeyCtx);

	if (IsS4Err(err))
		error = [NSError errorWithS4Error:err];

	if (errorOut) *errorOut = error;
	return success;
}


- (BOOL)getKeyForPassPhraseSource:(NSString *)passPhraseSource
					   keyContext:(S4KeyContextRef *)keyContextOut
							error:(NSError **)errorOut
{
	BOOL                success = FALSE;
	NSError*            error = NULL;
	S4Err               err = kS4Err_NoErr;

	S4KeyContextRef     *pKeyArray = NULL;
	size_t              pKeyCount = 0;

	// test for keychain
	NSDictionary* dictIn = [self keysDictWithError:NULL];
	NSDictionary* p2kDict = [dictIn objectForKey:passPhraseSource];

	if(p2kDict)
	{
		NSData *data = [NSJSONSerialization dataWithJSONObject:p2kDict
													   options:0
														 error:&error]; CKERROR;
		if(data)
		{
			// attempt to deserialize this
			err = S4Key_DeserializeKeys((uint8_t *)data.bytes, data.length,
										&pKeyCount, &pKeyArray); CKERR;

			if (pKeyArray && pKeyCount == 1)
			{
				err = S4Key_Copy(pKeyArray[0], keyContextOut); CKERR;
				success = YES;
			}
		}
	}

done:

	if (pKeyArray)
	{
		for (int i = 0 ; i < pKeyCount; i++)
		{
			S4Key_Free(pKeyArray[i]);
		}

		XFREE(pKeyArray);
		pKeyArray = NULL;
		pKeyCount = 0;
	}

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (errorOut) *errorOut = error;
	return success;
}



- (void)deleteAllPasscodeData
{
	[self deleteKeychainPassphraseWithError:NULL];
 	[self deleteBioPassphraseWithError:NULL];

	if (S4KeyContextRefIsValid(sKeyCtx)) {
		S4Key_Free(sKeyCtx);
	}

	sKeyCtx     = NULL;

	NSURL *storageBlobURL = [self storageBlobURL];
	[[NSFileManager defaultManager] removeItemAtURL:storageBlobURL error:NULL];
}

//
//	// create fake key
//	uint8_t*  key = XMALLOC(32);
//
//	NSData* keyData =  [[NSData alloc] initWithBytesNoCopy:key
//													length:32
//											   deallocator:^(void * _Nonnull bytes,
//															 NSUInteger length) {
//
//												   ZERO(bytes, length);
//												   XFREE(bytes);
//											   }];
//
//	if(keyFoundBlockIn)
//		(keyFoundBlockIn)(keyData,NULL);
//}
//
//- (NSData *)retrieveKeyFromKeychain
//{
//	uint8_t*  key = XMALLOC(32);
//
//	NSData* keyData =  [[NSData alloc] initWithBytesNoCopy:key
//													length:32
//											   deallocator:^(void * _Nonnull bytes,
//															 NSUInteger length) {
//
//												   ZERO(bytes, length);
//												   XFREE(bytes);
//											   }];
//
//	return keyData;
//}

@end
