/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <XCTest/XCTest.h>

#import <stdatomic.h>
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import <ZeroDarkCloud/NSData+S4.h>

typedef NS_ENUM(NSInteger, ZDCFileChecksumTest) {
	
	ZDCFileChecksumTest_File,
	ZDCFileChecksumTest_Stream
};

@interface test_ZDCFileChecksum : XCTestCase
@end

@implementation test_ZDCFileChecksum

- (void)test_SHA1_file
{
	const HASH_Algorithm algorithm = kHASH_Algorithm_SHA1;
	
	// The following values were created using the built-in 'shasum' utility on macOS.
	//
	// $ shasum filename
	
	NSDictionary *expected = @{
		@"13th_Amendment.jpg"                    : @"596374a3a6f155f10cb1152bee7cc5d006fafa0c",
		@"21st_Amendment.jpg"                    : @"ffe3f64f95002fac5cff51ad4dd45873b99369a7",
		@"Constitution of the United States.pdf" : @"7746ce7e2741428aa14c6d0e53a45248fe5b2dca",
		@"Declaration of Independence.jpg"       : @"b2667ae80e7e39760bdd3ebbb078d095544539b0",
		@"The Bill of Rights.pdf"                : @"8cf5a50c95ed6bd5482582e42dcea01741593170",
		@"Tiny File.txt"                         : @"0759b479c10bcd5eddfdfc4629b0f1888f2bfd65"
	};
	
	[self _testType:ZDCFileChecksumTest_File   withAlgorithm:algorithm expected:expected];
	[self _testType:ZDCFileChecksumTest_Stream withAlgorithm:algorithm expected:expected];
}

- (void)test_SHA1_chunks
{
	const HASH_Algorithm algorithm = kHASH_Algorithm_SHA1;
	
	// The following values were created using command-line tools on macOS.
	//
	// First, we split the "Declaration of Independence.jpg" file (1.9MB) into 256KiB chunks:
	// $ split -b 256k filename
	//
	// Then we can calculate the checksum of each:
	// $ shasum filename
	
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	NSURL *fileURL = [testFilesURL URLByAppendingPathComponent:@"Declaration of Independence.jpg"];
	
	NSDictionary *expected = @{
		@(0) : @"4172596a3340147baeda870ef090f63ba66d9ee5",
		@(1) : @"b1bef5f7b71883b849121ba738d6f9319e71d475",
		@(2) : @"ad3294f4d181b3e4b1b8122410c4fdd999251083",
		@(3) : @"95d26035ead3bbd2c2ba37606187aa548a60a305",
		@(4) : @"4a517b1062cb863492d4801b563a192199bcdb49",
		@(5) : @"41d45f0e04cbcbb4dbd9105b6a2b145639d34ae5",
		@(6) : @"86d9ff2cd087c53359cb203b5bbeb6e1063bc5a9",
		@(7) : @"250392e876ae83dbac5f6df332b4a04d16c25108",
	};
	
	uint64_t chunkSize = (1024 * 256);
	
	[self _testType:ZDCFileChecksumTest_File
	  withAlgorithm:algorithm
	           file:fileURL
	          range:nil
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	[self _testType:ZDCFileChecksumTest_Stream
	  withAlgorithm:algorithm
	           file:fileURL
	           range:nil
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	for (NSNumber *number in expected)
	{
		NSUInteger index = [number unsignedIntegerValue];
		NSString *expectedChecksum = expected[number];
		
		NSUInteger offset = chunkSize * index;
		NSUInteger length = chunkSize;
		
		NSRange range = NSMakeRange(offset, length);
		
		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:range]
		      chunkSize:nil
				 expected:@{ @(0): expectedChecksum }];
		
		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:range]
		      chunkSize:nil
		       expected:@{ @(0): expectedChecksum }];
	}
}

