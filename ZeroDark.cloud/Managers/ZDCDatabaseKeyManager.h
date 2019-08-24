/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This class provides optional tools for securely storing & retrieving the key
 * used to encrypt the sqlite database file.
 *
 * The local sqlite database (stored on the user's device) is encrypted using SQLCipher.
 * In order to start using the framework, this database file must first be unlocked.
 *
 * @note Encryption of the local database is required in order to protect the user's data.
 *       The database stores all the node encryption keys, and other sensitive content.
 *       And it's rather common for this database file to get backed up to various locations,
 *       such as iCloud.
 *
 * The DatabaseKeyManager provides flexibility for your app.
 * For example, you may want to add password protection or TouchID to your app.
 * This class can help, while maintaining strong security backed by solid crypto.
 *
 * Here's how it works:
 * - A random key is generated for encrypting the database file.
 * - This key is then wrapped (encrypted) using PBKDF2, and the resulting PBKDF2 file is stored to disk.
 * - The key to unlock the PBKDF2 is stored separately, and is configurable to fit the needs of your application.
 *
 * By protecting access to this key, you protect access to the database, and thus all user data stored locally.
 * This even includes files stored via the DiskManager (which are also encrypted with keys stored in the database).
 *
 * @note Use of this class is optional. If your app already has a custom solution for encrypting & storing
 *       the database key, then you're welcome to use it.
 *
 * This class gives your app 3 different options for storing the database key:
 *
 * 1. Keychain
 *    The easiest option is simply to store the database key in the OS keychain.
 *
 * 2. Passphrase
 *    You can allow users to protect the data with a passphrase.
 *
 * 3. Biometric
 *    You can allow users to use the biometrics available on their device.
 *
 * Long story short: This class provides the security options you'd expect, backed by the crypto you'd hope for.
 *
 * Additional documentation can be found in the docs:
 * https://zerodarkcloud.readthedocs.io/en/latest/client/databaseKeyManager/
 */
@interface ZDCDatabaseKeyManager : NSObject

/**
 * Returns NO/false if the database hasn't been setup yet.
 * This should only be the case if the framework is being run for the first time.
 * (e.g. first run after app install / re-install)
 *
 * In particular, this method checks to see if the a PBKDF2 file exists.
 */
@property (atomic, readonly) BOOL isConfigured;

/**
 * Returns YES/true if the PBKDF2 file exists, and can be decrypted using a key stored in the OS keychain.
 *
 * @note The PBKDF2 file contains the key used to encrypt the database.
 */
@property (atomic, readonly) BOOL usesKeychainKey;

/**
 * Returns YES/true if the PBKDF2 file exists, and can be decrypted using a passphrase.
 *
 * @note The PBKDF2 file contains the key used to encrypt the database.
 */
@property (atomic, readonly) BOOL usesPassphrase;

/**
 * Returns YES/true if the PBKDF2 file exists, and can be decrypted using biometrics.
 *
 * @note The PBKDF2 file contains the key used to encrypt the database.
 */
@property (atomic, readonly) BOOL usesBioMetrics;

/**
 * Returns YES/true if biometrics are available on the current device.
 */
@property (atomic, readonly) BOOL canUseBioMetrics;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Keychain
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates an entry in the PBKDF2 file, and a corresponding entry in the OS keychain.
 *
 * In other words, the OS keychain entry can be used to unlock the PBKDF2 file.
 *
 * @note Locked inside the PBKDF2 file is the databsae encryption key.
 */
- (BOOL)createKeychainEntry:(NSError *_Nullable *_Nullable)outError;

/**
 * Attempts to unlock the PBKDF2 file using the passcode stored in the keychain.
 *
 * @note Locked inside the PBKDF2 file is the databsae encryption key.
 *
 * On success, the database encryption key is returned.
 * You can then use the returned key to unlock the database via `-[ZeroDarkCloud unlockOrCreateDatabase:]`.
 *
 * If the system isn't configured yet (isConfigured == NO),
 * this method automatically configures the system using the default configuration.
 * That is, it automatically creates a PBKDF2 file, backed by a keychain entry.
 * Meaning this method will "do the right thing", and return a non-nil result.
 */
- (nullable NSData *)unlockUsingKeychain:(NSError *_Nullable *_Nullable)outError;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Passphrase
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates an entry in the PBKDF2 file using the given passphrase.
 *
 * If there's an existing keychain entry, that keychain entry will be deleted.
 * Because it does NOT make sense to have both a keychain entry and password protection.
 *
 * If there's an existing biometric entry, it is NOT deleted.
 * Because it makes perfect sense to have both a biometric entry and password protection.
 */
- (BOOL)createPassphraseEntry:(NSString *)passphrase
                     withHint:(NSString *_Nullable)hint
                        error:(NSError *_Nullable *_Nullable)outError;

/**
 * Attempts to unlock the PBKDF2 file using the given passphrase.
 *
 * @note Locked inside the PBKDF2 file is the databsae encryption key.
 *
 * On success, the database encryption key is returned.
 * You can then use the returned key to unlock the database via `-[ZeroDarkCloud unlockOrCreateDatabase:]`.
 *
 * @param passphrase
 *   A passphrase gathered from the user.
 *
 * @param outError
 *   If an error occurs, this value will be set with information about the error.
 */
- (nullable NSData *)unlockUsingPassphase:(NSString *)passphrase
                                    error:(NSError **)outError;

/**
 * Returns the passphrase hint.
 * The hint was set when the passphrase was created.
 */
- (nullable NSString *)passphraseHint;

/**
 * Removes the passphrase entry from the PBKDF2 file.
 *
 * If there aren't any biometric entries remaining in the PBKDF2 file,
 * this method will automatically create a keychain entry. This ensures you're not accidentally locked out.
 */
- (BOOL)removePassphraseEntry:(NSError *_Nullable *_Nullable)outError;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Biometric
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates an entry in the PBKDF2 file that can be unlocked using biometric techniques provided by the device.
 */
- (BOOL)createBiometricEntry:(NSError *_Nullable *_Nullable)outError;

/**
 * Attempts to unlock the PBKDF2 file using biometric techniques provided by the device.
 *
 * @note Locked inside the PBKDF2 file is the databsae encryption key.
 *
 * On success, the database encryption key is returned.
 * You can then use the returned key to unlock the database via `-[ZeroDarkCloud unlockOrCreateDatabase:]`.
 */
- (nullable NSData *)unlockUsingBiometricWithPrompt:(NSString *_Nullable)prompt
                                              error:(NSError *_Nullable *_Nullable)outError;

/**
 * Removes the passphrase entry from the PBKDF2 file.
 *
 * If there aren't any passphrase entries remaining in the PBKDF2 file,
 * this method will automatically create a keychain entry. This ensures you're not accidentally locked out.
 */
- (BOOL)removeBiometricEntry:(NSError *_Nullable *_Nullable)outError;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Danger
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * DANGER!!! This method deletes the PBKDF2 file.
 * You could easily be locked out of the database if you don't understand what you're doing.
 */
- (void)deleteAllPasscodeData;

@end

NS_ASSUME_NONNULL_END
