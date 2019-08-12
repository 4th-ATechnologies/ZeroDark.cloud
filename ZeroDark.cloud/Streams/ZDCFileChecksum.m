/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCFileChecksum.h"

#import "ZDCLogging.h"

#import "NSData+S4.h"
#import "NSError+POSIX.h"
#import "NSError+S4.h"

#import <S4Crypto/S4Crypto.h>

#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelVerbose | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@interface ZDCFileChecksumInstruction () {
@public
	
	NSError *error;
	
	HASH_ContextRef hashRef;
	
	void *hashBuffer;
	size_t hashBufferSize;
	
	uint64_t chunkIndex;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCFileChecksum

+ (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

+ (NSError *)abortedByUserError
{
	NSString *msg = @"Operation aborted by user via [progress cancel]";
	return [self errorWithDescription:msg];

}

/**
 * See header file for description.
**/
+ (NSProgress *)checksumFileURL:(NSURL *)fileURL
                  withAlgorithm:(HASH_Algorithm)algorithm
                completionQueue:(dispatch_queue_t)completionQueue
                completionBlock:(void (^)(NSData *digest, NSError *error))completionBlock
{
	ZDCFileChecksumCallbackBlock callbackBlock = ^(NSData *hash, uint64_t chunkIndex, BOOL done, NSError *error){
		
		if (completionBlock) {
			completionBlock(hash, error);
		}
	};
	
	ZDCFileChecksumInstruction *instruction = [[ZDCFileChecksumInstruction alloc] init];
	instruction.algorithm = algorithm;
	instruction.callbackQueue = completionQueue;
	instruction.callbackBlock = callbackBlock;
	
	NSError *error = nil;
	NSProgress *progress = [self checksumFileURL:fileURL withInstructions:@[instruction] error:&error];
	
	if (error)
	{
		dispatch_queue_t q = completionQueue ?: dispatch_get_main_queue();
		dispatch_async(q, ^{ @autoreleasepool {
			callbackBlock(nil, 0, YES, error);
		}});
	}
	
	return progress;
}

/**
 * See header file for description.
**/
+ (NSProgress *)checksumFileStream:(NSInputStream *)fileStream
                    withStreamSize:(uint64_t)streamSize
                         algorithm:(HASH_Algorithm)algorithm
                   completionQueue:(dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(NSData *hash, NSError *error))completionBlock
{
	ZDCFileChecksumCallbackBlock callbackBlock = ^(NSData *hash, uint64_t chunkIndex, BOOL done, NSError *error){
		
		if (completionBlock) {
			completionBlock(hash, error);
		}
	};
	
	ZDCFileChecksumInstruction *instruction = [[ZDCFileChecksumInstruction alloc] init];
	instruction.algorithm = algorithm;
	instruction.callbackQueue = completionQueue;
	instruction.callbackBlock = callbackBlock;
	
	NSError *error = nil;
	NSProgress *progress =
	  [self checksumFileStream:fileStream withStreamSize:streamSize instructions:@[instruction] error:&error];
	
	if (error)
	{
		dispatch_queue_t q = completionQueue ?: dispatch_get_main_queue();
		dispatch_async(q, ^{ @autoreleasepool {
			callbackBlock(nil, 0, YES, error);
		}});
	}
	
	return progress;
}

/**
 * See header file for description.
**/
+ (NSProgress *)checksumFileURL:(NSURL *)fileURL
               withInstructions:(NSArray<ZDCFileChecksumInstruction *> *)inInstructions
                          error:(NSError **)errorPtr
{
	if (fileURL == nil)
	{
		NSError *error = [self errorWithDescription:@"Bad parameter: fileURL is nil"];
		
		if (errorPtr) *errorPtr = error;
		return nil;
	}
	if (inInstructions.count == 0)
	{
		NSError *error = [self errorWithDescription:@"Bad parameter: instructions is nil or empty"];
		
		if (errorPtr) *errorPtr = error;
		return nil;
	}
	
	NSArray<ZDCFileChecksumInstruction *> *instructions = [[NSArray alloc] initWithArray:inInstructions copyItems:YES];
	
	// Validate the instructions
	
	NSRange minRange = NSMakeRange(0, 0);
	
	NSError *badInstructionError = nil;
	NSUInteger i = 0;
	for (ZDCFileChecksumInstruction *instruction in instructions)
	{
		if (instruction.algorithm == kHASH_Algorithm_Invalid)
		{
			NSString *msg = [NSString stringWithFormat:
			  @"instruction[%llu].algorithm == kHASH_Algorithm_Invalid", (unsigned long long)i];
			
			badInstructionError = [self errorWithDescription:msg];
			break;
		}
		
		if (instruction.callbackBlock == nil)
		{
			NSString *msg = [NSString stringWithFormat:
			  @"instruction[%llu].callbackBlock == nil", (unsigned long long)i];
			
			badInstructionError = [self errorWithDescription:msg];
			break;
		}
		
		if (instruction.range)
		{
			// User wants a subset of the file/stream
			
			NSRange iRange = [instruction.range rangeValue];
			if (iRange.length == 0)
			{
				NSString *msg = [NSString stringWithFormat:
				  @"instruction[%llu].range.length == 0", (unsigned long long)i];
				
				badInstructionError = [self errorWithDescription:msg];
				break;
			}
			
			NSUInteger iRangeMaxLength = NSUIntegerMax - iRange.location;
			if (iRange.length > iRangeMaxLength)
			{
				// This should have been sanitized automatically in the setRange property.
				
				NSString *msg = [NSString stringWithFormat:
				  @"instruction[%llu].range: location + length = overflow", (unsigned long long)i];
				
				badInstructionError = [self errorWithDescription:msg];
				break;
			}
			
			if (i == 0)
			{
				minRange = iRange;
			}
			else
			{
				NSRange iRange = [instruction.range rangeValue];
				
			#pragma clang diagnostic push
			#pragma clang diagnostic ignored "-Wambiguous-macro"
				
				NSUInteger min = MIN(minRange.location, iRange.location);
				NSUInteger max = MAX(NSMaxRange(minRange), NSMaxRange(iRange));
				
			#pragma clang diagnostic pop
				
				minRange = NSMakeRange(min, (max - min));
			}
		}
		else
		{
			// User wants the full file/stream
			
			minRange = NSMakeRange(0, NSUIntegerMax);
		}
		
		if (instruction.callbackQueue == nil)
			instruction.callbackQueue = dispatch_get_main_queue();
		
		i++;
	}
	
	if (badInstructionError)
	{
		if (errorPtr) *errorPtr = badInstructionError;
		return nil;
	}
	
	// Read basic IO information,
	// and configure low/high watermark settings.
	
	NSArray<NSURLResourceKey> *attrKeys = @[NSURLPreferredIOBlockSizeKey, NSURLFileSizeKey];
	NSDictionary<NSURLResourceKey,id> *attrs = [fileURL resourceValuesForKeys:attrKeys error:nil];
	
	uint64_t waterMark = 0;
	
	NSNumber *preferredIOBlockSize = attrs[NSURLPreferredIOBlockSizeKey];
	if (preferredIOBlockSize != nil) {
		waterMark = [preferredIOBlockSize unsignedLongLongValue];
	}
	else {
		waterMark = (1024 * 32); // Pick a sane default chunk size
	}
	
	NSNumber *fileSize = attrs[NSURLFileSizeKey];
	
	// Setup progress
	
	NSProgress *progress = nil;
	progress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
	progress.pausable = NO;
	progress.cancellable = YES;
	
	if (fileSize != nil)
	{
		uint64_t fMax = [fileSize unsignedLongLongValue];
		uint64_t rMax = NSMaxRange(minRange);
		
		uint64_t min = minRange.location;
		uint64_t max = MIN(fMax, rMax);
		
		uint64_t expectedByteCount = max - min;
		
		int64_t totalUnitCount = (int64_t)(expectedByteCount / waterMark);
		if ((expectedByteCount % waterMark) != 0) {
			totalUnitCount++;
		}
		
		progress.totalUnitCount = totalUnitCount;
	}
	else
	{
		progress.totalUnitCount = 0;
	}
	
	// Setup helper blocks
	
	void (^InvokeAllCallbackBlocksWithError)(NSError *) =
	^void (NSError *error){
		
		for (ZDCFileChecksumInstruction *instruction in instructions)
		{
			if (instruction->error) continue;
			
			instruction->error = error;
			dispatch_async(instruction.callbackQueue, ^{ @autoreleasepool {
				
				instruction.callbackBlock(nil, instruction->chunkIndex, YES, instruction->error);
			}});
		}
	};
	
	void (^InvokeCallbackBlockWithError)(ZDCFileChecksumInstruction *) =
	^void (ZDCFileChecksumInstruction *instruction){
		
		NSAssert(instruction->error != nil, @"Bad state");
		
		dispatch_async(instruction.callbackQueue, ^{ @autoreleasepool {
			
			instruction.callbackBlock(nil, instruction->chunkIndex, YES, instruction->error);
		}});
	};
	
	void (^InvokeCallbackBlockWithHash)(ZDCFileChecksumInstruction *, NSData *, uint64_t, BOOL) =
	^void (ZDCFileChecksumInstruction *instruction, NSData *hash, uint64_t chunkIndex, BOOL done){
		
		// Important: the chunkIndex is a parameter because we need to copy it.
		// That is, after invoking this function, instruction->chunkIndex is incremented.
		// But we're performing an async operation here, so we need to be sure we have the correct
		// chunkIndex value when the dispatch_async block actually executes.
		
		dispatch_async(instruction.callbackQueue, ^{ @autoreleasepool {
			
			instruction.callbackBlock(hash, chunkIndex, done, nil);
		}});
	};
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
	
		// Setup dispatch_io channel
		//
		// IMPORTANT:
		//
		//   There is a BUG in dispatch_io_cancel.
		//   It causes mysterious looking crashes when draining the autorelease pool within GCD.
		//
		//   After spending half a day tracking down this bug, I was finally able to pinpoint that
		//   the problem was indeed the call to dispatch_io_cancel.
		//   (I could reliably enable/disable the crash by simply commenting out a single line of code.)
		//
		//   After much searching, I finally stumbled across this comment on StackOverflow:
		//   https://stackoverflow.com/questions/9550676/proper-disposal-of-a-grand-central-dispatch-i-o-channel
		//
		//   "It turns out this is a bug (radar #10246694). Further experimenting seems to indicate
		//    that it only affects path-based dispatch channels, i.e. those created with
		//    dispatch_io_create_with_path(), as opposed to dispatch_io_create()."
		//
		//   After making the change, indeed this appears to still be true.
		//   So we need to handle the file opening/closing ourself.
		
	// Do NOT use this code.
	// It causes CRASHES via dispatch_io_cancel. (See note above)
	//
	//	dispatch_io_t channel =
	//	  dispatch_io_create_with_path(DISPATCH_IO_RANDOM,
	//	                               [filePath UTF8String],
	//	                               O_RDONLY,                // flags to pass to the open function
	//	                               0,                       // mode to pass to the open function
	//	                               io_queue,                // queue for cleanup block
	//											 cleanupHandler);         // cleanup block
		
		int fd = open([[fileURL path] UTF8String], O_RDONLY);
		if (fd < 0)
		{
			NSError *error = [self errorWithDescription:@"Unable to open file."];
			
			InvokeAllCallbackBlocksWithError(error);
			return;
		}
		
		dispatch_queue_t io_queue = dispatch_queue_create("ZDCFileChecksum", DISPATCH_QUEUE_SERIAL);
		
		void (^cleanupHandler)(int error) = ^(int error){
			
			close(fd);
		};
		
		dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_RANDOM, fd, io_queue, cleanupHandler);
		if (channel == NULL)
		{
			NSError *error = [self errorWithDescription:@"Unable to open channel."];
			
			InvokeAllCallbackBlocksWithError(error);
			return;
		}
		
		dispatch_io_set_low_water(channel, (size_t)waterMark);
		dispatch_io_set_high_water(channel, (size_t)waterMark);
	
		// Start IO
			
		off_t read_offset = (off_t)minRange.location;
		size_t read_length;
		
		if (minRange.length == NSUIntegerMax)
			read_length = SIZE_MAX;
		else
			read_length = (size_t)minRange.length;
		
		__block BOOL aborted = NO;
		__block uint64_t dispatchReadCount = 0;
		
		__block uint64_t fileStart = read_offset;
		__block uint64_t fileOffset = read_offset;
		
		dispatch_io_read(channel, read_offset, read_length, io_queue,
			^(bool done, dispatch_data_t data, int dispatch_error){ @autoreleasepool {
			
			if (aborted) return;
			if (progress.cancelled)
			{
				aborted = YES;
				dispatch_io_close(channel, DISPATCH_IO_STOP);
				
				NSError *error = [self abortedByUserError];
				
				InvokeAllCallbackBlocksWithError(error);
				return;
			}
			
			size_t dataSize = data ? dispatch_data_get_size(data) : 0;
			if (dataSize > 0)
			{
				for (ZDCFileChecksumInstruction *instruction in instructions)
				{
					if (instruction->error)
					{
						// We've already fired an error for this instruction.
						continue;
					}
					
					NSRange instruction_range = NSMakeRange(0, 0);
					BOOL instruction_hasRange = NO;
					
					if (instruction.range)
					{
						instruction_range = [instruction.range rangeValue];
						instruction_hasRange = YES;
					}
					
					uint64_t instruction_chunkSize = 0;
					BOOL instruction_hasChunkSize = NO;
					
					if (instruction.chunkSize != nil)
					{
						instruction_chunkSize = [instruction.chunkSize unsignedLongLongValue];
						instruction_hasChunkSize = YES;
					}
					
					dispatch_data_apply(data,
						^bool(dispatch_data_t region, size_t regionOffset, const void *buffer, size_t fullBufferSize)
					{
						if (fullBufferSize == 0) {
							return true; // ignore empty data (defensive programming)
						}
						
						size_t bufferOffset = 0;
						size_t bufferSize = fullBufferSize;
						
						if (instruction_hasRange)
						{
							NSRange regionRange = NSMakeRange((NSUInteger)(fileOffset + regionOffset), bufferSize);
							NSRange intersectionRange = NSIntersectionRange(regionRange, instruction_range);
							
							// From the docs: NSIntersectionRange:
							//
							// If the returned range’s length field is 0,
							// then the two ranges don’t intersect, and the value of the location field is undefined.
							
							if (intersectionRange.length == 0)
							{
								// Nothing to hash in this region
								bufferOffset = bufferSize;
							}
							else
							{
								bufferOffset = intersectionRange.location - regionRange.location;
								bufferSize = bufferOffset + intersectionRange.length;
								
								NSAssert(bufferSize <= fullBufferSize, @"Either 'math is hard' or range was out-of-bounds");
							}
						}
						
						S4Err err = kS4Err_NoErr;
						
						while (bufferOffset < bufferSize)
						{
							size_t sizeToHash = 0;
							
							if (instruction->hashRef == kInvalidHASH_ContextRef)
							{
								err = HASH_Init(instruction.algorithm, &instruction->hashRef);
								
								if (err != kS4Err_NoErr)
								{
									ZDCLogWarn(@"HASH_Init: err = %d", err);
									
									instruction->error = [NSError errorWithS4Error:err];
									InvokeCallbackBlockWithError(instruction);
									
									return false; // from dispatch_data_apply
								}
								
								if (instruction->hashBuffer == NULL)
								{
									HASH_GetSize(instruction->hashRef, &instruction->hashBufferSize);
									instruction->hashBuffer = malloc(instruction->hashBufferSize);
								}
							}
							
							if (instruction_hasChunkSize)
							{
								// We're supposed to be hashing in chunks.
								// For example, every 1K chunk gets its own checksum.
								//
								// Let's look at a few examples.
								//
								// Example #1:
								// - instruction_chunkSize = 1024
								// - region_start = 0
								// - region_end = 1000
								//
								// Example #2:
								// - instruction_chunkSize = 1024
								// - region_start = 0
								// - region_end = 2000
								//
								// Example #3:
								// - instruction_chunkSize = 1024
								// - region_start = 1000
								// - region_end = 1050
								//
								// Example #4:
								// - instruction_chunkSize = 1024
								// - region_start = 2000
								// - region_end = 4000
								
								uint64_t region_offset = (fileOffset + regionOffset + bufferOffset) - fileStart;
								
								uint64_t leftInChunk = instruction_chunkSize - (region_offset % instruction_chunkSize);
								uint64_t leftInRegion = bufferSize - bufferOffset;
								
								sizeToHash = (NSUInteger)MIN(leftInChunk, leftInRegion);
								
								// Calculation of sizeToHash
								//
								// Example #1:
								// leftInChunk = 1024
								// leftInRegion = 1000
								// sizeToHash = 1000
								//
								// Example #2
								// leftInChunk = 1024
								// leftInRegion = 2000
								// sizeToHash = 1024
								//
								// Example #3:
								// leftInChunk = 24
								// leftInRegion = 50
								// sizeToHash = 24
								//
								// Example #4:
								// leftInChunk = 48
								// leftInRegion = 2000
								// sizeToHash = 48
								
								err = HASH_Update(instruction->hashRef, (buffer + bufferOffset), sizeToHash);
								
								if (err != kS4Err_NoErr)
								{
									ZDCLogWarn(@"HASH_Update: err = %d", err);
									
									instruction->error = [NSError errorWithS4Error:err];
									InvokeCallbackBlockWithError(instruction);
									
									return false; // from dispatch_data_apply
								}
								
								if (sizeToHash == leftInChunk)
								{
									err = HASH_Final(instruction->hashRef, instruction->hashBuffer);
									
									if (err != kS4Err_NoErr)
									{
										ZDCLogWarn(@"HASH_Final: err = %d", err);
										
										instruction->error = [NSError errorWithS4Error:err];
										InvokeCallbackBlockWithError(instruction);
										
										return false; // from dispatch_data_apply
									}
									
									NSData *chunkChecksum = // copy bytes
									  [NSData dataWithBytes:instruction->hashBuffer
														  length:instruction->hashBufferSize];
									
									InvokeCallbackBlockWithHash(instruction, chunkChecksum, instruction->chunkIndex, NO);
									instruction->chunkIndex++;
									
									HASH_Free(instruction->hashRef);
									instruction->hashRef = kInvalidHASH_ContextRef;
								}
								
							}
							else
							{
								// We're hashing the entire file/stream.
								
								sizeToHash = bufferSize - bufferOffset;
								err = HASH_Update(instruction->hashRef, (buffer + bufferOffset), sizeToHash);
								
								if (err != kS4Err_NoErr)
								{
									ZDCLogWarn(@"HASH_Update: err = %d", err);
									
									instruction->error = [NSError errorWithS4Error:err];
									InvokeCallbackBlockWithError(instruction);
									
									return false; // from dispatch_data_apply
								}
							}
							
							bufferOffset += sizeToHash;
						
						} // end while (bufferOffset < bufferSize)
						
						return true;
						
					}); // end dispatch_data_apply()
				}
				
				if (fileSize != nil)
				{
					dispatchReadCount++;
					progress.completedUnitCount = (int64_t)dispatchReadCount;
				}
				fileOffset += dataSize;
			}
			
			if (done)
			{
				for (ZDCFileChecksumInstruction *instruction in instructions)
				{
					if (instruction->error)
					{
						// We've already fired an error for this instruction.
						continue;
					}
					
					S4Err err = kS4Err_NoErr;
					
					if (fileOffset == 0 && instruction.range == nil)
					{
						// Edge case:
						// - we're hashing an empty file
						// - this instruction is for the entire file
						
						if (instruction->hashRef == kInvalidHASH_ContextRef)
						{
							err = HASH_Init(instruction.algorithm, &instruction->hashRef);
							
							if (err != kS4Err_NoErr)
							{
								ZDCLogWarn(@"HASH_Init: err = %d", err);
								
								instruction->error = [NSError errorWithS4Error:err];
								InvokeCallbackBlockWithError(instruction);
								
								continue;
							}
							
							if (instruction->hashBuffer == NULL)
							{
								HASH_GetSize(instruction->hashRef, &instruction->hashBufferSize);
								instruction->hashBuffer = malloc(instruction->hashBufferSize);
							}
						}
					}
					
					if (instruction->hashRef != kInvalidHASH_ContextRef)
					{
						err = HASH_Final(instruction->hashRef, instruction->hashBuffer);
						
						if (err != kS4Err_NoErr)
						{
							ZDCLogWarn(@"HASH_Final: err = %d", err);
							
							instruction->error = [NSError errorWithS4Error:err];
							InvokeCallbackBlockWithError(instruction);
							
							continue;
						}
						
						NSData *chunkChecksum = // copy bytes
						  [NSData dataWithBytes:instruction->hashBuffer
											  length:instruction->hashBufferSize];
						
						BOOL done = (instruction.chunkSize != nil) ? NO : YES;
						
						InvokeCallbackBlockWithHash(instruction, chunkChecksum, instruction->chunkIndex, done);
						instruction->chunkIndex++;
						
						HASH_Free(instruction->hashRef);
						instruction->hashRef = kInvalidHASH_ContextRef;
					}
					
					if (instruction.range)
					{
						// Edge case:
						// - we're hashing a range
						// - the range was out-of-bounds
						//
						// We can detect this by simply looking at the chunkIndex.
						// If it's still zero, then the callback has never been fired.
						
						if (instruction->chunkIndex == 0)
						{
							NSString *msg = [NSString stringWithFormat:
							  @"Range is out-of-bounds for file/stream with length %llu", (unsigned long long)fileOffset];
							
							instruction->error = [self errorWithDescription:msg];
							InvokeCallbackBlockWithError(instruction);
							
							continue;
						}
					}
					
					if (instruction.chunkSize != nil)
					{
						// Fire last callback for chunk'd instruction.
						
						InvokeCallbackBlockWithHash(instruction, nil, instruction->chunkIndex, YES);
						instruction->chunkIndex++;
					}
				}
				
				progress.completedUnitCount = progress.totalUnitCount;
			}
			
			if (dispatch_error)
			{
				NSString *msg = [NSString stringWithFormat:@"dispatch_io_read failed with error: %d", dispatch_error];
				NSError *error = [self errorWithDescription:msg];
				
				InvokeAllCallbackBlocksWithError(error);
				
				progress.completedUnitCount = progress.totalUnitCount;
			}
			
		}}); // end dispatch_io_read(...)
		
	}}); // end dispatch_async(bgQueue, ...)
	
	return progress;
}