- (void)test_SHA1_weirdOffset
{
	const HASH_Algorithm algorithm = kHASH_Algorithm_SHA1;
	
	// The following values were created using command-line tools on macOS.
	//
	// First, we split the "Declaration of Independence.jpg" file at some weird offset:
	// $ split -b 658764 "Declaration of Independence.jpg"
	//
	// This will create a bunch of files: xaa, xab, xac, xad
	// Delete the first chunk, and combine the last 3:
	// $ rm xaa
	// $ cat xa? >> goofy.bin
	//
	// Now, we split the "goofy.bin" file (1.3MB) into 256KiB chunks:
	// $ split -b 256k goofy.bin
	//
	// Then we can calculate the checksum of each:
	// $ shasum filename
	
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	NSURL *fileURL = [testFilesURL URLByAppendingPathComponent:@"Declaration of Independence.jpg"];
	
	NSDictionary *expected = @{
		@(0) : @"13b4981f295b168a93379f51d6c014964fdf48a8",
		@(1) : @"3e23f5a6302f2195a901ef11ee95092b7466c3ff",
		@(2) : @"a6c10e59e95568a8ab060604bcbcd0dff59caccf",
		@(3) : @"d460c89129112669d031d621d3842097a119340f",
		@(4) : @"c0e988e19f29bf8950b7c7d36b42110aa2b04172",
		@(5) : @"526ecf215cc04af5480fcc266aeb2cfc7e8f6ef5",
	};
	
	NSRange range = NSMakeRange(658764, NSUIntegerMax);
	
	uint64_t chunkSize = (1024 * 256);
	
	[self _testType:ZDCFileChecksumTest_File
	  withAlgorithm:algorithm
	           file:fileURL
	          range:[NSValue valueWithRange:range]
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	[self _testType:ZDCFileChecksumTest_Stream
	  withAlgorithm:algorithm
	           file:fileURL
	          range:[NSValue valueWithRange:range]
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	NSArray *orderedKeys = [[expected allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSNumber *number in orderedKeys)
	{
		NSUInteger index = [number unsignedIntegerValue];
		NSString *expectedChecksum = expected[number];
		
		NSUInteger offset = chunkSize * index;
		NSUInteger length = chunkSize;
		
		NSRange sub_range = NSMakeRange(range.location + offset, length);
		
		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:sub_range]
		      chunkSize:nil
		       expected:@{ @(0): expectedChecksum }];

		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:sub_range]
		      chunkSize:nil
		       expected:@{ @(0): expectedChecksum }];
	}
}

- (void)test_MD5_file
{
	const HASH_Algorithm algorithm = kHASH_Algorithm_MD5;
	
	// The following values were created using the built-in 'md5' utility on macOS.
	//
	// $ md5 filename
	
	NSDictionary *expected = @{
		@"13th_Amendment.jpg"                    : @"d63c4ffe428c0e5685c8fae1071ebb52",
		@"21st_Amendment.jpg"                    : @"8505e55a85b97aa0669641ce954252bf",
		@"Constitution of the United States.pdf" : @"5dfaa1ee8aa586ec8fd96985c07aadf6",
		@"Declaration of Independence.jpg"       : @"f8f8102de9d5796228811c52ee08f52f",
		@"The Bill of Rights.pdf"                : @"85fbc57809e6ff605117d67fda3bb9b4",
		@"Tiny File.txt"                         : @"c12de51b11fab773ce4f45558309b6f0"
	};
	
	[self _testType:ZDCFileChecksumTest_File   withAlgorithm:algorithm expected:expected];
	[self _testType:ZDCFileChecksumTest_Stream withAlgorithm:algorithm expected:expected];
}

- (void)test_MD5_chunks
{
	const HASH_Algorithm algorithm = kHASH_Algorithm_MD5;
	
	// The following values were created using command-line tools on macOS.
	//
	// First, we split the "Declaration of Independence.jpg" file (1.9MB) into 256KiB chunks:
	// $ split -b 256k filename
	//
	// Then we can calculate the checksum of each:
	// $ md5 filename
	
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	NSURL *fileURL = [testFilesURL URLByAppendingPathComponent:@"Declaration of Independence.jpg"];
	
	NSDictionary *expected = @{
		@(0) : @"12fcf4cae0efe32183b9a1381f9d71aa",
		@(1) : @"7f2a5210022a4c4466b21f0dac6de286",
		@(2) : @"158eda0c79531dce84ec851d5498a082",
		@(3) : @"144edf2dd14654895ad12b65059af252",
		@(4) : @"5a257efaca07d0ccf84f8b51206baf83",
		@(5) : @"a7c09edaf5d0a8cb39c9dcab7dbae056",
		@(6) : @"85286a5d10c7e02cd433ce9d77443609",
		@(7) : @"bb1531ceeeb5b6c55cdbfde4a270010a",
	};
	
	uint64_t chunkSize = (1024 * 256);
	
	[self _testType:ZDCFileChecksumTest_File
	  withAlgorithm:algorithm
	           file:fileURL
	          range:nil
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	[self _testType:ZDCFileChecksumTest_Stream
	  withAlgorithm:algorithm
	           file:fileURL
	          range:nil
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	for (NSNumber *number in expected)
	{
		NSUInteger index = [number unsignedIntegerValue];
		NSString *expectedChecksum = expected[number];
		
		NSUInteger offset = chunkSize * index;
		NSUInteger length = chunkSize;
		
		NSRange range = NSMakeRange(offset, length);
		
		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:range]
		      chunkSize:nil
				 expected:@{ @(0): expectedChecksum}];
		
		[self _testType:ZDCFileChecksumTest_Stream
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:range]
		      chunkSize:nil
		       expected:@{ @(0): expectedChecksum}];
	}
}

