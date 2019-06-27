/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The DatabaseKeyManager class provides tools for securely storing & retrieving the database key.
 *
 * That is, the local sqlite database (stored on the user's device) is encrypted using SQLCipher.
 * In order to start using the framework, this database file must be unlocked first.
 *
 * @note Encryption of the local database is required in order to protect the user's data.
 *       The database stores all the file encryption keys, and other sensitive content.
 *       And it's quite easy for the database file to get leaked (for example: backed up to iCloud).
 *
 * The DatabaseKeyManager provides flexibility for your app, while maintaining security.
 * For example, if you want to add password protection or TouchID to your app, this class can help.
 * Furthermore, if you use this class to assist in adding features like password protection to your app,
 * the protection that you offer will be backed by solid crypto.
 *
 * Here's how it works:
 * - A random key is generated for encrypting the database file.
 * - This key is then encrypted using PBKDF2 and then stored to disk.
 * - The key to unlock the PBKDF2 is then stored. For example, it could be stored in the OS keychain.
 *
 * < Why the heck do we do ^this^ ? >
 * < Add explanation in terms of how this protects the user. >
 *
 * 1. Keychain
 *    The easiest option is simply to store the database key in the OS keychain.
 *    This is the option that...
 *
 * Vinnie - fill this out.
 * The style of documentation should assume:
 * - the reader is unfamiliar with crypto
 * - the reader's reaction after reading the docs should be, "this is really cool, and easy to use!"
 * - in other words, the focus should be less on what the code does (although that's obviously required),
 *   and more on how it helps the developer make his/her app really really cool.
 * - think 1/3 high level overview, 1/3 documentation, and 1/3 subtle marketing
 */
@interface ZDCDatabaseKeyManager : NSObject

@property (atomic, readonly) BOOL isConfigured;
 
@property (atomic, readonly) BOOL usesKeychainKey;
@property (atomic, readonly) BOOL usesPassphrase;
@property (atomic, readonly) BOOL usesBioMetrics;
@property (atomic, readonly) BOOL canUseBioMetrics;
 

// initial setup storageKey and create temporary keychain password.
-(BOOL) configureStorageKey:(Cipher_Algorithm)algorithm
					  error:(NSError *_Nullable *_Nullable) outError;

// keychain
-(BOOL) createKeychainEntryKeyWithError:(NSError *_Nullable *_Nullable) outError;

-(nullable NSData*) unlockUsingKeychainKeyWithError:(NSError *_Nullable *_Nullable) outError;

// passphrase
-(BOOL) createPassPhraseKey:(NSString*)passPhrase
			 passPhraseHint:(NSString* _Nullable)passPhraseHint
					  error:(NSError *_Nullable *_Nullable) outError;

-(nullable NSData*) unlockUsingPassphaseKey:(NSString*)passPhrase
						  error:(NSError**)outError;

-(nullable NSString*) hintStringForPassphraseKey;

-(BOOL) removePassphraseKeyWithError:(NSError *_Nullable *_Nullable) outError;

// biometric passphrase
-(BOOL) createBiometricKeyWithError:(NSError *_Nullable *_Nullable) outError;

-(nullable NSData*) unlockUsingBiometricKeyWithPrompt:(NSString* _Nullable)prompt
												 error:(NSError *_Nullable *_Nullable) outError;

-(BOOL) removeBioMetricKeyWithError:(NSError *_Nullable *_Nullable) outError;

// dangerous API, only call it when judiciously
-(void) deleteAllPasscodeData;

@end

NS_ASSUME_NONNULL_END
