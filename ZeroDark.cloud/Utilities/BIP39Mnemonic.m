/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "BIP39Mnemonic.h"

#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import <S4Crypto/S4Crypto.h>
#import "NSError+S4.h"
#import "NSString+ZeroDark.h"

@implementation NSString (BIP39Encoder)

+ (NSString *)binaryStringRepresentationOfInt:(long)value numberOfDigits:(unsigned int)length
{
    NSMutableString *string = [NSMutableString new];
    
    for(int i = 0; i < length; i ++) {
        NSString *part = [NSString stringWithFormat:@"%i", value & (1 << i) ? 1 : 0];
        [string insertString:part atIndex:0];
    }
    
    return string;
}

//
//- (NSString *)sanitizeStringWithLocaleIdentifier:(NSString*)localeIdentifier
//{
//	localeIdentifier = [localeIdentifier stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
//
//	NSLocale *usLocale = [[NSLocale alloc] initWithLocaleIdentifier:localeIdentifier];
//
//	// Replace accents, umlauts etc with equivalent letter i.e 'é' becomes 'e'.
//	// Always use en_GB (or a locale without the characters you wish to strip) as locale,
//	// no matter which language we're taking as input.
//	NSString *processedString = [self stringByFoldingWithOptions: NSDiacriticInsensitiveSearch locale: usLocale];
//
//	// remove non-letters
//	processedString = [[processedString componentsSeparatedByCharactersInSet:[[NSCharacterSet letterCharacterSet] invertedSet]] componentsJoinedByString:@""];
//
//	// trim whitespace
//	processedString = [processedString stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
//	return processedString;
//}

@end


@implementation BIP39Mnemonic

+(nullable NSString*)languageIDForlocaleIdentifier:(NSString* _Nullable)localeIdentifier;
{
	NSString* languageID = nil;

	NSArray* available = [self availableLanguages];

	if(!localeIdentifier)
		localeIdentifier =  NSLocale.currentLocale.localeIdentifier;

	localeIdentifier = [localeIdentifier stringByReplacingOccurrencesOfString:@"-" withString:@"_"];

	if([available containsObject:localeIdentifier])
	{
		languageID = localeIdentifier;
	}
	else
	{
		NSArray* comp = [localeIdentifier componentsSeparatedByString:@"_"];
		NSString* languageCode = comp[0];

		for(NSString* lang in available)
		{
			if([lang hasPrefix:languageCode])
			{
				languageID = lang;
				break;
			}
		}
	}

	return languageID;
}

+(nullable NSArray<NSString*> *) availableLanguages
{
	NSMutableArray* langs = NSMutableArray.array;

	NSBundle *bundle = [NSBundle bundleForClass:[ZeroDarkCloud class]];
	NSArray* contents = [bundle URLsForResourcesWithExtension:@"bip39" subdirectory:@""];

  	for (NSURL *url in contents) {

		NSString* lang = url.lastPathComponent.stringByDeletingPathExtension;
		[langs addObject:lang];
	}

	return langs;
}

+(NSURL*) langFileURLforLanguageID:(NSString* _Nullable)languageID
						 error:(NSError *_Nullable *_Nullable)errorOut

{
	NSURL* url = nil;
	NSError * error = nil;

	NSString* identifier = languageID;
	NSBundle *bundle = [NSBundle bundleForClass:[ZeroDarkCloud class]];

	if(!identifier)
	{
		identifier = [self languageIDForlocaleIdentifier:[NSLocale currentLocale].localeIdentifier];
	}

	NSString* fileName= [NSString stringWithFormat:@"%@", identifier];
	NSURL *langFileURL  = [bundle URLForResource:fileName withExtension:@"bip39"];

	if([langFileURL checkResourceIsReachableAndReturnError:&error])
	{
		url = langFileURL;
	}
	
	if (errorOut) *errorOut = error;

	return url;
}

+(nullable NSArray<NSString*> *) wordListForLanguageID:(NSString* _Nullable)languageID
											 error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError * error = nil;

	NSURL* languageFileURL = nil;
	NSString* fileText = nil;
	NSArray<NSString*> *wordTable = nil;

	languageFileURL = [self langFileURLforLanguageID:languageID error:&error];
	if (error) {
		goto done;
	}

	fileText = [NSString stringWithContentsOfURL:languageFileURL encoding:NSUTF8StringEncoding error:&error];
	if (error) {
		goto done;
	}
	// remove any extra blank lines
	fileText = [fileText stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];


	wordTable = [fileText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	if (wordTable.count != 2048) {
		NSString *msg = @"Invalid language file - must contain at least 2048 words";
		error = [self errorWithDescription:msg];
		goto done;
	}

done:

	if (errorOut) *errorOut = error;

	return wordTable;
}

