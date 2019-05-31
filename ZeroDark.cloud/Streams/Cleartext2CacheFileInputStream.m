#import "Cleartext2CacheFileInputStream.h"

#import "CacheFile2CleartextInputStream.h"
#import "ZDCCacheFileHeader.h"
#import "ZDCConstants.h"
#import "ZDCInterruptingInputStream.h"
#import "ZDCLogging.h"

#import "NSError+POSIX.h"
#import "NSError+S4.h"

#import <S4Crypto/S4Crypto.h>

#if DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

@interface ZDCInputStream (Private)

- (NSError *)errorWithDescription:(NSString *)description;
+ (NSError *)errorWithDescription:(NSString *)description;
- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;
+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;

- (void)sendEvent:(NSStreamEvent)streamEvent;
- (void)notifyDelegateOfEvent:(NSStreamEvent)streamEvent;

@end

#define CKS4ERR  if ((err != kS4Err_NoErr)) { goto done; }


typedef NS_ENUM(NSInteger, S4CacheFileEncryptState) {
	S4CacheFileEncryptState_Init = 0,
	S4CacheFileEncryptState_Open,
	S4CacheFileEncryptState_Data,
	S4CacheFileEncryptState_Pad,
	S4CacheFileEncryptState_Done,
};

/**
 * A CacheFile has 3 sections:
 * - header (@see ZDCCacheFileHeader)
 * - encrypted data
 * - padding
 *
 * The encryption is done using a block cipher.
 * It's critical to understand what this means:
 *
 * > A block cipher operates on blocks of a fixed size.
 * > You must feed the block cipher a block of exactly the correct size to get a result.
 * > If the input is too small, the block cipher will give you an error.
 * > If the input is too big, the block cipher will give you an error.
 *
 * So this is where the complication lies. Because the underlying inputStream
 * will give us cleartext data in whatever size it has available. And we'll
 * have to buffer it until we get at least 1 block. Only then can we
 * encrypt it, and start returning data to our reader.
**/
@implementation Cleartext2CacheFileInputStream
{
	// Variables explanation:
	//
	// We place cleartext into the `inBuffer`.
	// This includes the unencrypted header, cleartext from the underlying inputStream, and also the padding.
	//
	// Data must be encrypted in blocks of size encryptionKey.length (the "block size").
	//
	// When `inBufferLength` >= blockSize, we have enough data to produce an encrypted block.
	//
	// However, the reader might ask for some amount of data that's not evenly divisible by the blockSize.
	// For example, they might say "give me (blockSize * 1.5) bytes".
	//
	// In this case we'll be forced to encrypt 2 blocks,
	// but we'll have leftover ciphertext that we can't return to the reader yet.
	//
	// Leftover ciphertext (already encrypted) data goes into `overflowBuffer`.
	
	NSData *                encryptionKey;
	
	uint8_t *               inBuffer;
	uint64_t                inBufferMallocSize;
	uint64_t                inBufferLength;
	
	uint8_t                 overflowBuffer[kZDCNode_TweakBlockSizeInBytes];
	uint64_t                overflowBufferOffset;
	uint64_t                overflowBufferLength;
	
	S4CacheFileEncryptState encryptState;
	TBC_ContextRef          TBC;
	
	uint64_t                stateBytesProcessed; // bytes processed per state (data, pad)
	uint64_t                totalBytesProcessed; // for calculating padLength
	uint64_t                totalBytesEncrypted; // for tracking blocks during encryption
	uint64_t                padLength;
	
	BOOL                    cleartextFileSizeImplicitlySet;
}

@synthesize cleartextFileURL = cleartextFileURL;
@synthesize cleartextData = cleartextData;
@synthesize cleartextFileSize = cleartextFileSize;
@synthesize cleartextFileSizeUnknown = cleartextFileSizeUnknown;
@dynamic encryptedFileSize;

/**
 * See header file for description.
 */
- (instancetype)initWithCleartextFileURL:(NSURL *)inCleartextFileURL encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		cleartextFileURL = inCleartextFileURL;
		encryptionKey = [inEncryptionKey copy];
		
		inputStream = [NSInputStream inputStreamWithURL:cleartextFileURL];
		inputStream.delegate = self;
		
		encryptState = S4CacheFileEncryptState_Init;
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCleartextFileStream:(NSInputStream *)cleartextFileStream encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		inputStream = cleartextFileStream;
		inputStream.delegate = self;
		
		encryptionKey = [inEncryptionKey copy];
		
		encryptState  = S4CacheFileEncryptState_Init;
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCleartextData:(NSData *)inCleartextData
                        encryptionKey:(NSData *)inEncryptionKey
{
	
	NSInputStream *inStream = [NSInputStream inputStreamWithData:inCleartextData];
	
	self = [self initWithCleartextFileStream: inStream
	                           encryptionKey: inEncryptionKey];
	if (self)
	{
		cleartextData = inCleartextData;
		cleartextFileSize = @(cleartextData.length);
	}
	return self;
}

