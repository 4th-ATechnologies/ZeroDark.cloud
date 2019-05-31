/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <XCTest/XCTest.h>

#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import <ZeroDarkCloud/ZDCNodePrivate.h>

@interface test_Streams : XCTestCase
@end

@implementation test_Streams

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

- (NSURL *)randomFileURL
{
	return [ZDCDirectoryManager generateTempURL];
}

- (NSData *)generateRandomData:(NSUInteger)random_length
{
	NSMutableData *random_data = [NSMutableData dataWithLength:random_length];
	void *random_buffer = random_data.mutableBytes;
	
	int result = SecRandomCopyBytes(kSecRandomDefault, (size_t)random_length, random_buffer);
	if (result != 0) {
		NSLog(@"SecRandomCopyBytes returned error");
		return nil;
	}
	
	return random_data;
}

- (NSURL *)generateRandomFile:(uint64_t)file_length
{
	// I'm not sure if SecRandomCopyBytes will give us an unlimited amount of data.
	// So instead I'm asking for a managable chunk,
	// and then repeating the chunk to achieve the desired file_length.
	
	NSUInteger random_length = (1024 * 1024 * 1);
	NSMutableData *random_data = [NSMutableData dataWithLength:random_length];
	void *random_buffer = random_data.mutableBytes;
	
	int result = SecRandomCopyBytes(kSecRandomDefault, (size_t)random_length, random_buffer);
	if (result != 0) {
		NSLog(@"SecRandomCopyBytes returned error");
		return nil;
	}
	
	NSMutableData *file_data = [NSMutableData dataWithLength:file_length];
	void *file_buffer = file_data.mutableBytes;
	
	NSUInteger offset = 0;
	while (offset < file_length)
	{
		NSUInteger bytesToCopy = MIN(random_length, (file_length - offset));
		memcpy((file_buffer + offset), random_buffer, bytesToCopy);
		
		offset += bytesToCopy;
	}
	
	NSInputStream *stream = [NSInputStream inputStreamWithData:file_data];
	return [self writeStream:stream error:NULL];
}

- (NSURL *)writeStream:(NSInputStream *)inputStream error:(NSError **)errorPtr
{
	NSError *error = nil;
	
	NSURL *outURL = [self randomFileURL];
	NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:outURL append:NO];
	
	size_t bufferSize = 1024 * 1024 * 1;
	uint8_t *buffer = (uint8_t *)malloc(bufferSize);
	
	[inputStream open];
	[outputStream open];
	
	NSInteger totalBytesRead = 0;
	BOOL done = NO;
	do
	{
		NSInteger bytesRead = 0;
		NSInteger loopBytesWritten = 0;
		
		bytesRead = [inputStream read:buffer maxLength:bufferSize];
		if (bytesRead < 0)
		{
			error = inputStream.streamError;
			NSLog(@"Error reading stream: %@", error);
			
			goto done;
		}
		else if (bytesRead == 0)
		{
			// This does NOT imply EOF.
			// CloudFile2CleartextInputStream uses "soft breaks" between sections.
			//
			// That is, it will return 0 to signal the end of a section.
		}
		
		totalBytesRead += bytesRead;
		
		while (loopBytesWritten < bytesRead)
		{
			NSInteger bytesWritten =
			  [outputStream write:(buffer + loopBytesWritten)
			            maxLength:(bytesRead - loopBytesWritten)];
			
			if (bytesWritten < 0)
			{
				error = outputStream.streamError;
				NSLog(@"Error writing stream: %@", error);
				
				goto done;
			}
			
			loopBytesWritten += bytesWritten;
		}
		
		// Remember: (bytesRead == 0) does NOT imply EOF.
		// CloudFile2CleartextInputStream uses this to signal the end of a section.
		//
		done = ((bytesRead == 0) && (inputStream.streamStatus == NSStreamStatusAtEnd));
		
	} while (!done);
	