+ (nullable NSString *)matchingMnemonicForString:(NSString*)word
									  languageID:(NSString* _Nullable)languageID
										   error:(NSError *_Nullable *_Nullable)errorOut
{
	NSLocale* matchingLocale = [NSLocale localeWithLocaleIdentifier:languageID];
	NSArray<NSString*> *wordTable = nil;

	__block NSString* mnemonic = NULL;
	NSError * error = nil;
 
	if(!matchingLocale)
	{
		NSString *msg = @"Invalid languageID";
		error = [self errorWithDescription:msg];
		goto done;
	}

	wordTable = [self wordListForLanguageID:languageID error:&error];
	if (error) {
		goto done;
	}

	if([wordTable containsObject:word])
		mnemonic = word;
	else if(word.length > 3)
	{
		NSString *normalized = [word stringByFoldingWithOptions: NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
														 locale: matchingLocale];


		[wordTable enumerateObjectsUsingBlock:^(NSString * entry, NSUInteger idx, BOOL * _Nonnull stop) {

			NSString* test  = [entry stringByFoldingWithOptions:
							   (NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
														 locale: matchingLocale];

			if([test hasPrefix:normalized])
			{
				mnemonic = entry;
				*stop = YES;
			}
		}];
	}

done:

	if (errorOut) *errorOut = error;
	return mnemonic;
}

+ (NSDictionary*)bipPrefDict
{
	static NSDictionary* jsonDict = nil;

	if(!jsonDict)
	{
		NSString *jsonPath = [[ZeroDarkCloud frameworkBundle] pathForResource:@"bip39" ofType:@"json"];
		NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
		jsonDict = [NSJSONSerialization JSONObjectWithData:(NSData *)jsonData options:0 error:nil];
	}
	return jsonDict;
}

+ (BOOL) canShortenWordForlanguageID:(NSString* _Nullable)languageID
{
	BOOL canAbbreviate = YES;

	NSDictionary* jsonDict = [self bipPrefDict];

	NSArray* fullwordsLanguages = [jsonDict objectForKey:@"fullwords"];

	if([fullwordsLanguages containsObject: languageID])
		canAbbreviate = NO;

	return canAbbreviate;
}

+ (BOOL) mnemonicCountForBits:(NSUInteger)bitSize
				mnemonicCount:(NSUInteger*)mnemonicCountOut
{
 	BOOL valid = YES;
	NSUInteger wordsNeeded = 0;

	// From BIP32:
	//
	// CS = ENT / 32
	// MS = (ENT + CS) / 11
	//
	// |  ENT  | CS | ENT+CS |  MS  |
	// +-------+----+--------+------+
	// |  128  |  4 |   132  |  12  |
	// |  160  |  5 |   165  |  15  |
	// |  192  |  6 |   198  |  18  |
	// |  224  |  7 |   231  |  21  |
	// |  256  |  8 |   264  |  24  |

	switch (bitSize) {
		case 128:
			wordsNeeded = 12;
			break;

		case 160:
			wordsNeeded = 15;
			break;

		case 192:
			wordsNeeded = 18;
			break;

		case 224:
			wordsNeeded = 21;
			break;

		case 256:
			wordsNeeded = 24;
			break;

 	 	default:
			valid = NO;
			break;
	}

	if(valid && mnemonicCountOut !=nil)
		*mnemonicCountOut = wordsNeeded;

	return valid;
}


+ (nullable NSData *)dataFromMnemonic:(NSArray<NSString*> *)mnemonic
						   languageID:(NSString* _Nullable)languageID
								error:(NSError *_Nullable *_Nullable)errorOut
{
	NSData* result = nil;
	NSError * error = nil;
	S4Err     err = kS4Err_NoErr;

	NSLocale* matchingLocale = [NSLocale localeWithLocaleIdentifier:languageID];

	uint8_t dataBytes[33] = {0};  // key + checksum; 33 bytes == 264 bits
	uint8_t hashBuf[32] = {0};

	NSArray<NSString*> *wordTable = nil;
	NSMutableString *bitString = nil;
	NSString *checksumBits_calc = nil;
	NSString *checksumBits_input = nil;


	if(!matchingLocale)
	{
		NSString *msg = @"Invalid languageID";
		error = [self errorWithDescription:msg];
		goto done;
	}

	// From BIP32:
	//
	// CS = ENT / 32
	// MS = (ENT + CS) / 11
	//
	// |  ENT  | CS | ENT+CS |  MS  |
	// +-------+----+--------+------+
	// |  128  |  4 |   132  |  12  |
	// |  160  |  5 |   165  |  15  |
	// |  192  |  6 |   198  |  18  |
	// |  224  |  7 |   231  |  21  |
	// |  256  |  8 |   264  |  24  |

	NSUInteger mnemonicCount = mnemonic.count;
	
	if (mnemonicCount != 12 &&
		mnemonicCount != 15 &&
		mnemonicCount != 18 &&
		mnemonicCount != 21 &&
		mnemonicCount != 24)
	{
		NSString *msg = @"Invalid mnemonic - contains an invalid number of words";
		error = [self errorWithDescription:msg];
		goto done;
	}

	wordTable = [self wordListForLanguageID:languageID error:&error];
	if (error) {
		goto done;
	}

	bitString = [NSMutableString stringWithCapacity:264];

	for (NSString *word in mnemonic)
	{
		NSString *normalized = [word stringByFoldingWithOptions: NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
														 locale: matchingLocale];

		NSUInteger index = [wordTable indexOfObjectPassingTest:
							^BOOL(NSString *entry, NSUInteger idx, BOOL *stop)
							{
								NSString* test  = [entry stringByFoldingWithOptions:
												   (NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
																			 locale: matchingLocale];

								if([test localizedCaseInsensitiveCompare:normalized] == NSOrderedSame)
								{
									*stop = YES;
									return YES;
								}

								return NO;
							}];

		// if we didnt find an index then we have bad mnemonic word
		ASSERTERR(index != NSNotFound, kS4Err_BadParams);

		NSString *bits = [NSString binaryStringRepresentationOfInt:index numberOfDigits:11];
		[bitString appendString:bits];
	}

	// From BIP32:
	//
	// CS = ENT / 32
	// MS = (ENT + CS) / 11
	//
	// |  ENT  | CS | ENT+CS |  MS  |
	// +-------+----+--------+------+
	// |  128  |  4 |   132  |  12  |
	// |  160  |  5 |   165  |  15  |
	// |  192  |  6 |   198  |  18  |
	// |  224  |  7 |   231  |  21  |
	// |  256  |  8 |   264  |  24  |

	NSUInteger ent = 0;
	NSUInteger cs = 0;
	switch (mnemonicCount)
	{
		case 12 : ent = 128; cs = 4; break;
		case 15 : ent = 160; cs = 5; break;
		case 18 : ent = 192; cs = 6; break;
		case 21 : ent = 224; cs = 7; break;
		case 24 : ent = 256; cs = 8; break;
	}

	ASSERTERR(bitString.length == (ent + cs), kS4Err_BadParams);
	// fill encrypted_key with decoded bytes from mnemonicArray offset - include checksum byte

	for (int index = 0; index < ((ent + cs)/ 8); index++)
	{
		NSString *bits = [bitString substringWithRange:NSMakeRange(index*8,8)];
		dataBytes[index] = strtol(bits.UTF8String, NULL, 2);
	}

	// caclulate checksum
	err = HASH_DO(
				  kHASH_Algorithm_SHA256,
				  dataBytes, ent/8,
				  hashBuf, sizeof(hashBuf));
	CKERR;

	// check for proper checksum
	checksumBits_calc = [self bitArrayFromData:[NSData dataWithBytesNoCopy:hashBuf
																	length:sizeof(hashBuf)
															  freeWhenDone:NO]];
	checksumBits_calc = [checksumBits_calc substringToIndex:cs];
	checksumBits_input = [bitString substringFromIndex:ent];

	if (![checksumBits_calc isEqualToString:checksumBits_input])
	{
		err = kS4Err_BadIntegrity;
	}
	else
	{
		result = [[NSData alloc] initWithBytes:dataBytes length:ent/8];
	}


done:
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (errorOut) *errorOut = error;
	return result;

}

+ (nullable NSArray<NSString*> *)mnemonicFromData:(NSData *)data
									   languageID:(NSString* _Nullable)languageID
											error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError * error = nil;
	S4Err     err = kS4Err_NoErr;
	NSMutableArray *words = nil;
	NSArray<NSString*> *wordTable = nil;
	uint8_t hashBuf[32] = {0};

	if ((data.length % 4) != 0)
	{
		NSString *msg = @"The keyData length must be a multiple of 32 bits";
		error = [self errorWithDescription:msg];
		goto done;
	}
	if (data.length < (128 / 8) ||
		data.length > (256 / 8) )
	{
		NSString *msg = @"The keyData length must be between 128-256 bits (inclusive)";
		error = [self errorWithDescription:msg];
		goto done;
	}

	wordTable = [self wordListForLanguageID:languageID error:&error];
	if (error) {
		goto done;
	}

	// caclulate checksum
	err = HASH_DO(
				  kHASH_Algorithm_SHA256,
				  data.bytes, (int)data.length,
				  hashBuf, sizeof(hashBuf));
	CKERR;

 	{ // Scoping
		words = [NSMutableArray arrayWithCapacity:24];

		// Convert encypted key and checksum to bit array
		NSString *bitString = [self bitArrayFromData:data];

		NSString *checksumBits = [self bitArrayFromData:[NSData dataWithBytesNoCopy:hashBuf
																		length:sizeof(hashBuf)
																  freeWhenDone:NO]];

		// Append the checksum bits to the keyData
		NSRange checksumRange = NSMakeRange(0, bitString.length / 32);

		bitString = [bitString stringByAppendingString:[checksumBits substringWithRange:checksumRange]];

		for (int i = 0; i < (int)bitString.length / 11; i++)
		{
			NSString *bits = [bitString substringWithRange:NSMakeRange(i * 11, 11)];
			NSUInteger wordNumber = strtol(bits.UTF8String, NULL, 2);

			[words addObject:wordTable[wordNumber]];
		}
	}


done:

 	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (errorOut) *errorOut = error;
	return words;

}


+ (nullable NSArray<NSString*> *)mnemonicFromKey:(NSData *)keyData
									  passphrase:(nullable NSString *)passphrase
									  languageID:(NSString* _Nullable)languageID
									   algorithm:(Mnemonic_Algorithm)algorithm
										   error:(NSError *_Nullable *_Nullable)errorOut

{
	NSArray<NSString*> * result = nil;
	NSError * error = nil;

	
	switch (algorithm) {
		case Mnemonic_Storm4:
			result = [self storm4MnemonicFromKey:keyData
									  passphrase:passphrase
								 languageID:languageID
										   error:&error];
			break;

		case Mnemonic_ZDC:
			result = [self zdcMnemonicFromKey:keyData
									  passphrase:passphrase
								 languageID:languageID
										   error:&error];
			break;

		default:
			error = [self errorWithDescription:@"invalid algorithm"];
 		break;
	}

	if (errorOut) *errorOut = error;

	return result;
}

+ (nullable NSArray<NSString*> *)zdcMnemonicFromKey:(NSData *)keyData
											passphrase:(nullable NSString *)passphrase
										 languageID:(NSString* _Nullable)languageID
												 error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError * error = nil;
	NSMutableArray *words = nil;


	error = [self errorWithDescription:@"lazy programmer"];

	if (errorOut) *errorOut = error;
	return words;
}