- (void)test_MD5_weirdOffset
{
	const HASH_Algorithm algorithm = kHASH_Algorithm_MD5;
	
	// The following values were created using command-line tools on macOS.
	//
	// First, we split the "Declaration of Independence.jpg" file at some weird offset:
	// $ split -b 658764 "Declaration of Independence.jpg"
	//
	// This will create a bunch of files: xaa, xab, xac, xad
	// Delete the first chunk, and combine the last 3:
	// $ rm xaa
	// $ cat xa? >> goofy.bin
	//
	// Now, we split the "goofy.bin" file (1.3MB) into 256KiB chunks:
	// $ split -b 256k goofy.bin
	//
	// Then we can calculate the checksum of each:
	// $ md5 filename
	
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	NSURL *fileURL = [testFilesURL URLByAppendingPathComponent:@"Declaration of Independence.jpg"];
	
	NSDictionary *expected = @{
		@(0) : @"67c1ae6b4602cb22e969307d247d1d48",
		@(1) : @"0f54e452ab926ef8b78f0cf16aa0086e",
		@(2) : @"cd09df201eb031bac4570eb5c686bfbf",
		@(3) : @"f91e9c6a4cdbd40e6236ee64ce02155d",
		@(4) : @"306fe37e67881e2e2a7600fc99eb6e9a",
		@(5) : @"3e152dd2e23cd48afe3980cd38efe7a0",
	};
	
	NSRange range = NSMakeRange(658764, NSUIntegerMax);
	
	uint64_t chunkSize = (1024 * 256);
	
	[self _testType:ZDCFileChecksumTest_File
	  withAlgorithm:algorithm
	           file:fileURL
	          range:[NSValue valueWithRange:range]
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	[self _testType:ZDCFileChecksumTest_Stream
	  withAlgorithm:algorithm
	           file:fileURL
	          range:[NSValue valueWithRange:range]
	      chunkSize:@(chunkSize)
	       expected:expected];
	
	NSArray *orderedKeys = [[expected allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSNumber *number in orderedKeys)
	{
		NSUInteger index = [number unsignedIntegerValue];
		NSString *expectedChecksum = expected[number];
		
		NSUInteger offset = chunkSize * index;
		NSUInteger length = chunkSize;
		
		NSRange sub_range = NSMakeRange(range.location + offset, length);
		
		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:sub_range]
		      chunkSize:nil
		       expected:@{ @(0): expectedChecksum }];

		[self _testType:ZDCFileChecksumTest_File
		  withAlgorithm:algorithm
		           file:fileURL
		          range:[NSValue valueWithRange:sub_range]
		      chunkSize:nil
		       expected:@{ @(0): expectedChecksum }];
	}
}