- (void)dealloc
{
	DDLogAutoTrace();
	
	[self close];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Copying a stream is generally used for [NSURLSessionDelegate streamForTask:inSession:].
 * E.g. when when the stream has to be restarted.
 *
 * So it's not designed to completely copy the stream inclusive of all internal state.
 * It's designed to make a duplicate of the stream in such a way that the duplicate can be subsequently opened,
 * and result in being able to upload the intended data.
**/
- (id)copyWithZone:(NSZone *)zone
{
	Cleartext2CacheFileInputStream *copy = nil;
	
	if (cleartextFileURL)
	{
		copy = [[[self class] alloc] initWithCleartextFileURL:cleartextFileURL encryptionKey:encryptionKey];
	}
	else if (cleartextData)
	{
		copy = [[[self class] alloc] initWithCleartextData:cleartextData encryptionKey:encryptionKey];
	}
	else
	{
		NSInputStream *inputStreamCopy = nil;
		
		if ([inputStream conformsToProtocol:@protocol(NSCopying)])
		{
			inputStreamCopy = [inputStream copy];
		}
		
		if (inputStreamCopy)
		{
			copy = [[[self class] alloc] initWithCleartextFileStream:inputStreamCopy encryptionKey:encryptionKey];
		}
	}
	
	if (copy)
	{
		if (!cleartextFileSizeImplicitlySet) {
			copy->cleartextFileSize = cleartextFileSize;
		}
		copy.cleartextFileSizeUnknown = cleartextFileSizeUnknown;
		
		if (fileMinOffset) {
			[copy setProperty:fileMinOffset forKey:ZDCStreamFileMinOffset];
		}
		if (fileMaxOffset) {
			[copy setProperty:fileMaxOffset forKey:ZDCStreamFileMaxOffset];
		}
		
		copy->returnEOFOnWouldBlock = returnEOFOnWouldBlock;
		copy.retainToken = self.retainToken;
	}
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (Cipher_Algorithm)cipherAlgorithm:(NSData *)encryptionKey
{
	switch (encryptionKey.length * 8) // numBytes * 8 = numBits
	{
		case 256  : return kCipher_Algorithm_3FISH256;
		case 512  : return kCipher_Algorithm_3FISH512;
		case 1024 : return kCipher_Algorithm_3FISH1024;
		default   : return kCipher_Algorithm_Invalid;
	}
}

- (Cipher_Algorithm)cipherAlgorithm
{
	return [[self class] cipherAlgorithm:encryptionKey];
}

- (NSNumber *)encryptedFileSize
{
	if (cleartextFileSize == nil) {
		return nil;
	}
	
	uint64_t total = 0;
	
	total += sizeof(ZDCCacheFileHeader);
	total += [cleartextFileSize unsignedLongLongValue];
	total += [self padLength];
	
	return @(total);
}

- (NSUInteger)padLength
{
	if (cleartextFileSize == nil) {
		return 0;
	}
	
	NSUInteger padLength = 0;
	NSUInteger const keyLength = encryptionKey.length;
	
	if (keyLength > 0) // watch out for EXC_ARITHMETIC
	{
		uint64_t total = 0;
		
		total += sizeof(ZDCCacheFileHeader);
		total += [cleartextFileSize unsignedLongLongValue];
		
		padLength = keyLength - (total % keyLength);
		if (padLength == 0)
		{
			// We always force padding at the end of the file.
			// This increases security a bit,
			// and also helps when there's a zero byte file.
			
			padLength = keyLength;
		}
	}
	
	return padLength;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSStream subclass overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)open
{
	DDLogAutoTrace();
	
	if (streamStatus != NSStreamStatusNotOpen) {
		return;
	}
	
	// Check for valid encryptionKey
	if ([self cipherAlgorithm] == kCipher_Algorithm_Invalid)
	{
		NSString *desc = @"Unsupported keysize.";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	if (!inputStream)
	{
		NSString *desc = @"Bad parameter: cleartextFileStream || cleartextFileURL.";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	[inputStream open];
	
	streamStatus = [inputStream streamStatus];
	if (streamStatus == NSStreamStatusClosed || streamStatus == NSStreamStatusError)
	{
		streamError = [inputStream streamError];
		streamStatus = NSStreamStatusError;
		// We will automatically forward streamEvent from inputStream
		
		return;
	}
	
	if (cleartextFileSize == nil)
	{
		if (cleartextFileURL)
		{
			// I don't trust Apple's caching mechanism within NSURL.
			// I've seen too many bugs with it in the past.
			[cleartextFileURL removeCachedResourceValueForKey:NSURLFileSizeKey];
			
			NSNumber *fileSizeNumber = nil;
			if ([cleartextFileURL getResourceValue:&fileSizeNumber forKey:NSURLFileSizeKey error:nil])
			{
				cleartextFileSize = fileSizeNumber;
				cleartextFileSizeImplicitlySet = YES;
			}
		}
		else if ([inputStream isKindOfClass:[CacheFile2CleartextInputStream class]])
		{
			cleartextFileSize = [(CacheFile2CleartextInputStream *)inputStream cleartextFileSize];
			cleartextFileSizeImplicitlySet = YES;
		}
		else if ([inputStream isKindOfClass:[ZDCInterruptingInputStream class]])
		{
			cleartextFileSize = [(ZDCInterruptingInputStream *)inputStream fileSize];
			cleartextFileSizeImplicitlySet = YES;
		}
	}
	
	// The `cleartextFileSize` will be needed to write the header.
	// We check it later in `read:maxLength:` to allow the caller to set it after open (just in case).
	
	encryptState = S4CacheFileEncryptState_Open;
	
	streamError = nil;
	streamStatus = NSStreamStatusOpen;
	[self sendEvent:NSStreamEventOpenCompleted];
}

- (void)close
{
	DDLogAutoTrace();
	
	if (streamStatus == NSStreamStatusClosed) return;
	
	if (inBuffer)
	{
		ZERO(inBuffer, inBufferMallocSize);
		
		free(inBuffer);
		inBuffer = NULL;
		inBufferMallocSize = 0;
		inBufferLength = 0;
	}
	
	ZERO(overflowBuffer, sizeof(overflowBuffer));
	overflowBufferOffset = 0;
	overflowBufferLength = 0;
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	stateBytesProcessed = 0;
	totalBytesProcessed = 0;
	totalBytesEncrypted = 0;
	padLength           = 0;
	
	[inputStream close];
	streamStatus = NSStreamStatusClosed;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSInputStream subclass overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)read:(uint8_t *)requestBuffer maxLength:(NSUInteger)requestBufferMallocSize
{
	DDLogAutoTrace();
	
	if (streamStatus == NSStreamStatusNotOpen ||
	    streamStatus == NSStreamStatusError   ||
	    streamStatus == NSStreamStatusClosed)
	{
		// I tested these scenarios with a normal NSInputStream.
		//
		// Attempting a read on a non-open stream simply returns -1,
		// and does not modify streamStatus or streamError.
		//
		// It also doesn't broadcast NSStreamEventErrorOccurred.
		
		return -1;
	}
	
	if (streamStatus == NSStreamStatusAtEnd) {
		return 0;
	}
	
	if (requestBufferMallocSize == 0)
	{
		// I tested this scenario with a normal NSInputStream.
		//
		// Calling read with a maxLength of zero simply returns 0,
		// and does not modify streamStatus or streamError.
		//
		// It also doesn't broadcast NSStreamEventErrorOccurred.
		
		return 0;
	}
	
	if (!cleartextFileSize && !cleartextFileSizeUnknown)
	{
		NSString *desc =
			@"You must set the cleartextFileSize property before you can read."
			@" If you're unable to get that value in advance, you can set cleartextFileSizeUnknown to YES,"
			@" but then you'll also have to re-write the CacheFile header afterwards. "
			@" See [Cleartext2CacheFileInputstream updateCacheFileHeader:withCleartextFileSize:encryptionKey:]";
		
		streamError = [self errorWithDescription:desc];
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return -1;
	}
	
	S4Err err = kS4Err_NoErr;
	NSUInteger const keyLength = encryptionKey.length;
	NSUInteger requestBufferOffset = 0;
	
	// Drain the overflowBuffer first (if available)
	
	uint64_t overflowAvailable = overflowBufferLength - overflowBufferOffset;
	
	if (overflowAvailable > 0)
	{
		size_t bytesToCopy = (size_t) MIN(requestBufferMallocSize, overflowAvailable);
		
		memcpy((requestBuffer + requestBufferOffset), (overflowBuffer + overflowBufferOffset), bytesToCopy);
		
		requestBufferOffset += bytesToCopy;
		overflowBufferOffset += bytesToCopy;
		
		if (overflowBufferOffset >= overflowBufferLength)
		{
			overflowBufferOffset = 0;
			overflowBufferLength = 0;
		}
		
		if (requestBufferOffset == requestBufferMallocSize)
		{
			return requestBufferOffset;
		}
	}
	
	// Calculate how many bytes we're actually going to read from the underlying stream.
	//
	// bytesToRead:
	// - we need at least keyLength bytes (64) in order to encrypt something
	// - we prefer to read in multiples of kZDCNode_TweakBlockSizeInBytes (1024),
	//   and then store the excess in the overflowBuffer
	//
	// minBytesToRead
	// - don't output zero to the reader unless we're actually at EOF
	// - unless reader asked for zero bytes
	
	NSUInteger bytesToRead = 0;
	NSUInteger minBytesToRead = 0;
	
	{ // scope limiting for various variables
		
		NSUInteger neededToFillRequest = requestBufferMallocSize - requestBufferOffset;
		NSUInteger neededToReturnNonZero = (requestBufferOffset > 0) ? 0 : 1;
		
	//	if (pendingSeek_ignore)
	//	{
	//		// Placeholder for future work
	//	}
		
		bytesToRead = neededToFillRequest;
		minBytesToRead = neededToReturnNonZero;
		
		// At this point both `bytesToRead` & `minBytesToRead` express the number of
		// ciphertext bytes we need to produce. That is, the number of bytes we need to put
		// into the caller's requestBuffer.
		//
		// Of course, to get these bytes, we need to encrypt something first.
		// And we can only perform encryption on blockSize chunks.
		//
		// So if these values are non-zero, then we need to round them to a blockSize multiple.
		
		if (bytesToRead > 0)
		{
			if (bytesToRead <= kZDCNode_TweakBlockSizeInBytes)
			{
				bytesToRead = kZDCNode_TweakBlockSizeInBytes;
			}
			else if ((bytesToRead % kZDCNode_TweakBlockSizeInBytes) != 0)
			{
				// round up to next blockSize multiplier
		
				NSUInteger multiplier = (NSUInteger)(bytesToRead / kZDCNode_TweakBlockSizeInBytes) + 1;
				bytesToRead =  multiplier * kZDCNode_TweakBlockSizeInBytes;
			}
		}
		
		if ((minBytesToRead > 0) && (keyLength > 0 /* Silence analyzer warning: division by zero */))
		{
			if (minBytesToRead <= keyLength)
			{
				minBytesToRead = keyLength;
			}
			else if ((minBytesToRead % keyLength) != 0)
			{
				// round up to next keyLength multiplier
				
				NSUInteger multiplier = (NSUInteger)(minBytesToRead / keyLength) + 1;
				minBytesToRead =  multiplier * keyLength;
			}
		}
		
		if (inBufferLength > 0)
		{
			// We got less data than requested during previous read.
			// Theoretically possible when reading directly from disk,
			// but more likely we're reading from a network backed stream (e.g. Network Attached Storage).
			
			if (bytesToRead >= inBufferLength)
				bytesToRead -= inBufferLength;
			else
				bytesToRead = 0;
			
			if (minBytesToRead >= inBufferLength)
				minBytesToRead -= inBufferLength;
			else
				minBytesToRead = 0;
		}
	}
	
	// Make sure we have room in 'inBuffer'
	
	uint64_t inBufferSpace = inBuffer ? (inBufferMallocSize - inBufferLength) : 0;
	if (inBufferSpace < bytesToRead)
	{
		inBufferMallocSize += (bytesToRead - inBufferSpace);
		
		if (inBuffer)
			inBuffer = reallocf(inBuffer, (size_t)inBufferMallocSize);
		else
			inBuffer = malloc((size_t)inBufferMallocSize);
		
		if (inBuffer == NULL)
		{
			inBufferMallocSize = 0;
			return requestBufferOffset;
		}
	}
	
	// Fill as much of the 'inBuffer' as we can.
	//
	// Note: We may be starting with leftover data in 'inBuffer' from a previous read.
	// In other words, 'inBufferLength' may be non-zero.
	// This is the reason we have an explicit 'bytesRead' specifically for this pass.
	
	NSUInteger bytesRead = 0;
	BOOL readPartial = NO;
	
	while ((bytesRead < bytesToRead) && (encryptState != S4CacheFileEncryptState_Done) && !readPartial)
	{
		switch (encryptState)
		{
			case S4CacheFileEncryptState_Open:
			{
				NSAssert((inBufferMallocSize - inBufferLength) >= sizeof(ZDCCacheFileHeader), @"Bad buffer");
				
				uint64_t inStreamSize = cleartextFileSize ? [cleartextFileSize unsignedLongLongValue] : 0;
				
				uint8_t *p = inBuffer + inBufferLength;
                
				S4_Store64(kZDCCacheFileContextMagic,      &p);
				S4_Store64(inStreamSize,                  &p);
				S4_StorePad(0, kZDCCacheFileReservedBytes, &p); // reserved
				
				NSUInteger headerBytesUsed = p - (inBuffer + inBufferLength);
				
				NSAssert(headerBytesUsed == sizeof(ZDCCacheFileHeader), @"Bad math !");
				
				bytesRead           += headerBytesUsed;
				inBufferLength      += headerBytesUsed;
				totalBytesProcessed += headerBytesUsed;
				
				stateBytesProcessed = 0;
				encryptState = S4CacheFileEncryptState_Data;
				
				break;
			}
			case S4CacheFileEncryptState_Data:
			{
				NSInteger inFromStream = 0;
				
				BOOL shouldRead = YES;
				if ([returnEOFOnWouldBlock boolValue])
				{
					// Caller doesn't want to block.
					// Supports returning 0 from this method,
					// and understands it might not mean EOF (checks streamStatus to differentiate).
					
					if (![inputStream hasBytesAvailable])
					{
						shouldRead = NO;
						readPartial = YES;
					}
				}
				
				if (shouldRead)
				{
					inFromStream = [inputStream read:(inBuffer + inBufferLength)
				                          maxLength:(bytesToRead - bytesRead)];
				}
				
				if (inFromStream < 0)
				{
					streamError = [inputStream streamError];
					streamStatus = NSStreamStatusError;
					[self sendEvent:NSStreamEventErrorOccurred];
					
					if (requestBufferOffset > 0)
						return requestBufferOffset;
					else
						return inFromStream;
				}
				
				bytesRead           += inFromStream;
				inBufferLength      += inFromStream;
				stateBytesProcessed += inFromStream;
				totalBytesProcessed += inFromStream;
				
				BOOL inputStreamEOF = (inFromStream == 0) && shouldRead;
				
				if (cleartextFileSize)
				{
					uint64_t expectedFileSize = [cleartextFileSize unsignedLongLongValue];
				
					if ((stateBytesProcessed < expectedFileSize) && inputStreamEOF)
					{
						// File is smaller than expected !
				
						NSString *desc =
						  [NSString stringWithFormat:@"Unexpected cleartextFileSize: found(%llu) < expected(%llu)",
						    stateBytesProcessed, expectedFileSize];
				
						streamError = [self errorWithDescription:desc code:ZDCStreamUnexpectedFileSize];
						streamStatus = NSStreamStatusError;
						[self sendEvent:NSStreamEventErrorOccurred];
				
						return -1;
					}
					else if (stateBytesProcessed > expectedFileSize)
					{
						// File is bigger than expected !
				
						NSString *desc =
						  [NSString stringWithFormat:@"Unexpected cleartextFileSize: found(%llu) > expected(%llu)",
						    stateBytesProcessed, expectedFileSize];
				
						streamError = [self errorWithDescription:desc code:ZDCStreamUnexpectedFileSize];
						streamStatus = NSStreamStatusError;
						[self sendEvent:NSStreamEventErrorOccurred];
				
						return -1;
					}
					else if ((stateBytesProcessed == expectedFileSize) && inputStreamEOF)
					{
						stateBytesProcessed = 0;
						encryptState = S4CacheFileEncryptState_Pad;
					}
				}
				else // if (cleartextFileSize == nil)
				{
					// We didn't know what the cleartextFileSize would be in advance.
					
					if (inputStreamEOF)
					{
						cleartextFileSize = @(stateBytesProcessed);
						
						stateBytesProcessed = 0;
						encryptState = S4CacheFileEncryptState_Pad;
					}
				}
				
				if ((encryptState != S4CacheFileEncryptState_Pad) && !readPartial)
				{
					// We read from the inputStream once, and it gave us data.
					// However, it may not have given us as much data as we wanted.
					//
					// If this is the case, then we can stop reading IF
					// we have enough data to output something to the reader.
					//
					// We need to avoid returning a zero at the end of this method,
					// which is the indicator for EOF. (Even though we're not EOF.)
					
					if (inBufferLength >= minBytesToRead)
					{
						readPartial = YES;
					}
				}
				
				break;
			}
			case S4CacheFileEncryptState_Pad:
			{
				NSUInteger padLength = [self padLength];
				uint64_t bytesToPad = MIN((padLength - stateBytesProcessed), (bytesToRead - bytesRead));
				
				uint64_t padNumber = padLength;
				while (padNumber > UINT8_MAX) {
					padNumber -= UINT8_MAX;
				}
				
				uint8_t *p = inBuffer + inBufferLength;
				S4_StorePad((uint8_t)padNumber, (size_t)bytesToPad, &p);
				
				bytesRead           += bytesToPad;
				inBufferLength      += bytesToPad;
				stateBytesProcessed += bytesToPad;
				totalBytesProcessed += bytesToPad;
				
				if (stateBytesProcessed >= padLength)
				{
					stateBytesProcessed = 0;
					encryptState = S4CacheFileEncryptState_Done;
				}
				
				break;
			}
			default: { break; }
		}
	}
	
	// Encrypt as much as we can
	
	NSUInteger bytesEncrypted = 0;

	while ((bytesEncrypted < inBufferLength) && ((inBufferLength - bytesEncrypted) >= keyLength))
	{
		// Set/Reset Tweakable Block Cipher (TBC) if:
		//
		// - we're on a block boundary
		// - we just initialized the TBC
		//
		BOOL needsSetTweak = NO;
		if (!TBC_ContextRefIsValid(TBC))
		{
			err = TBC_Init([self cipherAlgorithm], encryptionKey.bytes, encryptionKey.length, &TBC); CKS4ERR;
			needsSetTweak = YES;
		}
		else
		{
			needsSetTweak = ((totalBytesEncrypted % kZDCNode_TweakBlockSizeInBytes) == 0);
		}
		
		if (needsSetTweak)
		{
			uint64_t tweakBlockNum = (uint64_t)(totalBytesEncrypted / kZDCNode_TweakBlockSizeInBytes);
			uint64_t tweak[2] = {tweakBlockNum, 0};
			
			err = TBC_SetTweek(TBC, tweak, sizeof(tweak)); CKS4ERR;
		}
		
		NSUInteger requestBufferSpace = requestBufferMallocSize - requestBufferOffset;
		if (requestBufferSpace >= keyLength)
		{
			// Encrypt directly into requestBuffer
			
			err = TBC_Encrypt(TBC, (inBuffer + bytesEncrypted), (requestBuffer + requestBufferOffset)); CKS4ERR;
			
			bytesEncrypted += keyLength;
			totalBytesEncrypted += keyLength;
			requestBufferOffset += keyLength;
		}
		else // if (requestBufferSpace < keyLength)
		{
			// Not enough space in the requestBuffer for the entire chunk.
			// Encrypt into the overflowBuffer.
			
			NSAssert((sizeof(overflowBuffer) - overflowBufferLength) >= keyLength,
			         @"Unexpected state: overflowBuffer doesn't have space");
			
			err = TBC_Encrypt(TBC, (inBuffer + bytesEncrypted), (overflowBuffer + overflowBufferLength)); CKS4ERR;
			
			bytesEncrypted += keyLength;
			totalBytesEncrypted += keyLength;
			overflowBufferLength += keyLength;
			
			// Copy bytes into the requestBuffer (if possible).
			
			if (requestBufferSpace > 0)
			{
				uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
				
				uint64_t bytesToCopy = MIN(requestBufferSpace, overflowSize);
				
				memcpy((requestBuffer + requestBufferOffset), (overflowBuffer + overflowBufferOffset), (size_t)bytesToCopy);
				
				requestBufferOffset += bytesToCopy;
				overflowBufferOffset += bytesToCopy;
				
				if (overflowBufferOffset >= overflowBufferLength)
				{
					overflowBufferOffset = 0;
					overflowBufferLength = 0;
				}
			}
		}
	}
	
	// Check for leftover bytes in the 'inBuffer' that we couldn't encrypt.
	// For example:
	//
	// The inputStream gave us 69 bytes.
	// We encrypted 64 bytes.
	// So we have 5 bytes leftover.
	//
	// We move any leftover bytes to the beginning of 'inBuffer',
	// and update 'inBufferLength' accordingly.
	
	if (bytesEncrypted > 0)
	{
		NSAssert(inBufferLength >= bytesEncrypted, @"Logic error");
		
		uint64_t leftover = inBufferLength - bytesEncrypted;
		if (leftover > 0)
		{
			// We cannot use memcpy because the src & dst may overlap.
			// We MUST used memmove.
			
			memmove(inBuffer, (inBuffer + inBufferLength - leftover), leftover);
			inBufferLength = leftover;
		}
		else
		{
			inBufferLength = 0;
		}
	}
	
	// Check for EOF
	
	if (requestBufferOffset == 0) // Can't transition to EOF until we return zero to reader !
	{
		if (encryptState == S4CacheFileEncryptState_Done)
		{
			if (streamStatus < NSStreamStatusAtEnd)
			{
				streamStatus = NSStreamStatusAtEnd;
				[self sendEvent:NSStreamEventEndEncountered];
			}
		}
	}
	
	return requestBufferOffset;
	
done:
	
	streamError = [NSError errorWithS4Error:err];
	streamStatus = NSStreamStatusError;
	[self sendEvent:NSStreamEventErrorOccurred];
	
	return -1;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)length
{
	// Not appropriate for this kind of stream; return NO.
	return NO;
}

- (BOOL)hasBytesAvailable
{
	if ((streamStatus < NSStreamStatusOpen) || (streamStatus >= NSStreamStatusAtEnd)) {
		return NO;
	}
	
	// Here's what the docs for `hasBytesAvailable` say:
	//
	// > YES if the receiver has bytes available to read, otherwise NO.
	// > May also return YES if a read must be attempted in order to determine the availability of bytes.
	//
	// But from the user's perspective, this method is generally used to determine
	// if a call to `read:maxLength:` would block.
	// So we're going to do our best to answer that question.
	
	if ((overflowBufferLength - overflowBufferOffset) > 0)
	{
		// We have data in the overflowBuffer.
		// That is, data we've already encrypted, but didn't fit into the reader's last `read:maxLength:` request.
		
		return YES;
	}
	
	if (encryptState == S4CacheFileEncryptState_Open)
	{
		// We can always generate the header.
		return YES;
	}
	
	if (encryptState == S4CacheFileEncryptState_Pad)
	{
		// We can always generate the padding.
		return YES;
	}
	
	if (encryptState == S4CacheFileEncryptState_Data)
	{
		// Here's where it gets complicated.
		// We can ask the underlying stream if it has data.
		// Let's say it says YES, but it only has a single byte of data available for us.
		// So we could read it without blocking, but that won't give us enough data to form a block.
		// And without a full block we won't be able to encrypt anything.
		//
		// And there's no API to ask the underlying stream how much data it has available for us.
		// So we're forced to return YES in this case, even though performing a read might block the user.
		//
		// For a solution to this problem, we offer the user the `ZDCStreamReturnEOFOnWouldBlock` property.
		
		return [inputStream hasBytesAvailable];
	}
	
	// We're at EOF, but haven't returned EOF to the reader yet.
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDCInputStream subclass overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses should return YES if the `ZDCStreamReturnEOFOnWouldBlock` property is supported.
 * Otherwise ZDCInputStream will refuse to set it, and will return NO in `setProperty:forKey:`.
**/
- (BOOL)supportsEOFOnWouldBlock
{
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSStreamDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Do NOT call this method directly.
 * Instead, you should use [self sendEvent:streamEvent].
 * 
 * @see [ZDCInputStream sendEvent:]
**/
- (void)stream:(NSStream *)sender handleEvent:(NSStreamEvent)streamEvent
{
	switch (streamEvent)
	{
		case NSStreamEventOpenCompleted:
			if (sender == self) {
				[self notifyDelegateOfEvent:streamEvent];
			}
			else {
				DDLogVerbose(@"Ignoring inputStream.NSStreamEventOpenCompleted: We handle this ourself");
			}
			break;
			
		case NSStreamEventHasBytesAvailable:
			[self notifyDelegateOfEvent:streamEvent];
			break;
			
		case NSStreamEventErrorOccurred:
			[self notifyDelegateOfEvent:streamEvent];
			break;
			
		case NSStreamEventEndEncountered:
			if (sender == self) {
				[self notifyDelegateOfEvent:streamEvent];
			}
			else {
				DDLogVerbose(@"Ignoring inputStream.NSStreamEventEndEncountered: We handle this ourself");
			}
			break;
			
		case NSStreamEventHasSpaceAvailable:
			// This doesn't make sense for a read stream
			break;
			
		default:
			break;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Header Update
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Allows you to update the CacheFile header, and rewrites the cleartext file size.
 * Use this method to fixup the header when setting `cleartextFileSizeUnknown` to YES.
**/
+ (nullable NSError *)updateCacheFileHeader:(NSURL *)cacheFileURL
                      withCleartextFileSize:(uint64_t)cleartextFileSize
                              encryptionKey:(NSData *)encryptionKey
{
	NSError *error = nil;
	
	Cipher_Algorithm algo = [self cipherAlgorithm:encryptionKey];
	NSUInteger const keyLength = encryptionKey.length;
	
	NSAssert(keyLength == sizeof(ZDCCacheFileHeader), @"Lazy programmer");
	
	int const flags = O_RDWR;
	int fd = -1;
	
	ssize_t encryptedBufferOffset = 0;
	void *encryptedBuffer = NULL;
	void *decryptedBuffer = NULL;
	
	S4Err err = kS4Err_NoErr;
	TBC_ContextRef TBC = kInvalidTBC_ContextRef;
	
	fd = open(cacheFileURL.path.UTF8String, flags);
	if (fd < 0)
	{
		error = [NSError errorWithPOSIXCode:errno];
		goto cleanup;
	}
	
	encryptedBuffer = malloc(keyLength);
	decryptedBuffer = malloc(keyLength);
	
	do
	{
		ssize_t bytesRead = read(fd, (encryptedBuffer + encryptedBufferOffset), (keyLength - encryptedBufferOffset));
		
		if (bytesRead < 0)
		{
			error = [NSError errorWithPOSIXCode:errno];
			goto cleanup;
		}
		else if (bytesRead == 0)
		{
			error = [self errorWithDescription:@"Unexpected EOF while reading file, prior to end of CacheFile header."];
			goto cleanup;
		}
		else
		{
			encryptedBufferOffset += bytesRead;
		}
		
	} while (encryptedBufferOffset < keyLength);
	
	err = TBC_Init(algo, encryptionKey.bytes, encryptionKey.length, &TBC);
	if (err != kS4Err_NoErr) goto cleanup;
	
	uint64_t blockNumber = 0;
	uint64_t tweek[2]    = {blockNumber,0};
	
	err = TBC_SetTweek(TBC, tweek, sizeof(uint64_t) * 2);
	if (err != kS4Err_NoErr) goto cleanup;
	
	err = TBC_Decrypt(TBC, encryptedBuffer, decryptedBuffer);
	if (err != kS4Err_NoErr) goto cleanup;
	
	uint8_t *p = decryptedBuffer;
	
	uint64_t magic = S4_Load64(&p);
	if (magic != kZDCCacheFileContextMagic)
	{
		NSString *desc = @"File doesn't appear to be a cache File (header magic incorrect)";
		error = [self errorWithDescription:desc];
		goto cleanup;
	}
	
	S4_Store64(cleartextFileSize, &p);
	
	err = TBC_Encrypt(TBC, decryptedBuffer, encryptedBuffer);
	if (err != kS4Err_NoErr) goto cleanup;
	
	encryptedBufferOffset = 0;
	do
	{
		ssize_t bytesWritten =
			pwrite(fd, (encryptedBuffer + encryptedBufferOffset), (keyLength - encryptedBufferOffset),
			       encryptedBufferOffset);
		
		if (bytesWritten <= 0)
		{
			error = [NSError errorWithPOSIXCode:errno];
			goto cleanup;
		}
		else
		{
			encryptedBufferOffset += bytesWritten;
		}
		
	} while (encryptedBufferOffset < keyLength);
	
cleanup:
	
	if (fd >= 0) {
		close(fd);
	}
	
	if (encryptedBuffer) {
		free(encryptedBuffer);
	}
	if (decryptedBuffer) {
		ZERO(decryptedBuffer, keyLength);
		free(decryptedBuffer);
	}
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	if (err != kS4Err_NoErr) {
		error = [NSError errorWithS4Error:err];
	}
	
	return error;
}

@end
