/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <XCTest/XCTest.h>

#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import <ZeroDarkCloud/BIP39Mnemonic.h>

@interface test_BIP39Mnemonic : XCTestCase
@end

@implementation test_BIP39Mnemonic

- (NSString *)sanitizeString:(NSString*)str
{
	NSLocale *usLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];

	// Replace accents, umlauts etc with equivalent letter i.e 'é' becomes 'e'.
	// Always use en_GB (or a locale without the characters you wish to strip) as locale,
	// no matter which language we're taking as input.
	NSString *processedString = [str stringByFoldingWithOptions: NSDiacriticInsensitiveSearch locale: usLocale];

	// remove non-letters
	processedString = [[processedString componentsSeparatedByCharactersInSet:[[NSCharacterSet letterCharacterSet] invertedSet]] componentsJoinedByString:@""];

	// trim whitespace
	processedString = [processedString stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
	return processedString;
}

- (NSData *)dataFromHexString:(NSString *)inString
{
	NSMutableString *str = [inString mutableCopy];
	
	[str replaceOccurrencesOfString:@"<" withString:@"" options:0 range:NSMakeRange(0, str.length)];
	[str replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, str.length)];
	[str replaceOccurrencesOfString:@">" withString:@"" options:0 range:NSMakeRange(0, str.length)];
	
	NSUInteger inLength = [str length];
	
	unichar *inCharacters = alloca(sizeof(unichar) * inLength);
	[str getCharacters:inCharacters range:NSMakeRange(0, inLength)];
	
	UInt8 *outBytes = malloc(sizeof(UInt8) * ((inLength / 2) + 1));
	
	NSInteger i, o = 0;
	UInt8 outByte = 0;
	
	for (i = 0; i < inLength; i++) {
		
		UInt8 c = inCharacters[i];
		SInt8 value = -1;
		
		if      (c >= '0' && c <= '9') value =      (c - '0');
		else if (c >= 'A' && c <= 'F') value = 10 + (c - 'A');
		else if (c >= 'a' && c <= 'f') value = 10 + (c - 'a');
		
		if (value >= 0) {
			
			if (i % 2 == 1) {
				outBytes[o++] = (outByte << 4) | value;
				outByte = 0;
				
			} else {
				outByte = value;
			}
			
		} else {
			
			if (o != 0) break;
		}
	}
	
	return [[NSData alloc] initWithBytesNoCopy:outBytes length:o freeWhenDone:YES];
}

- (void)test_vector_1
{

	NSURL *vectorURL = [[NSBundle mainBundle] URLForResource:@"mnemonic_vectors" withExtension:@"json"];

	NSError *error = nil;

	NSDictionary* languages = [NSJSONSerialization
							   JSONObjectWithData:[NSData dataWithContentsOfURL:vectorURL]
							   options:0
							   error:&error];

	if (error) {
		NSLog(@"Error reading 'TestUser.json': %@", error);
		return;
	}

	for(NSString* language in languages.allKeys)
	{
		NSDictionary* tests = [languages objectForKey:language];

// 		if(![language isEqualToString:@"en_US"]) continue;
		
//		NSLocale* locale = [NSLocale localeWithLocaleIdentifier:language];
//		XCTAssert(locale, @"local %@ not supported on this device",language);

		NSArray<NSString*> * wordList = [BIP39Mnemonic wordListForLanguageID:language  error:&error  ];
		XCTAssert(error == nil);
		XCTAssert(wordList.count == 2048);

		for(NSString* test in tests.allKeys)
		{
			if([test isEqualToString:@"BIP39"])
			{
				// data to mnemonic and back
				for(NSArray* vectors in tests[test])
				{
					NSData* data  	 =   [self dataFromHexString:vectors[0]];
					NSArray* mnemonic  = [vectors[1] componentsSeparatedByString:@" "];

					NSData* result1 	= [BIP39Mnemonic dataFromMnemonic: mnemonic
																languageID:language
																 error:&error  ];
					XCTAssert(error == nil);
					XCTAssert([result1 isEqual: data]);

					NSArray<NSString*> *output = [BIP39Mnemonic mnemonicFromData:data
																		  languageID:language
																		   error:&error];
					XCTAssert(error == nil);
					XCTAssert(mnemonic.count == output.count);
					for(int i = 0; i <mnemonic.count; i++ )
					{
						NSString* str1 = [self sanitizeString:mnemonic[i]];
						NSString* str2 = [self sanitizeString:output[i]];

						if([str1 compare:str2]!= NSOrderedSame)
						{
							;
						}
						XCTAssert([str1 compare:str2] == NSOrderedSame);

					}
				}
			}
			else if([test isEqualToString:@"storm4"]
					|| [test isEqualToString:@"zdc"])
			{
		
				for(NSArray* vectors in tests[test])
				{
					NSString* passphrase =  vectors[0];
					NSString* mnemonic 	 = vectors[1];
					NSData* keyData  	 =   [self dataFromHexString:vectors[2]];

					NSArray<NSString*> *output =
					[BIP39Mnemonic mnemonicFromKey:keyData
										passphrase:passphrase
											languageID:language
											 error:&error];

					XCTAssert(error == nil);
					XCTAssert([mnemonic isEqual:[output componentsJoinedByString:@" "]]);

					NSData* result2 = [BIP39Mnemonic keyFromMnemonic: output
														  passphrase:passphrase
															  languageID:language
															   error:&error   ];


					XCTAssert([result2 isEqual: keyData]);

				}
			}
			else
				XCTFail(@"Unknown test: %@ ",test );
		}
	}

}

@end