/**
 * See header file for description.
 */
+ (nullable NSArray<NSString*> *)storm4MnemonicFromKey:(NSData *)keyData
											passphrase:(nullable NSString *)passphrase
											languageID:(NSString* _Nullable)languageID
												 error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError * error = nil;
	S4Err     err = kS4Err_NoErr;
	uint8_t   unlocking_key[32] = {0};
	
	NSArray<NSString*> *wordTable = nil;

	NSData *saltData = nil;
	NSMutableData *encrypted_key = nil;
	NSMutableData *hash = nil;
	NSMutableArray *words = nil;
	
	if ((keyData.length % 4) != 0)
	{
		NSString *msg = @"The keyData length must be a multiple of 32 bits";
		error = [self errorWithDescription:msg];
		goto done;
	}
	if (keyData.length < (128 / 8) ||
	    keyData.length > (256 / 8) )
	{
		NSString *msg = @"The keyData length must be between 128-256 bits (inclusive)";
		error = [self errorWithDescription:msg];
		goto done;
	}
	
	if (passphrase == nil) {
		passphrase = @"";
	}
	passphrase = [passphrase decomposedStringWithCompatibilityMapping]; // Normalization Form KD

	wordTable = [self wordListForLanguageID:languageID error:&error];
	if (error) {
		goto done;
	}

	// Encrypt keyData to passphrase
	saltData = [[@"mnemonic" stringByAppendingString:passphrase] dataUsingEncoding:NSUTF8StringEncoding];

	err = PASS_TO_KEY(                                                // Create PBKDF2
	  (uint8_t *)passphrase.UTF8String, passphrase.UTF8LengthInBytes, // passphrase
	  (uint8_t *)saltData.bytes, saltData.length,                     // salt
	  2048,                                                           // PBKDF2 rounds
	  unlocking_key, sizeof(unlocking_key));                          // output
	CKERR;
	
	encrypted_key = [NSMutableData dataWithLength:32];
	err = ECB_Encrypt(
	  kCipher_Algorithm_AES256,
	  unlocking_key,               // S4 bug - should also be passing unlocking_key length
	  keyData.bytes, keyData.length,
	  encrypted_key.mutableBytes, keyData.length);
	CKERR;

	// Calculate the sha256 hash to use with a checksum
	
	hash = [NSMutableData dataWithLength:32];
	err = HASH_DO(
	  kHASH_Algorithm_SHA256,
	  keyData.bytes, keyData.length,
	  hash.mutableBytes, hash.length);
	CKERR;
	
	{ // Scoping
		
		words = [NSMutableArray arrayWithCapacity:24];
		
		// Convert encypted key and checksum to bit array
		NSString *bitString = [self bitArrayFromData:encrypted_key];
		NSString *checksumBits = [self bitArrayFromData:hash];
		
		// Append the checksum bits to the keyData
		NSRange checksumRange = NSMakeRange(0, bitString.length / 32);
		
		bitString = [bitString stringByAppendingString:[checksumBits substringWithRange:checksumRange]];
        
		for (int i = 0; i < (int)bitString.length / 11; i++)
		{
			NSString *bits = [bitString substringWithRange:NSMakeRange(i * 11, 11)];
			NSUInteger wordNumber = strtol(bits.UTF8String, NULL, 2);
			
			[words addObject:wordTable[wordNumber]];
		}
	}
    