/**
 * See header file for description.
**/
+ (NSProgress *)checksumFileStream:(NSInputStream *)fileStream
                    withStreamSize:(uint64_t)streamSize
                      instructions:(NSArray<ZDCFileChecksumInstruction *> *)inInstructions
                             error:(NSError **)errorPtr
{
	if (fileStream == nil)
	{
		NSError *error = [self errorWithDescription:@"Bad parameter: fileStream is nil"];
		
		if (errorPtr) *errorPtr = error;
		return nil;
	}
	if (inInstructions.count == 0)
	{
		NSError *error = [self errorWithDescription:@"Bad parameter: instructions is nil or empty"];
		
		if (errorPtr) *errorPtr = error;
		return nil;
	}
	
	NSArray<ZDCFileChecksumInstruction *> *instructions = [[NSArray alloc] initWithArray:inInstructions copyItems:YES];
	
	// Validate the instructions
	
	__block NSRange minRange = NSMakeRange(0, 0);
	
	NSError *badInstructionError = nil;
	NSUInteger i = 0;
	for (ZDCFileChecksumInstruction *instruction in instructions)
	{
		if (instruction.algorithm == kHASH_Algorithm_Invalid)
		{
			NSString *msg = [NSString stringWithFormat:
			  @"instruction[%llu].algorithm == kHASH_Algorithm_Invalid", (unsigned long long)i];
			
			badInstructionError = [self errorWithDescription:msg];
			break;
		}
		
		if (instruction.callbackBlock == nil)
		{
			NSString *msg = [NSString stringWithFormat:
			  @"instruction[%llu].callbackBlock == nil", (unsigned long long)i];
			
			badInstructionError = [self errorWithDescription:msg];
			break;
		}
		
		if (instruction.range)
		{
			// User wants a subset of the file/stream
			
			NSRange iRange = [instruction.range rangeValue];
			if (iRange.length == 0)
			{
				NSString *msg = [NSString stringWithFormat:
				  @"instruction[%llu].range.length == 0", (unsigned long long)i];
				
				badInstructionError = [self errorWithDescription:msg];
				break;
			}
			
			NSUInteger iRangeMaxLength = NSUIntegerMax - iRange.location;
			if (iRange.length > iRangeMaxLength)
			{
				// This should have been sanitized automatically in the setRange property.
				
				NSString *msg = [NSString stringWithFormat:
					@"instruction[%llu].range: location + length = overflow", (unsigned long long)i];
				
				badInstructionError = [self errorWithDescription:msg];
				break;
			}
			
			if (i == 0)
			{
				minRange = iRange;
			}
			else
			{
				NSRange iRange = [instruction.range rangeValue];
				
			#pragma clang diagnostic push
			#pragma clang diagnostic ignored "-Wambiguous-macro"
				
				NSUInteger min = MIN(minRange.location, iRange.location);
				NSUInteger max = MAX(NSMaxRange(minRange), NSMaxRange(iRange));
				
			#pragma clang diagnostic pop
				
				minRange = NSMakeRange(min, (max - min));
			}
		}
		else
		{
			// User wants the full file/stream
			
			minRange = NSMakeRange(0, NSUIntegerMax);
		}
		
		if (instruction.callbackQueue == nil)
			instruction.callbackQueue = dispatch_get_main_queue();
		
		i++;
	}
	
	if (badInstructionError)
	{
		if (errorPtr) *errorPtr = badInstructionError;
		return nil;
	}
	
	// Setup progress
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];;
	progress.pausable = NO;
	progress.cancellable = YES;
	
	if (streamSize > 0)
	{
		uint64_t sMax = streamSize;
		uint64_t rMax = NSMaxRange(minRange);
		
		uint64_t min = minRange.location;
		uint64_t max = MIN(sMax, rMax);
		
		uint64_t expectedByteCount = max - min;
		
		progress.totalUnitCount = (int64_t)expectedByteCount;
	}
	else
	{
		progress.totalUnitCount = 0;
	}
	
	// Setup helper blocks
	
	void (^InvokeAllCallbackBlocksWithError)(NSError *) =
	^void (NSError *error){
		
		for (ZDCFileChecksumInstruction *instruction in instructions)
		{
			if (instruction->error) continue;
			
			instruction->error = error;
			dispatch_async(instruction.callbackQueue, ^{ @autoreleasepool {
				
				instruction.callbackBlock(nil, instruction->chunkIndex, YES, instruction->error);
			}});
		}
	};
	
	void (^InvokeCallbackBlockWithError)(ZDCFileChecksumInstruction *) =
	^void (ZDCFileChecksumInstruction *instruction){
		
		NSAssert(instruction->error != nil, @"Bad state");
		
		dispatch_async(instruction.callbackQueue, ^{ @autoreleasepool {
			
			instruction.callbackBlock(nil, instruction->chunkIndex, YES, instruction->error);
		}});
	};
	
	void (^InvokeCallbackBlockWithHash)(ZDCFileChecksumInstruction *, NSData *, uint64_t, BOOL) =
	^void (ZDCFileChecksumInstruction *instruction, NSData *hash, uint64_t chunkIndex, BOOL done){
		
		// Important: the chunkIndex is a parameter because we need to copy it.
		// That is, after invoking this function, instruction->chunkIndex is incremented.
		// But we're performing an async operation here, so we need to be sure we have the correct
		// chunkIndex value when the dispatch_async block actually executes.
		
		dispatch_async(instruction.callbackQueue, ^{ @autoreleasepool {
			
			instruction.callbackBlock(hash, chunkIndex, done, nil);
		}});
	};
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		if (progress.cancelled)
		{
			NSError *error = [self abortedByUserError];
			
			InvokeAllCallbackBlocksWithError(error);
			return;
		}

		[fileStream open];
		
		if (fileStream.streamStatus != NSStreamStatusOpen || fileStream.streamError)
		{
			NSError *error = fileStream.streamError;
			if (error == nil) {
				error = [self errorWithDescription:@"Error opening fileStream"];
			}
			
			InvokeAllCallbackBlocksWithError(error);
			return;
		}
		
		uint64_t fileStart = 0;
		uint64_t fileOffset = 0;
		
		if (minRange.location > 0)
		{
			BOOL canSeek = [fileStream setProperty:@(minRange.location) forKey:NSStreamFileCurrentOffsetKey];
			
			if (canSeek)
			{
				fileStart = minRange.location;
				fileOffset = minRange.location;
			}
			else
			{
				// The stream doesn't support seeking.
				// So we're going to have to read from the beginning.
				
				// Update minRange
				
				NSUInteger diff = minRange.location;
				minRange.location = 0;
				minRange.length += diff;
				
				// Update progress.totalUnitCount (if needed)
				
				if (streamSize > 0)
				{
					uint64_t sMax = streamSize;
					uint64_t rMax = NSMaxRange(minRange);
					
					uint64_t min = minRange.location;
					uint64_t max = MIN(sMax, rMax);
					
					uint64_t expectedByteCount = max - min;
					
					progress.totalUnitCount = (int64_t)expectedByteCount;
				}
			}
		}
		
		size_t bufferMallocSize = (1024 * 64);
		void *buffer = malloc(bufferMallocSize);
		
		do {
			
			if (progress.cancelled)
			{
				NSError *error = [self abortedByUserError];
				
				InvokeAllCallbackBlocksWithError(error);
				if (buffer)
				{
					free(buffer);
					buffer = NULL;
				}
				return;
			}
			
			// Read from the input stream
			
			NSUInteger bytesLeftInMinRange = NSMaxRange(minRange) - (NSUInteger)fileOffset;
			NSUInteger bytesToRead = MIN(bytesLeftInMinRange, bufferMallocSize);
			
			NSAssert(bytesToRead > 0, @"Logic error");
			
			NSInteger bytesRead = [fileStream read:buffer maxLength:bytesToRead];
			
			if (bytesRead < 0)
			{
				// Error reading
				
				NSError *error = fileStream.streamError;
				if (error == nil) {
					error = [self errorWithDescription:@"Error reading fileStream"];
				}
				
				InvokeAllCallbackBlocksWithError(error);
				if (buffer)
				{
					free(buffer);
					buffer = NULL;
				}
				return;
			}
			else if (bytesRead == 0)
			{
				// End of stream
				
				break;
			}
			
			// Process bytes
			
			for (ZDCFileChecksumInstruction *instruction in instructions)
			{
				if (instruction->error)
				{
					// We've already fired an error for this instruction.
					continue;
				}
				
				NSRange instruction_range = NSMakeRange(0, 0);
				BOOL instruction_hasRange = NO;
				
				if (instruction.range)
				{
					instruction_range = [instruction.range rangeValue];
					instruction_hasRange = YES;
				}
				
				uint64_t instruction_chunkSize = 0;
				BOOL instruction_hasChunkSize = NO;
				
				if (instruction.chunkSize != nil)
				{
					instruction_chunkSize = [instruction.chunkSize unsignedLongLongValue];
					instruction_hasChunkSize = YES;
				}
				
				size_t bufferSize = bytesRead;
				size_t bufferOffset = 0;
				
				if (instruction_hasRange)
				{
					NSRange bufferRange = NSMakeRange((NSUInteger)fileOffset, (NSUInteger)bufferSize);
					NSRange intersectionRange = NSIntersectionRange(bufferRange, instruction_range);
					
					// From the docs: NSIntersectionRange:
					//
					// If the returned range’s length field is 0,
					// then the two ranges don’t intersect, and the value of the location field is undefined.
					
					if (intersectionRange.length == 0)
					{
						// Nothing to hash in this region
						bufferOffset = bufferSize;
					}
					else
					{
						bufferOffset = intersectionRange.location - bufferRange.location;
						bufferSize = bufferOffset + intersectionRange.length;
						
						NSAssert(bufferSize <= bytesRead, @"Either 'math is hard' or range was out-of-bounds");
					}
				}
				
				S4Err err = kS4Err_NoErr;
				
				while (bufferOffset < bufferSize)
				{
					size_t sizeToHash = 0;
					
					if (instruction->hashRef == kInvalidHASH_ContextRef)
					{
						err = HASH_Init(instruction.algorithm, &instruction->hashRef);
						
						if (err != kS4Err_NoErr)
						{
							ZDCLogWarn(@"HASH_Init: err = %d", err);
							
							instruction->error = [NSError errorWithS4Error:err];
							InvokeCallbackBlockWithError(instruction);
							
							break;
						}
						
						if (instruction->hashBuffer == NULL)
						{
							HASH_GetSize(instruction->hashRef, &instruction->hashBufferSize);
							instruction->hashBuffer = malloc(instruction->hashBufferSize);
						}
					}
					
					if (instruction_hasChunkSize)
					{
						// We're supposed to be hashing in chunks.
						// For example, every 1K chunk gets its own checksum.
						//
						// Let's look at a few examples.
						//
						// Example #1:
						// - instruction_chunkSize = 1024
						// - region_start = 0
						// - region_end = 1000
						//
						// Example #2:
						// - instruction_chunkSize = 1024
						// - region_start = 0
						// - region_end = 2000
						//
						// Example #3:
						// - instruction_chunkSize = 1024
						// - region_start = 1000
						// - region_end = 1050
						//
						// Example #4:
						// - instruction_chunkSize = 1024
						// - region_start = 2000
						// - region_end = 4000
						
						uint64_t region_offset = (fileOffset + bufferOffset) - fileStart;
						
						uint64_t leftInChunk = instruction_chunkSize - (region_offset % instruction_chunkSize);
						uint64_t leftInRegion = bufferSize - bufferOffset;
						
						sizeToHash = (size_t)MIN(leftInChunk, leftInRegion);
						
						// Calculation of sizeToHash
						//
						// Example #1:
						// leftInChunk = 1024
						// leftInRegion = 1000
						// sizeToHash = 1000
						//
						// Example #2
						// leftInChunk = 1024
						// leftInRegion = 2000
						// sizeToHash = 1024
						//
						// Example #3:
						// leftInChunk = 24
						// leftInRegion = 50
						// sizeToHash = 24
						//
						// Example #4:
						// leftInChunk = 48
						// leftInRegion = 2000
						// sizeToHash = 48
						
						err = HASH_Update(instruction->hashRef, (buffer + bufferOffset), sizeToHash);
						
						if (err != kS4Err_NoErr)
						{
							ZDCLogWarn(@"HASH_Update: err = %d", err);
							
							instruction->error = [NSError errorWithS4Error:err];
							InvokeCallbackBlockWithError(instruction);
							
							break;
						}
						
						if (sizeToHash == leftInChunk)
						{
							err = HASH_Final(instruction->hashRef, instruction->hashBuffer);
							
							if (err != kS4Err_NoErr)
							{
								ZDCLogWarn(@"HASH_Final: err = %d", err);
								
								instruction->error = [NSError errorWithS4Error:err];
								InvokeCallbackBlockWithError(instruction);
								
								break;
							}
							
							NSData *chunkChecksum = // copy bytes
							[NSData dataWithBytes:instruction->hashBuffer
												length:instruction->hashBufferSize];
							
							InvokeCallbackBlockWithHash(instruction, chunkChecksum, instruction->chunkIndex, NO);
							instruction->chunkIndex++;
							
							HASH_Free(instruction->hashRef);
							instruction->hashRef = kInvalidHASH_ContextRef;
						}
						
					}
					else
					{
						// We're hashing the entire file/stream.
						
						sizeToHash = bufferSize - bufferOffset;
						err = HASH_Update(instruction->hashRef, (buffer + bufferOffset), sizeToHash);
						
						if (err != kS4Err_NoErr)
						{
							ZDCLogWarn(@"HASH_Update: err = %d", err);
							
							instruction->error = [NSError errorWithS4Error:err];
							InvokeCallbackBlockWithError(instruction);
							
							break;
						}
					}
					
					bufferOffset += sizeToHash;
					
				} // end while (bufferOffset < bufferSize)
			
			} // end for (ZDCFileChecksumInstruction *instruction in instructions)
			
			// Updates offsets & progress
			
			fileOffset += bytesRead;
			progress.completedUnitCount = (fileOffset - fileStart);
			
			if (fileOffset >= NSMaxRange(minRange))
			{
				// We read as many bytes as needed according to given instruction(s)
				
				break;
			}
			
		} while (YES);
		
		
		for (ZDCFileChecksumInstruction *instruction in instructions)
		{
			if (instruction->error)
			{
				// We've already fired an error for this instruction.
				continue;
			}
			
			S4Err err = kS4Err_NoErr;
			
			if (fileOffset == 0 && instruction.range == nil)
			{
				// Edge case:
				// - we're hashing an empty file
				// - this instruction is for the entire file
				
				if (instruction->hashRef == kInvalidHASH_ContextRef)
				{
					err = HASH_Init(instruction.algorithm, &instruction->hashRef);
					
					if (err != kS4Err_NoErr)
					{
						ZDCLogWarn(@"HASH_Init: err = %d", err);
						
						instruction->error = [NSError errorWithS4Error:err];
						InvokeCallbackBlockWithError(instruction);
						
						continue;
					}
					
					if (instruction->hashBuffer == NULL)
					{
						HASH_GetSize(instruction->hashRef, &instruction->hashBufferSize);
						instruction->hashBuffer = malloc(instruction->hashBufferSize);
					}
				}
			}
			
			if (instruction->hashRef != kInvalidHASH_ContextRef)
			{
				err = HASH_Final(instruction->hashRef, instruction->hashBuffer);
				
				if (err != kS4Err_NoErr)
				{
					ZDCLogWarn(@"HASH_Final: err = %d", err);
					
					instruction->error = [NSError errorWithS4Error:err];
					InvokeCallbackBlockWithError(instruction);
					
					continue;
				}
				
				NSData *chunkChecksum = // copy bytes
				  [NSData dataWithBytes:instruction->hashBuffer
				                 length:instruction->hashBufferSize];
				
				BOOL done = (instruction.chunkSize != nil) ? NO : YES;
				
				InvokeCallbackBlockWithHash(instruction, chunkChecksum, instruction->chunkIndex, done);
				instruction->chunkIndex++;
				
				HASH_Free(instruction->hashRef);
				instruction->hashRef = kInvalidHASH_ContextRef;
			}
			
			if (instruction.range)
			{
				// Edge case:
				// - we're hashing a range
				// - the range was out-of-bounds
				//
				// We can detect this by simply looking at the chunkIndex.
				// If it's still zero, then the callback has never been fired.
				
				if (instruction->chunkIndex == 0)
				{
					NSString *msg = [NSString stringWithFormat:
					  @"Range is out-of-bounds for file/stream with length %llu", (unsigned long long)fileOffset];
					
					instruction->error = [self errorWithDescription:msg];
					InvokeCallbackBlockWithError(instruction);
					
					continue;
				}
			}
			
			if (instruction.chunkSize != nil)
			{
				// Fire last callback for chunk'd instruction.
				
				InvokeCallbackBlockWithHash(instruction, nil, instruction->chunkIndex, YES);
				instruction->chunkIndex++;
			}
		}
		
		progress.completedUnitCount = progress.totalUnitCount;
		
		if (buffer)
		{
			free(buffer);
			buffer = nil;
		}
	}});
	
	return progress;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCFileChecksumInstruction

