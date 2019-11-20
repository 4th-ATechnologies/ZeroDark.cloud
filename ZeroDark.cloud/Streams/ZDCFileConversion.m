/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCFileConversion.h"

#import "CacheFile2CleartextInputStream.h"
#import "Cleartext2CacheFileInputStream.h"
#import "Cleartext2CloudFileInputStream.h"
#import "CloudFile2CleartextInputStream.h"
#import "ZDCConstants.h"
#import "ZDCDirectoryManager.h"
#import "ZDCLogging.h"

#import "NSError+S4.h"
#import "OSImage+ZeroDark.h"

#import <S4Crypto/S4Crypto.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

#define CKS4ERR  if ((err != kS4Err_NoErr)) { goto S4ErrOccurred; }

@implementation ZDCFileConversion

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encrypt (Cleartext -> Cachefile)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (NSProgress *)encryptCleartextFile:(NSURL *)inFileURL
                  toCacheFileWithKey:(NSData *)encryptionKey
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *cryptoFile, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		Cleartext2CacheFileInputStream *inStream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL: inFileURL
		                                                     encryptionKey: encryptionKey];
		
		NSNumber *blockSize = nil;
		[inFileURL getResourceValue:&blockSize forKey:NSURLPreferredIOBlockSizeKey error:nil];
		
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		NSOutputStream *outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		NSError *error =
		  [self _pipeCacheFileStream: inStream
		              toOutputStream: outStream
		                withProgress: progress
		        preferredIOBlockSize: blockSize];
		
		if (completionBlock)
		{
			ZDCCryptoFile *cryptoFile =
			  [[ZDCCryptoFile alloc] initWithFileURL: outFileURL
			                              fileFormat: ZDCCryptoFileFormat_CacheFile
			                           encryptionKey: encryptionKey
			                             retainToken: nil];
			
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(cryptoFile, error);
			}});
		}
		
		if (error) {
			[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
		}
	}});
	
	return progress;
}