done:
	
	[inputStream close];
	[outputStream close];
	
	if (error)
	{
		[[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
		
		if (errorPtr) *errorPtr = error;
		return nil;
	}
	else
	{
		if (errorPtr) *errorPtr = nil;
		return outURL;
	}

}

- (NSURL *)combineParts:(NSArray<NSURL *> *)parts
{
	NSURL *outputURL = [self randomFileURL];
	
	NSOutputStream *outputStream = [NSOutputStream outputStreamWithURL:outputURL append:NO];
	
	[outputStream open];
	
	for (NSURL *partURL in parts)
	{
		NSData *partData = [NSData dataWithContentsOfURL:partURL];
		
		uint8_t *buffer = (uint8_t *)[partData bytes];
		NSUInteger bufferOffset = 0;
		
		while (bufferOffset < partData.length)
		{
			NSInteger bytesWritten = [outputStream write:(buffer + bufferOffset)
														  maxLength:(partData.length - bufferOffset)];
			
			if (bytesWritten < 0)
			{
				NSLog(@"Error writing to outputStream: %@", outputStream.streamError);
				return nil;
			}
			else
			{
				bufferOffset += bytesWritten;
			}
		}
	}
	
	[outputStream close];
	return outputURL;
}

- (NSRange)randomRangeForFileSize:(uint64_t)fileSize withMaxLength:(NSUInteger)maxLength
{
	uint32_t location = arc4random_uniform((uint32_t)fileSize);
	
	uint32_t remaining = (uint32_t)(fileSize - location);
	uint32_t upper = (uint32_t)MIN(remaining, maxLength);
	
	uint32_t length = arc4random_uniform((uint32_t)upper);
	if (length == 0)
		length = 1;
	
	return NSMakeRange(location, length);
}

- (NSData *)readRange:(NSRange)range ofFile:(NSURL *)fileURL error:(NSError **)errorPtr
{
	NSInputStream *stream = [NSInputStream inputStreamWithURL:fileURL];
	
	NSData *data = [self readRange:range ofStream:stream error:errorPtr];
	
	[stream close];
	return data;
}

- (NSData *)readRange:(NSRange)range ofStream:(NSInputStream *)stream error:(NSError **)errorPtr
{
	NSError *error = nil;
	NSMutableData *data = [NSMutableData dataWithLength:range.length];
	
	void *buffer = [data mutableBytes];
	NSUInteger bufferOffset = 0;
	
	if (stream.streamStatus == NSStreamStatusNotOpen)
	{
		[stream open];
		error = stream.streamError;
		if (error) { goto abort; }
	}
	
	if (![stream setProperty:@(range.location) forKey:NSStreamFileCurrentOffsetKey])
	{
		error = [NSError errorWithDomain:@"Unable to seek" code:0 userInfo:nil];
		goto abort;
	}
	
	while (bufferOffset < range.length)
	{
		NSUInteger remaining = range.length - bufferOffset;
		NSInteger read = [stream read:(buffer + bufferOffset) maxLength:remaining];
		
		if (read < 0)
		{
			error = stream.streamError;
			goto abort;
		}
		else if (read == 0)
		{
			error = [NSError errorWithDomain:@"Unexpected EOF" code:0 userInfo:nil];
			goto abort;
		}
		else
		{
			bufferOffset += read;
		}
	}
	
	return data;
	
abort:
	
	if (errorPtr) *errorPtr = error;
	return nil;
}

- (NSData *)readRange:(NSRange)fileRange ofReader:(ZDCFileReader *)reader error:(NSError **)errorPtr
{
	NSError *error = nil;
	NSMutableData *data = [NSMutableData dataWithLength:fileRange.length];
	
	void *buffer = [data mutableBytes];
	NSUInteger bufferOffset = 0;
	
	[reader openFileWithError:&error];
	if (error) { goto abort; }
	
	while (bufferOffset < fileRange.length)
	{
		NSUInteger remaining = fileRange.length - bufferOffset;
		NSRange readRange = NSMakeRange(fileRange.location + bufferOffset, remaining);
		
		ssize_t read = [reader getBytes:(buffer + bufferOffset) range:readRange error:&error];
		
		if (read < 0)
		{
			goto abort;
		}
		else if (read == 0)
		{
			error = [NSError errorWithDomain:@"Unexpected EOF" code:0 userInfo:nil];
			goto abort;
		}
		else
		{
			bufferOffset += read;
		}
	}
	
	return data;
	
abort:
	
	if (errorPtr) *errorPtr = error;
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)sample_raw_key
{
	NSString *rawKey =
	@"<e90b45d2 54bdd842 00244e3b d20aeeb1 fa3417d6 32928433 938ed73a bcd604ea cf289bef 2267fd61 7798e36f bc5337a2 01e8dfc6 97c6dc93 8e8a35f1 1a7955ee>";
	
	return [self dataFromHexString:rawKey];
}

- (NSData *)sample_raw_metadata
{
	NSString *rawMetadata =
	@"<7b224d6f 64696669 63617469 6f6e4461 7465223a 22323031 372d3037 2d313154 31363a31 383a3032 5a222c22 46696c65 53697a65 223a3130 34383537 36302c22 4d656469 61547970 65223a22 636f6d2e 6170706c 652e6d61 6362696e 6172792d 61726368 69766522 2c224d69 6d655479 7065223a 22617070 6c696361 74696f6e 5c2f6d61 6362696e 61727922 2c224372 65617469 6f6e4461 7465223a 22323031 372d3037 2d313154 30303a34 313a3337 5a227d>";
	
	return [self dataFromHexString:rawMetadata];
}

- (NSData *)sample_raw_thumbnail
{
	NSString *rawThumbnail = @"<ffd8ffe0 00104a46 49460001 01000048 00480000 ffe10040 45786966 00004d4d 002a0000 00080001 87690004 00000001 0000001a 00000000 0002a002 00040000 00010000 00c6a003 00040000 00010000 01000000 0000ffed 00385068 6f746f73 686f7020 332e3000 3842494d 04040000 00000000 3842494d 04250000 00000010 d41d8cd9 8f00b204 e9800998 ecf8427e ffe21b24 4943435f 50524f46 494c4500 01010000 1b146170 706c0210 00006d6e 74725247 42205859 5a2007e1 0003001d 00110014 000b6163 73704150 504c0000 00004150 504c0000 00000000 00000000 00000000 00000000 f6d60001 00000000 d32d6170 706c0000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00116465 73630000 01500000 00626473 636d0000 01b40000 04186370 72740000 05cc0000 00237774 70740000 05f00000 00147258 595a0000 06040000 00146758 595a0000 06180000 00146258 595a0000 062c0000 00147254 52430000 06400000 080c6161 72670000 0e4c0000 00207663 67740000 0e6c0000 06126e64 696e0000 14800000 063e6368 61640000 1ac00000 002c6d6d 6f640000 1aec0000 00286254 52430000 06400000 080c6754 52430000 06400000 080c6161 62670000 0e4c0000 00206161 67670000 0e4c0000 00206465 73630000 00000000 00084469 73706c61 79000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00006d6c 75630000 00000000 00220000 000c6872 48520000 00140000 01a86b6f 4b520000 000c0000 01bc6e62 4e4f0000 00120000 01c86964 00000000 00120000 01da6875 48550000 00140000 01ec6373 435a0000 00160000 02006461 444b0000 001c0000 0216756b 55410000 001c0000 02326172 00000000 00140000 024e6974 49540000 00140000 0262726f 524f0000 00120000 02766e6c 4e4c0000 00160000 02886865 494c0000 00160000 029e6573 45530000 00120000 02766669 46490000 00100000 02b47a68 54570000 000c0000 02c47669 564e0000 000e0000 02d0736b 534b0000 00160000 02de7a68 434e0000 000c0000 02c47275 52550000 00240000 02f46672 46520000 00160000 03186d73 00000000 00120000 032e6361 45530000 00180000 03407468 54480000 000c0000 03586573 584c0000 00120000 02766465 44450000 00100000 0364656e 55530000 00120000 03747074 42520000 00180000 0386706c 504c0000 00120000 039e656c 47520000 00220000 03b07376 53450000 00100000 03d27472 54520000 00140000 03e26a61 4a500000 000c0000 03f67074 50540000 00160000 0402004c 00430044 00200075 00200062 006f006a 0069ceec b7ec0020 004c0043 00440046 00610072 00670065 002d004c 00430044 004c0043 00440020 00570061 0072006e 00610053 007a00ed 006e0065 00730020 004c0043 00440042 00610072 00650076 006e00fd 0020004c 00430044 004c0043 0044002d 00660061 00720076 00650073 006b00e6 0072006d 041a043e 043b044c 043e0440 043e0432 04380439 0020004c 00430044 200f004c 00430044 00200645 06440648 06460629 004c0043 00440020 0063006f 006c006f 00720069 004c0043 00440020 0063006f 006c006f 0072004b 006c0065 00750072 0065006e 002d004c 00430044 200f004c 00430044 002005e6 05d105e2 05d505e0 05d90056 00e40072 0069002d 004c0043 00445f69 82720020 004c0043 0044004c 00430044 0020004d 00e00075 00460061 00720065 0062006e 00fd0020 004c0043 00440426 04320435 0442043d 043e0439 00200416 041a002d 04340438 0441043f 043b0435 0439004c 00430044 00200063 006f0075 006c0065 00750072 00570061 0072006e 00610020 004c0043 0044004c 00430044 00200065 006e0020 0063006f 006c006f 0072004c 00430044 00200e2a 0e350046 00610072 0062002d 004c0043 00440043 006f006c 006f0072 0020004c 00430044 004c0043 00440020 0043006f 006c006f 00720069 0064006f 004b006f 006c006f 00720020 004c0043 00440388 03b303c7 03c103c9 03bc03b7 002003bf 03b803cc 03bd03b7 0020004c 00430044 004600e4 00720067 002d004c 00430044 00520065 006e006b 006c0069 0020004c 00430044 30ab30e9 30fc004c 00430044 004c0043 00440020 00610020 0043006f 00720065 00737465 78740000 0000436f 70797269 67687420 4170706c 6520496e 632e2c20 32303137 00005859 5a200000 00000000 f3520001 00000001 16cf5859 5a200000 00000000 616c0000 38320000 0a425859 5a200000 00000000 6f1c0000 ae950000 16995859 5a200000 00000000 264e0000 19390000 b2526375 72760000 00000000 04000000 0005000a 000f0014 0019001e 00230028 002d0032 0036003b 00400045 004a004f 00540059 005e0063 0068006d 00720077 007c0081 0086008b 00900095 009a009f 00a300a8 00ad00b2 00b700bc 00c100c6 00cb00d0 00d500db 00e000e5 00eb00f0 00f600fb 01010107 010d0113 0119011f 0125012b 01320138 013e0145 014c0152 01590160 0167016e 0175017c 0183018b 0192019a 01a101a9 01b101b9 01c101c9 01d101d9 01e101e9 01f201fa 0203020c 0214021d 0226022f 02380241 024b0254 025d0267 0271027a 0284028e 029802a2 02ac02b6 02c102cb 02d502e0 02eb02f5 0300030b 03160321 032d0338 0343034f 035a0366 0372037e 038a0396 03a203ae 03ba03c7 03d303e0 03ec03f9 04060413 0420042d 043b0448 04550463 0471047e 048c049a 04a804b6 04c404d3 04e104f0 04fe050d 051c052b 053a0549 05580567 05770586 059605a6 05b505c5 05d505e5 05f60606 06160627 06370648 0659066a 067b068c 069d06af 06c006d1 06e306f5 07070719 072b073d 074f0761 07740786 079907ac 07bf07d2 07e507f8 080b081f 08320846 085a086e 08820896 08aa08be 08d208e7 08fb0910 0925093a 094f0964 0979098f 09a409ba 09cf09e5 09fb0a11 0a270a3d 0a540a6a 0a810a98 0aae0ac5 0adc0af3 0b0b0b22 0b390b51 0b690b80 0b980bb0 0bc80be1 0bf90c12 0c2a0c43 0c5c0c75 0c8e0ca7 0cc00cd9 0cf30d0d 0d260d40 0d5a0d74 0d8e0da9 0dc30dde 0df80e13 0e2e0e49 0e640e7f 0e9b0eb6 0ed20eee 0f090f25 0f410f5e 0f7a0f96 0fb30fcf 0fec1009 10261043 1061107e 109b10b9 10d710f5 11131131 114f116d 118c11aa 11c911e8 12071226 12451264 128412a3 12c312e3 13031323 13431363 138313a4 13c513e5 14061427 1449146a 148b14ad 14ce14f0 15121534 15561578 159b15bd 15e01603 16261649 166c168f 16b216d6 16fa171d 17411765 178917ae 17d217f7 181b1840 1865188a 18af18d5 18fa1920 1945196b 199119b7 19dd1a04 1a2a1a51 1a771a9e 1ac51aec 1b141b3b 1b631b8a 1bb21bda 1c021c2a 1c521c7b 1ca31ccc 1cf51d1e 1d471d70 1d991dc3 1dec1e16 1e401e6a 1e941ebe 1ee91f13 1f3e1f69 1f941fbf 1fea2015 2041206c 209820c4 20f0211c 21482175 21a121ce 21fb2227 22552282 22af22dd 230a2338 23662394 23c223f0 241f244d 247c24ab 24da2509 25382568 259725c7 25f72627 26572687 26b726e8 27182749 277a27ab 27dc280d 283f2871 28a228d4 29062938 296b299d 29d02a02 2a352a68 2a9b2acf 2b022b36 2b692b9d 2bd12c05 2c392c6e 2ca22cd7 2d0c2d41 2d762dab 2de12e16 2e4c2e82 2eb72eee 2f242f5a 2f912fc7 2ffe3035 306c30a4 30db3112 314a3182 31ba31f2 322a3263 329b32d4 330d3346 337f33b8 33f1342b 3465349e 34d83513 354d3587 35c235fd 36373672 36ae36e9 37243760 379c37d7 38143850 388c38c8 39053942 397f39bc 39f93a36 3a743ab2 3aef3b2d 3b6b3baa 3be83c27 3c653ca4 3ce33d22 3d613da1 3de03e20 3e603ea0 3ee03f21 3f613fa2 3fe24023 406440a6 40e74129 416a41ac 41ee4230 427242b5 42f7433a 437d43c0 44034447 448a44ce 45124555 459a45de 46224667 46ab46f0 4735477b 47c04805 484b4891 48d7491d 496349a9 49f04a37 4a7d4ac4 4b0c4b53 4b9a4be2 4c2a4c72 4cba4d02 4d4a4d93 4ddc4e25 4e6e4eb7 4f004f49 4f934fdd 50275071 50bb5106 5150519b 51e65231 527c52c7 5313535f 53aa53f6 5442548f 54db5528 557555c2 560f565c 56a956f7 57445792 57e0582f 587d58cb 591a5969 59b85a07 5a565aa6 5af55b45 5b955be5 5c355c86 5cd65d27 5d785dc9 5e1a5e6c 5ebd5f0f 5f615fb3 60056057 60aa60fc 614f61a2 61f56249 629c62f0 63436397 63eb6440 649464e9 653d6592 65e7663d 669266e8 673d6793 67e9683f 689668ec 6943699a 69f16a48 6a9f6af7 6b4f6ba7 6bff6c57 6caf6d08 6d606db9 6e126e6b 6ec46f1e 6f786fd1 702b7086 70e0713a 719571f0 724b72a6 7301735d 73b87414 747074cc 75287585 75e1763e 769b76f8 775677b3 7811786e 78cc792a 798979e7 7a467aa5 7b047b63 7bc27c21 7c817ce1 7d417da1 7e017e62 7ec27f23 7f847fe5 804780a8 810a816b 81cd8230 829282f4 835783ba 841d8480 84e38547 85ab860e 867286d7 873b879f 88048869 88ce8933 899989fe 8a648aca 8b308b96 8bfc8c63 8cca8d31 8d988dff 8e668ece 8f368f9e 9006906e 90d6913f 91a89211 927a92e3 934d93b6 9420948a 94f4955f 95c99634 969f970a 977597e0 984c98b8 99249990 99fc9a68 9ad59b42 9baf9c1c 9c899cf7 9d649dd2 9e409eae 9f1d9f8b 9ffaa069 a0d8a147 a1b6a226 a296a306 a376a3e6 a456a4c7 a538a5a9 a61aa68b a6fda76e a7e0a852 a8c4a937 a9a9aa1c aa8fab02 ab75abe9 ac5cacd0 ad44adb8 ae2daea1 af16af8b b000b075 b0eab160 b1d6b24b b2c2b338 b3aeb425 b49cb513 b58ab601 b679b6f0 b768b7e0 b859b8d1 b94ab9c2 ba3bbab5 bb2ebba7 bc21bc9b bd15bd8f be0abe84 beffbf7a bff5c070 c0ecc167 c1e3c25f c2dbc358 c3d4c451 c4cec54b c5c8c646 c6c3c741 c7bfc83d c8bcc93a c9b9ca38 cab7cb36 cbb6cc35 ccb5cd35 cdb5ce36 ceb6cf37 cfb8d039 d0bad13c d1bed23f d2c1d344 d3c6d449 d4cbd54e d5d1d655 d6d8d75c d7e0d864 d8e8d96c d9f1da76 dafbdb80 dc05dc8a dd10dd96 de1cdea2 df29dfaf e036e0bd e144e1cc e253e2db e363e3eb e473e4fc e584e60d e696e71f e7a9e832 e8bce946 e9d0ea5b eae5eb70 ebfbec86 ed11ed9c ee28eeb4 ef40efcc f058f0e5 f172f1ff f28cf319 f3a7f434 f4c2f550 f5def66d f6fbf78a f819f8a8 f938f9c7 fa57fae7 fb77fc07 fc98fd29 fdbafe4b fedcff6d ffff7061 72610000 00000003 00000002 66660000 f2a70000 0d590000 13d00000 0a0e7663 67740000 00000000 00000003 01000002 00000056 012e01eb 02c40383 04530540 0627071a 0818091f 0a3d0b4e 0c6b0d90 0eb90fec 112d1265 13a314e3 162a1779 18bf1a0f 1b571ca4 1df31f3c 208421cd 23112452 258d26cb 28002933 2a662b97 2cca2df7 2f283051 318032ab 33d53502 3631375d 388a39b6 3ae13c0d 3d383e60 3f8940b1 41dc4308 44364563 469047b8 48de4a01 4b244c47 4d6a4e8f 4fb450d8 51f85316 5433554f 566d578d 58ae59cb 5ae15bf0 5cf75dfb 5f00600a 6119622d 63416452 655f6665 67616853 693c6a20 6b016be0 6cbf6da0 6e836f68 70507138 72207308 73ef74d6 75be76a8 7793787e 796c7a59 7b497c3d 7d377e36 7f398041 814b8257 83658474 85858694 87a488b3 89c08acc 8bd68cdf 8de78eed 8ff290f5 91f692f5 93f594fa 96049715 982c9947 9a639b7f 9c989dae 9ebf9fcb a0d4a1da a2e0a3e9 a4f4a603 a715a82a a942aa5c ab77ac94 adb2aed1 aff1b111 b233b353 b473b590 b6a9b7ba b8c1b9c3 bac0bbbb bcb5bdaf bea9bfa3 c09dc195 c28ac37c c46ac553 c636c718 c7f9c8e0 c9cfcac6 cbc3ccc1 cdbcceaf cf98d073 d143d20d d2d3d39b d466d535 d605d6d7 d7a8d876 d940da06 dac7db80 dc35dce7 dd91de3b dee3df8d e03be0eb e19fe252 e303e3af e455e4f9 e594e62c e6bfe752 e7e4e885 e92fe9e4 eaa8eb6e ec33ecf5 edafee63 ef11efb5 f050f0e6 f17cf217 f2c6f38f f46ef561 f666f78a f8e4fac5 fd2effff 00000056 012301b0 026a0332 03e804b1 05800658 073d082d 09270a27 0b220c30 0d3a0e51 0f63107e 119f12be 13e91510 16381761 188819b4 1ade1c0b 1d331e5b 1f8020a1 21bf22db 23f5250b 261f2735 28492960 2a792b93 2cb12dcc 2ee83004 3121323c 335a3474 358b36a4 37b938cd 39e23af4 3c063d1b 3e313f4d 406c418f 42b043d0 44ed4608 471d4832 49454a55 4b634c6e 4d784e7e 4f835085 51865288 538a548c 558a5684 57795868 59545a44 5b3f5c46 5d5a5e77 5f9560b0 61c262ca 63c564b5 659c667b 67576830 690c69ec 6ad06bba 6ca96d9b 6e8f6f82 7072715c 7240731f 73fb74d5 75ad7686 77627845 79307a24 7b1d7c19 7d157e10 7f067ff6 80e281ca 82b18395 8477855d 864a8744 884c8961 8a818ba5 8cc68dde 8eee8ff5 90f791f5 92f393f0 94ed95ec 96ee97f8 99109a39 9b6e9ca6 9dce9ee3 9fe9a0e5 a1dfa2d9 a3d1a4c8 a5bea6bc a7caa8ed aa21ab5d ac9cadd9 af14b04e b188b2c2 b3f9b52e b664b79b b8d2ba05 bb34bc5f bd85bea6 bfbcc0be c1aac290 c37dc477 c580c68f c79dc8a3 c99eca8e cb75cc53 cd2dce04 cedacfb2 d08bd16a d251d345 d445d551 d662d775 d884d987 da7ddb66 dc43dd1a ddecdeb9 df87e058 e12de208 e2e6e3c3 e49de571 e640e70c e7d4e8a3 e97fea69 eb64ec68 ed6dee70 ef70f070 f172f276 f379f477 f569f647 f70ff7b3 f845f8cb f95af9ed fad0fc0c fddaffff 0000002b 00c4014b 01d80265 0306038f 042b04cf 057a062f 06e907a5 0868092f 09f90aca 0b9f0c77 0d520e32 0f0e0ff6 10d911c0 12a91393 147d1567 1652173d 18291915 19fc1ae8 1bd21cbe 1dae1ea3 1f9b2096 2194228f 23862476 25612645 272027f8 28cc299f 2a732b48 2c212d02 2de92ed7 2fc830ba 31aa3298 33803460 35393606 36cf3795 38583919 39d93a9d 3b643c32 3d063dde 3eb63f8f 40684144 42264310 440044f3 45e746d6 47bb4896 49654a25 4ae04b98 4c4f4d07 4dc34e83 4f495018 50ea51be 52935368 543b550d 55de56ad 577c584a 591559df 5aa85b6f 5c355cf9 5dbd5e80 5f436008 60d1619c 626b633c 640c64da 65a76671 673867fc 68bf6980 6a406b00 6bc06c81 6d436e04 6ec56f85 704170f8 71ab7259 730173a9 744f74f4 7598763c 76de7780 781d78bd 79607a16 7ada7bab 7c837d58 7e287ef6 7fc38093 81678244 832a8418 850b8600 86f487e3 88cd89af 8a8c8b61 8c348d07 8dda8eb0 8f8a906b 91479212 92c6935b 93ec947a 95419642 97889908 9a8a9be4 9d199e32 9f39a039 a135a22f a328a421 a519a611 a70aa809 a90faa21 ab3dac60 ad87aead afd3b0fc b228b35a b492b5d1 b714b859 b99cbad7 bc05bd29 be47bf62 c07fc19e c2bec3df c4ffc621 c743c867 c98ccab1 cbd6ccfd ce29cf5b d097d1de d332d48d d5eed753 d8b9da21 db95dd2f df0ee177 e48be879 ed4ef2f6 f951ffff 00006e64 696e0000 00000000 06360000 93950000 568d0000 56e90000 91b70000 26bb0000 170a0000 500d0000 54390002 87ae0002 47ae0001 6b850003 01000002 00000001 00040008 000f0016 001f0029 00340040 004c005a 00690078 0089009a 00ac00be 00d200e6 00fc0112 01290140 01590173 018d01a9 01c501e3 02010221 02420264 028702ac 02d202fa 0323034d 037a03a8 03d70408 043a046d 04a304d9 0512054b 058605c3 06010640 068006c2 0705074a 079007d8 0821086c 08b90907 095709a8 09fa0a4d 0aa10af7 0b4e0ba8 0c040c62 0cc30d25 0d890dee 0e540ebc 0f250f91 10001071 10e41159 11cf1246 12bd1338 13b6143a 14c31552 15e31675 17061796 182618b8 194e19e8 1a881b31 1be31c9f 1d621e2b 1ef81fc6 20952164 22342306 23db24b3 258f266c 274b282b 290d29f0 2ad52bbb 2c9e2d7e 2e5c2f39 301430f0 31cd32aa 33893468 354a362e 371537ff 38ed39de 3ad23bca 3cc53dc4 3ec73fce 40da41e8 42f64400 45064608 47084808 49094a0c 4b144c21 4d344e4e 4f6e5094 51bc52e5 540d5534 5659577d 58a059c4 5ae75c0b 5d305e56 5f7c60a4 61ce62f8 64246553 668567bc 68fa6a43 6b996cf9 6e636fd2 714672bc 743475af 772d78b1 7a3c7bd0 7d6f7f1c 80d68294 844c85f6 8794892c 8ac58c65 8e158fdf 91cd93dd 95ff9820 9a399c4c 9e5fa079 a2a0a4da a72da9a0 ac30aee0 b1a1b45e b70bb9ae bc5dbf2b c21fc546 c8a2cc0c cf28d1f6 d491d728 d9d1dc9e df97e2d2 e660e9f9 ed12efac f200f430 f639f7ff f98afab8 fbd4fcbb fda3fe70 ff37ffff 00000001 0005000a 0012001b 00260032 003f004d 005c006d 007e0091 00a400b9 00cf00e5 00fd0116 012f014a 01660183 01a201c1 01e20204 0227024c 0272029a 02c302ef 031c034b 037c03af 03e4041a 0452048b 04c50501 053d057b 05bb05fc 063f0683 06c90710 075907a5 07f20841 089308e6 093b0993 09ec0a46 0aa10afc 0b580bb4 0c120c72 0cd40d39 0da00e0b 0e780ee7 0f590fce 104610c0 113e11bf 124312ca 135313dd 146a14fa 158f162a 16cb1771 181618b6 195119e6 1a791b0d 1ba41c40 1ce41d91 1e4a1f0e 1fdd20b3 218e2269 23422418 24eb25bd 26902766 28422925 2a122b08 2c052d08 2e0e2f12 30113108 31f932e8 33d734ca 35c136c1 37ca38db 39f23b0e 3c303d51 3e693f74 40724168 42584347 44394534 46384747 485f497e 4aa14bc7 4cf04e1b 4f45506b 51865294 53975495 559456a0 57bf58f1 5a355b80 5ccd5e1e 5f7460cf 62236366 649565b5 66ce67e4 68fb6a16 6b336c54 6d766e9a 6fc070ea 72177346 747675a7 76da7810 794d7a8f 7bd87d26 7e7d7fe3 81678310 84ca8674 88068987 8b048c88 8e1b8fc3 91829358 9543973b 993b9b3b 9d399f29 a104a2c6 a476a61b a7bda962 ab15acdd aec5b0cf b2f5b531 b77cb9cb bc0fbe44 c072c2a6 c4e9c742 c9b2cc31 ce9cd0dd d2f4d4f1 d6e7d8e3 dae8dcf4 df01e10a e314e524 e748e996 ec37ef8a f3a6f76c f9cefb84 fcc3fdf4 fef9ffff 00000002 00080011 001e002d 003e0051 0066007d 009600b0 00cc00ea 0109012b 014d0172 019801c0 01ea0216 02440274 02a602da 03110349 038403c0 03fd043b 047a04ba 04fc0541 058a05d7 06290681 06dd073e 07a20808 086f08d4 0939099d 0a020a6a 0ad50b44 0bbb0c39 0cc10d50 0de60e82 0f210fc0 105c10f6 1190122d 12cd136e 140d14a8 154215dc 1679171e 17ce188e 19621a42 1b2a1c14 1cfb1ddd 1eb81f92 206d214c 22302318 240624f9 25f126ef 27f328fd 2a0e2b24 2c402d60 2e802f9d 30b831d3 32f3341a 35493682 37c3390c 3a5c3bb0 3d073e60 3fbe4122 42934416 45ae475a 49114ad1 4c9a4e6f 50555232 53da555a 56cc5848 59d35b66 5cf85e83 60016170 62d56437 659c6709 68816a0a 6ba36d4d 6f0070b7 726f741e 75c37775 79647bee 7ea48079 81d682fc 84028508 86108733 887389d4 8b558ce9 8e88902e 91d99388 953b96f1 98a99a5e 9c0a9da7 9f37a0bd a23fa3c0 a544a6ca a850a9d4 ab54acd0 ae46afb9 b128b297 b408b57d b6fcb889 ba26bbd0 bd82bf36 c0e9c29c c44fc604 c7bbc973 cb2bcce4 ce9ed058 d214d3d2 d58fd74a d8ffdaac dc4fdde8 df75e0fd e282e403 e582e702 e883ea04 eb7fecee ee46ef79 f09df18d f275f344 f3f7f4aa f54ef5db f668f6f6 f776f7e9 f85cf8cf f943f9ab fa0dfa70 fad2fb35 fb98fbf1 fc49fca2 fcfbfd54 fdadfe03 fe58feac ff01ff55 ffaaffff 00007366 33320000 00000001 0c420000 05deffff f3260000 07920000 fd91ffff fba2ffff fda30000 03dc0000 c06c6d6d 6f640000 00000000 06100000 9cdf0000 0000ca2a d5800000 00000000 00000000 00000000 0000ffc0 00110801 0000c603 01220002 11010311 01ffc400 1f000001 05010101 01010100 00000000 00000001 02030405 06070809 0a0bffc4 00b51000 02010303 02040305 05040400 00017d01 02030004 11051221 31410613 51610722 71143281 91a10823 42b1c115 52d1f024 33627282 090a1617 18191a25 26272829 2a343536 3738393a 43444546 4748494a 53545556 5758595a 63646566 6768696a 73747576 7778797a 83848586 8788898a 92939495 96979899 9aa2a3a4 a5a6a7a8 a9aab2b3 b4b5b6b7 b8b9bac2 c3c4c5c6 c7c8c9ca d2d3d4d5 d6d7d8d9 dae1e2e3 e4e5e6e7 e8e9eaf1 f2f3f4f5 f6f7f8f9 faffc400 1f010003 01010101 01010101 01000000 00000001 02030405 06070809 0a0bffc4 00b51100 02010204 04030407 05040400 01027700 01020311 04052131 06124151 07617113 22328108 144291a1 b1c10923 3352f015 6272d10a 162434e1 25f11718 191a2627 28292a35 36373839 3a434445 46474849 4a535455 56575859 5a636465 66676869 6a737475 76777879 7a828384 85868788 898a9293 94959697 98999aa2 a3a4a5a6 a7a8a9aa b2b3b4b5 b6b7b8b9 bac2c3c4 c5c6c7c8 c9cad2d3 d4d5d6d7 d8d9dae2 e3e4e5e6 e7e8e9ea f2f3f4f5 f6f7f8f9 faffdb00 43000606 06060606 0a06060a 0e0a0a0a 0e120e0e 0e0e1217 12121212 12171c17 17171717 171c1c1c 1c1c1c1c 1c222222 22222227 27272727 2c2c2c2c 2c2c2c2c 2c2cffdb 00430107 07070b0a 0b130a0a 132e1f1a 1f2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2e2e 2e2e2eff dd000400 0dffda00 0c030100 02110311 003f00fa 56ee4669 16252470 4f071553 cb6fef3f fdf47fc6 a6979be5 1fec37f3 153ec140 14bcb6fe f3ff00df 47fc68f2 dbfbcfff 007d1ff1 abbb051b 050052f2 dbfbcfff 007d1ff1 a3cb6fef 3ffdf47f c6aeec14 6c14014b cb6fef3f fdf47fc6 90a38fe2 7ffbe8ff 008d5ed8 290a0a00 a055ff00 beff00f7 d1ff001a 63090747 6ffbe8d5 f2829850 1a00f24f 88de25d7 3c3ab62d a55c98bc e3287c80 d9dbb71f 7b3ea6b3 fc19e2ff 00136bb0 ddc9757a 886dca05 cc59cee0 c79c15c0 e3ad56f8 cabb534c facdff00 b25713e0 98bc3b25 bdf7f6eb 0560d1f9 79729c61 b24608c9 aa484f63 b41f17f5 fd37505d 3af2dad7 55629bcb e9d233a8 5e73d8f2 00c915e9 da27c46d 0b568e13 33359c93 8051271b 3767a60f 43f81af9 56c34ebd 4d505e7c 3f6bab88 502c6d33 4582ad26 41040c8c 62babf1a ead7e960 ba5ea768 d1cee54a c840dbf2 f5287b52 b05cfaf9 1d5c6e53 9069d5f3 6fc2bf17 6ae96cf0 6ab234d6 cae12376 392bc742 7d2be8c8 2649903a 1c834864 d4514500 14514500 14514500 14514500 14514500 7fffd0fa 4c8cdf8f f71bf98a b9b6aa0e 7501fee3 7f315a18 a008b6d1 b6a5c518 a008b6d1 b6a5c518 a008b6d2 15a9b148 4500572b 4c2b5671 4d2b401e 05f1a461 74bfacdf fb2571de 01bafb35 b5f83a6c 97f968c9 291ac810 00d9ce4f 19f515eb 1f10bc3c de24d534 8d384a21 40b71248 e464845f 2f381dcf 22aee83a 3f87fc2b 8b3d34bb cb3cb1ef 77624920 e01c0e07 53569322 724b4678 768369a9 ebd749a8 f86443a3 5a2cca24 b4170589 78d4b798 43004a90 40c0acff 001e36ae ba8c36ba a989bcb8 b31988e5 5831393c 9383918f c2bea19a fcb43289 1f2a2390 91ec149e dcd795f8 cfc1fa66 b96b36b5 a74ed1dc 5bc458c6 c7721441 92067e60 7193df34 dc5a2633 4d90f83b 4a107862 02473366 4cff00bd d2bd47c3 f7930b5c 75684ec7 1ea3b1fa e3f95616 8f6de468 7670e3ee 4083f4ad 7d0d766a 12c5da48 f3f8a9ff 00ebd666 a77704f1 ce81d0e6 a7ae7889 2d64f362 e9fc4beb 5b36f729 3a065340 1628a28a 0028a28a 0028a28a 0028a28a 00ffd1fa 557fe422 3fdc6fe6 2b4b159c bff2111f f5cdbf98 ad2c5002 628c52e2 8c500262 8c52e28c 50026293 14ec518a 008f1484 54845262 803ca7c7 ba98d275 ed0a7738 494dc42e 7d9c263f f1e02a8f 9c91ce92 83f76456 fd6b1be3 802134ac 1c106720 fbfc958b a2cf3ea5 043bdf62 f9425676 380020e7 27f0ab52 b22250bb b9d2c7ac 2ca5e3dd f7a3907e 686b1fc4 baa47a5e 8775229c 493af908 3d4bf5ff 00c77358 fa7c50dc de2dbdbd edbbcae1 95556552 492a4740 735c878c 2ee5b8b8 b6b67ced 553263dd 8ede7f05 a399ec2e 4573e938 23d9650a fa46a3f4 a9b4b5c6 a91fbab0 fd335246 bfe8d17f b8bfcaa4 d353fe26 711f66ff 00d04d41 a1d1c91e 6b39d24b 77f361eb dc7635b8 cb9aab24 79a0092d ae92e172 3a8ea3d2 add73ae9 241279d0 f07b8f5a d7b5ba4b 94c8e08e a3b8a00b 74514500 14514500 14514500 7fffd2fa 593fe422 3feb9b7f 315a7598 9ff2111f f5cdbf98 ad3a0028 a28a0028 a28a0028 a28a0029 b4ea4340 1e07f1c0 7c9a57d6 7ffd92b8 af00d8e3 49d66eb2 7f7be55b aa9e8779 2588fc05 76df1bbe e695f59f ff0064a6 f82ec963 f085b363 e6b8b879 0fb85040 fe754852 764451d9 c56b2c37 4b0c6861 91242ca8 0310a413 92393c57 92f8cec0 69de2dd4 edc679b8 6907b2c9 f3a8fa00 78afa09e d03215c7 504578ef c4a876f8 8e2b93d6 e6d6090f d42ecffd 969b5622 12b9f46c 6bfe8d17 fb8bfcaa 6d357fe2 6087d15a 9f127fa3 47fee2ff 002a843c b6b2f9b1 6338239f 7a8343ac 23351b2d 71971a9e adcec9b6 7d157fa8 ac69b56d 781f96ec 8ff8027f 85007a1c 91e6b2e5 8a4864f3 e0e18751 eb5c29d7 fc451759 d64f6645 fe805397 c65a947c 5ddac728 f54254fe b9a00f4d b4bc4b85 f461d47a 55daf33b 5f13e997 5206466b 69bfbb27 00fe35dd 585fc776 9d46efaf 5fa50069 51451400 51451401 ffd3fa59 3fe4223f eb9b7f31 5a75989f f2111ff5 cdbf98ad 3a0028a2 8a0028a2 8a0028a2 8a0028a2 8a00f04f 8dfc2694 7de7ff00 d92b7743 586cbc2d a589d846 b1db1776 6380371a c1f8e5c4 5a5ffdb7 fe4956bc 41a2eb3a 8d969165 a64b0470 8b6563e7 16c33055 c01b7b8c f7e2aa2c 89aba2e6 9de29f0d ead71f64 d3afe296 63d133b5 8e3d01c6 6bcefe27 c58bbd2e 623adbb4 7ff7c4ad fe358c9a 46996777 e478c56e e2d6d20f 30b308cc 0103fc85 0dbe5b77 b9f7f6ae 8be246f9 74bf0fdd c9f7a68a 46391827 3b1b2476 c9269b77 428c6cf4 3e87863f f468bfdc 5fe555a5 8bb56a5b a836b17f b8bfca9a f166a0d0 e7658335 9d25ae7b 5750f0d5 6683da80 3947b3cf 6aa72580 3dabb06b 715035b8 f4a00e0e e34a5704 15cd56b4 9352d166 1359b164 1d6363c6 3dbd2bbd 7b607b55 09ac9587 4a00ebf4 5d66db57 b6134470 c38653d5 4fa1adba f25b659b 4abc1776 fc03c3af 661fe22b d42d2e52 ea15950f 0c2802d5 1451401f ffd4fa59 3fe4223f eb9b7f31 5a75989f f2111ff5 cdbf98ad 3a0028a2 8a0028a2 8a0028a2 8a0028a2 8a00f03f 8e2331e9 63febbff 00ec950f 83fc49a4 78ab404f 0e6b376d 65796802 248b2796 cc3900a9 c8cf1c10 6ac7c6ff 00b9a57d 67ff00d9 2bc9fc37 0e88d05d bea48c65 0d1f96ca 8cd8186c f2a383d2 a9099ef1 e19f0869 be11b52b 71756af1 a8606748 3ca9dd58 e76bca5d b72f6c00 2bc5bc7d e291e27f 11116ca5 2d2cb304 40f1920f ccd8ed93 fa01567c 3de1ef11 6baa97ba 65d3dbe9 4c8420bc 90487786 c1f9412d f8d71fa9 5b4967ac 5e5b4c43 491dccaa ecbd0b07 2091ed9a 04b73ede b5ff008f 68bfdc5f e5531151 daff00c7 ac5fee2f f2a96a4a 212a2a26 8c55a229 84500516 88542d1d 6895a88a d0066b44 2abbc20d 6ab2540c 94018735 b03daaf6 8d29b790 dbb7dd3c 8ab0d1d5 674f2996 51c6d20d 00756391 4b5144db 901a9680 3fffd5fa 593fe422 3feb9b7f 315a7598 9ff2111f f5cdbf98 ad3a0028 a28a0028 a28a0028 a28a0028 a28a00f0 5f8dff00 734afacf ff00b257 27f0e2eb 5eb6b7d4 468d64b7 619a2df9 9563c603 606181dd 9f415d67 c6ff00b9 a57d67ff 00d92b8f f87763a8 de5bea06 c751fb08 568b70f2 964dc4ab 60e5beee 3d455226 5b1268d6 fa35ceac 750f125c 8d0b526b 72af636d 03e9c150 3f0e6490 ed3bbd07 5fc2bcfb 56581759 bc5b690c d10b9942 484ee2eb bce189ef 91ce6bd1 743bcb3d 3f55fb06 b167fdbf a92db166 be8676bf 0d197f95 3cb930ab b7d7a8fc 6bcef577 8e4d6af6 48a230a3 5cca5632 30501738 523b6071 402dcfb7 6d7fe3da 2ff717f9 54d51daf fc7ac5fe e2ff002a 9715250d 22929d46 28023229 8454b498 a00ae56a 32b568ad 308a00a8 5076a826 8b31b7d0 d686da6b 20208a00 5b17dd02 93e95733 59ba77fa 9c7a135a 1401ffd6 fa593fe4 223feb9b 7f315a75 989ff211 1ff5cdbf 98ad3a00 28a28a00 28a28a00 28a28a00 28a28a00 f05f8dff 00734afa cfff00b2 579ff826 0f0d4d05 eff6fcbe 5b068fcb fde6ce08 6c9f7c71 c57a07c6 ff00b9a5 7d67ff00 d92b89f0 05dc76d6 fa8799a5 4ba964c6 731c2b28 40036724 9f973ea2 a90a5b1b 7e159b5c b6db63e0 e437ba32 c4cc9717 117d9f32 17f997cc 38ce3d3f c2bcc75b 6b86d7af daed424c 6ee63228 e406321c 81f435e8 be1280eb 7702f744 d462d1ad 4c2ca34d 8ae1af25 460fcb98 6400286f 5ff1af3a d6a378b5 ebf8a593 ce75bb98 3498c6f2 24396c0f 5eb4096e 7db96bff 001eb17f b8bfcaa7 a82d7fe3 d62ff717 f954f525 098a4a75 1400ca4c 53f1498a 00662908 a9292802 3db46da9 31498a00 ced3ff00 d59fa9fe 75a159fa 7ffab3f5 3fceb428 03ffd7fa 593fe422 3feb9b7f 315a7598 9ff2111f f5cdbf98 ad3a0028 a28a0028 a28a0028 a28a0028 a28a00f0 bf8db6f2 3dae9972 a3291bca ac7d0b05 c7f235cc f80965b0 d264bcb7 d42180dd cbca490b b9531640 20ac8bd7 77715f40 788343b4 f116972e 97783e57 1956eeac 3a11f4af 9ab5af84 fe24b091 8daa7dae 2c9da632 7763dd69 a626afa1 b971e17b 5d53526d 535ff100 be98c422 c9b358f8 0723eeb8 1ebdabce 75ad2a2b 2f10cba6 594a2e15 a4428e17 6e7cd018 0db93d37 63ad4f17 c3ff0015 4ae10699 72b9eeca c07e75ec 1e06f859 3699791e adaf152f 17cd1c20 eec3762c 7dbd2982 3db2dd4a dbc6a7a8 451fa54d 4515230a 28a2800a 28a2800a 3028a280 1314b8a2 8a00cab0 ff0056df 53fceb42 b3ec3ee3 7d4ff3ad 0a00ffd0 fa593fe4 223feb9b 7f315a75 989ff211 1ff5cdbf 98ad3a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 cab0fb8d f53fceb4 2b3ec3ee 37d4ff00 3ad0a00f ffd1fa59 3fe4223f eb9b7f31 5a75989f f2111ff5 cdbf98ad 3a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a0028a2 8a00cab0 fb8df53f ceb42b3e c3ee37d4 ff003ad0 a00fffd2 fa593fe4 223feb9b 7f315a75 989ff212 1ff5cdbf 98ad3a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 28a28a00 cab0fb8d f53fceb4 2b3f4fff 0056df53 fceb4280 3fffd3fa 593fe424 3feb9b7f 315a7598 9ff2121f f5cdbf98 ad3a0028 a28a0028 a28a0028 a28a0028 a2b01bc5 5e1c4628 f7f082a7 046ee845 006fd159 16bafe89 7b2086d2 f6191cf4 50e371fa 0ea6b524 91224696 42155412 49e800a0 07d154ad b51b1bcb 63796b32 490ae72e a7206393 f95163a8 d8ea5199 ac2649d1 4ed250e7 07d2802e d1455287 52b0b8ba 92ca0991 e687efa0 3cafd450 05da28a2 800a28a2 800a28a2 800a28a2 8032b4ff 00f56df5 3fceb42b 3f4fff00 56df53fc eb42803f ffd4fa59 3fe4243f eb9b7f31 5a75989f f2121ff5 cdbf98ad 3a0028a2 8a0028a2 8a0028a2 8a0046fb a7e95e37 e06d0f4a d59f537d 46dd2664 b8c29619 c025abd9 1bee9fa5 783785ad 7c4f712e a07409e3 8504e7cc 0fdce4e3 1401d5f8 bbc21a05 ae8b3ea1 6708b59a 00195909 009c8e31 d2b5f46b bb9bdf03 f9f76497 36ee327a 9001c1ae 3f59d23c 6423173a d917f690 fcf24313 edc81df1 8c9c576f 63aae9fa af852697 4e5f2d12 07431f74 214f1401 85e08ff9 11ae3fed bffe835c 0f84f51b ef0d343a c365ac2e dcc32e3f 84a9e0fd 476fc6bb ef047fc8 8d71ff00 6dff00f4 1a83c13a 65b6b1e0 c96c2e80 2b24b260 ff0074f6 23e9401e a514b1cd 1acd110c 8e010474 20d798f8 63fe47bd 6bfddfea b4be0fd5 6e749be7 f09eb248 910fee19 ba32fa0f cb8a4f0c 7fc8f7ad 7fbbfd56 803d468a 28a0028a 28a0028a 28a0028a 28a00cad 3ffd5b7d 4ff3ad0a cfd3ff00 d5b7d4ff 003ad0a0 0fffd5fa 593fe424 3feb9b7f 315a7598 9ff2121f f5cdbf98 ad3a0028 a28a0028 a28a0028 a28a0046 fba7e95e 2fe09f10 e8fa2c9a 947a9dc0 85a4b8ca 82ac7201 6cf406bd a6b19bc3 9e1f762c da75a924 e4930a64 9fca8039 7d5be20f 8723b295 2ce63733 3a955454 61924606 4b002b3b c29a5ddd 8f85f50b abc431b5 da3b843c 1030d8e3 b6735dfd be8ba3da 3892d6ca 0898720a 46aa7f41 5a2e8922 18e450ca c3041190 41ec4500 799f823f e446b8ff 00b6ff00 fa0d5bf8 65ff0022 e7fdb67f e95dcc16 3656b01b 5b68238a 16ce6345 0aa73d78 1c734b6b 67696317 93650a41 1e73b635 0a327be0 500727e3 2f0e36af 6a2fac7e 4beb5f9e 261c16c7 3b7fc2b8 cf873777 17de23d4 2eaec626 7846f18c 7cc1941e 3b74af68 aa7069f6 16d3bdd5 bdbc51cb 2fdf7440 19b3cf24 0c9a00b9 45145001 45145001 45145001 45145006 569ffead bea7f9d6 8567e9ff 00eadbea 7f9d6850 07ffd6fa 5970ba80 2781e5b7 f315a1e6 c7fde1f9 d52bbb34 b818600d 63368701 3f707e54 01d379b1 ff00787e 7479b1ff 00787e75 cc7f6141 fdc1f951 fd8507f7 07e5401d 3f9b1ff7 87e7479b 1ff787e7 5cc7f614 1fdc1f95 1fd8507f 707e5401 d3f9b1ff 00787e74 79b1ff00 787e75cc 7f6141fd c1f951fd 8507f707 e5401d3f 9b1ff787 e7479b1f f787e75c c7f6141f dc1f951f d8507f70 7e5401d3 f9b1ff00 787e7479 b1ff0078 7e75cc7f 6141fdc1 f951fd85 07f707e5 401d3f9b 1ff787e7 479b1ff7 87e75cc7 f6141fdc 1f951fd8 507f707e 5401d3f9 b1ff0078 7e7479b1 ff00787e 75cc7f61 41fdc1f9 51fd8507 f707e540 1d3f9b1f f787e747 9b1ff787 e75cc7f6 141fdc1f 951fd850 7f707e54 01d3f9b1 ff00787e 7479b1ff 00787e75 cc7f6141 fdc1f951 fd8507f7 07e5401d 3f9b1ff7 87e7479b 1ff787e7 5cc7f614 1fdc1f95 1fd8507f 707e5401 d3f9b1ff 00787e74 7991ff00 787e75cc 7f6141fd c1f954b1 68b0a1ce c1f95006 8d803e59 fa9fe757 e990c223 5da38a9b 1401ffd9 1401ffd9 1401ffd9 1401ffd9>";
	
	return [self dataFromHexString:rawThumbnail];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_Cleartext_Cache_Cleartext
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *fileURL in enumerator)
	{
		ZDCNode *file = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cacheFileURL = nil;
		NSURL *cleartextFileURL = nil;
		
		cacheFileURL = [self _convertCleartextFile:fileURL toCacheFileFor:file error:&error];
//		NSLog(@"Result (cleartext -> cacheFile):\n"
//		      @" - cacheFileURL: %@\n"
//		      @" - error: %@",
//		      [cacheFileURL path], error);
		
		XCTAssert(cacheFileURL != nil);
		
		if (cacheFileURL)
		{
			cleartextFileURL = [self _convertCacheFile:cacheFileURL toCleartextFileFor:file error:&error];
//			NSLog(@"Result (cacheFile -> cleartext):\n"
//			      @" - cleartextFileURL: %@\n"
//			      @" - error: %@",
//			      [cleartextFileURL path], error);
			
			XCTAssert(cleartextFileURL != nil);
		}
		
		BOOL same = YES;
		
		if (cleartextFileURL)
		{
			same = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
			                                                   andPath:[cleartextFileURL path]];
			
			XCTAssert(same, @"File diff: %@", [fileURL lastPathComponent]);
		}
		
		if (cacheFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		}
		if (cleartextFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cleartextFileURL error:nil];
		}
	}
}