@synthesize algorithm = algorithm;
@synthesize range = range;
@synthesize chunkSize = chunkSize;
@synthesize callbackQueue = callbackQueue;
@synthesize callbackBlock = callbackBlock;

- (void)setRange:(NSValue *)value
{
	// Sanitize the range such that NSMaxRange() doesn't exceed NSUIntegerMax.
	// If we don't do this then NSIntersectionRange() runs into overflow issues.
	
	NSValue *sanitizedValue = nil;
	if (value)
	{
		NSRange sanitizedRange = [value rangeValue];
		if (sanitizedRange.location == 0 && sanitizedRange.length == NSUIntegerMax)
		{
			// Ignore - this just means the entire file.
			// It's not really a subrange.
		}
		else
		{
			NSUInteger maxLength = NSUIntegerMax - sanitizedRange.location;
			sanitizedRange.length = MIN(sanitizedRange.length, maxLength);
			
			sanitizedValue = [NSValue valueWithRange:sanitizedRange];
		}
	}
	
	range = sanitizedValue;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		algorithm = kHASH_Algorithm_Invalid;
		hashRef = kInvalidHASH_ContextRef;
	}
	return self;
}

- (void)dealloc
{
	if (hashRef != kInvalidHASH_ContextRef) {
		HASH_Free(hashRef);
		hashRef = kInvalidHASH_ContextRef;
	}
	
	if (hashBuffer) {
		free(hashBuffer);
		hashBuffer = NULL;
	}
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCFileChecksumInstruction *copy = [[ZDCFileChecksumInstruction alloc] init];
	
	copy->algorithm = algorithm;
	copy->range = [range copy];
	copy->chunkSize = [chunkSize copy];
	copy->callbackQueue = callbackQueue;
	copy->callbackBlock = callbackBlock;
	
	return copy;
}

@end