/**
 * See header file for description.
**/
+ (BOOL)encryptCleartextFile:(NSURL *)inFileURL
          toCacheFileWithKey:(NSData *)encryptionKey
                outputStream:(NSOutputStream *)outStream
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CacheFileInputStream *inStream =
	  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL: inFileURL
	                                                     encryptionKey: encryptionKey];
	
	NSNumber *blockSize = nil;
	[inFileURL getResourceValue:&blockSize forKey:NSURLPreferredIOBlockSizeKey error:nil];
	
	NSError *error =
	  [self _pipeCacheFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: blockSize];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)inFileURL
          toCacheFileWithKey:(NSData *)encryptionKey
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError **)outError
{
	Cleartext2CacheFileInputStream *inStream =
	[[Cleartext2CacheFileInputStream alloc] initWithCleartextFileURL: inFileURL
																		encryptionKey: encryptionKey];
	
	NSNumber *blockSize = nil;
	[inFileURL getResourceValue:&blockSize forKey:NSURLPreferredIOBlockSizeKey error:nil];
	
	NSOutputStream *outStream = [NSOutputStream outputStreamWithURL:outputFileURL append:NO];
	
	NSError *error =
	  [self _pipeCacheFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: blockSize];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (NSProgress *)encryptCleartextData:(NSData *)cleartextData
                  toCacheFileWithKey:(NSData *)encryptionKey
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *_Nullable cryptoFile, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		Cleartext2CacheFileInputStream *inStream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextData: cleartextData
		                                                  encryptionKey: encryptionKey];
		
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		NSOutputStream *outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		NSError *error =
		  [self _pipeCacheFileStream: inStream
		              toOutputStream: outStream
		                withProgress: progress
		        preferredIOBlockSize: nil];
		
		if (completionBlock)
		{
			ZDCCryptoFile *cryptoFile =
			  [[ZDCCryptoFile alloc] initWithFileURL: outFileURL
			                              fileFormat: ZDCCryptoFileFormat_CacheFile
			                           encryptionKey: encryptionKey
			                             retainToken: nil];
			
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(cryptoFile, error);
			}});
		}
		
		if (error) {
			[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
		}
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCacheFileWithKey:(NSData *)encryptionKey
                outputStream:(NSOutputStream *)outStream
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CacheFileInputStream *inStream =
	  [[Cleartext2CacheFileInputStream alloc] initWithCleartextData: cleartextData
	                                                  encryptionKey: encryptionKey];
	
	NSError *error =
	  [self _pipeCacheFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: nil];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCacheFileWithKey:(NSData *)encryptionKey
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CacheFileInputStream *inStream =
	  [[Cleartext2CacheFileInputStream alloc] initWithCleartextData: cleartextData
	                                                  encryptionKey: encryptionKey];
	
	NSOutputStream *outStream = [[NSOutputStream alloc] initWithURL:outputFileURL append:NO];
	
	NSError *error =
	  [self _pipeCacheFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: nil];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (nullable NSData *)encryptCleartextData:(NSData *)cleartextData
                       toCacheFileWithKey:(NSData *)encryptionKey
                                    error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CacheFileInputStream *inStream =
	  [[Cleartext2CacheFileInputStream alloc] initWithCleartextData: cleartextData
	                                                  encryptionKey: encryptionKey];
	
	NSOutputStream *outStream = [NSOutputStream outputStreamToMemory];
	
	NSError *error =
	  [self _pipeCacheFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: nil];
	
	NSData *cleartext = nil;
	if (!error) {
		cleartext = [outStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	}
	
	if (outError) *outError = error;
	return cleartext;
}

+ (nullable NSError *)_pipeCacheFileStream:(Cleartext2CacheFileInputStream *)inStream
                            toOutputStream:(NSOutputStream *)outStream
                              withProgress:(nullable NSProgress *)progress
                      preferredIOBlockSize:(nullable NSNumber *)preferredIOBlockSize
{
	NSError *error = nil;
	
	uint64_t fileSize = 0;
	
	uint8_t *buffer = NULL;
	NSUInteger bufferSize = 0;
	
	if (progress.cancelled)
	{
		error = [self errorUserCanceled];
		goto done;
	}
	
	// Open streams
	
	[inStream open];
	
	if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
	{
		error = [self errorOpeningStream:inStream forFile:inStream.cleartextFileURL];
		goto done;
	}
	
	[outStream open];
	
	if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
	{
		error = [self errorOpeningStream:outStream forFile:nil];
		goto done;
	}
	
	// Prepare for IO
	
	fileSize = [inStream.encryptedFileSize unsignedLongLongValue]; // size of cloud file
	
	if (fileSize > 0) {
		progress.totalUnitCount = fileSize;
	}
	
	if (preferredIOBlockSize != nil) {
		bufferSize = [preferredIOBlockSize unsignedIntegerValue];
	}
	else {
		bufferSize = (1024 * 32); // Pick a sane default chunk size
	}
	
	if (fileSize > 0 && fileSize < NSUIntegerMax) { // Don't over-allocate buffer
		bufferSize = MIN(bufferSize, (NSUInteger)fileSize);
	}
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wambiguous-macro"
	bufferSize = MAX(bufferSize, kZDCNode_TweakBlockSizeInBytes);
#pragma clang diagnostic pop

	buffer = malloc((size_t)bufferSize);
	
	// Start IO

	NSUInteger totalBytesWritten = 0;

	BOOL done = NO;
	do {
		
		// Read a chunk from the input stream
		
		NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
		
		if (bytesRead < 0)
		{
			// Error reading
			
			error = [self errorReadingWritingStream:inStream forFile:inStream.cleartextFileURL];
			goto done;
		}
		else if (bytesRead == 0)
		{
			// End of stream
			
			done = YES;
		}
		else // if (bytesRead > 0)
		{
			// Write chunk to the output stream.
			// To be safe, we do this in loop (just in case).
			
			NSUInteger loopBytesWritten = 0;
			do {
				
				NSInteger bytesWritten = [outStream write:(buffer + loopBytesWritten)
				                                maxLength:(bytesRead - loopBytesWritten)];
				
				if (bytesWritten <= 0)
				{
					// Error writing
					
					error = [self errorReadingWritingStream:outStream forFile:inStream.cleartextFileURL];
					goto done;
				}
				else
				{
					// Update totals and continue
					
					loopBytesWritten += bytesWritten;
					totalBytesWritten += bytesWritten;
				}
				
			} while (loopBytesWritten < bytesRead);
			
			if (fileSize > 0) {
				progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
			}
			
			if (progress.cancelled)
			{
				error = [self errorUserCanceled];
				goto done;
			}
		}
		
	} while (!done);
	
done:
	
	if (inStream) {
		[inStream close];
	}
	if (outStream) {
		[outStream close];
	}
	
	if (buffer) {
		ZERO(buffer, bufferSize);
		free(buffer);
		buffer = NULL;
	}
	
	return error;
}

/**
 * See header file for description.
 */
+ (nullable NSError *)encryptCleartextWithDataBlock:(NSError*_Nullable (^*)(NSData*))dataBlockOut
                                    completionBlock:(NSError*_Nullable (^*)(void))completionBlockOut
                                        toCacheFile:(NSURL *)outputFileURL
                                            withKey:(NSData *)encryptionKey
{
	NSInputStream *pump_inputStream = nil;
	NSOutputStream *pump_outputStream = nil;
	
	[NSStream getBoundStreamsWithBufferSize: (1024 * 1024 * 8)
	                            inputStream: &pump_inputStream
	                           outputStream: &pump_outputStream];
	
	[pump_outputStream open];
	[pump_inputStream open];
	
	if ((pump_outputStream.streamStatus != NSStreamStatusOpen) || pump_outputStream.streamError ||
	    (pump_outputStream.streamStatus != NSStreamStatusOpen) || pump_outputStream.streamError)
	{
		NSError *error = [self errorWithDescription:@"Unable to create bound input/output stream pair."];
		return error;
	}
	
	// Writing to the `pump_outputStream` will make data available on the `pump_inputStream`.
	// And now we can connect the `pump_inputStream` to a Cleartext2CacheFileInputStream.
	
	Cleartext2CacheFileInputStream *encryptionStream =
		[[Cleartext2CacheFileInputStream alloc] initWithCleartextFileStream: pump_inputStream
		                                                      encryptionKey: encryptionKey];
	encryptionStream.cleartextFileSizeUnknown = YES;
	
	[encryptionStream setProperty:@(YES) forKey:ZDCStreamReturnEOFOnWouldBlock];
	[encryptionStream open];
	
	if ((encryptionStream.streamStatus != NSStreamStatusOpen) || encryptionStream.streamError)
	{
		NSError *error = [self errorOpeningStream:encryptionStream forFile:nil];
		return error;
	}
	
	// And we need the outputStream, to write the encrypted file to disk.
	
	NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:outputFileURL append:NO];
	
	[outputStream open];
	
	if ((outputStream.streamStatus != NSStreamStatusOpen) || outputStream.streamError)
	{
		NSError *error = [self errorOpeningStream:outputStream forFile:outputFileURL];
		return error;
	}
	
	// Pre-allocate a buffer to be used by the pump.
	// Try to align the buffer size with the preferred IO block size of the output destination.
	
	NSMutableData *encryptedBufferContainer = nil;
	{
		NSUInteger bufferSize = 0;
		
		NSArray<NSString *> *keys = @[ NSURLPreferredIOBlockSizeKey ];
		
		NSDictionary *resourceValues = [outputFileURL resourceValuesForKeys:keys error:nil];
		NSNumber *number = resourceValues[NSURLPreferredIOBlockSizeKey];
		
		if (number != nil) {
			bufferSize = [number unsignedIntegerValue];
		}
		else {
			bufferSize = (1024 * 32); // Pick a sane default chunk size
		}
		
		void *buffer = malloc(bufferSize);
		encryptedBufferContainer =
			[[NSMutableData alloc] initWithBytesNoCopy: buffer
			                                    length: bufferSize
			                              freeWhenDone: YES];
	}
	
	// Setup the pumpDataBlock.
	// This would be what we call everytime the 3rd party API gives us a chunk of data.
	
	NSError* (^pumpDataBlock)(NSData*) = ^NSError* (NSData *cleartextData){ @autoreleasepool {
		
		if (cleartextData.length == 0) return nil;
		
		NSUInteger cleartextOffset = 0;
		const void *cleartextBuffer = cleartextData.bytes;
		
		do {
		
			NSInteger writtenToPump = [pump_outputStream write: (cleartextBuffer + cleartextOffset)
			                                         maxLength: (cleartextData.length - cleartextOffset)];
			if (writtenToPump <= 0)
			{
				NSError *error = pump_outputStream.streamError;
				if (error == nil) {
					error = [self errorWithDescription:@"Unable to write to pump"];
				}
				return error;
			}
			
			cleartextOffset += writtenToPump;
			
			NSUInteger const encryptedBufferSize = encryptedBufferContainer.length;
			void *encryptedBuffer = encryptedBufferContainer.mutableBytes;
			
			while ([encryptionStream hasBytesAvailable])
			{
				NSInteger encryptedBufferLength =
					[encryptionStream read: encryptedBuffer
					             maxLength: encryptedBufferSize];
				
				if (encryptedBufferLength < 0)
				{
					return [self errorReadingWritingStream:encryptionStream forFile:nil];
				}
				
				NSUInteger encryptedBufferOffset = 0;
				while (encryptedBufferOffset < encryptedBufferLength)
				{
					NSInteger written = [outputStream write: (encryptedBuffer + encryptedBufferOffset)
					                              maxLength: (encryptedBufferLength - encryptedBufferOffset)];
					
					if (written <= 0)
					{
						return [self errorReadingWritingStream:outputStream forFile:outputFileURL];
					}
					
					encryptedBufferOffset += written;
				}
			}
		
		} while (cleartextOffset < cleartextData.length);
		
		return nil;
	}};
	
	// Setup the pumpCompletionBlock.
	// This would be what we call when the 3rd party API tells us we're done.
	
	NSError* (^pumpCompletionBlock)(void) = ^NSError* (){ @autoreleasepool {
		
		// Send EOF signal through the pipes: pump_outputStream => pump_inputStream => encryptionStream
		[pump_outputStream close];
		
		NSUInteger const encryptedBufferSize = encryptedBufferContainer.length;
		void *encryptedBuffer = encryptedBufferContainer.mutableBytes;
		
		BOOL done = NO;
		do
		{
			NSInteger encryptedBufferLength =
				[encryptionStream read: encryptedBuffer
				             maxLength: encryptedBufferSize];
			
			if (encryptedBufferLength < 0)
			{
				return [self errorReadingWritingStream:encryptionStream forFile:nil];
			}
			else if (encryptedBufferLength == 0)
			{
				// We enabled the `ZDCStreamReturnEOFOnWouldBlock` property,
				// which means a result of 0 may not actually be EOF.
				// 
				if (encryptionStream.streamStatus == NSStreamStatusAtEnd)
				{
					done = YES;
				}
			}
			
			NSUInteger encryptedBufferOffset = 0;
			while (encryptedBufferOffset < encryptedBufferLength)
			{
				NSInteger written = [outputStream write: (encryptedBuffer + encryptedBufferOffset)
				                              maxLength: (encryptedBufferLength - encryptedBufferOffset)];
				
				if (written <= 0)
				{
					return [self errorReadingWritingStream:outputStream forFile:outputFileURL];
				}
			
				encryptedBufferOffset += written;
			}
			
		} while (!done);
		
		[outputStream close];
		[encryptionStream close];
		
		NSNumber *discovered = encryptionStream.cleartextFileSize;
		
		return [Cleartext2CacheFileInputStream updateCacheFileHeader: outputFileURL
		                                       withCleartextFileSize: discovered.unsignedLongLongValue
		                                               encryptionKey: encryptionKey];
	}};
	
	if (dataBlockOut) *dataBlockOut = pumpDataBlock;
	if (completionBlockOut) *completionBlockOut = pumpCompletionBlock;
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encrypt (Cleartext -> Cloudfile)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (NSProgress *)encryptCleartextFile:(NSURL *)inFileURL
                  toCloudFileWithKey:(NSData *)encryptionKey
                            metadata:(nullable NSData *)metadata
                           thumbnail:(nullable NSData *)thumbnail
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *cryptoFile, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	metadata = [metadata copy];           // mutable data protection
	thumbnail = [thumbnail copy];         // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		Cleartext2CloudFileInputStream *inStream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: inFileURL
		                                                     encryptionKey: encryptionKey];
		
		inStream.rawMetadata = metadata;
		inStream.rawThumbnail = thumbnail;
		
		NSNumber *blockSize = nil;
		[inFileURL getResourceValue:&blockSize forKey:NSURLPreferredIOBlockSizeKey error:nil];
		
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		NSOutputStream *outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		NSError *error =
		  [self _pipeCloudFileStream: inStream
		              toOutputStream: outStream
		                withProgress: progress
		        preferredIOBlockSize: blockSize];
		
		if (completionBlock)
		{
			ZDCCryptoFile *cryptoFile =
			  [[ZDCCryptoFile alloc] initWithFileURL: outFileURL
			                              fileFormat: ZDCCryptoFileFormat_CloudFile
			                           encryptionKey: encryptionKey
			                             retainToken: nil];
			
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(cryptoFile, error);
			}});
		}
		
		if (error) {
			[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
		}
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)inFileURL
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                outputStream:(NSOutputStream *)outStream
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CloudFileInputStream *inStream =
	  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: inFileURL
	                                                     encryptionKey: encryptionKey];
	
	inStream.rawMetadata = metadata;
	inStream.rawThumbnail = thumbnail;
	
	NSNumber *blockSize = nil;
	[inFileURL getResourceValue:&blockSize forKey:NSURLPreferredIOBlockSizeKey error:nil];
	
	NSError *error =
		  [self _pipeCloudFileStream: inStream
		              toOutputStream: outStream
		                withProgress: nil
		        preferredIOBlockSize: blockSize];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextFile:(NSURL *)inFileURL
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CloudFileInputStream *inStream =
	  [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileURL: inFileURL
	                                                     encryptionKey: encryptionKey];
	
	inStream.rawMetadata = metadata;
	inStream.rawThumbnail = thumbnail;
	
	NSNumber *blockSize = nil;
	[inFileURL getResourceValue:&blockSize forKey:NSURLPreferredIOBlockSizeKey error:nil];
	
	NSOutputStream *outStream = [NSOutputStream outputStreamWithURL:outputFileURL append:NO];
	
	NSError *error =
		  [self _pipeCloudFileStream: inStream
		              toOutputStream: outStream
		                withProgress: nil
		        preferredIOBlockSize: blockSize];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (NSProgress *)encryptCleartextData:(NSData *)cleartextData
                  toCloudFileWithKey:(NSData *)encryptionKey
                            metadata:(nullable NSData *)metadata
                           thumbnail:(nullable NSData *)thumbnail
                     completionQueue:(nullable dispatch_queue_t)completionQueue
                     completionBlock:(void (^)(ZDCCryptoFile *cryptoFile, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	metadata = [metadata copy];           // mutable data protection
	thumbnail = [thumbnail copy];         // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		Cleartext2CloudFileInputStream *inStream =
		  [[Cleartext2CloudFileInputStream alloc] initWithCleartextData: cleartextData
		                                                  encryptionKey: encryptionKey];

		inStream.rawMetadata = metadata;
		inStream.rawThumbnail = thumbnail;
		
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		NSOutputStream *outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		NSError *error =
		  [self _pipeCloudFileStream: inStream
		              toOutputStream: outStream
		                withProgress: progress
		        preferredIOBlockSize: nil];
		
		if (completionBlock)
		{
			ZDCCryptoFile *cryptoFile =
			  [[ZDCCryptoFile alloc] initWithFileURL: outFileURL
			                              fileFormat: ZDCCryptoFileFormat_CloudFile
			                           encryptionKey: encryptionKey
			                             retainToken: nil];
			
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				completionBlock(cryptoFile, error);
			}});
		}
		
		if (error) {
			[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
		}
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                outputStream:(NSOutputStream *)outStream
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CloudFileInputStream *inStream =
	  [[Cleartext2CloudFileInputStream alloc] initWithCleartextData: cleartextData
	                                                  encryptionKey: encryptionKey];
	
	inStream.rawMetadata = metadata;
	inStream.rawThumbnail = thumbnail;
	
	NSError *error =
	  [self _pipeCloudFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: nil];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (BOOL)encryptCleartextData:(NSData *)cleartextData
          toCloudFileWithKey:(NSData *)encryptionKey
                    metadata:(nullable NSData *)metadata
                   thumbnail:(nullable NSData *)thumbnail
                   outputURL:(NSURL *)outputFileURL
                       error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CloudFileInputStream *inStream =
	  [[Cleartext2CloudFileInputStream alloc] initWithCleartextData: cleartextData
	                                                  encryptionKey: encryptionKey];
	
	inStream.rawMetadata = metadata;
	inStream.rawThumbnail = thumbnail;
	
	NSOutputStream *outStream = [[NSOutputStream alloc] initWithURL:outputFileURL append:NO];
	
	NSError *error =
	  [self _pipeCloudFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: nil];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (nullable NSData *)encryptCleartextData:(NSData *)cleartextData
                       toCloudFileWithKey:(NSData *)encryptionKey
                                 metadata:(nullable NSData *)metadata
                                thumbnail:(nullable NSData *)thumbnail
                                    error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	Cleartext2CloudFileInputStream *inStream =
	  [[Cleartext2CloudFileInputStream alloc] initWithCleartextData: cleartextData
	                                                  encryptionKey: encryptionKey];
	
	inStream.rawMetadata = metadata;
	inStream.rawThumbnail = thumbnail;
	
	NSOutputStream *outStream = [NSOutputStream outputStreamToMemory];
	
	NSError *error =
	  [self _pipeCloudFileStream: inStream
	              toOutputStream: outStream
	                withProgress: nil
	        preferredIOBlockSize: nil];
	
	NSData *cleartext = nil;
	if (!error) {
		cleartext = [outStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	}
	
	if (outError) *outError = error;
	return cleartext;
}

+ (nullable NSError *)_pipeCloudFileStream:(Cleartext2CloudFileInputStream *)inStream
                            toOutputStream:(NSOutputStream *)outStream
                              withProgress:(nullable NSProgress *)progress
                      preferredIOBlockSize:(nullable NSNumber *)preferredIOBlockSize
{
	NSError *error = nil;
	
	uint64_t fileSize = 0;
	
	uint8_t *buffer = NULL;
	NSUInteger bufferSize = 0;
	
	// Open streams
	
	[inStream open];
	
	if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
	{
		error = [self errorOpeningStream:inStream forFile:inStream.cleartextFileURL];
		goto done;
	}
	
	[outStream open];
	
	if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
	{
		error = [self errorOpeningStream:outStream forFile:nil];
		goto done;
	}
	
	// Prepare for IO
	
	fileSize = [inStream.encryptedFileSize unsignedLongLongValue]; // size of cloud file
	
	if (fileSize > 0) {
		progress.totalUnitCount = fileSize;
	}
	
	if (preferredIOBlockSize != nil) {
		bufferSize = [preferredIOBlockSize unsignedIntegerValue];
	}
	else {
		bufferSize = (1024 * 32); // Pick a sane default chunk size
	}
	
	if (fileSize > 0 && fileSize < NSUIntegerMax) { // Don't over-allocate buffer
		bufferSize = MIN(bufferSize, (NSUInteger)fileSize);
	}
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wambiguous-macro"
	bufferSize = MAX(bufferSize, kZDCNode_TweakBlockSizeInBytes);
#pragma clang diagnostic pop

	buffer = malloc((size_t)bufferSize);
	
	// Start IO

	NSUInteger totalBytesWritten = 0;

	BOOL done = NO;
	do {
		
		// Read a chunk from the input stream
		
		NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
		
		if (bytesRead < 0)
		{
			// Error reading
			
			error = [self errorReadingWritingStream:inStream forFile:inStream.cleartextFileURL];
			goto done;
		}
		else if (bytesRead == 0)
		{
			// End of stream
			
			done = YES;
		}
		else // if (bytesRead > 0)
		{
			// Write chunk to the output stream.
			// To be safe, we do this in loop (just in case).
			
			NSUInteger loopBytesWritten = 0;
			do {
				
				NSInteger bytesWritten = [outStream write:(buffer + loopBytesWritten)
				                                maxLength:(bytesRead - loopBytesWritten)];
				
				if (bytesWritten <= 0)
				{
					// Error writing
					
					error = [self errorReadingWritingStream:outStream forFile:inStream.cleartextFileURL];
					goto done;
				}
				else
				{
					// Update totals and continue
					
					loopBytesWritten += bytesWritten;
					totalBytesWritten += bytesWritten;
				}
				
			} while (loopBytesWritten < bytesRead);
			
			if (fileSize > 0) {
				progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
			}
			
			if (progress.cancelled)
			{
				error = [self errorUserCanceled];
				goto done;
			}
		}
		
	} while (!done);
	
done:
	
	if (inStream) {
		[inStream close];
	}
	
	if (outStream) {
		[outStream close];
	}
	
	if (buffer) {
		ZERO(buffer, bufferSize);
		free(buffer);
		buffer = NULL;
	}
	
	return error;
}

/**
 * See header file for description.
 */
+ (nullable NSError *)encryptCleartextWithDataBlock:(NSError*_Nullable (^*)(NSData*))dataBlockOut
                                    completionBlock:(NSError*_Nullable (^*)(void))completionBlockOut
                                        toCloudFile:(NSURL *)outputFileURL
                                            withKey:(NSData *)encryptionKey
                                           metadata:(nullable NSData *)metadata
                                          thumbnail:(nullable NSData *)thumbnail
{
	NSInputStream *pump_inputStream = nil;
	NSOutputStream *pump_outputStream = nil;
	
	[NSStream getBoundStreamsWithBufferSize: (1024 * 1024 * 8)
	                            inputStream: &pump_inputStream
	                           outputStream: &pump_outputStream];
	
	[pump_outputStream open];
	[pump_inputStream open];
	
	if ((pump_outputStream.streamStatus != NSStreamStatusOpen) || pump_outputStream.streamError ||
	    (pump_outputStream.streamStatus != NSStreamStatusOpen) || pump_outputStream.streamError)
	{
		NSError *error = [self errorWithDescription:@"Unable to create bound input/output stream pair."];
		return error;
	}
	
	// Writing to the `pump_outputStream` will make data available on the `pump_inputStream`.
	// And now we can connect the `pump_inputStream` to a Cleartext2CloudFileInputStream.
	
	Cleartext2CloudFileInputStream *encryptionStream =
		[[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: pump_inputStream
		                                                      encryptionKey: encryptionKey];
	
	encryptionStream.cleartextFileSizeUnknown = YES;
	
	encryptionStream.rawMetadata = metadata;
	encryptionStream.rawThumbnail = thumbnail;
	
	[encryptionStream setProperty:@(YES) forKey:ZDCStreamReturnEOFOnWouldBlock];
	[encryptionStream open];
	
	if ((encryptionStream.streamStatus != NSStreamStatusOpen) || encryptionStream.streamError)
	{
		NSError *error = [self errorOpeningStream:encryptionStream forFile:nil];
		return error;
	}
	
	// And we need the outputStream, to write the encrypted file to disk.
	
	NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:outputFileURL append:NO];
	
	[outputStream open];
	
	if ((outputStream.streamStatus != NSStreamStatusOpen) || outputStream.streamError)
	{
		NSError *error = [self errorOpeningStream:outputStream forFile:outputFileURL];
		return error;
	}
	
	// Pre-allocate a buffer to be used by the pump.
	// Try to align the buffer size with the preferred IO block size of the output destination.
	
	NSMutableData *encryptedBufferContainer = nil;
	{
		NSUInteger bufferSize = 0;
		
		NSArray<NSString *> *keys = @[ NSURLPreferredIOBlockSizeKey ];
		
		NSDictionary *resourceValues = [outputFileURL resourceValuesForKeys:keys error:nil];
		NSNumber *number = resourceValues[NSURLPreferredIOBlockSizeKey];
		
		if (number != nil) {
			bufferSize = [number unsignedIntegerValue];
		}
		else {
			bufferSize = (1024 * 32); // Pick a sane default chunk size
		}
		
		void *buffer = malloc(bufferSize);
		encryptedBufferContainer =
			[[NSMutableData alloc] initWithBytesNoCopy: buffer
			                                    length: bufferSize
			                              freeWhenDone: YES];
	}
	
	// Setup the pumpDataBlock.
	// This would be what we call everytime the 3rd party API gives us a chunk of data.
	
	NSError* (^pumpDataBlock)(NSData*) = ^NSError* (NSData *cleartextData){ @autoreleasepool {
		
		if (cleartextData.length == 0) return nil;
		
		NSUInteger cleartextOffset = 0;
		const void *cleartextBuffer = cleartextData.bytes;
		
		do {
		
			NSInteger writtenToPump = [pump_outputStream write: (cleartextBuffer + cleartextOffset)
			                                         maxLength: (cleartextData.length - cleartextOffset)];
			if (writtenToPump <= 0)
			{
				NSError *error = pump_outputStream.streamError;
				if (error == nil) {
					error = [self errorWithDescription:@"Unable to write to pump"];
				}
				return error;
			}
			
			cleartextOffset += writtenToPump;
			
			NSUInteger const encryptedBufferSize = encryptedBufferContainer.length;
			void *encryptedBuffer = encryptedBufferContainer.mutableBytes;
			
			while ([encryptionStream hasBytesAvailable])
			{
				NSInteger encryptedBufferLength =
					[encryptionStream read: encryptedBuffer
					             maxLength: encryptedBufferSize];
				
				if (encryptedBufferLength < 0)
				{
					return [self errorReadingWritingStream:encryptionStream forFile:nil];
				}
				
				NSUInteger encryptedBufferOffset = 0;
				while (encryptedBufferOffset < encryptedBufferLength)
				{
					NSInteger written = [outputStream write: (encryptedBuffer + encryptedBufferOffset)
					                              maxLength: (encryptedBufferLength - encryptedBufferOffset)];
					
					if (written <= 0)
					{
						return [self errorReadingWritingStream:outputStream forFile:outputFileURL];
					}
					
					encryptedBufferOffset += written;
				}
			}
		
		} while (cleartextOffset < cleartextData.length);
		
		return nil;
	}};
	
	// Setup the pumpCompletionBlock.
	// This would be what we call when the 3rd party API tells us we're done.
	
	NSError* (^pumpCompletionBlock)(void) = ^NSError* (){ @autoreleasepool {
		
		// Send EOF signal through the pipes: pump_outputStream => pump_inputStream => encryptionStream
		[pump_outputStream close];
		
		NSUInteger const encryptedBufferSize = encryptedBufferContainer.length;
		void *encryptedBuffer = encryptedBufferContainer.mutableBytes;
		
		BOOL done = NO;
		do
		{
			NSInteger encryptedBufferLength =
				[encryptionStream read: encryptedBuffer
				             maxLength: encryptedBufferSize];
			
			if (encryptedBufferLength < 0)
			{
				return [self errorReadingWritingStream:encryptionStream forFile:nil];
			}
			else if (encryptedBufferLength == 0)
			{
				// We enabled the `ZDCStreamReturnEOFOnWouldBlock` property,
				// which means a result of 0 may not actually be EOF.
				//
				if (encryptionStream.streamStatus == NSStreamStatusAtEnd)
				{
					done = YES;
				}
			}
			
			NSUInteger encryptedBufferOffset = 0;
			while (encryptedBufferOffset < encryptedBufferLength)
			{
				NSInteger written = [outputStream write: (encryptedBuffer + encryptedBufferOffset)
				                              maxLength: (encryptedBufferLength - encryptedBufferOffset)];
				
				if (written <= 0)
				{
					return [self errorReadingWritingStream:outputStream forFile:outputFileURL];
				}
			
				encryptedBufferOffset += written;
			}
			
		} while (!done);
		
		[outputStream close];
		[encryptionStream close];
		
		NSNumber *discovered = encryptionStream.cleartextFileSize;
		
		return [Cleartext2CloudFileInputStream updateCloudFileHeader: outputFileURL
		                                       withCleartextFileSize: discovered.unsignedLongLongValue
		                                               encryptionKey: encryptionKey];
	}};
	
	if (dataBlockOut) *dataBlockOut = pumpDataBlock;
	if (completionBlockOut) *completionBlockOut = pumpCompletionBlock;
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Decrypt (Crypto -> Cleartext)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (NSProgress *)decryptCryptoFile:(ZDCCryptoFile *)cryptoFile
                  completionQueue:(nullable dispatch_queue_t)completionQueue
                  completionBlock:(void (^)(NSURL *_Nullable cleartexFileURL, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
	{
		return [self decryptCacheFile: cryptoFile.fileURL
		                encryptionKey: cryptoFile.encryptionKey
		                  retainToken: cryptoFile.retainToken
		              completionQueue: completionQueue
		              completionBlock: completionBlock];
	}
	else if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile)
	{
		return [self decryptCloudFile: cryptoFile.fileURL
		                encryptionKey: cryptoFile.encryptionKey
		                  retainToken: cryptoFile.retainToken
		              completionQueue: completionQueue
						  completionBlock:^(ZDCCloudFileHeader headerInfo,
		                                NSData *metadata, NSData *thumbnail,
		                                NSURL *cleartextFileURL, NSError *error)
		{
			completionBlock(cleartextFileURL, error);
		}];
	}
	else
	{
		NSError *error = [self errorWithDescription:@"Unknown file format"];
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			
			completionBlock(nil, error);
		}});
		
		NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
		return progress;
	}
}