- (void)_testType:(ZDCFileChecksumTest)testType
    withAlgorithm:(HASH_Algorithm)algorithm
         expected:(NSDictionary<NSString*, NSString*> *)expected
{
	NSURL *testFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Test Files" withExtension:nil];
	NSLog(@"testFilesURL: %@", [testFilesURL path]);
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL:testFilesURL
	                       includingPropertiesForKeys:nil
	                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler:nil];
	
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_queue_t queue = dispatch_queue_create("", DISPATCH_QUEUE_SERIAL);
	
	__block atomic_uint pendingCount = 1;
	
	for (NSURL *fileURL in enumerator)
	{
		NSLog(@"fileURL: %@", [fileURL path]);
		
		ZDCFileChecksumCallbackBlock callbackBlock =
			^(NSData *hash, uint64_t chunkIndex, BOOL done, NSError *error)
		{
			XCTAssert(done == YES);
			XCTAssert(error == nil);
			
			NSString *calculatedChecksum = [hash hexString];
			NSString *expectedChecksum = expected[fileURL.lastPathComponent];
			
			NSLog(@"=====================================================================");
			NSLog(@"file: %@", fileURL.lastPathComponent);
			NSLog(@"streamChecksum  : %@", calculatedChecksum);
			NSLog(@"expectedChecksum: %@", expectedChecksum);
			NSLog(@"=====================================================================");
			
			XCTAssert([calculatedChecksum isEqualToString:expectedChecksum],
				@"%@ - bad checksum: %@",
				[self algorithmName:algorithm],
				fileURL.lastPathComponent);
			
			uint newPendingCount = atomic_fetch_sub(&pendingCount, 1) - 1; // annoyingly returns previous value
			if (newPendingCount == 0)
			{
				dispatch_semaphore_signal(semaphore);
			}
		};
		
		ZDCFileChecksumInstruction *instruction = [[ZDCFileChecksumInstruction alloc] init];
		instruction.algorithm = algorithm;
		instruction.callbackQueue = queue;
		instruction.callbackBlock = callbackBlock;
		
		NSError *error = nil;
		if (testType == ZDCFileChecksumTest_File)
		{
			[ZDCFileChecksum checksumFileURL: fileURL
			                withInstructions: @[instruction]
			                           error: &error];
		}
		else
		{
			NSInputStream *stream = [NSInputStream inputStreamWithURL:fileURL];
			
			[ZDCFileChecksum checksumFileStream: stream
			                     withStreamSize: 0
			                       instructions: @[instruction]
			                              error: &error];
		}
		
		XCTAssert(error == nil);
		
		atomic_fetch_add(&pendingCount, 1);
	}
	
	atomic_fetch_sub(&pendingCount, 1);
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)_testType:(ZDCFileChecksumTest)testType
    withAlgorithm:(HASH_Algorithm)algorithm
             file:(NSURL *)fileURL
            range:(NSValue *)rangeValue
        chunkSize:(NSNumber *)chunkSizeNumber
         expected:(NSDictionary<NSNumber*, NSString*> *)expected
{
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_queue_t queue = dispatch_queue_create("", DISPATCH_QUEUE_SERIAL);
	
	__block NSUInteger count = 0;
	
	ZDCFileChecksumCallbackBlock callbackBlock =
		^(NSData *hash, uint64_t chunkIndex, BOOL done, NSError *error)
	{
		XCTAssert(error == nil);
		
		if (hash)
		{
			NSString *calculatedChecksum = [hash hexString];
			NSString *expectedChecksum = expected[@(chunkIndex)];
			
			NSLog(@"=====================================================================");
			NSLog(@"chunk: %llu", chunkIndex);
			NSLog(@"calculatedChecksum : %@", calculatedChecksum);
			NSLog(@"expectedChecksum   : %@", expectedChecksum);
			NSLog(@"=====================================================================");
			
			XCTAssert([calculatedChecksum isEqualToString:expectedChecksum],
				@"%@ - bad checksum (%llu): %@",
				[self algorithmName:algorithm],
				chunkIndex,
				fileURL.lastPathComponent);
			
			count++;
		}
		
		if (done)
		{
			dispatch_semaphore_signal(semaphore);
		}
	};
	
	ZDCFileChecksumInstruction *instruction = [[ZDCFileChecksumInstruction alloc] init];
	instruction.algorithm = algorithm;
	instruction.range = rangeValue;
	instruction.chunkSize = chunkSizeNumber;
	instruction.callbackQueue = queue;
	instruction.callbackBlock = callbackBlock;
	
	NSError *error = nil;
	if (testType == ZDCFileChecksumTest_File)
	{
		[ZDCFileChecksum checksumFileURL: fileURL
		                withInstructions: @[instruction]
		                           error: &error];
	}
	else
	{
		NSInputStream *stream = [NSInputStream inputStreamWithURL:fileURL];
		
		[ZDCFileChecksum checksumFileStream: stream
		                     withStreamSize: 0
		                       instructions: @[instruction]
		                              error: &error];
	}
	
	XCTAssert(error == nil);
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	XCTAssert(count == expected.count,
		@"Bad chunk count: %llu vs %llu",
		(unsigned long long)count,
		(unsigned long long)expected.count);
}

- (NSString *)algorithmName:(HASH_Algorithm)algorithm
{
	switch (algorithm)
	{
		case kHASH_Algorithm_SHA1       : return @"SHA-1";
		case kHASH_Algorithm_SHA224     : return @"SHA-224";
		case kHASH_Algorithm_SHA256     : return @"SHA-256";
		case kHASH_Algorithm_SHA384     : return @"SHA-384";
		case kHASH_Algorithm_SHA512     : return @"SHA-512";
		case kHASH_Algorithm_SHA512_256 : return @"SHA-512/256";
		case kHASH_Algorithm_SKEIN256   : return @"SKEIN-256";
		case kHASH_Algorithm_SKEIN512   : return @"SKEIN-512";
		case kHASH_Algorithm_SKEIN1024  : return @"SKEIN-1024";
		case kHASH_Algorithm_xxHash32   : return @"xxHash-32";
		case kHASH_Algorithm_xxHash64   : return @"xxHash-64";
		default                         : return @"Unknown";
	}
}

@end