done:
    
	ZERO(unlocking_key, sizeof(unlocking_key));
	ZERO(encrypted_key.bytes, encrypted_key.length);
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (errorOut) *errorOut = error;
	return words;
}


+ (nullable NSData *)keyFromMnemonic:(NSArray<NSString*> *)mnemonic
						  passphrase:(nullable NSString *)passphrase
						  languageID:(NSString* _Nullable)languageID
						   algorithm:(Mnemonic_Algorithm)algorithm
							   error:(NSError *_Nullable *_Nullable)errorOut
{
	NSData* result = nil;
	NSError * error = nil;

	switch (algorithm) {
		case Mnemonic_Storm4:
			result = [self storm4KeyFromMnemonic:mnemonic
									  passphrase:passphrase
										  languageID:languageID
										   error:&error];
			break;

		case Mnemonic_ZDC:
			result = [self zdcKeyFromMnemonic:mnemonic
									 passphrase:passphrase
									   languageID:languageID
										  error:&error];
			break;

		default:
			error = [self errorWithDescription:@"invalid algorithm"];
			break;
	}

	if (errorOut) *errorOut = error;

	return result;
}

+ (nullable NSData *)zdcKeyFromMnemonic:(NSArray<NSString*> *)mnemonic
								passphrase:(nullable NSString *)passphrase
							 languageID:(NSString* _Nullable)languageID
									 error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError * error = nil;
	NSData *result = nil;

	error = [self errorWithDescription:@"lazy programmer"];

	if (errorOut) *errorOut = error;
	return result;
	
}