/**
 * See header file for description.
 */
+ (BOOL)decryptCryptoFile:(ZDCCryptoFile *)cryptoFile
           toOutputStream:(NSOutputStream *)outputStream
                    error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
	{
		return [self decryptCacheFile: cryptoFile.fileURL
		                encryptionKey: cryptoFile.encryptionKey
		                  retainToken: cryptoFile.retainToken
		               toOutputStream: outputStream
		                        error: outError];
	}
	else if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile)
	{
		return [self decryptCloudFile: cryptoFile.fileURL
		                encryptionKey: cryptoFile.encryptionKey
		                  retainToken: cryptoFile.retainToken
		               toOutputStream: outputStream
		                        error: outError];
	}
	else
	{
		if (outError) *outError = [self errorWithDescription:@"Unknown file format"];
		return NO;
	}
}

/**
 * See header file for description.
 */
+ (nullable NSData *)decryptCryptoFileIntoMemory:(ZDCCryptoFile *)cryptoFile
                                           error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
	{
		return [self decryptCacheFileIntoMemory: cryptoFile.fileURL
		                          encryptionKey: cryptoFile.encryptionKey
		                            retainToken: cryptoFile.retainToken
		                                  error: outError];
	}
	else if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile)
	{
		return [self decryptCloudFileIntoMemory: cryptoFile.fileURL
		                          encryptionKey: cryptoFile.encryptionKey
		                            retainToken: cryptoFile.retainToken
		                                  error: outError];
	}
	else
	{
		if (outError) *outError = [self errorWithDescription:@"Unknown file format"];
		return nil;
	}
}