- (void)test_Cleartext_Cloud_Cleartext
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *fileURL in enumerator)
	{
//		if (![fileURL.lastPathComponent isEqualToString:@"Declaration of Independence.jpg"])
//		{
//			NSLog(@"SKIPPING: %@", fileURL.lastPathComponent);
//			continue;
//		}
		
//		NSLog(@"PROCESSING: %@", fileURL.lastPathComponent);
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cloudFileURL = nil;
		NSURL *cleartextFileURL = nil;
		
		cloudFileURL = [self _convertCleartextFile:fileURL toCloudFileFor:node error:&error];
//		NSLog(@"Result (cleartext -> cloudFile):\n"
//		      @" - cloudFileURL: %@\n"
//		      @" - error: %@",
//		      [cloudFileURL path], error);
		
		XCTAssert(cloudFileURL != nil);
		
		if (cloudFileURL)
		{
			cleartextFileURL = [self _convertCloudFile:cloudFileURL toCleartextFileFor:node error:&error];
//			NSLog(@"Result (cloudFile -> cleartext):\n"
//			      @" - cleartextFileURL: %@\n"
//			      @" - error: %@",
//			      [cleartextFileURL path], error);
			
			XCTAssert(cleartextFileURL != nil);
		}
		
		BOOL same = YES;
		
		if (cleartextFileURL)
		{
			same = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
			                                                   andPath:[cleartextFileURL path]];
			
			XCTAssert(same, @"File diff: %@", [fileURL lastPathComponent]);
		}
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
		if (cleartextFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cleartextFileURL error:nil];
		}
	}
}

