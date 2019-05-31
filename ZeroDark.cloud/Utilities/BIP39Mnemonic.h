/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSInteger, Mnemonic_Algorithm) {
	Mnemonic_Storm4 ,
	Mnemonic_ZDC ,
	Mnemonic_Invalid = NSIntegerMax
};


/**
 * Bitcoin Improvement Protocol (BIP) #39
 * "Mnemonic code for generating deterministic keys"
 *
 * https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
 *
 * This class implements mnemonic encoding/decoding according to BIP-39.
 */
@interface BIP39Mnemonic : NSObject

/**
* Return a the closest language identifier for given localeIdentifier
* the language identifier is passed to APIs below that require a language identifier
*
* @param localeIdentifier
*   optional locale for the wordlist - for null will default to prefered locale
*
* @return A string matching the closest language identifier for the locale.
*/
+ (nullable NSString *)languageIDForlocaleIdentifier:(NSString *_Nullable)localeIdentifier;

/**
 * Return an array of languageIDs supported
 *
 * @return An array of string's of the languageIDs supported
 */
+ (nullable NSArray<NSString*> *)availableLanguages;

/**
 * Return a the number of mnemonic words needed for given bit size
 *
 * @param bitSize
 *  number of bits to encode/decode
 *
 * @param mnemonicountOut
 *   if bitsSize is valid, return the number of words needed
 *
 * @return TRUE if bitSize is valid 128/160/192/224/256
 */
+ (BOOL)mnemonicCountForBits:(NSUInteger)bitSize
               mnemonicCount:(NSUInteger*)mnemonicountOut;

/**
 * Return a list of acceptable mnemonic words for a given Locale
 *
 * @param languageID
 *   optional languageID for the wordlist - for null will default to prefered locale
 *
 * @param errorOut
 *   If an error occurs, this parameter will indicate what the problem was.
 *
 * @return An array of 2048 unique words in the word list
 */
+(nullable NSArray<NSString*> *)wordListForLanguageID:(NSString *_Nullable)languageID
                                                error:(NSError *_Nullable *_Nullable)errorOut;


/**
 * Return a matching mnemonic word  for a given string - expend abbreviated to proper mnemonic
 *
 * @param languageID
 *   optional languageID for the wordlist - for null will default to prefered locale

 * @param word
 *   word to use to search wordlist
 *
 * @param errorOut
 *   If an error occurs, this parameter will indicate what the problem was.
 *
 * @return A string with matching mnemonic
 */
+ (nullable NSString *)matchingMnemonicForString:(NSString*)word
						   languageID:(NSString* _Nullable)languageID
								error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Converts from a mnemonic to its data.
 *
 * @param mnemonic
 *   The mnemonic output from a previous encoding (using the same language file).
 *
 * @param languageID
 *   optional languageID for the wordlist - for null will default to prefered locale
 *
 * @param errorOut
 *   If an error occurs, this parameter will indicate what the problem was.
 *
 * @return The key which the mnemonic was encoding.
 */
+ (nullable NSData *)dataFromMnemonic:(NSArray<NSString*> *)mnemonic
                           languageID:(NSString* _Nullable)languageID
                                error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Converts from data  to a mnemonic (word list).
 *
 * @param keyData
 *   The data to convert to a mnemonic.
 *   The data size must be a multiple of 32 bits, with a total length between 128-256 bits (inclusive).
 *
 * @param languageID
 *   optional languageID for the wordlist - for null will default to prefered locale
 *
 * @param errorOut
 *   If an error occurs, this parameter will indicate what the problem was.
 *
 * @return The mnemonic, represented as an array of words from the language file.
 */
+ (nullable NSArray<NSString*> *)mnemonicFromData:(NSData *)keyData
                                       languageID:(NSString *_Nullable)languageID
                                            error:(NSError *_Nullable *_Nullable)errorOut;

 /**
 * Converts from a key  to a mnemonic (word list).
 *
 * @param keyData
 *   The key to convert to a mnemonic.
 *   The key size must be a multiple of 32 bits, with a total length between 128-256 bits (inclusive).
 *
 * @param passphrase
 *   The mnemonic may be optionally protected with a passphrase.
 *   If a passphrase is not present, an empty string "" is used instead.
 *
 * @param languageID
 *   optional languageID for the wordlist - for null will default to prefered locale
 *
 * @param errorOut
 *   If an error occurs, this parameter will indicate what the problem was.
 *
 * @return The mnemonic, represented as an array of words from the language file.
 */
+ (nullable NSArray<NSString*> *)mnemonicFromKey:(NSData *)keyData
                                       passphrase:(nullable NSString *)passphrase
									  languageID:(NSString* _Nullable)languageID
									   algorithm:(Mnemonic_Algorithm)algorithm
                                            error:(NSError *_Nullable *_Nullable)errorOut;

/**
 * Converts from a mnemonic back to a key.
 * 
 * @param mnemonic
 *   The mnemonic output from a previous encoding (using the same passphrase & language file).
 *
 * @param passphrase
 *   If the mnemonic was protected with a passphrase, that should be passed here.
 *
 * @param languageID
 *   optional languageID for the wordlist - for null will default to prefered locale
 *
 * @param errorOut
 *   If an error occurs, this parameter will indicate what the problem was.
 *
 * @return The key which the mnemonic was encoding.
 */
+ (nullable NSData *)keyFromMnemonic:(NSArray<NSString*> *)mnemonic
                           passphrase:(nullable NSString *)passphrase
						  languageID:(NSString* _Nullable)languageID
						   algorithm:(Mnemonic_Algorithm)algorithm
                                error:(NSError *_Nullable *_Nullable)errorOut;

@end

NS_ASSUME_NONNULL_END