/**
 * See header file for description.
 */
+ (NSProgress *)decryptCryptoFileIntoMemory:(ZDCCryptoFile *)cryptoFile
                            completionQueue:(nullable dispatch_queue_t)completionQueue
                            completionBlock:(void (^)(NSData *_Nullable cleartext,
                                                      NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile)
	{
		return [self decryptCacheFileIntoMemory: cryptoFile.fileURL
		                          encryptionKey: cryptoFile.encryptionKey
		                            retainToken: cryptoFile.retainToken
		                        completionQueue: completionQueue
		                        completionBlock: completionBlock];
	}
	else if (cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile)
	{
		return [self decryptCloudFileIntoMemory: cryptoFile.fileURL
		                          encryptionKey: cryptoFile.encryptionKey
		                            retainToken: cryptoFile.retainToken
		                        completionQueue: completionQueue
		                        completionBlock:^(ZDCCloudFileHeader header,
		                                          NSData *metadata, NSData *thumbnail,
		                                          NSData *cleartext, NSError *error)
		{
			completionBlock(cleartext, error);
		}];
	}
	else
	{
		NSError *error = [self errorWithDescription:@"Unknown file format"];
		dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			
			completionBlock(nil, error);
		}});
		
		NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
		return progress;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Decrypt (Cachefile -> Cleartext)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (NSProgress *)decryptCacheFile:(NSURL *)inFileURL
                   encryptionKey:(NSData *)encryptionKey
                     retainToken:(nullable id)retainToken
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSURL *cleartexFileURL, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		__block NSOutputStream *outStream = nil;
		__block BOOL outFileCreated = NO;
		
		// Create temp output file location
		
		NSURL *const outFileURL = [ZDCDirectoryManager generateTempURL];
		
		// Setup routine for completion and errors
		
		void (^NotifyAndCleanup)(NSError *error);
		NotifyAndCleanup = ^(NSError *error) {
			
			[outStream close];
			
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
					completionBlock(outFileURL, error);
				}});
			}
			
			if (outFileCreated && error) {
				[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
			}
		};
		
		NSError *error = nil;
		
		// Setup output stream
		
		outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		if (outStream == nil)
		{
			error = [self errorCreatingStreamForFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		[outStream open];
		
		if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
		{
			error = [self errorOpeningStream:outStream forFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		outFileCreated = YES;
		
		// Check for cancellation before we start disk IO
		
		if (progress.cancelled)
		{
			NSError *error = [self errorUserCanceled];
			NotifyAndCleanup(error);
			return;
		}
		
		// Run decryption
		
		error = [self _decryptCacheFile: inFileURL
		                 encryptionKey: encryptionKey
		                   retainToken: retainToken
		                toOutputStream: outStream
		                  withProgress: nil];
		
		NotifyAndCleanup(error);
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (BOOL)decryptCacheFile:(NSURL *)inFileURL
           encryptionKey:(NSData *)encryptionKey
             retainToken:(nullable id)retainToken
          toOutputStream:(NSOutputStream *)outStream
                   error:(NSError **)outError
{
	ZDCLogAutoTrace();
	
	NSError *error =
	 [self _decryptCacheFile: inFileURL
	           encryptionKey: encryptionKey
	             retainToken: retainToken
	          toOutputStream: outStream
	            withProgress: nil];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (nullable NSData *)decryptCacheFileIntoMemory:(NSURL *)inFileURL
                                  encryptionKey:(NSData *)encryptionKey
                                    retainToken:(nullable id)retainToken
                                          error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	NSError *error = nil;
	NSData *cleartext = nil;
	
	NSOutputStream *outStream = [NSOutputStream outputStreamToMemory];
	
	[outStream open];
	
	if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
	{
		error = [self errorOpeningStream:outStream forFile:nil];
		goto done;
	}
	
	// Run decryption
	
	error = [self _decryptCacheFile: inFileURL
	                  encryptionKey: encryptionKey
	                    retainToken: retainToken
	                 toOutputStream: outStream
	                   withProgress: nil];
	
done:
	
	if (error == nil) {
		cleartext = [outStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	}
	
	[outStream close];
	
	if (outError) *outError = error;
	return cleartext;
}

/**
 * See header file for description.
 */
+ (NSProgress *)decryptCacheFileIntoMemory:(NSURL *)inFileURL
                             encryptionKey:(NSData *)encryptionKey
                               retainToken:(nullable id)retainToken
                           completionQueue:(nullable dispatch_queue_t)completionQueue
                           completionBlock:(void (^)(NSData *_Nullable cleartext, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		__block NSOutputStream *outStream = nil;
		
		// Setup routine for completion and errors
		
		void (^NotifyAndCleanup)(NSError *_Nullable) = ^(NSError *_Nullable error) {
			
			NSData *cleartext = nil;
			if (error == nil) {
				cleartext = [outStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
			}
			
			[outStream close];
			
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
					completionBlock(cleartext, error);
				}});
			}
		};
		
		NSError *error = nil;
		
		// Setup output stream
		
		outStream = [NSOutputStream outputStreamToMemory];
		
		[outStream open];
		
		if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
		{
			error = [self errorOpeningStream:outStream forFile:nil];
			NotifyAndCleanup(error);
			return;
		}
		
		// Check for cancellation before we start disk IO
		
		if (progress.cancelled)
		{
			NSError *error = [self errorUserCanceled];
			NotifyAndCleanup(error);
			return;
		}
		
		// Run decryption
		
		error = [self _decryptCacheFile: inFileURL
		                  encryptionKey: encryptionKey
		                   retainToken: retainToken
		                toOutputStream: outStream
		                  withProgress: nil];
		
		NotifyAndCleanup(error);
	}});
	
	return progress;
}