- (void)test_Cleartext_Cache_Cloud_Cache_Cleartext
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *fileURL in enumerator)
	{
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cacheFile1URL    = nil;
		NSURL *cloudFileURL     = nil;
		NSURL *cacheFile2URL    = nil;
		NSURL *cleartextFileURL = nil;
		
		cacheFile1URL = [self _convertCleartextFile:fileURL toCacheFileFor:node error:&error];
//		NSLog(@"Result (cleartext -> cacheFile1):\n"
//		      @" - cacheFile1URL: %@\n"
//		      @" - error: %@",
//		      [cacheFile1URL path], error);
		
		XCTAssert(cacheFile1URL != nil);
		
		if (cacheFile1URL)
		{
			cloudFileURL = [self _convertCacheFile:cacheFile1URL toCloudFileFor:node error:&error];
//			NSLog(@"Result (cacheFile1 -> cloudFile):\n"
//			      @" - cloudFileURL: %@\n"
//			      @" - error: %@",
//			      [cloudFileURL path], error);
			
			XCTAssert(cloudFileURL != nil);
		}
		
		if (cloudFileURL)
		{
			cacheFile2URL = [self _convertCloudFile:cloudFileURL toCacheFileFor:node error:&error];
//			NSLog(@"Result (cloudFile -> cacheFile2URL):\n"
//			      @" - cacheFile2URL: %@\n"
//			      @" - error: %@",
//			      [cacheFile2URL path], error);
			
			XCTAssert(cacheFile2URL != nil);
		}
		
		if (cacheFile1URL && cacheFile2URL)
		{
			BOOL same = [[NSFileManager defaultManager] contentsEqualAtPath:[cacheFile1URL path]
			                                                        andPath:[cacheFile2URL path]];
			
			XCTAssert(same, @"CacheFile diff: \"%@\" vs \"%@\"", [cacheFile1URL path], [cacheFile2URL path]);
		}
		
		if (cacheFile2URL)
		{
			cleartextFileURL = [self _convertCacheFile:cacheFile2URL toCleartextFileFor:node error:&error];
//			NSLog(@"Result (cacheFile2URL -> cleartext):\n"
//					@" - cleartextFileURL: %@\n"
//					@" - error: %@",
//					[cleartextFileURL path], error);
			
			XCTAssert(cleartextFileURL != nil);
		}
		
		if (cleartextFileURL)
		{
			BOOL same = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
			                                                        andPath:[cleartextFileURL path]];
			
			XCTAssert(same, @"File diff: %@", [fileURL lastPathComponent]);
		}
		
		if (cacheFile1URL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFile1URL error:nil];
		}
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
		if (cacheFile2URL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFile2URL error:nil];
		}
		if (cleartextFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cleartextFileURL error:nil];
		}
	}
}