/**
 * See header file for description.
 */
+ (nullable NSData *)storm4KeyFromMnemonic:(NSArray<NSString*> *)mnemonic
                           passphrase:(nullable NSString *)passphrase
								languageID:(NSString* _Nullable)languageID
                                error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError * error = nil;
	S4Err     err = kS4Err_NoErr;

	NSLocale* matchingLocale = [NSLocale localeWithLocaleIdentifier:languageID];

	uint8_t unlocking_key[32] = {0};
	uint8_t decrypted_key[32] = {0};
	uint8_t hashBuf[32] = {0};
	uint8_t encrypted_key[33] = {0};  // key + checksum; 33 bytes == 264 bits
	
	NSArray<NSString*> *wordTable = nil;
	
	NSData *saltData = nil;
	NSMutableString *bitString = nil;
	NSString *checksumBits_calc = nil;
	NSString *checksumBits_input = nil;
	NSData *result = nil;

	if(!matchingLocale)
	{
		NSString *msg = @"Invalid languageID";
		error = [self errorWithDescription:msg];
		goto done;
	}

	if (passphrase == nil) {
		passphrase = @"";
	}
	passphrase = [passphrase decomposedStringWithCompatibilityMapping]; // Normalization Form KD
	
	// From BIP32:
	//
	// CS = ENT / 32
	// MS = (ENT + CS) / 11
	//
	// |  ENT  | CS | ENT+CS |  MS  |
	// +-------+----+--------+------+
	// |  128  |  4 |   132  |  12  |
	// |  160  |  5 |   165  |  15  |
	// |  192  |  6 |   198  |  18  |
	// |  224  |  7 |   231  |  21  |
	// |  256  |  8 |   264  |  24  |
	
	NSUInteger mnemonicCount = mnemonic.count;
	if (mnemonicCount != 12 &&
	    mnemonicCount != 15 &&
	    mnemonicCount != 18 &&
	    mnemonicCount != 21 &&
	    mnemonicCount != 24)
	{
		NSString *msg = @"Invalid mnemonic - contains an invalid number of words";
		error = [self errorWithDescription:msg];
		goto done;
	}

	wordTable = [self wordListForLanguageID:languageID error:&error];
	if (error) {
		goto done;
	}

	saltData = [[@"mnemonic" stringByAppendingString:passphrase] dataUsingEncoding:NSUTF8StringEncoding];
    
	// search the wordlist for a words that matches the first four chars
	bitString = [NSMutableString stringWithCapacity:264];

	for (NSString *word in mnemonic)
	{
		NSString *normalized = [word stringByFoldingWithOptions: NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
														 locale: matchingLocale];

		NSUInteger index = [wordTable indexOfObjectPassingTest:
							^BOOL(NSString *entry, NSUInteger idx, BOOL *stop)
							{
								NSString* test  = [entry stringByFoldingWithOptions:
												   (NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
																			 locale: matchingLocale];

								if([test localizedCaseInsensitiveCompare:normalized] == NSOrderedSame)
								{
									*stop = YES;
									return YES;
								}

								return NO;
							}];

		// if we didnt find an index then we have bad mnemonic word
		ASSERTERR(index != NSNotFound, kS4Err_BadParams);

		NSString *bits = [NSString binaryStringRepresentationOfInt:index numberOfDigits:11];
		[bitString appendString:bits];
	}

/*	for (NSString *word in mnemonic)
	{
		NSString *normalized = [word sanitizeStringWithLocaleIdentifier:languageID];
		NSUInteger nLength = MIN(normalized.length, 4);
		if(canAbbreviate)
		{
			normalized = [normalized substringToIndex:nLength];
		}

		NSUInteger index = [wordTable indexOfObjectPassingTest:
		  ^BOOL(NSString *line, NSUInteger idx, BOOL *stop)
		{
			NSString *line1 = [line sanitizeStringWithLocaleIdentifier:languageID];

			if(canAbbreviate)
			{
				NSUInteger lLength = MIN(line1.length, 4);
				if (nLength == lLength && [line1 hasPrefix:normalized])
				{
					*stop = YES;
					return YES;
				}
			}
			else
			{
				if([line1 isEqualToString:normalized])
				{
					*stop = YES;
					return YES;
				}
			}
			return NO;
		}];
        
		if (index != NSNotFound)
		{
			NSString *bits = [NSString binaryStringRepresentationOfInt:index numberOfDigits:11];

			[bitString appendString:bits];

//			bitString = [bitString stringByAppendingString: bits];
		}
	}
*/

	// From BIP32:
	//
	// CS = ENT / 32
	// MS = (ENT + CS) / 11
	//
	// |  ENT  | CS | ENT+CS |  MS  |
	// +-------+----+--------+------+
	// |  128  |  4 |   132  |  12  |
	// |  160  |  5 |   165  |  15  |
	// |  192  |  6 |   198  |  18  |
	// |  224  |  7 |   231  |  21  |
	// |  256  |  8 |   264  |  24  |
	
	NSUInteger ent = 0;
	NSUInteger cs = 0;
	switch (mnemonicCount)
	{
		case 12 : ent = 128; cs = 4; break;
		case 15 : ent = 160; cs = 5; break;
		case 18 : ent = 192; cs = 6; break;
		case 21 : ent = 224; cs = 7; break;
		case 24 : ent = 256; cs = 8; break;
	}
	
	ASSERTERR(bitString.length == (ent + cs), kS4Err_BadParams);
	
	// fill encrypted_key with decoded bytes from mnemonicArray offset - include checksum byte
    
	for (int index = 0; index < ((ent + cs)/ 8); index++)
	{
		NSString *bits = [bitString substringWithRange:NSMakeRange(index*8,8)];
		encrypted_key[index] = strtol(bits.UTF8String, NULL, 2);
	}
	
	// calculate the unlocking key
	err = PASS_TO_KEY(                                                // Create PBKDF2
	  (uint8_t *)passphrase.UTF8String, passphrase.UTF8LengthInBytes, // passphrase
	  (uint8_t *)saltData.bytes, saltData.length,                     // salt
	  2048,                                                           // PBKDF2 rounds
	  unlocking_key, sizeof(unlocking_key));                          // output
	CKERR;
    
	// decrypt the original key
	err = ECB_Decrypt(
	  kCipher_Algorithm_AES256,
	  unlocking_key,                        // S4 bug - should also be passing unlocking_key length
	  encrypted_key, sizeof(decrypted_key),
	  decrypted_key, sizeof(decrypted_key));                       // S4 bug - should also be passing encrypted_key length
	CKERR;
	
	// caclulate checksum checksum
	err = HASH_DO(
	  kHASH_Algorithm_SHA256,
	  decrypted_key, sizeof(decrypted_key),
	  hashBuf, sizeof(hashBuf));
	CKERR;

	// check for proper checksum
	checksumBits_calc = [self bitArrayFromData:[NSData dataWithBytesNoCopy:hashBuf
																	length:sizeof(hashBuf)
															  		freeWhenDone:NO]];
	checksumBits_calc = [checksumBits_calc substringToIndex:cs];
	checksumBits_input = [bitString substringFromIndex:ent];

	if (![checksumBits_calc isEqualToString:checksumBits_input])
	{
		err = kS4Err_BadIntegrity;
	}
	else
	{
		result = [[NSData alloc] initWithBytes:decrypted_key length:ent/8];
	}

done:
    
	ZERO(unlocking_key, sizeof(unlocking_key));
	ZERO(encrypted_key, sizeof(encrypted_key));
	ZERO(decrypted_key, sizeof(decrypted_key));
    
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (errorOut) *errorOut = error;
	return result;
}

#pragma mark Utilities

+ (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

+ (NSString *)bitArrayFromData:(NSData *)data
{
	NSMutableString *bitString = [NSMutableString stringWithCapacity:(data.length * 4)];
	
	static const char *bit_rep[16] = {
		[ 0] = "0000", [ 1] = "0001", [ 2] = "0010", [ 3] = "0011",
		[ 4] = "0100", [ 5] = "0101", [ 6] = "0110", [ 7] = "0111",
		[ 8] = "1000", [ 9] = "1001", [10] = "1010", [11] = "1011",
		[12] = "1100", [13] = "1101", [14] = "1110", [15] = "1111",
	};
	
	[data enumerateByteRangesUsingBlock:
	  ^(const void *bytes, NSRange byteRange, BOOL *stop)
	{
		// To print raw byte values as hex
		for (int i = 0; i < byteRange.length; ++i)
		{
			uint8_t byte =  ((uint8_t *)bytes)[i];
			
			[bitString appendFormat:@"%s%s", bit_rep[byte >> 4], bit_rep[byte & 0x0F]];
		}
	}];
	
	return bitString;
}

@end