+ (nullable NSError *)_decryptCacheFile:(NSURL *)inFileURL
                          encryptionKey:(NSData *)encryptionKey
                            retainToken:(nullable id)retainToken
                         toOutputStream:(NSOutputStream *)outStream
                           withProgress:(nullable NSProgress *)progress
{
	ZDCLogAutoTrace();
	
	NSError *error = nil;
	CacheFile2CleartextInputStream *inStream = nil;
	
	NSUInteger fileSize = 0;
	NSUInteger bufferSize = 0;
	
	NSArray<NSString *> *keys = @[ NSURLFileSizeKey, NSURLPreferredIOBlockSizeKey];
	NSDictionary *resourceValues = nil;
	NSNumber *number = nil;
	
	uint8_t *buffer = NULL;
	
	NSUInteger totalBytesWritten = 0;
	BOOL done = NO;
	
	// Instantiate stream(s)
	
	inStream = [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: inFileURL
	                                                          encryptionKey: encryptionKey];
	inStream.retainToken = retainToken;
	
	if (inStream == nil)
	{
		error = [self errorCreatingStreamForFile:inFileURL];
		goto done;
	}
	
	// Open stream
	
	[inStream open];
	
	if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
	{
		error = [self errorOpeningStream:inStream forFile:inFileURL];
		goto done;
	}
	
	// Prepare for IO
	
	resourceValues = [inFileURL resourceValuesForKeys:keys error:nil];
	
	number = resourceValues[NSURLFileSizeKey];
	if (number != nil) {
		fileSize = [number unsignedIntegerValue];
	}
	
	if (progress && fileSize > 0) {
		progress.totalUnitCount = [inStream.cleartextFileSize longLongValue];
	}
	
	number = resourceValues[NSURLPreferredIOBlockSizeKey];
	if (number != nil) {
		bufferSize = [number unsignedIntegerValue];
	}
	else {
		bufferSize = (1024 * 32); // Pick a sane default chunk size
	}
	
	if (fileSize > 0) { // Don't over-allocate buffer
		bufferSize = MIN(bufferSize, fileSize);
	}
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wambiguous-macro"
	bufferSize = MAX(bufferSize, kZDCNode_TweakBlockSizeInBytes);
#pragma clang diagnostic pop
	
	buffer = malloc((size_t)bufferSize);
	
	// Start IO
	
	do {
		
		// Read a chunk from the input stream
		
		NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
		
		if (bytesRead < 0)
		{
			// Error reading
			
			error = [self errorReadingWritingStream:inStream forFile:inFileURL];
			goto done;
		}
		else if (bytesRead == 0)
		{
			// End of stream
			
			done = YES;
		}
		else // if (bytesRead > 0)
		{
			// Write chunk to the output stream.
			// To be safe, we do this in loop (just in case).
			
			NSUInteger loopBytesWritten = 0;
			do {
				
				NSInteger bytesWritten = [outStream write:(buffer + loopBytesWritten)
				                                maxLength:(bytesRead - loopBytesWritten)];
				
				if (bytesWritten <= 0)
				{
					// Error writing
					
					error = [self errorReadingWritingStream:outStream forFile:nil];
					goto done;
				}
				else
				{
					// Update totals and continue
					
					loopBytesWritten += bytesWritten;
					totalBytesWritten += bytesWritten;
				}
				
			} while (loopBytesWritten < bytesRead);
			
			if (progress)
			{
				if (fileSize > 0) {
					progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
				}
				
				if (progress.cancelled)
				{
					error = [self errorUserCanceled];
					goto done;
				}
			}
		}
	
	} while (!done);

done:

	if (inStream) {
		[inStream close];
	}
	
	if (buffer) {
		ZERO(buffer, bufferSize);
		free(buffer);
		buffer = NULL;
	}
	
	return error;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Decrypt (Cloudfile -> Cleartext)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (NSProgress *)decryptCloudFile:(NSURL *)inFileURL
                   encryptionKey:(NSData *)encryptionKey
                     retainToken:(nullable id)retainToken
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCCloudFileHeader header,
                                           NSData *_Nullable metadata,
                                           NSData *_Nullable thumbnail,
                                           NSURL *_Nullable cleartextFileURL,
                                           NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		__block ZDCCloudFileHeader header;
		__block NSData *metadata = nil;
		__block NSData *thumbnail = nil;
		
		__block NSOutputStream *outStream = nil;
		__block BOOL outFileCreated = NO;
		
		bzero(&header, sizeof(header));
		
		// Create temp output file location
		
		NSURL *const outFileURL = [ZDCDirectoryManager generateTempURL];
		
		// Setup routine for completion and errors
		
		void (^NotifyAndCleanup)(NSError *error);
		NotifyAndCleanup = ^(NSError *error) {
			
			[outStream close];
			
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
					completionBlock(header, metadata, thumbnail, outFileURL, error);
				}});
			}
			
			if (outFileCreated && error) {
				[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
			}
		};
		
		NSError *error = nil;
		
		// Setup output stream
		
		outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		if (outStream == nil)
		{
			error = [self errorCreatingStreamForFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		[outStream open];
		
		if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
		{
			error = [self errorOpeningStream:outStream forFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		outFileCreated = YES;
		
		// Check for cancellation before we start disk IO
		
		if (progress.cancelled)
		{
			error = [self errorUserCanceled];
			NotifyAndCleanup(error);
			return;
		}
		
		// Run decryption
		
		error = [self _decryptCloudFile: inFileURL
		                  encryptionKey: encryptionKey
		                    retainToken: retainToken
		                       toHeader: &header
		                       metadata: &metadata
		                      thumbnail: &thumbnail
		                   outputStream: outStream
		                   withProgress: progress];
		
		NotifyAndCleanup(error);
		
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (BOOL)decryptCloudFile:(NSURL *)inFileURL
           encryptionKey:(NSData *)encryptionKey
             retainToken:(nullable id)retainToken
          toOutputStream:(NSOutputStream *)outStream
                   error:(NSError **)outError
{
	NSError *error =
	  [self _decryptCloudFile: inFileURL
	            encryptionKey: encryptionKey
		           retainToken: retainToken
	                 toHeader: nil
	                 metadata: nil
	                thumbnail: nil
	             outputStream: outStream
	             withProgress: nil];
	
	if (outError) *outError = error;
	return (error == nil);
}

/**
 * See header file for description.
 */
+ (nullable NSData *)decryptCloudFileIntoMemory:(NSURL *)inFileURL
                                  encryptionKey:(NSData *)encryptionKey
                                    retainToken:(nullable id)retainToken
                                          error:(NSError *_Nullable *_Nullable)outError
{
	ZDCLogAutoTrace();
	
	NSError *error = nil;
	NSData *cleartext = nil;
	
	NSOutputStream *outStream = [NSOutputStream outputStreamToMemory];

	[outStream open];
	
	if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
	{
		error = [self errorOpeningStream:outStream forFile:nil];
		goto done;
	}
	
	// Run decryption
	
	error = [self _decryptCloudFile: inFileURL
	                  encryptionKey: encryptionKey
	                    retainToken: retainToken
	                       toHeader: nil
	                       metadata: nil
	                      thumbnail: nil
	                   outputStream: outStream
	                   withProgress: nil];
	
done:
	
	if (error == nil) {
		cleartext = [outStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	}
	
	[outStream close];
	
	if (outError) *outError = error;
	return cleartext;
}

/**
 * See header file for description.
 */
+ (NSProgress *)decryptCloudFileIntoMemory:(NSURL *)inFileURL
                             encryptionKey:(NSData *)encryptionKey
                               retainToken:(nullable id)retainToken
                           completionQueue:(nullable dispatch_queue_t)completionQueue
                           completionBlock:(void (^)(ZDCCloudFileHeader headerInfo,
                                                     NSData *_Nullable metadata,
                                                     NSData *_Nullable thumbnail,
                                                     NSData *_Nullable cleartext,
                                                     NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	encryptionKey = [encryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		__block ZDCCloudFileHeader header;
		__block NSData *metadata = nil;
		__block NSData *thumbnail = nil;
		
		__block NSOutputStream *outStream = nil;
		
		bzero(&header, sizeof(header));
		
		// Setup routine for completion and errors
		
		void (^NotifyAndCleanup)(NSError *error);
		NotifyAndCleanup = ^(NSError *error) {
			
			NSData *cleartext = nil;
			if (error == nil) {
				cleartext = [outStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
			}
			
			[outStream close];
			
			if (completionBlock)
			{
				dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
					completionBlock(header, metadata, thumbnail, cleartext, error);
				}});
			}
		};
		
		NSError *error = nil;
		
		// Setup output stream
		
		outStream = [NSOutputStream outputStreamToMemory];
		
		[outStream open];
		
		if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
		{
			error = [self errorOpeningStream:outStream forFile:nil];
			NotifyAndCleanup(error);
			return;
		}
		
		// Check for cancellation before we start disk IO
		
		if (progress.cancelled)
		{
			error = [self errorUserCanceled];
			NotifyAndCleanup(error);
			return;
		}
		
		// Run decryption
		
		error = [self _decryptCloudFile: inFileURL
		                  encryptionKey: encryptionKey
		                    retainToken: retainToken
		                       toHeader: &header
		                       metadata: &metadata
		                      thumbnail: &thumbnail
		                   outputStream: outStream
		                   withProgress: progress];
		
		NotifyAndCleanup(error);
		
	}});
	
	return progress;
}

+ (nullable NSError *)_decryptCloudFile:(NSURL *)inFileURL
                          encryptionKey:(NSData *)encryptionKey
                            retainToken:(nullable id)retainToken
                               toHeader:(ZDCCloudFileHeader *_Nullable)outHeader
                               metadata:(NSData *_Nullable *_Nullable)outMetadata
                              thumbnail:(NSData *_Nullable *_Nullable)outThumbnail
                           outputStream:(NSOutputStream *)outStream
                           withProgress:(nullable NSProgress *)progress
{
	NSError *error = nil;
	CloudFile2CleartextInputStream *inStream = nil;
	
	NSUInteger fileSize = 0;
	NSUInteger bufferSize = 0;
	
	NSArray<NSString *> *keys = @[ NSURLPreferredIOBlockSizeKey, NSURLFileSizeKey];
	NSDictionary *resourceValues = nil;
	NSNumber *number = nil;
	
	uint8_t *buffer = NULL;
	
	void *sectionBuffer = NULL;
	uint64_t sectionBufferMallocSize = 0;
	uint64_t sectionBufferLength = 0;
	
	ZDCCloudFileHeader header;
	NSData *metadata = nil;
	NSData *thumbnail = nil;
	
	NSUInteger totalBytesWritten = 0;
	BOOL done = NO;
	
	bzero(&header, sizeof(header));
	
	// Instantiate stream(s)
	
	inStream = [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: inFileURL
	                                                          encryptionKey: encryptionKey];
	inStream.retainToken = retainToken;
	
	if (inStream == nil)
	{
		error = [self errorCreatingStreamForFile:inFileURL];
		goto done;
	}
	
	// Open stream
	
	[inStream open];
	
	if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
	{
		error = [self errorOpeningStream:inStream forFile:inFileURL];
		goto done;
	}
	
	// Prepare for IO
	
	resourceValues = [inFileURL resourceValuesForKeys:keys error:nil];
	
	number = resourceValues[NSURLFileSizeKey];
	if (number != nil) {
		fileSize = [number unsignedIntegerValue];
	}
	
	if (progress && fileSize > 0) {
		progress.totalUnitCount = [inStream.cleartextFileSize longLongValue];
	}
	
	number = resourceValues[NSURLPreferredIOBlockSizeKey];
	if (number != nil) {
		bufferSize = [number unsignedIntegerValue];
	}
	else {
		bufferSize = (1024 * 32); // Pick a sane default chunk size
	}
	
	if (fileSize > 0) { // Don't over-allocate buffer
		bufferSize = MIN(bufferSize, fileSize);
	}
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wambiguous-macro"
	bufferSize = MAX(bufferSize, kZDCNode_TweakBlockSizeInBytes);
#pragma clang diagnostic pop
	
	buffer = malloc((size_t)bufferSize);
	
	if (outHeader || outMetadata || outThumbnail)
	{
		// Read the following sections of the cloud file:
		// - header
		// - metadata
		// - thumbnail
		
		do {
			
			ZDCCloudFileSection sectionRead = inStream.cloudFileSection;
			NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
				
			if (bytesRead < 0)
			{
				// Error reading
				
				error = [self errorReadingWritingStream:inStream forFile:inFileURL];
				goto done;
			}
			else if (bytesRead > 0)
			{
				if (sectionRead == ZDCCloudFileSection_Metadata ||
				    sectionRead == ZDCCloudFileSection_Thumbnail)
				{
					if (sectionBuffer == NULL)
					{
					#pragma clang diagnostic push
					#pragma clang diagnostic ignored "-Wambiguous-macro"
						sectionBufferMallocSize = MAX(header.metadataSize, header.thumbnailSize);
					#pragma clang diagnostic pop
						
						sectionBuffer = malloc((size_t)sectionBufferMallocSize);
					}
					
					uint64_t sectionBufferSpace = sectionBufferMallocSize - sectionBufferLength;
					
					if (sectionBufferSpace < bytesRead)
					{
						sectionBufferMallocSize += (bytesRead - sectionBufferSpace);
						sectionBuffer = reallocf(sectionBuffer, (size_t)sectionBufferMallocSize);
					}
					
					memcpy((sectionBuffer + sectionBufferLength), buffer, bytesRead);
					sectionBufferLength += bytesRead;
				}
			}
			else // if (bytesRead == 0) (end of section)
			{
				if (sectionRead == ZDCCloudFileSection_Header)
				{
					header = inStream.cloudFileHeader;
				}
				else if (sectionRead == ZDCCloudFileSection_Metadata)
				{
					if (sectionBuffer && sectionBufferLength > 0)
					{
						metadata = [NSData dataWithBytes:sectionBuffer length:(NSUInteger)sectionBufferLength];
					}
				}
				else if (sectionRead == ZDCCloudFileSection_Thumbnail)
				{
					if (sectionBuffer && sectionBufferLength > 0)
					{
						thumbnail = [NSData dataWithBytes:sectionBuffer length:(NSUInteger)sectionBufferLength];
					}
				}
				
				sectionBufferLength = 0;
			}
				
		} while (inStream.cloudFileSection < ZDCCloudFileSection_Data);
	}
	else
	{
		// SKIP the following sections of the cloud file:
		// - header
		// - metadata
		// - thumbnail
		//
		[inStream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
	}
	
	// Read the data section of the cloud file
	
	do {
		
		// Read a chunk from the input stream
		
		ZDCCloudFileSection section = inStream.cloudFileSection;
		NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
		
		if (bytesRead < 0)
		{
			// Error reading
			
			error = [self errorReadingWritingStream:inStream forFile:inFileURL];
			goto done;
		}
		else if (bytesRead == 0)
		{
			// End of stream
			
			done = YES;
		}
		else if (section == ZDCCloudFileSection_Data)
		{
			// Write chunk to the output stream.
			// To be safe, we do this in loop (just in case).
			
			NSUInteger loopBytesWritten = 0;
			do {
				
				NSInteger bytesWritten = [outStream write:(buffer + loopBytesWritten)
				                                maxLength:(bytesRead - loopBytesWritten)];
				
				if (bytesWritten <= 0)
				{
					// Error writing
					
					error = [self errorReadingWritingStream:outStream forFile:nil];
					goto done;
				}
				else
				{
					// Update totals and continue
					
					loopBytesWritten += bytesWritten;
					totalBytesWritten += bytesWritten;
				}
				
			} while (loopBytesWritten < bytesRead);
			
			if (progress)
			{
				if (fileSize > 0) {
					progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
				}
				
				if (progress.cancelled)
				{
					error = [self errorUserCanceled];
					goto done;
				}
			}
		}
		
	} while (!done);
	
done:

	if (inStream) {
		[inStream close];
	}

	if (sectionBuffer) {
		ZERO(sectionBuffer, sectionBufferMallocSize);
		free(sectionBuffer);
		sectionBuffer = NULL;
	}
	
	if (buffer) {
		ZERO(buffer, bufferSize);
		free(buffer);
		buffer = NULL;
	}

	if (outHeader) *outHeader = header;
	if (outMetadata) *outMetadata = metadata;
	if (outThumbnail) *outThumbnail = thumbnail;
	
	return error;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convert (Crypto -> Crypto)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
**/
+ (NSProgress *)convertCacheFile:(NSURL *)inFileURL
                     retainToken:(nullable id)retainToken
                   encryptionKey:(NSData *)cacheFileEncryptionKey
              toCloudFileWithKey:(NSData *)cloudFileEncryptionKey
                        metadata:(nullable NSData *)rawMetadata
                       thumbnail:(nullable NSData *)rawThumbnail
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSURL *outputFileURL, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	cacheFileEncryptionKey = [cacheFileEncryptionKey copy]; // mutable data protection
	cloudFileEncryptionKey = [cloudFileEncryptionKey copy]; // mutable data protection
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		__block CacheFile2CleartextInputStream *clearStream = nil;
		__block Cleartext2CloudFileInputStream *inStream = nil;
		__block NSOutputStream *outStream = nil;
		
		__block uint8_t *buffer = NULL;
		__block NSUInteger bufferSize = 0;
		
		__block BOOL outFileCreated = NO;
		
		// Create temp output file location
		
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		
		// Setup routine for completion and errors
		
		void (^NotifyAndCleanup)(NSError *error);
		NotifyAndCleanup = ^(NSError *error) {
			
			[inStream close];
			[outStream close];
			
			if (buffer) {
				ZERO(buffer, bufferSize);
				free(buffer);
				buffer = NULL;
			}
			
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(outFileURL, error);
				}});
			}
			
			if (outFileCreated && error) {
				[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
			}
		};
		
		if (progress.cancelled)
		{
			NSError *error = [self errorUserCanceled];
			NotifyAndCleanup(error);
			return;
		}
		
		// Create streams
		
		clearStream = [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL: inFileURL
		                                                             encryptionKey: cacheFileEncryptionKey];
		clearStream.retainToken = retainToken;
		
		if (clearStream == nil)
		{
			NSError *error = [self errorCreatingStreamForFile:inFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		inStream = [[Cleartext2CloudFileInputStream alloc] initWithCleartextFileStream: clearStream
		                                                                 encryptionKey: cloudFileEncryptionKey];
		
		inStream.rawMetadata = rawMetadata;
		inStream.rawThumbnail = rawThumbnail;
		
		if (inStream == nil)
		{
			NSError *error = [self errorCreatingStreamForFile:inFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		if (outStream == nil)
		{
			NSError *error = [self errorCreatingStreamForFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		// Open streams
		
		[inStream open];
		
		if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
		{
			NSError *error = [self errorOpeningStream:inStream forFile:inFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		[outStream open];
		
		if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
		{
			NSError *error = [self errorOpeningStream:outStream forFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		outFileCreated = YES;
		
		// Prepare for IO
		
		NSUInteger fileSize = [inStream.encryptedFileSize unsignedIntegerValue]; // size of cloud file
		
		if (fileSize > 0) {
			progress.totalUnitCount = fileSize;
		}
		
		NSArray<NSString *> *keys = @[ NSURLPreferredIOBlockSizeKey ];
		
		NSDictionary *resourceValues = [inFileURL resourceValuesForKeys:keys error:nil];
		NSNumber *number = nil;
		
		number = resourceValues[NSURLPreferredIOBlockSizeKey];
		if (number != nil) {
			bufferSize = [number unsignedIntegerValue];
		}
		else {
			bufferSize = (1024 * 32); // Pick a sane default chunk size
		}
		
		if (fileSize > 0) { // Don't over-allocate buffer
			bufferSize = MIN(bufferSize, fileSize);
		}
		
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wambiguous-macro"
		bufferSize = MAX(bufferSize, kZDCNode_TweakBlockSizeInBytes);
	#pragma clang diagnostic pop
		
		buffer = malloc((size_t)bufferSize);
		
		// Start IO
		
		NSUInteger totalBytesWritten = 0;
		
		BOOL done = NO;
		do {
			
			// Read a chunk from the input stream
			
			NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
			
			if (bytesRead < 0)
			{
				// Error reading
				
				NSError *error = [self errorReadingWritingStream:inStream forFile:inFileURL];
				NotifyAndCleanup(error);
				return;
			}
			else if (bytesRead == 0)
			{
				// End of stream
				
				done = YES;
			}
			else // if (bytesRead > 0)
			{
				// Write chunk to the output stream.
				// To be safe, we do this in loop (just in case).
				
				NSUInteger loopBytesWritten = 0;
				do {
					
					NSInteger bytesWritten = [outStream write:(buffer + loopBytesWritten)
					                                maxLength:(bytesRead - loopBytesWritten)];
					
					if (bytesWritten <= 0)
					{
						// Error writing
						
						NSError *error = [self errorReadingWritingStream:outStream forFile:outFileURL];
						NotifyAndCleanup(error);
						return;
					}
					else
					{
						// Update totals and continue
						
						loopBytesWritten += bytesWritten;
						totalBytesWritten += bytesWritten;
					}
					
				} while (loopBytesWritten < bytesRead);
				
				if (fileSize > 0) {
					progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
				}
				
				if (progress.cancelled)
				{
					NSError *error = [self errorUserCanceled];
					NotifyAndCleanup(error);
					return;
				}
			}
			
		} while (!done);
		
		// Done !
		
		NotifyAndCleanup(nil);
		
	}});
	
	return progress;
}

/**
 * See header file for description.
**/
+ (NSProgress *)convertCloudFile:(NSURL *)inFileURL
                     retainToken:(nullable id)retainToken
                   encryptionKey:(NSData *)cloudFileEncryptionKey
              toCacheFileWithKey:(NSData *)cacheFileEncryptionKey
                 completionQueue:(dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(ZDCCloudFileHeader headerInfo,
                                           NSData *metadata, NSData *thumbnail,
                                           NSURL *cacheFileURL, NSError *error))completionBlock
{
	ZDCLogAutoTrace();
	
	cloudFileEncryptionKey = [cloudFileEncryptionKey copy]; // mutable data protection
	cacheFileEncryptionKey = [cacheFileEncryptionKey copy]; // mutable data protection
	
	if (!completionQueue && completionBlock)
		completionQueue = dispatch_get_main_queue();
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		__block CloudFile2CleartextInputStream *clearStream = nil;
		__block Cleartext2CacheFileInputStream *inStream = nil;
		__block NSOutputStream *outStream = nil;
		
		__block uint8_t *buffer = NULL;
		__block NSUInteger bufferSize = 0;
		
		__block uint8_t *sectionBuffer = NULL;
		__block NSUInteger sectionBufferMallocSize = 0;
		__block NSUInteger sectionBufferLength = 0;
		
		__block ZDCCloudFileHeader header;
		__block NSData *metadata = nil;
		__block NSData *thumbnail = nil;
		__block BOOL outFileCreated = NO;
		
		bzero(&header, sizeof(header));
		
		// Create temp output file location
		
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		
		// Setup routine for completion and errors
		
		void (^NotifyAndCleanup)(NSError *error);
		NotifyAndCleanup = ^(NSError *error) {
			
			[inStream close];
			[outStream close];
			
			if (buffer) {
				ZERO(buffer, bufferSize);
				free(buffer);
				buffer = NULL;
			}
			
			if (sectionBuffer) {
				ZERO(sectionBuffer, sectionBufferMallocSize);
				free(sectionBuffer);
				sectionBuffer = NULL;
			}
			
			if (completionBlock)
			{
				dispatch_async(completionQueue, ^{ @autoreleasepool {
					completionBlock(header, metadata, thumbnail, outFileURL, error);
				}});
			}
			
			if (outFileCreated && error) {
				[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
			}
		};
		
		if (progress.cancelled)
		{
			NSError *error = [self errorUserCanceled];
			NotifyAndCleanup(error);
			return;
		}
		
		// Instantiate streams
		
		clearStream = [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: inFileURL
		                                                             encryptionKey: cloudFileEncryptionKey];
		clearStream.retainToken = retainToken;
		
		if (clearStream == nil)
		{
			NSError *error = [self errorCreatingStreamForFile:inFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		inStream =
		  [[Cleartext2CacheFileInputStream alloc] initWithCleartextFileStream: clearStream
		                                                        encryptionKey: cacheFileEncryptionKey];
		
		if (inStream == nil)
		{
			NSError *error = [self errorCreatingStreamForFile:inFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];
		
		if (outStream == nil)
		{
			NSError *error = [self errorCreatingStreamForFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		// Open streams
		
		[inStream open];
		
		if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
		{
			NSError *error = [self errorOpeningStream:inStream forFile:inFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		[outStream open];
		
		if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
		{
			NSError *error = [self errorOpeningStream:outStream forFile:outFileURL];
			NotifyAndCleanup(error);
			return;
		}
		
		outFileCreated = YES;
		
		// Prepare for IO
		
		NSUInteger fileSize = 0;
		
		NSArray<NSString *> *keys = @[ NSURLPreferredIOBlockSizeKey, NSURLFileSizeKey];
		
		NSDictionary *resourceValues = [inFileURL resourceValuesForKeys:keys error:nil];
		NSNumber *number = nil;
		
		number = resourceValues[NSURLFileSizeKey];
		if (number != nil) {
			fileSize = [number unsignedIntegerValue];
		}
		
		if (fileSize > 0) {
			progress.totalUnitCount = fileSize;
		}
		
		number = resourceValues[NSURLPreferredIOBlockSizeKey];
		if (number != nil) {
			bufferSize = [number unsignedIntegerValue];
		}
		else {
			bufferSize = (1024 * 32); // Pick a sane default chunk size
		}
		
		if (fileSize > 0) { // Don't over-allocate buffer
			bufferSize = MIN(bufferSize, fileSize);
		}
		
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wambiguous-macro"
		bufferSize = MAX(bufferSize, kZDCNode_TweakBlockSizeInBytes);
	#pragma clang diagnostic pop
		
		buffer = malloc((size_t)bufferSize);
		
		// Read the following sections of the cloud file:
		// - header
		// - metadata
		// - thumbnail
		
		{ // Scope limiting
			
			do {
			
				ZDCCloudFileSection sectionRead = clearStream.cloudFileSection;
				NSInteger bytesRead = [clearStream read:buffer maxLength:bufferSize];
				
				if (bytesRead < 0)
				{
					// Error reading
					
					NSError *error = [self errorReadingWritingStream:inStream forFile:inFileURL];
					NotifyAndCleanup(error);
					return;
				}
				else if (bytesRead > 0)
				{
					if (sectionRead == ZDCCloudFileSection_Metadata ||
					    sectionRead == ZDCCloudFileSection_Thumbnail)
					{
						if (sectionBuffer == NULL)
						{
						#pragma clang diagnostic push
						#pragma clang diagnostic ignored "-Wambiguous-macro"
							sectionBufferMallocSize = (NSUInteger)MAX(header.metadataSize, header.thumbnailSize);
						#pragma clang diagnostic pop
							
							// Protect against rogue header sections
							sectionBufferMallocSize = MIN(sectionBufferMallocSize, (1024 * 1024 * 16));
							
							sectionBuffer = malloc((size_t)sectionBufferMallocSize);
						}
						
						NSUInteger sectionBufferSpace = sectionBufferMallocSize - sectionBufferLength;
						
						if (sectionBufferSpace < bytesRead)
						{
							sectionBufferMallocSize += (bytesRead - sectionBufferSpace);
							sectionBuffer = reallocf(sectionBuffer, (size_t)sectionBufferMallocSize);
						}
						
						memcpy((sectionBuffer + sectionBufferLength), buffer, bytesRead);
						sectionBufferLength += bytesRead;
					}
				}
				else // if (bytesRead == 0) (end of section)
				{
					if (sectionRead == ZDCCloudFileSection_Header)
					{
						header = clearStream.cloudFileHeader;
					}
					else if (sectionRead == ZDCCloudFileSection_Metadata)
					{
						metadata = [NSData dataWithBytes:sectionBuffer length:(NSUInteger)sectionBufferLength];
					}
					else if (sectionRead == ZDCCloudFileSection_Thumbnail)
					{
						thumbnail = [NSData dataWithBytesNoCopy:sectionBuffer length:(NSUInteger)sectionBufferLength];
					}
					
					sectionBufferLength = 0;
				}
				
			} while (clearStream.cloudFileSection < ZDCCloudFileSection_Data);
			
		}
		
		// Read the data section of the cloud file
		
		uint64_t cleartextFileSize = clearStream.cloudFileHeader.dataSize;
		inStream.cleartextFileSize = @(cleartextFileSize);
		
		NSUInteger totalBytesWritten = 0;
		
		BOOL done = NO;
		do {
			
			// Read a chunk from the input stream
			
			ZDCCloudFileSection section = clearStream.cloudFileSection;
			NSInteger bytesRead = [inStream read:buffer maxLength:bufferSize];
			
			if (bytesRead < 0)
			{
				// Error reading
				
				NSError *error = [self errorReadingWritingStream:inStream forFile:inFileURL];
				NotifyAndCleanup(error);
				return;
			}
			else if (bytesRead == 0)
			{
				// End of stream
				
				done = YES;
			}
			else if (section == ZDCCloudFileSection_Data)
			{
				// Write chunk to the output stream.
				// To be safe, we do this in loop (just in case).
				
				NSUInteger loopBytesWritten = 0;
				do {
					
					NSInteger bytesWritten = [outStream write:(buffer + loopBytesWritten)
					                                maxLength:(bytesRead - loopBytesWritten)];
					
					if (bytesWritten <= 0)
					{
						// Error writing
						
						NSError *error = [self errorReadingWritingStream:outStream forFile:outFileURL];
						NotifyAndCleanup(error);
						return;
					}
					else
					{
						// Update totals and continue
						
						loopBytesWritten += bytesWritten;
						totalBytesWritten += bytesWritten;
					}
					
				} while (loopBytesWritten < bytesRead);
				
				if (fileSize > 0) {
					progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
				}
				
				if (progress.cancelled)
				{
					NSError *error = [self errorUserCanceled];
					NotifyAndCleanup(error);
					return;
				}
			}
			
		} while (!done);
		
		
		// Done !
		
		NotifyAndCleanup(nil);
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (NSProgress *)reEncryptFile:(NSURL *)inFileURL
                      fromKey:(NSData *)inEncryptionKey
                        toKey:(NSData *)outEncryptionKey
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(void (^)(NSURL *_Nullable dstFileURL, NSError *_Nullable error))completionBlock
{
	ZDCLogAutoTrace();
	
	inEncryptionKey = [inEncryptionKey copy]; // mutable data protection
	outEncryptionKey = [outEncryptionKey copy]; // mutable data protection
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:0];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		NSError *error = nil;
		NSURL *outFileURL = [ZDCDirectoryManager generateTempURL];
		
		if (progress.cancelled)
		{
			error = [self errorUserCanceled];
		}
		else
		{
			error =
			  [self _reEncryptFile: inFileURL
			               fromKey: inEncryptionKey
			                toFile: outFileURL
			                 toKey: outEncryptionKey
			              progress: progress];
		}
		
		if (completionBlock)
		{
			dispatch_async(completionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
				
				if (error) {
					completionBlock(nil, error);
				} else {
					completionBlock(outFileURL, nil);
				}
			}});
		}
	}});
	
	return progress;
}

/**
 * See header file for description.
 */
+ (BOOL)reEncryptFile:(NSURL *)srcFileURL
              fromKey:(NSData *)srcEncryptionKey
               toFile:(NSURL *)dstFileURL
                toKey:(NSData *)dstEncryptionKey
                error:(NSError *_Nullable *_Nullable)outError
{
	NSError *error =
	  [self _reEncryptFile: srcFileURL
	               fromKey: srcEncryptionKey
	                toFile: dstFileURL
	                 toKey: dstEncryptionKey
	              progress: nil];
	
	if (outError) *outError = nil;
	return (error == nil);
}

+ (nullable NSError *)_reEncryptFile:(NSURL *)inFileURL
                             fromKey:(NSData *)inEncryptionKey
                              toFile:(NSURL *)outFileURL
                               toKey:(NSData *)outEncryptionKey
                            progress:(nullable NSProgress *)progress
{
	NSError *error = nil;
	
	NSInputStream *inStream = nil;
	NSOutputStream *outStream = nil;
	
	NSUInteger fileSize = 0;
	
	NSArray<NSString *> *keys = nil;
	NSDictionary *resourceValues = nil;
	NSNumber *number = nil;
	
	TBC_ContextRef decryptTBC = kInvalidTBC_ContextRef;
	TBC_ContextRef encryptTBC = kInvalidTBC_ContextRef;
	
	NSUInteger bufferMallocSize = 0;
	
	uint8_t *readBuffer = NULL;
	NSUInteger readBufferOffset = 0;
	
	uint8_t *decryptBuffer = NULL;
	uint8_t *encryptBuffer = NULL;
	
	BOOL outFileCreated = NO;
	
	NSUInteger const keyLength = inEncryptionKey.length; // == outEncryptionKey.length (verified above)
	
	Cipher_Algorithm cipherAlgorithm;
	switch (keyLength * 8) // numBytes * 8 = numBits
	{
		case  256 : cipherAlgorithm = kCipher_Algorithm_3FISH256;  break;
		case  512 : cipherAlgorithm = kCipher_Algorithm_3FISH512;  break;
		case 1024 : cipherAlgorithm = kCipher_Algorithm_3FISH1024; break;
		default   : cipherAlgorithm = kCipher_Algorithm_Invalid;   break;
	}
	
	if (inEncryptionKey.length != outEncryptionKey.length)
	{
		error = [self errorWithDescription:@"Key length mismatch !"];
		goto done;
	}
	if (cipherAlgorithm == kCipher_Algorithm_Invalid)
	{
		error = [self errorWithDescription:@"Invalid key length !"];
		goto done;
	}
	
	// Create streams
	
	inStream = [NSInputStream inputStreamWithURL:inFileURL];

	if (inStream == nil)
	{
		error = [self errorCreatingStreamForFile:inFileURL];
		goto done;
	}

	outStream = [NSOutputStream outputStreamWithURL:outFileURL append:NO];

	if (outStream == nil)
	{
		error = [self errorCreatingStreamForFile:outFileURL];
		goto done;
	}

	// Open streams

	[inStream open];

	if (inStream.streamStatus != NSStreamStatusOpen || inStream.streamError)
	{
		error = [self errorOpeningStream:inStream forFile:inFileURL];
		goto done;
	}

	[outStream open];

	if (outStream.streamStatus != NSStreamStatusOpen || outStream.streamError)
	{
		error = [self errorOpeningStream:outStream forFile:outFileURL];
		goto done;
	}

	outFileCreated = YES;

	// Prepare for IO

	keys = @[ NSURLFileSizeKey, NSURLPreferredIOBlockSizeKey];
	resourceValues = [inFileURL resourceValuesForKeys:keys error:nil];

	number = resourceValues[NSURLFileSizeKey];
	if (number != nil) {
		fileSize = [number unsignedIntegerValue];
	}

	if (fileSize > 0) {
		progress.totalUnitCount = fileSize;
	}

	number = resourceValues[NSURLPreferredIOBlockSizeKey];
	if (number != nil) {
		bufferMallocSize = [number unsignedIntegerValue];
	}
	else {
		bufferMallocSize = (1024 * 32); // Pick a sane default chunk size
	}

	if (fileSize > 0) { // Don't over-allocate buffer
		bufferMallocSize = MIN(bufferMallocSize, fileSize);
	}

	// Ensure bufferSize is a perfect multiple of kZDCNode_TweakBlockSizeInBytes
	//
	if (bufferMallocSize <= kZDCNode_TweakBlockSizeInBytes)
	{
		bufferMallocSize = kZDCNode_TweakBlockSizeInBytes;
	}
	else if ((bufferMallocSize % kZDCNode_TweakBlockSizeInBytes) != 0)
	{
		// round down to the closest blockSize multiplier
		
		NSUInteger multiplier = (NSUInteger)(bufferMallocSize / kZDCNode_TweakBlockSizeInBytes);
		bufferMallocSize =  multiplier * kZDCNode_TweakBlockSizeInBytes;
	}

	readBuffer    = malloc((size_t)bufferMallocSize);
	decryptBuffer = malloc((size_t)bufferMallocSize);
	encryptBuffer = malloc((size_t)bufferMallocSize);

	// Start IO

	uint64_t totalBytesReEncrypted = 0;
	uint64_t totalBytesWritten = 0;
	
	BOOL done = NO;
	do {
		
		// Read a chunk from the input stream
		
		NSInteger bytesRead = [inStream read:(readBuffer + readBufferOffset)
		                           maxLength:(bufferMallocSize - readBufferOffset)];
		
		if (bytesRead < 0)
		{
			// Error reading
			
			error = [self errorReadingWritingStream:inStream forFile:inFileURL];
			goto done;
		}
		else if (bytesRead == 0)
		{
			// End of stream
			
			if (readBufferOffset != 0)
			{
				error = [self errorWithDescription:@"Unexpected EOF (non-keyLength boundry)"];
				goto done;
			}
			
			done = YES;
		}
		else // if (bytesRead > 0)
		{
			readBufferOffset += bytesRead;
			
			// Decrypt as much as we can.
			//
			// On each iteration through the loop we need to:
			// - decrypt a block (of keyLength), and store in decryptBuffer
			// - encrypt a block (of keyLength), and store in encryptBuffer
			
			if (!TBC_ContextRefIsValid(decryptTBC))
			{
				S4Err err = TBC_Init(cipherAlgorithm, inEncryptionKey.bytes, inEncryptionKey.length, &decryptTBC);
				if (err != kS4Err_NoErr)
				{
					error = [NSError errorWithS4Error:err];
					goto done;
				}
			}
			if (!TBC_ContextRefIsValid(encryptTBC))
			{
				S4Err err = TBC_Init(cipherAlgorithm,
				                     outEncryptionKey.bytes,
				                     outEncryptionKey.length,
				                     &encryptTBC);
				
				if (err != kS4Err_NoErr)
				{
					error = [NSError errorWithS4Error:err];
					goto done;
				}
			}
			
			NSUInteger loopBytesReEncrypted = 0;
			
			while ((loopBytesReEncrypted < readBufferOffset) &&
			       ((readBufferOffset - loopBytesReEncrypted) >= keyLength))
			{
				S4Err err = kS4Err_NoErr;
				
				if (((totalBytesReEncrypted % kZDCNode_TweakBlockSizeInBytes) == 0))
				{
					uint64_t blockNumber = (uint64_t)(totalBytesReEncrypted / kZDCNode_TweakBlockSizeInBytes);
					uint64_t tweek[2]    = {blockNumber,0};
					
					err = TBC_SetTweek(decryptTBC, tweek, sizeof(uint64_t) * 2); CKS4ERR;
					err = TBC_SetTweek(encryptTBC, tweek, sizeof(uint64_t) * 2); CKS4ERR;
				}
				
				err = TBC_Decrypt(decryptTBC, (readBuffer + loopBytesReEncrypted),
				                              (decryptBuffer + loopBytesReEncrypted)); CKS4ERR;
				
				err = TBC_Encrypt(encryptTBC, (decryptBuffer + loopBytesReEncrypted),
				                              (encryptBuffer + loopBytesReEncrypted)); CKS4ERR;
				
				loopBytesReEncrypted += keyLength;
				totalBytesReEncrypted += keyLength;
				
				continue;
			S4ErrOccurred:
				{
					error = [NSError errorWithS4Error:err];
					goto done;
				}
			}
			
			// Write chunk(s) to the output stream.
			// To be safe, we do this in loop (just in case).
			
			NSUInteger loopBytesWritten = 0;
			while (loopBytesWritten < loopBytesReEncrypted)
			{
				NSInteger bytesWritten = [outStream write:(encryptBuffer + loopBytesWritten)
														  maxLength:(loopBytesReEncrypted - loopBytesWritten)];
				
				if (bytesWritten <= 0)
				{
					// Error writing
					
					error = [self errorReadingWritingStream:outStream forFile:outFileURL];
					goto done;
				}
				else
				{
					// Update totals and continue
					
					loopBytesWritten += bytesWritten;
					totalBytesWritten += bytesWritten;
				}
			}
			
			// If the input stream gave us an odd number of bytes,
			// we may not have been able to re-encrypt all of it.
			//
			// - move any leftover bytes to the beginning of the readBuffer.
			// - reset offset values
			
			uint64_t leftover = readBufferOffset - loopBytesReEncrypted;
			if ((leftover > 0) && (loopBytesReEncrypted > 0)) // (loopBytesReEncrypted == 0) => no action required
			{
				// We cannot use memcpy because the src & dst may overlap.
				// We MUST used memmove.
				//
				// memmove(void *dst, const void *src, size_t len)
				
				memmove(readBuffer, (readBuffer + readBufferOffset - leftover), leftover);
				
				readBufferOffset = (NSUInteger)leftover;
			}
			else
			{
				readBufferOffset = 0;
			}
			
			// Update progress
			
			if (fileSize > 0) {
				progress.completedUnitCount = MIN(totalBytesWritten, fileSize);
			}
			
			if (progress.cancelled)
			{
				error = [self errorUserCanceled];
				goto done;
			}
		}
		
	} while (!done);
	
done:
	
	[inStream close];
	[outStream close];
	
	if (TBC_ContextRefIsValid(decryptTBC)) {
		TBC_Free(decryptTBC);
		decryptTBC = kInvalidTBC_ContextRef;
	}
	
	if (TBC_ContextRefIsValid(encryptTBC)) {
		TBC_Free(encryptTBC);
		encryptTBC = kInvalidTBC_ContextRef;
	}
	
	if (readBuffer) {
		ZERO(readBuffer, bufferMallocSize);
		free(readBuffer);
		readBuffer = NULL;
	}
	
	if (decryptBuffer) {
		ZERO(decryptBuffer, bufferMallocSize);
		free(decryptBuffer);
		decryptBuffer = NULL;
	}
	
	if (encryptBuffer) {
		ZERO(encryptBuffer, bufferMallocSize);
		free(encryptBuffer);
		encryptBuffer = NULL;
	}
	
	if (outFileCreated && error) {
		[[NSFileManager defaultManager] removeItemAtURL:outFileURL error:nil];
	}
	
	return error;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSError *)errorCreatingStreamForFile:(nullable NSURL *)fileURL
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
	
	userInfo[@"errorCodeType"] = @"ErrorCreatingStream";
	
	NSString *filePath = fileURL.path;
	if (filePath) {
		userInfo[@"filePath"] = filePath;
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:1001 userInfo:[userInfo copy]];
}

+ (NSError *)errorUserCanceled
{
	NSDictionary *userInfo = @{
		@"errorCodeType": @"ErrorUserCancelled"
	};
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:NSURLErrorCancelled userInfo:[userInfo copy]];
}

+ (NSError *)errorOpeningStream:(NSStream *)stream forFile:(nullable NSURL *)fileURL
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:5];
	
	userInfo[@"errorCodeType"] = @"ErrorOpeningStream";
	
	NSString *streamClass = NSStringFromClass([stream class]);
	if (streamClass)
		userInfo[@"streamClass"] = streamClass;
	
	NSString *streamStatus = [self stringFromStreamStatus:stream.streamStatus];
	if (streamStatus)
		userInfo[@"streamStatus"] = streamStatus;
	
	NSError *streamError = stream.streamError;
	if (streamError)
		userInfo[@"streamError"] = streamError;
	
	NSString *filePath = fileURL.path;
	if (filePath)
		userInfo[@"filePath"] = filePath;
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:1002 userInfo:[userInfo copy]];
}

+ (NSError *)errorReadingWritingStream:(NSStream *)stream forFile:(nullable NSURL *)fileURL
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:5];
	
	userInfo[@"errorCodeType"] = @"ErrorReadingWritingStream";
	
	NSString *streamClass = NSStringFromClass([stream class]);
	if (streamClass)
		userInfo[@"streamClass"] = streamClass;
	
	NSString *streamStatus = [self stringFromStreamStatus:stream.streamStatus];
	if (streamStatus)
		userInfo[@"streamStatus"] = streamStatus;
	
	NSError *streamError = stream.streamError;
	if (streamError)
		userInfo[@"streamError"] = streamError;
	
	NSString *filePath = fileURL.path;
	if (filePath)
		userInfo[@"filePath"] = filePath;
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:1003 userInfo:[userInfo copy]];
}

+ (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

+ (NSString *)stringFromStreamStatus:(NSStreamStatus)streamStatus
{
	switch (streamStatus)
	{
		case NSStreamStatusNotOpen : return @"NotOpen";
		case NSStreamStatusOpening : return @"Opening";
		case NSStreamStatusOpen    : return @"Open";
		case NSStreamStatusReading : return @"Reading";
		case NSStreamStatusWriting : return @"Writing";
		case NSStreamStatusAtEnd   : return @"AtEnd";
		case NSStreamStatusClosed  : return @"Closed";
		case NSStreamStatusError   : return @"Error";
		default                    : return @"Unknown";
	}
}

@end