- (NSURL *)_convertCleartextFile:(NSURL *)cleartextFileURL
                  toCacheFileFor:(ZDCNode *)node
                           error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion encryptCleartextFile: cleartextFileURL
	                     toCacheFileWithKey: node.encryptionKey
	                        completionQueue: bgQueue
	                        completionBlock:^(ZDCCryptoFile *cryptoFile, NSError *error)
	{
		outFileURL = cryptoFile.fileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

- (NSURL *)_convertCleartextFile:(NSURL *)cleartextFileURL
                  toCloudFileFor:(ZDCNode *)node
                           error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion encryptCleartextFile: cleartextFileURL
	                     toCloudFileWithKey: node.encryptionKey
	                               metadata: nil
	                              thumbnail: nil
	                        completionQueue: bgQueue
	                        completionBlock:^(ZDCCryptoFile *cryptoFile, NSError *error)
	{
		outFileURL = cryptoFile.fileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

- (NSURL *)_convertCacheFile:(NSURL *)cacheFileURL
          toCleartextFileFor:(ZDCNode *)node
                       error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion decryptCacheFile: cacheFileURL
	                      encryptionKey: node.encryptionKey
	                        retainToken: nil
	                    completionQueue: bgQueue
	                    completionBlock:^(NSURL *outputFileURL, NSError *error)
	{
		outFileURL = outputFileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

- (NSURL *)_convertCacheFile:(NSURL *)cacheFileURL
              toCloudFileFor:(ZDCNode *)node
                       error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion convertCacheFile: cacheFileURL
	                        retainToken: nil
	                      encryptionKey: node.encryptionKey
	                 toCloudFileWithKey: node.encryptionKey
	                           metadata: nil
	                          thumbnail: nil
	                    completionQueue: bgQueue
	                    completionBlock:^(NSURL *outputFileURL, NSError *error)
	{
		outFileURL = outputFileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

- (NSURL *)_convertCloudFile:(NSURL *)cloudFileURL
          toCleartextFileFor:(ZDCNode *)node
                       error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion decryptCloudFile: cloudFileURL
	                      encryptionKey: node.encryptionKey
	                        retainToken: nil
	                    completionQueue: bgQueue
	                    completionBlock:^(ZDCCloudFileHeader headerInfo,
	                                      NSData *metadata, NSData *thumbnail,
	                                      NSURL *outputFileURL, NSError *error)
	{
		outFileURL = outputFileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

- (NSURL *)_convertCloudFile:(NSURL *)cloudFileURL
              toCacheFileFor:(ZDCNode *)node
                       error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion convertCloudFile: cloudFileURL
	                        retainToken: nil
	                      encryptionKey: node.encryptionKey
	                 toCacheFileWithKey: node.encryptionKey
	                    completionQueue: bgQueue
	                    completionBlock:^(ZDCCloudFileHeader headerInfo,
	                                      NSData *metadata, NSData *thumbnail,
	                                      NSURL *outputFileURL, NSError *error)
	{
		outFileURL = outputFileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

- (NSURL *)_reEncryptFile:(NSURL *)fileURL fromKey:(NSData *)srcKey toKey:(NSData *)dstKey error:(NSError **)errorPtr
{
	__block NSURL *outFileURL = nil;
	__block NSError *outError = nil;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	[ZDCFileConversion reEncryptFile: fileURL
	                        fromKey: srcKey
	                          toKey: dstKey
	                completionQueue: bgQueue
	                completionBlock:^(NSURL *dstFileURL, NSError *error)
	{
		outFileURL = dstFileURL;
		outError = error;
		
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	if (errorPtr) *errorPtr = outError;
	return outFileURL;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_infiniteLoop_badData
{
	NSString *str =
	  @"<1c6d1fd1 ac70bcc9 36712233 fa9ad220 87bc0700 b6a88e54 80a7692a c7330cde 1f5f4c6c eb065436 1d1e4146 ddff1af1 4fbd28ca c8833640 c61728ab f5d3d992 e6162fdf d5b81822 0df96b65 e9227710 fa80cd4a 555dd08b 1802aee5 6b6dcfbd b044d4a9 b96f2e46 d850e436 e356de02 976c3b7c 10a6d2ec 54825e3d b939abbb 39e000cf 72890ce3 9c6cdb7e ca4e4df5 9af9a107 d8b2aef4 f6831b69 9fce2bb3 c2df076e b02d110c a4b9f453 fecf003a 68220ee6 b937c4a9 b9b6c47b 9dc67f03 cfd46c81 957b70bc 6ab192dd 5982a005 ef4b7b50 5afc5cac a89aefd2 f0eb9c9d fb257ce2 a694451a db57b97e de72ceea 2e0e9fee 1128722d 28efb2fa 17c0c9f3 1da62dd5 30dd819f dbecbc92 aef7ef0a 39695a11 ee0a3e74 f58cd885 509c6fc4 71da7f1d bb71a0f6 758e9810 7e009df1 8139e1d1 a215173f a0948198 62b98821>";
	
	NSData *downloadedData = [self dataFromHexString:str];
	NSLog(@"downloadedData: %@", downloadedData);
	
	str = @"<d85e8c65 5a672642 3508adc7 9593cb01 51ca22a1 07c1b96d 41988626 8b955818 a9c6d476 babf066d f3594292 da005744 d4206e92 8838e374 bbd6e9e4 d9f1d895>";
	
	NSData *encryptionKeyData = [self dataFromHexString:str];
	NSLog(@"encryptionKeyData: %@", encryptionKeyData);
	
	ZDCCloudFileHeader headerInfo;
	bzero(&headerInfo, sizeof(headerInfo));
	
	NSData *rawMetadata = nil;
	NSData *rawThumbnail = nil;
	NSError *error = nil;
	
	// The given data includes:
	// - header
	// - metadata
	// - truncated thumbnail
	//
	// This occurs when we don't need to re-fetch the thumbnail, because its xxHash hasn't changed.
	// It's truncated because we needed to align the size to blockSize.
	//
	// This code used to get into an infinite loop.
	// This check assures the code won't infinite loop.
	
	BOOL result =
	  [CloudFile2CleartextInputStream decryptCloudFileData: downloadedData
	                                     withEncryptionKey: encryptionKeyData
	                                                header: &headerInfo
	                                           rawMetadata: &rawMetadata
	                                          rawThumbnail: &rawThumbnail
	                                                 error: &error];
	
	XCTAssert(result == NO);
	XCTAssert(error != nil);
	XCTAssert(error.code == ZDCStreamUnexpectedFileSize);
	
	XCTAssert(rawMetadata != nil);
	XCTAssert(rawThumbnail == nil);
}

- (void)test_infiniteLoop_prematureEnd
{
	NSString *str =
	  @"<1c6d1fd1>";
	
	NSData *downloadedData = [self dataFromHexString:str];
	NSLog(@"downloadedData: %@", downloadedData);
	
	str = @"<d85e8c65 5a672642 3508adc7 9593cb01 51ca22a1 07c1b96d 41988626 8b955818 a9c6d476 babf066d f3594292 da005744 d4206e92 8838e374 bbd6e9e4 d9f1d895>";
	
	NSData *encryptionKeyData = [self dataFromHexString:str];
	NSLog(@"encryptionKeyData: %@", encryptionKeyData);
	
	ZDCCloudFileHeader headerInfo;
	bzero(&headerInfo, sizeof(headerInfo));
	
	NSData *rawMetadata = nil;
	NSData *rawThumbnail = nil;
	NSError *error = nil;
	
	// The given data includes:
	// - header
	// - metadata
	// - truncated thumbnail
	//
	// This occurs when we don't need to re-fetch the thumbnail, because its xxHash hasn't changed.
	// It's truncated because we needed to align the size to blockSize.
	//
	// This code used to get into an infinite loop.
	// This check assures the code won't infinite loop.
	
	BOOL result =
	  [CloudFile2CleartextInputStream decryptCloudFileData: downloadedData
	                                     withEncryptionKey: encryptionKeyData
	                                                header: &headerInfo
	                                           rawMetadata: &rawMetadata
	                                          rawThumbnail: &rawThumbnail
	                                                 error: &error];
	
	XCTAssert(result == NO);
	XCTAssert(error != nil);
	XCTAssert(error.code == ZDCStreamUnexpectedFileSize);
	
	XCTAssert(rawMetadata == nil);
	XCTAssert(rawThumbnail == nil);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_truncatedCleartextFile
{
	uint64_t cleartext_size = 1024 * 1024 * 1;
	NSURL *cleartextFileURL = [self generateRandomFile:cleartext_size];
	
	// Cleartext2CacheFileInputStream
	{
		NSData *encryptionKey = [self dataFromHexString:
			@"<d85e8c65 5a672642 3508adc7 9593cb01 51ca22a1 07c1b96d 41988626 8b955818 a9c6d476 babf066d f3594292 da005744 d4206e92 8838e374 bbd6e9e4 d9f1d895>"];
		
		Cleartext2CacheFileInputStream *stream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL:cleartextFileURL encryptionKey:encryptionKey];
		stream.cleartextFileSize = @(cleartext_size / 2);
		
		NSError *error = nil;
		[self writeStream:stream error:&error];
		
		XCTAssert(error != nil);
		XCTAssert(error.code == ZDCStreamUnexpectedFileSize);
	}
	
	// Cleartext2CloudFileInputStream
	{
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		Cleartext2CloudFileInputStream *stream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		stream.cleartextFileSize = @(cleartext_size / 2);
		
		NSError *error = nil;
		[self writeStream:stream error:&error];
		
		XCTAssert(error != nil);
		XCTAssert(error.code == ZDCStreamUnexpectedFileSize);
	}
	
	if (cleartextFileURL) {
		[[NSFileManager defaultManager] removeItemAtURL:cleartextFileURL error:nil];
	}
}

- (void)test_truncatedCacheFile
{
	uint64_t cleartext_size = 1024 * 1024 * 1;
	NSURL *cleartextFileURL = [self generateRandomFile:cleartext_size];
	
	NSData *encryptionKey = [self dataFromHexString:
		@"<d85e8c65 5a672642 3508adc7 9593cb01 51ca22a1 07c1b96d 41988626 8b955818 a9c6d476 babf066d f3594292 da005744 d4206e92 8838e374 bbd6e9e4 d9f1d895>"];
	
	NSURL *cacheFileURL = nil;
	
	// Convert to cacheFile
	{
		Cleartext2CacheFileInputStream *stream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL:cleartextFileURL encryptionKey:encryptionKey];
		
		NSError *error = nil;
		cacheFileURL = [self writeStream:stream error:&error];
		
		XCTAssert(error == nil);
	}
	
	// Read truncated cacheFile
	{
		ZDCInterruptingInputStream *iStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
		[iStream setProperty:@(cleartext_size / 2) forKey:ZDCStreamFileMaxOffset];
		
		CacheFile2CleartextInputStream *stream =
		  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream:iStream encryptionKey:encryptionKey];
		
		NSError *error = nil;
		[self writeStream:stream error:&error];
		
		XCTAssert(error != nil);
		XCTAssert(error.code == ZDCStreamUnexpectedFileSize);
	}
	
	if (cleartextFileURL) {
		[[NSFileManager defaultManager] removeItemAtURL:cleartextFileURL error:nil];
	}
	if (cacheFileURL) {
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
	}
}

- (void)test_truncatedCloudFile
{
	uint64_t cleartext_size = 1024 * 1024 * 1;
	NSURL *cleartextFileURL = [self generateRandomFile:cleartext_size];
	
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	NSURL *cloudFileURL = nil;
	
	// Convert to cloudFile
	{
		Cleartext2CloudFileInputStream *stream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		NSError *error = nil;
		cloudFileURL = [self writeStream:stream error:&error];
		
		XCTAssert(error == nil);
	}
	
	// Read truncated cloudFile
	{
		ZDCInterruptingInputStream *iStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:cloudFileURL];
		[iStream setProperty:@(cleartext_size / 2) forKey:ZDCStreamFileMaxOffset];
		
		CloudFile2CleartextInputStream *stream =
		  [[CloudFile2CleartextInputStream alloc] initWithCloudFileStream: iStream
		                                                    encryptionKey: node.encryptionKey];
		
		NSError *error = nil;
		[self writeStream:stream error:&error];
		
		XCTAssert(error != nil);
		XCTAssert(error.code == ZDCStreamUnexpectedFileSize);
	}
	
	if (cleartextFileURL) {
		[[NSFileManager defaultManager] removeItemAtURL:cleartextFileURL error:nil];
	}
	if (cloudFileURL) {
		[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
	}
}

- (void)test_readCloudFileHeader
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	node.encryptionKey = [self sample_raw_key];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		Cleartext2CloudFileInputStream *stream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		NSURL *cloudFileURL = [self writeStream:stream error:nil];
		XCTAssert(cloudFileURL != nil);
		
		NSData *cloudFileData = [NSData dataWithContentsOfURL:cloudFileURL];
		XCTAssert(cloudFileURL != nil);
		
		NSUInteger length = 0;
		length += sizeof(ZDCCloudFileHeader);
		
		XCTAssert(length > 0);
		
		NSData *partialCloudFileData = [cloudFileData subdataWithRange:NSMakeRange(0, length)];
		XCTAssert(cloudFileURL != nil);
		
		ZDCCloudFileHeader headerInfo;
		NSError *error = nil;
		
		BOOL result =
		  [CloudFile2CleartextInputStream decryptCloudFileData: partialCloudFileData
		                                     withEncryptionKey: node.encryptionKey
		                                                header: &headerInfo
		                                           rawMetadata: NULL
		                                          rawThumbnail: NULL
		                                                 error: &error];
		
		XCTAssert(result == YES);
		XCTAssert(error == nil);
		
		XCTAssert(headerInfo.dataSize == cleartextFileSize);
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

- (void)test_readCloudFilePartial
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	node.encryptionKey = [self sample_raw_key];
	
	NSData *rawMetadata = [self sample_raw_metadata];
	NSData *rawThumbnail = [self sample_raw_thumbnail];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		Cleartext2CloudFileInputStream *stream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		stream.rawMetadata = rawMetadata;
		stream.rawThumbnail = rawThumbnail;
		
		NSURL *cloudFileURL = [self writeStream:stream error:nil];
		XCTAssert(cloudFileURL != nil);
		
		NSData *cloudFileData = [NSData dataWithContentsOfURL:cloudFileURL];
		XCTAssert(cloudFileURL != nil);
		
		NSUInteger length = 0;
		length += sizeof(ZDCCloudFileHeader);
		length += rawMetadata.length;
		length += rawThumbnail.length;
		
		if (length < kZDCNode_EncryptionKeySizeInBytes)
		{
			length = kZDCNode_EncryptionKeySizeInBytes;
		}
		else if ((length % kZDCNode_EncryptionKeySizeInBytes) != 0)
		{
			NSUInteger multiplier = (NSUInteger)(length / kZDCNode_EncryptionKeySizeInBytes) + 1;
			length =  multiplier * kZDCNode_EncryptionKeySizeInBytes;
		}
		
		XCTAssert(length > 0);
		
		NSData *partialCloudFileData = [cloudFileData subdataWithRange:NSMakeRange(0, length)];
		XCTAssert(cloudFileURL != nil);
		
		NSData *extractedMetadata = nil;
		NSData *extractedThumbnail = nil;
		NSError *error = nil;
		
		BOOL result =
		  [CloudFile2CleartextInputStream decryptCloudFileData: partialCloudFileData
		                                     withEncryptionKey: node.encryptionKey
		                                                header: NULL
		                                           rawMetadata: &extractedMetadata
		                                          rawThumbnail: &extractedThumbnail
		                                                 error: &error];
		
		XCTAssert(result == YES);
		XCTAssert(error == nil);
		
		XCTAssert(extractedMetadata != nil);
		XCTAssert(extractedThumbnail != nil);
		
		XCTAssert([extractedMetadata isEqualToData:rawMetadata]);
		XCTAssert([extractedThumbnail isEqualToData:rawThumbnail]);
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_seek_CacheFile2CleartextInputStream
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
//		if (![cleartextFileURL.lastPathComponent isEqualToString:@"Tiny File.txt"])
//		{
//			NSLog(@"SKIPPING: %@", cleartextFileURL.lastPathComponent);
//			continue;
//		}
		
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cache file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cacheFileURL = nil;
		
		cacheFileURL = [self _convertCleartextFile:cleartextFileURL toCacheFileFor:node error:&error];
		
		XCTAssert(cacheFileURL != nil);
		
		// Pick random ranges (of cleartext output), and ensure seeking works properly.
		
		for (NSUInteger i = 0; i < 10; i++)
		{ @autoreleasepool {
			
			NSRange range = [self randomRangeForFileSize:cleartextFileSize withMaxLength:512];
			
			ZDCInterruptingInputStream *underlyingStream = nil;
			CacheFile2CleartextInputStream *inputStream = nil;
			
			underlyingStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
		
			inputStream = [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: underlyingStream
			                                                                encryptionKey: node.encryptionKey];
			
			BOOL rangeReadMatches =
			  [self compareRange:range
			           ofRawFile:cleartextFileURL
			          withStream:inputStream];

			XCTAssert(rangeReadMatches,
						 @"SEEK broken for range(%@) file(%@)", NSStringFromRange(range), cleartextFileURL.lastPathComponent);
		}}
		
		if (cacheFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		}
	}
}

- (void)test_seek_Cleartext2CloudFileInputStream
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	[[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
								includingPropertiesForKeys:nil
														 options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
												  errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
//		if (![cleartextFileURL.lastPathComponent isEqualToString:@"Tiny File.txt"])
//		{
//			NSLog(@"SKIPPING: %@", cleartextFileURL.lastPathComponent);
//			continue;
//		}
		
		// Convert cleartext to cloud file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
//		NSString *str = @"<c2473bd8 047cca26 e33b465d c26dd806 eae932ea 211fc2e4 05aacf3a 7626cb5b f0c76d33 9c527cb9 927a2cf3 1d5c38a8 5f10fbf1 e2f2ac52 044293ec ed7a028f>";
//		file.encryptionKey = [self dataFromHexString:str];
		
		NSURL *cloudFileURL = [self _convertCleartextFile:cleartextFileURL toCloudFileFor:node error:nil];
		
		XCTAssert(cloudFileURL != nil);
		
		// Fetch size of cleartext file
		
		uint64_t cloudFileSize = 0;
		
		NSNumber *number = nil;
		if ([cloudFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cloudFileSize = [number unsignedLongLongValue];
		}
		
		// Pick random ranges (of cleartext output), and ensure seeking works properly.
		
		for (NSUInteger i = 0; i < 10; i++)
		{ @autoreleasepool {
			
			NSRange range = [self randomRangeForFileSize:cloudFileSize withMaxLength:512];
			
			Cleartext2CloudFileInputStream *inputStream =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
			                                                     encryptionKey: node.encryptionKey];
			
			BOOL rangeReadMatches =
			  [self compareRange:range
			           ofRawFile:cloudFileURL
			          withStream:inputStream];

			XCTAssert(rangeReadMatches,
						 @"SEEK broken for range(%@) file(%@)", NSStringFromRange(range), cleartextFileURL.lastPathComponent);
		}}
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

- (void)test_seek_CloudFile2CleartextInputStream
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	[[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
								includingPropertiesForKeys:nil
														 options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
												  errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
//		if (![cleartextFileURL.lastPathComponent isEqualToString:@"Tiny File.txt"])
//		{
//			NSLog(@"SKIPPING: %@", cleartextFileURL.lastPathComponent);
//			continue;
//		}
		
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cache file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
//		file.encryptionKey = [self dataFromHexString:@"<c2473bd8 047cca26 e33b465d c26dd806 eae932ea 211fc2e4 05aacf3a 7626cb5b f0c76d33 9c527cb9 927a2cf3 1d5c38a8 5f10fbf1 e2f2ac52 044293ec ed7a028f>"];
		
		NSError *error = nil;
		NSURL *cloudFileURL = nil;
		
		cloudFileURL = [self _convertCleartextFile:cleartextFileURL toCloudFileFor:node error:&error];
		
		XCTAssert(cloudFileURL != nil);
		
		// Pick random ranges (of cleartext output), and ensure seeking works properly.
		
		for (NSUInteger i = 0; i < 10; i++)
		{ @autoreleasepool {
			
			NSRange range = [self randomRangeForFileSize:cleartextFileSize withMaxLength:512];
//			range = NSMakeRange(19, 1);
			
		#if 0 // Test class only
			
			CloudFile2CleartextInputStream *inputStream =
			  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: cloudFileURL
			                                                 encryptionKey: node.encryptionKey];
			
		#else // Test with real conditions
			
			ZDCInterruptingInputStream *underlyingStream = nil;
			CloudFile2CleartextInputStream *inputStream = nil;
			
			underlyingStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:cloudFileURL];
			
			inputStream =
			  [[CloudFile2CleartextInputStream alloc] initWithCloudFileStream: underlyingStream
			                                                    encryptionKey: node.encryptionKey];
			
		#endif
			
			[inputStream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
			
			BOOL rangeReadMatches =
			  [self compareRange:range
			           ofRawFile:cleartextFileURL
			          withStream:inputStream];

			XCTAssert(rangeReadMatches,
			  @"SEEK broken for range(%@) file(%@)",
			  NSStringFromRange(range),
			  cleartextFileURL.lastPathComponent);
		}}
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

- (BOOL)compareRange:(NSRange)range
           ofRawFile:(NSURL *)rawFileURL
          withStream:(ZDCInputStream *)zdcInputStream
{
	NSData *data1 = [self readRange:range ofFile:rawFileURL error:nil];
	NSData *data2 = [self readRange:range ofStream:zdcInputStream error:nil];
	
	return [data1 isEqual:data2];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_split_2
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSURL *cacheFileURL = [self _convertCleartextFile:fileURL toCacheFileFor:node error:nil];
		
		NSArray<NSURL *> *parts = [self splitConvertCacheFile:cacheFileURL node:node];
		
		NSURL *cloudFileURL = [self combineParts:parts];
		
		NSURL *clearFileURL = [self _convertCloudFile:cloudFileURL toCleartextFileFor:node error:nil];
		
		BOOL same = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                        andPath:[clearFileURL path]];
		
		XCTAssert(same, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clearFileURL error:nil];
		
		for (NSURL *partURL in parts) {
			[[NSFileManager defaultManager] removeItemAtURL:partURL error:nil];
		}
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

- (NSArray<NSURL *> *)splitConvertCacheFile:(NSURL *)cacheFileURL node:(ZDCNode *)node
{
	NSMutableArray<NSURL *> *results = [NSMutableArray array];
	
	NSUInteger const chunkSize = (1024 * 1024 * 5);
	
	NSURL* (^ReadRange)(NSRange range) = ^NSURL* (NSRange range){
		
		uint8_t *buffer = (uint8_t *)malloc(chunkSize);
		NSUInteger bufferOffset = 0;
		
		ZDCInterruptingInputStream *s1 = nil;
		CacheFile2CleartextInputStream *s2 = nil;
		Cleartext2CloudFileInputStream *s3 = nil;
		
		s1 = [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
		
		s2 = [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream:s1 encryptionKey:node.encryptionKey];
		
		s3 = [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream:s2 encryptionKey:node.encryptionKey];
	
		uint64_t min = range.location;
		uint64_t max = range.location + range.length;
		
		[s3 setProperty:@(min) forKey:ZDCStreamFileMinOffset];
		[s3 setProperty:@(max) forKey:ZDCStreamFileMaxOffset];
		
		NSInputStream *inputStream = [s3 copy];
		
		[inputStream open];
		if (inputStream.streamError)
		{
			NSLog(@"Error opening stream: %@", inputStream.streamError);
			return nil;
		}
		
		BOOL done = NO;
		while (!done)
		{
			NSInteger bytesRead = [inputStream read:(buffer + bufferOffset) maxLength:(chunkSize - bufferOffset)];
			
			if (bytesRead < 0)
			{
				NSLog(@"Error reading stream: %@", inputStream.streamError);
				return nil;
			}
			else
			{
				bufferOffset+= bytesRead;
				
				done = (bytesRead == 0);
			}
		}
		
		NSData *data = [NSData dataWithBytesNoCopy:buffer length:bufferOffset freeWhenDone:YES];
		
		NSURL *partURL = [self randomFileURL];
		[data writeToURL:partURL atomically:NO];
		
		return partURL;
	};
	
	uint64_t cacheFileSize = 0;
	
	NSNumber *number = nil;
	if ([cacheFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
	{
		cacheFileSize = [number unsignedLongLongValue];
	}
	
	NSUInteger offset = 0;
	while (offset < cacheFileSize)
	{
		NSUInteger length = MIN(chunkSize, (cacheFileSize - offset));
		
		NSRange range = NSMakeRange(offset, length);
		
		NSURL *partURL = ReadRange(range);
		if (partURL) {
			[results addObject:partURL];
		}
		
		offset += length;
	}
	
	return results;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_split_1
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSURL *cacheFileURL = [self _convertCleartextFile:fileURL toCacheFileFor:node error:nil];
		
//		uint64_t size_header =       64;
//		uint64_t size_meta   =      179;
//		uint64_t size_thumb  =    12276;
//		uint64_t size_file   = 10485760;
//		uint64_t size_pad    =       25;
		
		NSRange range0 = NSMakeRange(0, 5230361);
		NSRange range1 = NSMakeRange(NSMaxRange(range0), 5242880);
		NSRange range2 = NSMakeRange(NSMaxRange(range1), 12519);
		
		NSMutableArray<NSURL *> *parts = [NSMutableArray arrayWithCapacity:3];
		
		[parts addObject:[self readCacheFile:cacheFileURL node:node range:range0]];
		[parts addObject:[self readCacheFile:cacheFileURL node:node range:range1]];
		[parts addObject:[self readCacheFile:cacheFileURL node:node range:range2]];
		
		NSURL *clearFileURL = [self combineParts:parts];
		
		BOOL same = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
																				  andPath:[clearFileURL path]];
		
		XCTAssert(same, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clearFileURL error:nil];
		
		for (NSURL *partURL in parts) {
			[[NSFileManager defaultManager] removeItemAtURL:partURL error:nil];
		}
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

- (NSURL *)readCacheFile:(NSURL *)cacheFileURL node:(ZDCNode *)node range:(NSRange)range
{
//	ZDCInterruptingInputStream *s1 = [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
	
	CacheFile2CleartextInputStream *inputStream =
	  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL:cacheFileURL encryptionKey:node.encryptionKey];
//	  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream:s1 encryptionKey:node.encryptionKey];
	
//	[inputStream setProperty:@(range.location) forKey:NSStreamFileCurrentOffsetKey];
	
	NSURL *outURL = [self randomFileURL];
	NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:outURL append:NO];
	
	size_t bufferSize = 1024 * 1024 * 1;
	uint8_t *buffer = (uint8_t *)malloc(bufferSize);
	
	[inputStream open];
	[outputStream open];
	
	[inputStream setProperty:@(range.location) forKey:NSStreamFileCurrentOffsetKey];
	
	NSInteger loopBytesRead = 0;
	BOOL done = NO;
	do
	{
		NSInteger byteToRead = MIN(bufferSize, (range.length - loopBytesRead));
		NSInteger bytesRead = [inputStream read:buffer maxLength:byteToRead];
		
		if (bytesRead < 0)
		{
			NSLog(@"Error reading stream: %@", inputStream.streamError);
			return nil;
		}
		
		loopBytesRead += bytesRead;
		
		NSInteger loopBytesWritten = 0;
		while (loopBytesWritten < bytesRead)
		{
			NSInteger bytesWritten =
			  [outputStream write:(buffer + loopBytesWritten)
			            maxLength:(bytesRead - loopBytesWritten)];
			
			if (bytesWritten < 0)
			{
				NSLog(@"Error writing stream: %@", outputStream.streamError);
				return nil;
			}
			
			loopBytesWritten += bytesWritten;
		}
		
		done = ((bytesRead == 0) && (inputStream.streamStatus == NSStreamStatusAtEnd)) || (loopBytesRead >= range.length);
		
	} while (!done);
	
	[inputStream close];
	[outputStream close];
	
	return outURL;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_multipart_1
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		node.encryptionKey = [self sample_raw_key];
		
		NSURL *url_full = nil;
		NSURL *url_part0 = nil;
		NSURL *url_part1 = nil;
		NSURL *url_part2 = nil;
		
		{
			Cleartext2CloudFileInputStream *stream_full =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL:fileURL encryptionKey:node.encryptionKey];
			
			stream_full.rawMetadata = [self sample_raw_metadata];
			stream_full.rawThumbnail = [self sample_raw_thumbnail];
			
			url_full = [self writeStream:stream_full error:NULL];
		}
		
		NSRange range_part0 = NSMakeRange(0, 5242880);
		NSRange range_part1 = NSMakeRange(NSMaxRange(range_part0), 5242880);
		NSRange range_part2 = NSMakeRange(NSMaxRange(range_part1), 5242880);
		
		{
			Cleartext2CloudFileInputStream *stream_part0 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL:fileURL encryptionKey:node.encryptionKey];
			
			stream_part0.rawMetadata = [self sample_raw_metadata];
			stream_part0.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part0 setProperty:@(range_part0.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part0 setProperty:@(NSMaxRange(range_part0)) forKey:ZDCStreamFileMaxOffset];
			
			url_part0 = [self writeStream:stream_part0 error:NULL];
		}
		
		{
			Cleartext2CloudFileInputStream *stream_part1 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL:fileURL encryptionKey:node.encryptionKey];
			
			stream_part1.rawMetadata = [self sample_raw_metadata];
			stream_part1.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part1 setProperty:@(range_part1.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part1 setProperty:@(NSMaxRange(range_part1)) forKey:ZDCStreamFileMaxOffset];
			
			url_part1 = [self writeStream:stream_part1 error:NULL];
		}
		
		{
			Cleartext2CloudFileInputStream *stream_part2 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL:fileURL encryptionKey:node.encryptionKey];
			
			stream_part2.rawMetadata = [self sample_raw_metadata];
			stream_part2.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part2 setProperty:@(range_part2.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part2 setProperty:@(NSMaxRange(range_part2)) forKey:ZDCStreamFileMaxOffset];
			
			url_part2 = [self writeStream:stream_part2 error:NULL];
		}
		
		NSArray<NSURL *> *parts = @[url_part0, url_part1, url_part2];
		NSURL *url_multi = [self combineParts:parts];
		
		BOOL same1 = [[NSFileManager defaultManager] contentsEqualAtPath:[url_full path]
		                                                         andPath:[url_multi path]];
		
		XCTAssert(same1, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_part0 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part2 error:nil];
		
		NSURL *clear_full = [self _convertCloudFile:url_full toCleartextFileFor:node error:nil];
		NSURL *clear_multi = [self _convertCloudFile:url_multi toCleartextFileFor:node error:nil];
		
		BOOL same2 = [[NSFileManager defaultManager] contentsEqualAtPath:[clear_full path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same2, @"Uh Oh SpaghettiOs !");
		
		BOOL same3 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same3, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:clear_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clear_multi error:nil];
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

- (void)test_multipart_2
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		NSNumber *cleartextFileSize = nil;
		[fileURL getResourceValue:&cleartextFileSize forKey:NSURLFileSizeKey error:nil];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		node.encryptionKey = [self sample_raw_key];
		
		NSURL *url_full = nil;
		NSURL *url_part0 = nil;
		NSURL *url_part1 = nil;
		NSURL *url_part2 = nil;
		
		{
			NSInputStream *inStream = [[NSInputStream alloc] initWithURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_full =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_full.cleartextFileSize = cleartextFileSize;
			
			stream_full.rawMetadata = [self sample_raw_metadata];
			stream_full.rawThumbnail = [self sample_raw_thumbnail];
			
			url_full = [self writeStream:stream_full error:NULL];
		}
		
		NSRange range_part0 = NSMakeRange(0, 5242880);
		NSRange range_part1 = NSMakeRange(NSMaxRange(range_part0), 5242880);
		NSRange range_part2 = NSMakeRange(NSMaxRange(range_part1), 5242880);
		
		{
			NSInputStream *inStream = [[NSInputStream alloc] initWithURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_part0 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part0.cleartextFileSize = cleartextFileSize;
			
			stream_part0.rawMetadata = [self sample_raw_metadata];
			stream_part0.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part0 setProperty:@(range_part0.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part0 setProperty:@(NSMaxRange(range_part0)) forKey:ZDCStreamFileMaxOffset];
			
			url_part0 = [self writeStream:stream_part0 error:NULL];
		}
		
		{
			NSInputStream *inStream = [[NSInputStream alloc] initWithURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_part1 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part1.cleartextFileSize = cleartextFileSize;
			
			stream_part1.rawMetadata = [self sample_raw_metadata];
			stream_part1.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part1 setProperty:@(range_part1.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part1 setProperty:@(NSMaxRange(range_part1)) forKey:ZDCStreamFileMaxOffset];
			
			url_part1 = [self writeStream:stream_part1 error:NULL];
		}
		
		{
			NSInputStream *inStream = [[NSInputStream alloc] initWithURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_part2 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part2.cleartextFileSize = cleartextFileSize;
			
			stream_part2.rawMetadata = [self sample_raw_metadata];
			stream_part2.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part2 setProperty:@(range_part2.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part2 setProperty:@(NSMaxRange(range_part2)) forKey:ZDCStreamFileMaxOffset];
			
			url_part2 = [self writeStream:stream_part2 error:NULL];
		}
		
		NSArray<NSURL *> *parts = @[url_part0, url_part1, url_part2];
		NSURL *url_multi = [self combineParts:parts];
		
		BOOL same1 = [[NSFileManager defaultManager] contentsEqualAtPath:[url_full path]
		                                                         andPath:[url_multi path]];
		
		XCTAssert(same1, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_part0 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part2 error:nil];
		
		NSURL *clear_full = [self _convertCloudFile:url_full toCleartextFileFor:node error:nil];
		NSURL *clear_multi = [self _convertCloudFile:url_multi toCleartextFileFor:node error:nil];
		
		BOOL same2 = [[NSFileManager defaultManager] contentsEqualAtPath:[clear_full path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same2, @"Uh Oh SpaghettiOs !");
		
		BOOL same3 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same3, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:clear_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clear_multi error:nil];
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

- (void)test_multipart_3
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
//	NSURL *fileURL = [NSURL fileURLWithPath:
//	  @"/var/folders/wm/kll_j5h575x407863mg481f00000gn/T/FC459B69-AC3A-4490-989B-580B6DF13161"];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		NSNumber *cleartextFileSize = nil;
		[fileURL getResourceValue:&cleartextFileSize forKey:NSURLFileSizeKey error:nil];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		node.encryptionKey = [self sample_raw_key];
		
		NSURL *url_full = nil;
		NSURL *url_part0 = nil;
		NSURL *url_part1 = nil;
		NSURL *url_part2 = nil;
		
		{
			ZDCInterruptingInputStream *inStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_full =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_full.cleartextFileSize = cleartextFileSize;
			
			stream_full.rawMetadata = [self sample_raw_metadata];
			stream_full.rawThumbnail = [self sample_raw_thumbnail];
			
			url_full = [self writeStream:stream_full error:NULL];
		}
		
		NSRange range_part0 = NSMakeRange(0, 5242880);
		NSRange range_part1 = NSMakeRange(NSMaxRange(range_part0), 5242880);
		NSRange range_part2 = NSMakeRange(NSMaxRange(range_part1), 5242880);
		
		{
			ZDCInterruptingInputStream *inStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_part0 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part0.cleartextFileSize = cleartextFileSize;
			
			stream_part0.rawMetadata = [self sample_raw_metadata];
			stream_part0.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part0 setProperty:@(range_part0.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part0 setProperty:@(NSMaxRange(range_part0)) forKey:ZDCStreamFileMaxOffset];
			
			url_part0 = [self writeStream:stream_part0 error:NULL];
		}
		
		{
			ZDCInterruptingInputStream *inStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_part1 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part1.cleartextFileSize = cleartextFileSize;
			
			stream_part1.rawMetadata = [self sample_raw_metadata];
			stream_part1.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part1 setProperty:@(range_part1.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part1 setProperty:@(NSMaxRange(range_part1)) forKey:ZDCStreamFileMaxOffset];
			
			url_part1 = [self writeStream:stream_part1 error:NULL];
		}
		
		{
			ZDCInterruptingInputStream *inStream = [[ZDCInterruptingInputStream alloc] initWithFileURL:fileURL];
			
			Cleartext2CloudFileInputStream *stream_part2 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part2.cleartextFileSize = cleartextFileSize;
			
			stream_part2.rawMetadata = [self sample_raw_metadata];
			stream_part2.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part2 setProperty:@(range_part2.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part2 setProperty:@(NSMaxRange(range_part2)) forKey:ZDCStreamFileMaxOffset];
			
			url_part2 = [self writeStream:stream_part2 error:NULL];
		}
		
		NSArray<NSURL *> *parts = @[url_part0, url_part1, url_part2];
		NSURL *url_multi = [self combineParts:parts];
		
		BOOL same1 = [[NSFileManager defaultManager] contentsEqualAtPath:[url_full path]
		                                                         andPath:[url_multi path]];
		
		XCTAssert(same1, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_part0 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part2 error:nil];
		
		NSURL *clear_full = [self _convertCloudFile:url_full toCleartextFileFor:node error:nil];
		NSURL *clear_multi = [self _convertCloudFile:url_multi toCleartextFileFor:node error:nil];
		
		BOOL same2 = [[NSFileManager defaultManager] contentsEqualAtPath:[clear_full path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same2, @"Uh Oh SpaghettiOs !");
		
		BOOL same3 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same3, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:clear_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clear_multi error:nil];
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

- (void)test_multipart_4
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		NSNumber *cleartextFileSize = nil;
		[fileURL getResourceValue:&cleartextFileSize forKey:NSURLFileSizeKey error:nil];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		node.encryptionKey = [self sample_raw_key];
		
		NSURL *cacheFileURL = [self _convertCleartextFile:fileURL toCacheFileFor:node error:nil];
		
		NSURL *url_full = nil;
		NSURL *url_part0 = nil;
		NSURL *url_part1 = nil;
		NSURL *url_part2 = nil;
		
		{
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: cacheFileURL
			                                                 encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_full =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_full.cleartextFileSize = cleartextFileSize;
			
			stream_full.rawMetadata = [self sample_raw_metadata];
			stream_full.rawThumbnail = [self sample_raw_thumbnail];
			
			url_full = [self writeStream:stream_full error:NULL];
		}
		
		NSRange range_part0 = NSMakeRange(0, 5242880);
		NSRange range_part1 = NSMakeRange(NSMaxRange(range_part0), 5242880);
		NSRange range_part2 = NSMakeRange(NSMaxRange(range_part1), 5242880);
		
		{
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: cacheFileURL
			                                                 encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_part0 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part0.cleartextFileSize = cleartextFileSize;
			
			stream_part0.rawMetadata = [self sample_raw_metadata];
			stream_part0.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part0 setProperty:@(range_part0.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part0 setProperty:@(NSMaxRange(range_part0)) forKey:ZDCStreamFileMaxOffset];
			
			url_part0 = [self writeStream:stream_part0 error:NULL];
		}
		
		{
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: cacheFileURL
			                                                 encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_part1 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part1.cleartextFileSize = cleartextFileSize;
			
			stream_part1.rawMetadata = [self sample_raw_metadata];
			stream_part1.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part1 setProperty:@(range_part1.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part1 setProperty:@(NSMaxRange(range_part1)) forKey:ZDCStreamFileMaxOffset];
			
			url_part1 = [self writeStream:stream_part1 error:NULL];
		}
		
		{
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: cacheFileURL
			                                                 encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_part2 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part2.cleartextFileSize = cleartextFileSize;
			
			stream_part2.rawMetadata = [self sample_raw_metadata];
			stream_part2.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part2 setProperty:@(range_part2.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part2 setProperty:@(NSMaxRange(range_part2)) forKey:ZDCStreamFileMaxOffset];
			
			url_part2 = [self writeStream:stream_part2 error:NULL];
		}
		
		NSArray<NSURL *> *parts = @[url_part0, url_part1, url_part2];
		NSURL *url_multi = [self combineParts:parts];
		
		BOOL same1 = [[NSFileManager defaultManager] contentsEqualAtPath:[url_full path]
		                                                         andPath:[url_multi path]];
		
		XCTAssert(same1, @"Uh Oh SpaghettiOs !");
		
		NSURL *clear_full = [self _convertCloudFile:url_full toCleartextFileFor:node error:nil];
		NSURL *clear_multi = [self _convertCloudFile:url_multi toCleartextFileFor:node error:nil];
		
		BOOL same2 = [[NSFileManager defaultManager] contentsEqualAtPath:[clear_full path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same2, @"Uh Oh SpaghettiOs !");
		
		BOOL same3 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_full path]];
		
		XCTAssert(same3, @"Uh Oh SpaghettiOs !");
		
		BOOL same4 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same4, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_part0 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part2 error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:url_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:clear_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clear_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

- (void)test_multipart_5
{
	uint64_t test_size = 10485760;
	NSURL *fileURL = [self generateRandomFile:test_size];
	
	// Reserved: we may want to test multiple random files
	{
		NSLog(@"SPLIT: %@", fileURL);
		
		NSNumber *cleartextFileSize = nil;
		[fileURL getResourceValue:&cleartextFileSize forKey:NSURLFileSizeKey error:nil];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		node.encryptionKey = [self sample_raw_key];
		
		NSURL *cacheFileURL = [self _convertCleartextFile:fileURL toCacheFileFor:node error:nil];
		
		NSURL *url_full = nil;
		NSURL *url_part0 = nil;
		NSURL *url_part1 = nil;
		NSURL *url_part2 = nil;
		
		{
			ZDCInterruptingInputStream *underlyingStream =
			  [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
			
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: underlyingStream
			                                                    encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_full =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_full.cleartextFileSize = cleartextFileSize;
			
			stream_full.rawMetadata = [self sample_raw_metadata];
			stream_full.rawThumbnail = [self sample_raw_thumbnail];
			
			url_full = [self writeStream:stream_full error:NULL];
		}
		
		NSRange range_part0 = NSMakeRange(0, 5242880);
		NSRange range_part1 = NSMakeRange(NSMaxRange(range_part0), 5242880);
		NSRange range_part2 = NSMakeRange(NSMaxRange(range_part1), 5242880);
		
		{
			ZDCInterruptingInputStream *underlyingStream =
			  [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
			
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: underlyingStream
			                                                    encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_part0 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part0.cleartextFileSize = cleartextFileSize;
			
			stream_part0.rawMetadata = [self sample_raw_metadata];
			stream_part0.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part0 setProperty:@(range_part0.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part0 setProperty:@(NSMaxRange(range_part0)) forKey:ZDCStreamFileMaxOffset];
			
			url_part0 = [self writeStream:stream_part0 error:NULL];
		}
		
		{
			ZDCInterruptingInputStream *underlyingStream =
			  [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
			
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: underlyingStream
			                                                    encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_part1 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part1.cleartextFileSize = cleartextFileSize;
			
			stream_part1.rawMetadata = [self sample_raw_metadata];
			stream_part1.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part1 setProperty:@(range_part1.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part1 setProperty:@(NSMaxRange(range_part1)) forKey:ZDCStreamFileMaxOffset];
			
			url_part1 = [self writeStream:stream_part1 error:NULL];
		}
		
		{
			ZDCInterruptingInputStream *underlyingStream =
			  [[ZDCInterruptingInputStream alloc] initWithFileURL:cacheFileURL];
			
			CacheFile2CleartextInputStream *inStream =
			  [[CacheFile2CleartextInputStream alloc] initWithCacheFileStream: underlyingStream
			                                                    encryptionKey: node.encryptionKey];
			
			Cleartext2CloudFileInputStream *stream_part2 =
			  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: inStream
			                                                        encryptionKey: node.encryptionKey];
			
			stream_part2.cleartextFileSize = cleartextFileSize;
			
			stream_part2.rawMetadata = [self sample_raw_metadata];
			stream_part2.rawThumbnail = [self sample_raw_thumbnail];
			
			[stream_part2 setProperty:@(range_part2.location)    forKey:ZDCStreamFileMinOffset];
			[stream_part2 setProperty:@(NSMaxRange(range_part2)) forKey:ZDCStreamFileMaxOffset];
			
			url_part2 = [self writeStream:stream_part2 error:NULL];
		}
		
		NSArray<NSURL *> *parts = @[url_part0, url_part1, url_part2];
		NSURL *url_multi = [self combineParts:parts];
		
		BOOL same1 = [[NSFileManager defaultManager] contentsEqualAtPath:[url_full path]
		                                                         andPath:[url_multi path]];
		
		XCTAssert(same1, @"Uh Oh SpaghettiOs !");
		
		NSURL *clear_full = [self _convertCloudFile:url_full toCleartextFileFor:node error:nil];
		NSURL *clear_multi = [self _convertCloudFile:url_multi toCleartextFileFor:node error:nil];
		
		BOOL same2 = [[NSFileManager defaultManager] contentsEqualAtPath:[clear_full path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same2, @"Uh Oh SpaghettiOs !");
		
		BOOL same3 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_full path]];
		
		XCTAssert(same3, @"Uh Oh SpaghettiOs !");
		
		BOOL same4 = [[NSFileManager defaultManager] contentsEqualAtPath:[fileURL path]
		                                                         andPath:[clear_multi path]];
		
		XCTAssert(same4, @"Uh Oh SpaghettiOs !");
		
		[[NSFileManager defaultManager] removeItemAtURL:url_part0 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_part2 error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:url_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:url_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:clear_full error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:clear_multi error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
	}
	
	[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_nodeReader_1
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cache file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cacheFileURL = nil;
		
		cacheFileURL = [self _convertCleartextFile:cleartextFileURL toCacheFileFor:node error:&error];
		
		XCTAssert(cacheFileURL != nil);
		
		// Setup ZDCFileReader
		
		ZDCFileReader *reader =
		  [[ZDCFileReader alloc] initWithFileURL :cacheFileURL
		                                 format: ZDCCryptoFileFormat_CacheFile
		                          encryptionKey: node.encryptionKey
		                            retainToken: nil];
		
		BOOL openResult = [reader openFileWithError:&error];
		XCTAssert(openResult);
		
		// Pick random ranges (of cleartext output), and ensure seeking works properly.
		
		for (NSUInteger i = 0; i < 10; i++)
		{ @autoreleasepool {
			
			NSRange range = [self randomRangeForFileSize:cleartextFileSize withMaxLength:512];
			
			BOOL rangeReadMatches =
			  [self compareRange:range
			           ofRawFile:cleartextFileURL
			          withReader:reader];
			
			XCTAssert(rangeReadMatches,
						 @"SEEK broken for range(%@) file(%@)", NSStringFromRange(range), cleartextFileURL.lastPathComponent);
		}}
		
		if (cacheFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		}
	}
}

- (void)test_nodeReader_2
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cloud file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cloudFileURL = nil;
		
		cloudFileURL = [self _convertCleartextFile:cleartextFileURL toCloudFileFor:node error:&error];
		XCTAssert(cloudFileURL != nil);
		
		// Setup ZDCFileReader
		
		ZDCFileReader *reader =
		  [[ZDCFileReader alloc] initWithFileURL: cloudFileURL
		                                  format: ZDCCryptoFileFormat_CloudFile
		                           encryptionKey: node.encryptionKey
		                             retainToken: nil];
		
		BOOL openResult = [reader openFileWithError:&error];
		XCTAssert(openResult);
		
		// Pick random ranges (of cleartext output), and ensure seeking works properly.
		
		for (NSUInteger i = 0; i < 10; i++)
		{ @autoreleasepool {
			
			NSRange range = [self randomRangeForFileSize:cleartextFileSize withMaxLength:512];
			
			BOOL rangeReadMatches =
			  [self compareRange:range
			           ofRawFile:cleartextFileURL
			          withReader:reader];
			
			XCTAssert(rangeReadMatches,
						 @"SEEK broken for range(%@) file(%@)", NSStringFromRange(range), cleartextFileURL.lastPathComponent);
		}}
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

- (void)test_nodeReader_3
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cache file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cacheFileURL = nil;
		
		cacheFileURL = [self _convertCleartextFile:cleartextFileURL toCacheFileFor:node error:&error];
		
		XCTAssert(cacheFileURL != nil);
		
		// Setup ZDCFileReader
		
		ZDCFileReader *reader =
		  [[ZDCFileReader alloc] initWithFileURL: cacheFileURL
		                                  format: ZDCCryptoFileFormat_CacheFile
		                           encryptionKey: node.encryptionKey
		                             retainToken: nil];
		
		BOOL openResult = [reader openFileWithError:&error];
		XCTAssert(openResult);
		
		// Read to EOF
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		NSRange fileRange = NSMakeRange(0, bufferMallocSize);
		ssize_t result;
		
		do
		{
			result = [reader getBytes:buffer range:fileRange error:&error];
			NSLog(@"result: %ld", result);
			
			if (result < 0)
			{
				XCTAssert(NO, @"Error reading file");
				break;
			}
			else
			{
				fileRange.location += result;
			}
			
		} while (result > 0);
		
		// Now that we've reached EOF, try seeking to beginning of file, and then reading again.
		
		fileRange.location = 0;
		fileRange.length = MIN(bufferMallocSize, cleartextFileSize);
		
		BOOL rangeReadMatches = [self compareRange:fileRange ofRawFile:cleartextFileURL withReader:reader];
		
		XCTAssert(rangeReadMatches, @"ZDCFileReader: Unable to seek to beginning of file after EOF");
		
		if (buffer) {
			free(buffer);
			buffer = NULL;
		}
		
		if (cacheFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		}
	}
}

- (void)test_nodeReader_4
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cloud file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError *error = nil;
		NSURL *cloudFileURL = nil;
		
		cloudFileURL = [self _convertCleartextFile:cleartextFileURL toCloudFileFor:node error:&error];
		XCTAssert(cloudFileURL != nil);
		
		// Setup ZDCFileReader
		
		ZDCFileReader *reader =
		  [[ZDCFileReader alloc] initWithFileURL: cloudFileURL
		                                  format: ZDCCryptoFileFormat_CloudFile
		                           encryptionKey: node.encryptionKey
		                             retainToken: nil];
		
		BOOL openResult = [reader openFileWithError:&error];
		XCTAssert(openResult);
		
		// Read to EOF
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		NSRange fileRange = NSMakeRange(0, bufferMallocSize);
		ssize_t result;
		
		do
		{
			result = [reader getBytes:buffer range:fileRange error:&error];
			NSLog(@"result: %ld", result);
			
			if (result < 0)
			{
				XCTAssert(NO, @"Error reading file");
				break;
			}
			else
			{
				fileRange.location += result;
			}
			
		} while (result > 0);
		
		// Now that we've reached EOF, try seeking to beginning of file, and then reading again.
		
		fileRange.location = 0;
		fileRange.length = MIN(bufferMallocSize, cleartextFileSize);
		
		BOOL rangeReadMatches = [self compareRange:fileRange ofRawFile:cleartextFileURL withReader:reader];
		
		XCTAssert(rangeReadMatches, @"ZDCFileReader: Unable to seek to beginning of file after EOF");
		
		if (buffer) {
			free(buffer);
			buffer = NULL;
		}
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

- (BOOL)compareRange:(NSRange)range
           ofRawFile:(NSURL *)rawFileURL
          withReader:(ZDCFileReader *)reader
{
	NSData *data1 = [self readRange:range ofFile:rawFileURL error:nil];
	NSData *data2 = [self readRange:range ofReader:reader error:nil];
	
	return [data1 isEqual:data2];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * We discovered the following peculiarity with NSURLSession (when using streams to provide the upload body):
 *
 * - From the perspective of the server (AWS), the upload would succeed
 * - From the perspective of the client, the upload would:
 *   - upload the entire file
 *   - then appear to freeze for 60 seconds
 *   - then fail with a timeout error
 *
 * Debugging the problem eventually lead to the following reason:
 * - NSURLSession will invoke 'hasBytesAvailable' before calling 'read:maxLength:'
 * - if 'hasBytesAvailable' returns NO, it won't call 'read:maxLength:'
 * - if the stream doesn't transition to NSStreamStatusAtEnd, the upload will fail
 *
 * This means that:
 * - the 'hasBytesAvailable' MUST return YES until NSStreamStatusAtEnd is set
**/

- (void)test_hasBytesAvailable_1
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Setup stream
		
		ZDCInterruptingInputStream *stream =
		  [[ZDCInterruptingInputStream alloc] initWithFileURL:cleartextFileURL];
		
		[stream open];
		
		uint64_t const fileSize = cleartextFileSize;
		
		// Read file until last byte (but not after - do NOT read EOF)
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		uint64_t offset = 0;
		do {
			uint64_t bytesLeft = fileSize - offset;
			uint64_t bytesToRead = MIN(bytesLeft, bufferMallocSize);
			
			XCTAssert([stream hasBytesAvailable] == YES);
			NSInteger bytesRead = [stream read:buffer maxLength:(NSUInteger)bytesToRead];
			
			if (bytesRead < 0)
			{
				XCTAssert(NO, @"read:maxLength: => %lld - %@", (long long)bytesRead, cleartextFileURL.lastPathComponent);
				break;
			}
			else if (bytesRead == 0)
			{
				XCTAssert(NO, @"read:maxLength: => 0 - %@", cleartextFileURL.lastPathComponent);
				break;
			}
			else
			{
				offset += bytesRead;
			}
			
		} while (offset < fileSize);
		
		// Here's the test we're after.
		// At this point, we need to ensure:
		//
		// - hasBytesAvailable returns YES
		
		XCTAssert(stream.streamStatus < NSStreamStatusAtEnd,
		  @"Don't transition to EOF until after returning zero to reader - %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == YES,
		  @"This will cause NSURLSession tasks to timeout if using stream - %@", cleartextFileURL.lastPathComponent);
		
		NSInteger bytesRead = [stream read:buffer maxLength:1];
		
		XCTAssert(bytesRead == 0,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert(stream.streamStatus == NSStreamStatusAtEnd,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == NO,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
	}
}

- (void)test_hasBytesAvailable_2
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Setup stream
		
		NSData *encryptionKey = [ZDCNode randomEncryptionKey];

		Cleartext2CacheFileInputStream *stream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL:cleartextFileURL
		                                                     encryptionKey:encryptionKey];
		
		[stream open];
		
		uint64_t const fileSize = [[stream encryptedFileSize] unsignedLongLongValue];
		
		// Read file until last byte (but not after - do NOT read EOF)
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		uint64_t offset = 0;
		do {
			uint64_t bytesLeft = fileSize - offset;
			uint64_t bytesToRead = MIN(bytesLeft, bufferMallocSize);
			
			XCTAssert([stream hasBytesAvailable] == YES);
			NSInteger bytesRead = [stream read:buffer maxLength:(NSUInteger)bytesToRead];
			
			if (bytesRead < 0)
			{
				XCTAssert(NO, @"read:maxLength: => %lld - %@", (long long)bytesRead, cleartextFileURL.lastPathComponent);
				break;
			}
			else if (bytesRead == 0)
			{
				XCTAssert(NO, @"read:maxLength: => 0 - %@", cleartextFileURL.lastPathComponent);
				break;
			}
			else
			{
				offset += bytesRead;
			}
			
		} while (offset < fileSize);
		
		// Here's the test we're after.
		// At this point, we need to ensure:
		//
		// - hasBytesAvailable returns YES
		
		XCTAssert(stream.streamStatus < NSStreamStatusAtEnd,
		  @"Don't transition to EOF until after returning zero to reader - %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == YES,
		  @"This will cause NSURLSession tasks to timeout if using stream - %@", cleartextFileURL.lastPathComponent);
		
		NSInteger bytesRead = [stream read:buffer maxLength:1];
		
		XCTAssert(bytesRead == 0,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert(stream.streamStatus == NSStreamStatusAtEnd,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == NO,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
	}
}

- (void)test_hasBytesAvailable_3
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Setup stream
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];

		Cleartext2CloudFileInputStream *stream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		[stream open];
		
		uint64_t const fileSize = [[stream encryptedFileSize] unsignedLongLongValue];
		
		// Read file until last byte (but not after - do NOT read EOF)
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		uint64_t offset = 0;
		do {
			uint64_t bytesLeft = fileSize - offset;
			uint64_t bytesToRead = MIN(bytesLeft, bufferMallocSize);
			
			XCTAssert([stream hasBytesAvailable] == YES);
			NSInteger bytesRead = [stream read:buffer maxLength:(NSUInteger)bytesToRead];
			
			if (bytesRead < 0)
			{
				XCTAssert(NO, @"read:maxLength: => %lld - %@", (long long)bytesRead, cleartextFileURL.lastPathComponent);
				break;
			}
			else if (bytesRead == 0)
			{
				XCTAssert(NO, @"read:maxLength: => 0 - %@", cleartextFileURL.lastPathComponent);
				break;
			}
			else
			{
				offset += bytesRead;
			}
			
		} while (offset < fileSize);
		
		// Here's the test we're after.
		// At this point, we need to ensure:
		//
		// - hasBytesAvailable returns YES
		
		XCTAssert(stream.streamStatus < NSStreamStatusAtEnd,
		  @"Don't transition to EOF until after returning zero to reader - %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == YES,
		  @"This will cause NSURLSession tasks to timeout if using stream - %@", cleartextFileURL.lastPathComponent);
		
		NSInteger bytesRead = [stream read:buffer maxLength:1];
		
		XCTAssert(bytesRead == 0,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert(stream.streamStatus == NSStreamStatusAtEnd,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == NO,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
	}
}

- (void)test_hasBytesAvailable_4
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cache file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSURL *cacheFileURL = [self _convertCleartextFile:cleartextFileURL toCacheFileFor:node error:nil];
		
		XCTAssert(cacheFileURL != nil);
		
		// Setup stream

		CacheFile2CleartextInputStream *stream =
		  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: cacheFileURL
		                                                 encryptionKey: node.encryptionKey];
		
		[stream open];
		
		uint64_t const fileSize = [[stream cleartextFileSize] unsignedLongLongValue];
		XCTAssert(fileSize == cleartextFileSize);
		
		// Read file until last byte (but not after - do NOT read EOF)
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		uint64_t offset = 0;
		do {
			uint64_t bytesLeft = fileSize - offset;
			uint64_t bytesToRead = MIN(bytesLeft, bufferMallocSize);
			
			XCTAssert([stream hasBytesAvailable] == YES);
			NSInteger bytesRead = [stream read:buffer maxLength:(NSUInteger)bytesToRead];
			
			if (bytesRead < 0)
			{
				XCTAssert(NO, @"read:maxLength: => %lld - %@", (long long)bytesRead, cleartextFileURL.lastPathComponent);
				break;
			}
			else if (bytesRead == 0)
			{
				XCTAssert(NO, @"read:maxLength: => 0 - %@", cleartextFileURL.lastPathComponent);
				break;
			}
			else
			{
				offset += bytesRead;
			}
			
		} while (offset < fileSize);
		
		// Here's the test we're after.
		// At this point, we need to ensure:
		//
		// - hasBytesAvailable returns YES
		
		XCTAssert(stream.streamStatus < NSStreamStatusAtEnd,
		  @"Don't transition to EOF until after returning zero to reader - %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == YES,
		  @"This will cause NSURLSession tasks to timeout if using stream - %@", cleartextFileURL.lastPathComponent);
		
		NSInteger bytesRead = [stream read:buffer maxLength:1];
		
		XCTAssert(bytesRead == 0,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert(stream.streamStatus == NSStreamStatusAtEnd,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == NO,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		if (cacheFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL error:nil];
		}

	}
}

- (void)test_hasBytesAvailable_5
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		// Fetch size of cleartext file
		
		uint64_t cleartextFileSize = 0;
		
		NSNumber *number = nil;
		if ([cleartextFileURL getResourceValue:&number forKey:NSURLFileSizeKey error:nil])
		{
			cleartextFileSize = [number unsignedLongLongValue];
		}
		
		// Convert cleartext to cache file
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSURL *cloudFileURL = [self _convertCleartextFile:cleartextFileURL toCloudFileFor:node error:nil];
		
		XCTAssert(cloudFileURL != nil);
		
		// Setup stream

		CloudFile2CleartextInputStream *stream =
		  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: cloudFileURL
		                                                 encryptionKey: node.encryptionKey];
		
		[stream open];
		[stream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
		
		uint64_t const fileSize = [[stream cleartextFileSize] unsignedLongLongValue];
		XCTAssert(fileSize == cleartextFileSize);
		
		// Read file until last byte (but not after - do NOT read EOF)
		
		size_t const bufferMallocSize = 1024 * 1024 * 1;
		void *buffer = malloc(bufferMallocSize);
		
		uint64_t offset = 0;
		do {
			uint64_t bytesLeft = fileSize - offset;
			uint64_t bytesToRead = MIN(bytesLeft, bufferMallocSize);
			
			XCTAssert([stream hasBytesAvailable] == YES);
			NSInteger bytesRead = [stream read:buffer maxLength:(NSUInteger)bytesToRead];
			
			if (bytesRead < 0)
			{
				XCTAssert(NO, @"read:maxLength: => %lld - %@", (long long)bytesRead, cleartextFileURL.lastPathComponent);
				break;
			}
			else if (bytesRead == 0)
			{
				XCTAssert(NO, @"read:maxLength: => 0 - %@", cleartextFileURL.lastPathComponent);
				break;
			}
			else
			{
				offset += bytesRead;
			}
			
		} while (offset < fileSize);
		
		// Here's the test we're after.
		// At this point, we need to ensure:
		//
		// - hasBytesAvailable returns YES
		
		XCTAssert(stream.streamStatus < NSStreamStatusAtEnd,
		  @"Don't transition to EOF until after returning zero to reader - %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == YES,
		  @"This will cause NSURLSession tasks to timeout if using stream - %@", cleartextFileURL.lastPathComponent);
		
		NSInteger bytesRead = [stream read:buffer maxLength:1];
		
		XCTAssert(bytesRead == 0,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert(stream.streamStatus == NSStreamStatusAtEnd,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		XCTAssert([stream hasBytesAvailable] == NO,
		  @"cleartextFile: %@", cleartextFileURL.lastPathComponent);
		
		if (cloudFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_streaming1
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	NSData *rawMetadata = [self sample_raw_metadata];
	NSData *rawThumbnail = [self sample_raw_thumbnail];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		Cleartext2CloudFileInputStream *encryptionStream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		encryptionStream.rawMetadata = rawMetadata;
		encryptionStream.rawThumbnail = rawThumbnail;
		
		NSURL *cloudFileURL = [self writeStream:encryptionStream error:nil];
		XCTAssert(cloudFileURL != nil);
		
		CloudFile2CleartextInputStream *decryptionStream =
		  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: cloudFileURL
		                                                 encryptionKey: node.encryptionKey];
		
		[decryptionStream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
		
		NSURL *decryptedFileURL = [self writeStream:decryptionStream error:nil];
		XCTAssert(decryptedFileURL != nil);
		
		BOOL matches =
		  [[NSFileManager defaultManager] contentsEqualAtPath:[cleartextFileURL path]
		                                              andPath:[decryptedFileURL path]];
		
		XCTAssert(matches, @"File diff: %@", [cleartextFileURL lastPathComponent]);
		
		[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:decryptedFileURL error:nil];
	}
}

- (void)test_streaming2
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	// Reproducing the crash we found in the "c&B.mp4" movie file.
	// It was a nice edge case:
	// - closest block offset was in thumbnail section
	// - bad logic created a situation that would overflow the overflowBuffer
	
	NSData *rawMetadata = [self generateRandomData:157];   // <= Picked to reproduce crash
	NSData *rawThumbnail = [self generateRandomData:1438]; // <= Picked to reproduce crash
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		Cleartext2CloudFileInputStream *encryptionStream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		encryptionStream.rawMetadata = rawMetadata;
		encryptionStream.rawThumbnail = rawThumbnail;
		
		NSURL *cloudFileURL = [self writeStream:encryptionStream error:nil];
		XCTAssert(cloudFileURL != nil);
		
		CloudFile2CleartextInputStream *decryptionStream =
		  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: cloudFileURL
		                                                 encryptionKey: node.encryptionKey];
		
		[decryptionStream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
		
		NSURL *decryptedFileURL = [self writeStream:decryptionStream error:nil];
		XCTAssert(decryptedFileURL != nil);
		
		BOOL matches =
		  [[NSFileManager defaultManager] contentsEqualAtPath:[cleartextFileURL path]
		                                              andPath:[decryptedFileURL path]];
		
		XCTAssert(matches, @"File diff: %@", [cleartextFileURL lastPathComponent]);
		
		[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:decryptedFileURL error:nil];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_reEncrypt_cacheFiles
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		NSData *encryptionKey1 = [ZDCNode randomEncryptionKey];
		NSData *encryptionKey2 = [ZDCNode randomEncryptionKey];
		
		Cleartext2CacheFileInputStream *encryptionStream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL:cleartextFileURL
		                                                     encryptionKey:encryptionKey1];
		
		NSURL *cacheFileURL1 = [self writeStream:encryptionStream error:nil];
		XCTAssert(cacheFileURL1 != nil);
		
		NSURL *cacheFileURL2 = [self _reEncryptFile:cacheFileURL1 fromKey:encryptionKey1 toKey:encryptionKey2 error:nil];
		XCTAssert(cacheFileURL2 != nil);
		
		CacheFile2CleartextInputStream *decryptStream1 =
		  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL:cacheFileURL1 encryptionKey:encryptionKey1];
		
		CacheFile2CleartextInputStream *decryptStream2 =
		  [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL:cacheFileURL2 encryptionKey:encryptionKey2];
		
		NSURL *decryptedFileURL1 = [self writeStream:decryptStream1 error:nil];
		XCTAssert(decryptedFileURL1 != nil);
		
		NSURL *decryptedFileURL2 = [self writeStream:decryptStream2 error:nil];
		XCTAssert(decryptedFileURL2 != nil);
		
		BOOL matches1 =
		  [[NSFileManager defaultManager] contentsEqualAtPath:[cleartextFileURL path]
		                                              andPath:[decryptedFileURL1 path]];
		
		BOOL matches2 =
		   [[NSFileManager defaultManager] contentsEqualAtPath:[cleartextFileURL path]
		                                               andPath:[decryptedFileURL2 path]];
		
		XCTAssert(matches1, @"File diff: %@", [cleartextFileURL lastPathComponent]);
		XCTAssert(matches2, @"File diff: %@", [cleartextFileURL lastPathComponent]);
		
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:cacheFileURL2 error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:decryptedFileURL1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:decryptedFileURL2 error:nil];
	}
}

- (void)test_reEncrypt_cloudFiles
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	NSData *rawMetadata = [self sample_raw_metadata];
	NSData *rawThumbnail = [self sample_raw_thumbnail];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		NSData *encryptionKey1 = [ZDCNode randomEncryptionKey];
		NSData *encryptionKey2 = [ZDCNode randomEncryptionKey];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		node.encryptionKey = encryptionKey1;
		
		Cleartext2CloudFileInputStream *encryptionStream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: cleartextFileURL
		                                                     encryptionKey: node.encryptionKey];
		
		encryptionStream.rawMetadata = rawMetadata;
		encryptionStream.rawThumbnail = rawThumbnail;
		
		NSURL *cloudFileURL1 = [self writeStream:encryptionStream error:nil];
		XCTAssert(cloudFileURL1 != nil);
		
		NSURL *cloudFileURL2 = [self _reEncryptFile:cloudFileURL1 fromKey:encryptionKey1 toKey:encryptionKey2 error:nil];
		XCTAssert(cloudFileURL2 != nil);
		
		CloudFile2CleartextInputStream *decryptStream1 =
		  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL:cloudFileURL1 encryptionKey:encryptionKey1];
		
		CloudFile2CleartextInputStream *decryptStream2 =
		  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL:cloudFileURL2 encryptionKey:encryptionKey2];
		
		[decryptStream1 setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
		[decryptStream2 setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
		
		NSURL *decryptedFileURL1 = [self writeStream:decryptStream1 error:nil];
		XCTAssert(decryptedFileURL1 != nil);
		
		NSURL *decryptedFileURL2 = [self writeStream:decryptStream2 error:nil];
		XCTAssert(decryptedFileURL2 != nil);
		
		BOOL matches1 =
		  [[NSFileManager defaultManager] contentsEqualAtPath:[cleartextFileURL path]
		                                              andPath:[decryptedFileURL1 path]];
		
		BOOL matches2 =
		   [[NSFileManager defaultManager] contentsEqualAtPath:[cleartextFileURL path]
		                                               andPath:[decryptedFileURL2 path]];
		
		XCTAssert(matches1, @"File diff: %@", [cleartextFileURL lastPathComponent]);
		XCTAssert(matches2, @"File diff: %@", [cleartextFileURL lastPathComponent]);
		
		[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:cloudFileURL2 error:nil];
		
		[[NSFileManager defaultManager] removeItemAtURL:decryptedFileURL1 error:nil];
		[[NSFileManager defaultManager] removeItemAtURL:decryptedFileURL2 error:nil];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_pump_cleartext_to_cachefile
{
	// Test encrypting "data" that gets given to us in chunks.
	// For example, from the iOS Asset Library, where there's a dataBlock that gets called with chunks.
	
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL: testFilesURL
	                       includingPropertiesForKeys: nil
	                                          options: NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler: nil];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		NSError *error = nil;
		
		NSURL *output_encryptedFileURL = [self randomFileURL];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError* (^pumpDataBlock)(NSData*) = nil;
		NSError* (^pumpCompletionBlock)(void) = nil;
		
		[ZDCFileConversion encryptCleartextWithDataBlock: &pumpDataBlock
		                                 completionBlock: &pumpCompletionBlock
		                                     toCacheFile: output_encryptedFileURL
		                                         withKey: node.encryptionKey];
		
		{ // Scoping
			
			// The `thirdPartyStream` is us "faking it".
			// Normally this data comes from some 3rd party data provider, such as the Asset Library.
			
			NSInputStream *thirdPartyStream = [NSInputStream inputStreamWithURL:cleartextFileURL];
			
			size_t bufferSize = 1024 * 1024 * 4;
			uint8_t *buffer = (uint8_t *)malloc(bufferSize);
		
			[thirdPartyStream open];
			
			BOOL done = NO;
			do
			{
				NSInteger bufferLength = [thirdPartyStream read:buffer maxLength:bufferSize];
			
				if (bufferLength < 0)
				{
					NSLog(@"Error reading thirdPartyStream: %@", thirdPartyStream.streamError);
					
					error = thirdPartyStream.streamError;
					if (error == nil) {
						error = [NSError errorWithDomain:@"UnitTest" code:0 userInfo:nil];
					}
					
					done = YES;
				}
				else if (bufferLength == 0)
				{
					done = YES;
				}
				else
				{
					NSData *wrapper = [NSData dataWithBytesNoCopy:buffer length:bufferLength freeWhenDone:NO];
					error = pumpDataBlock(wrapper);
					
					if (error)
					{
						NSLog(@"pumpDataBlock error: %@", error);
						done = YES;
					}
				}
			
			} while (!done);
			
			if (!error) {
				pumpCompletionBlock();
			}
			
			[thirdPartyStream close];
			
		} // end: scoping
		
		XCTAssert(error == nil);
		
		NSURL *output_decryptedFileURL = nil;
		if (!error)
		{
			output_decryptedFileURL =
				[self _convertCacheFile: output_encryptedFileURL
				     toCleartextFileFor: node
				                  error: &error];
		
			BOOL same = [[NSFileManager defaultManager] contentsEqualAtPath: [cleartextFileURL path]
			                                                        andPath: [output_decryptedFileURL path]];
		
			XCTAssert(same, @"Uh Oh SpaghettiOs !");
		}
		
		if (output_encryptedFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:output_encryptedFileURL error:nil];
		}
		if (output_decryptedFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:output_decryptedFileURL error:nil];
		}
	}
}

- (void)test_pump_cleartext_to_cloudfile
{
	// Test encrypting "data" that gets given to us in chunks.
	// For example, from the iOS Asset Library, where there's a dataBlock that gets called with chunks.
	
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL: testFilesURL
	                       includingPropertiesForKeys: nil
	                                          options: NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler: nil];
	
	NSData *rawMetadata = [self sample_raw_metadata];
	NSData *rawThumbnail = [self sample_raw_thumbnail];
	
	for (NSURL *cleartextFileURL in enumerator)
	{
		NSError *error = nil;
		
		NSURL *output_encryptedFileURL = [self randomFileURL];
		
		ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
		
		NSError* (^pumpDataBlock)(NSData*) = nil;
		NSError* (^pumpCompletionBlock)(void) = nil;
		
		[ZDCFileConversion encryptCleartextWithDataBlock: &pumpDataBlock
		                                 completionBlock: &pumpCompletionBlock
		                                     toCloudFile: output_encryptedFileURL
		                                         withKey: node.encryptionKey
		                                        metadata: rawMetadata
		                                       thumbnail: rawThumbnail];
		
		{ // Scoping
			
			// The `thirdPartyStream` is us "faking it".
			// Normally this data comes from some 3rd party data provider, such as the Asset Library.
			
			NSInputStream *thirdPartyStream = [NSInputStream inputStreamWithURL:cleartextFileURL];
			
			size_t bufferSize = 1024 * 1024 * 4;
			uint8_t *buffer = (uint8_t *)malloc(bufferSize);
		
			[thirdPartyStream open];
			
			BOOL done = NO;
			do
			{
				NSInteger bufferLength = [thirdPartyStream read:buffer maxLength:bufferSize];
			
				if (bufferLength < 0)
				{
					NSLog(@"Error reading thirdPartyStream: %@", thirdPartyStream.streamError);
					
					error = thirdPartyStream.streamError;
					if (error == nil) {
						error = [NSError errorWithDomain:@"UnitTest" code:0 userInfo:nil];
					}
					
					done = YES;
				}
				else if (bufferLength == 0)
				{
					done = YES;
				}
				else
				{
					NSData *wrapper = [NSData dataWithBytesNoCopy:buffer length:bufferLength freeWhenDone:NO];
					error = pumpDataBlock(wrapper);
					
					if (error)
					{
						NSLog(@"pumpDataBlock error: %@", error);
						done = YES;
					}
				}
			
			} while (!done);
			
			if (!error) {
				pumpCompletionBlock();
			}
			
			[thirdPartyStream close];
			
		} // end: scoping
		
		XCTAssert(error == nil);
		
		NSURL *output_decryptedFileURL = nil;
		if (!error)
		{
			output_decryptedFileURL =
				[self _convertCloudFile: output_encryptedFileURL
				     toCleartextFileFor: node
				                  error: &error];
		
			BOOL same = [[NSFileManager defaultManager] contentsEqualAtPath: [cleartextFileURL path]
			                                                        andPath: [output_decryptedFileURL path]];
		
			XCTAssert(same, @"Uh Oh SpaghettiOs !");
		}
		
		if (output_encryptedFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:output_encryptedFileURL error:nil];
		}
		if (output_decryptedFileURL) {
			[[NSFileManager defaultManager] removeItemAtURL:output_decryptedFileURL error:nil];
		}
	}
}

@end
