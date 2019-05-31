#import "CacheFile2CleartextInputStream.h"

#import "ZDCCacheFileHeader.h"
#import "ZDCConstants.h"
#import "ZDCLogging.h"

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


@implementation CacheFile2CleartextInputStream
{
	NSURL *             cacheFileURL;
	NSData *            cacheFileData;
	NSData *            encryptionKey;
	
	uint8_t *           inBuffer;
	uint64_t            inBufferMallocSize;
	uint64_t            inBufferLength;
	
	uint8_t             overflowBuffer[kZDCNode_TweakBlockSizeInBytes];
	uint64_t            overflowBufferOffset;
	uint64_t            overflowBufferLength;
	
	TBC_ContextRef      TBC;
	
	BOOL                hasReadHeader;
	uint64_t            fileSize;
	
	uint64_t            decryptionOffset;
	uint64_t            cursorOffset; // offset in underlying stream, excluding overflowBuffer
	
	NSNumber *          pendingSeek_offset;
	NSNumber *          pendingSeek_ignore;
}

@dynamic cleartextFileSize;

/**
 * See header file for description.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile
{
	if (cryptoFile) {
		NSParameterAssert(cryptoFile.fileFormat == ZDCCryptoFileFormat_CacheFile);
	}
	
	self = [self initWithCacheFileURL: cryptoFile.fileURL
	                    encryptionKey: cryptoFile.encryptionKey];
	
	if (self)
	{
		self.retainToken = cryptoFile.retainToken;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCacheFileURL:(NSURL *)inCacheFileURL
                       encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		cacheFileURL = inCacheFileURL;
		encryptionKey = [inEncryptionKey copy];
		
		inputStream = [NSInputStream inputStreamWithURL:cacheFileURL];
		inputStream.delegate = self;
		
		inBuffer = NULL;
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCacheFileStream:(NSInputStream *)inCacheFileStream
                          encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		encryptionKey = [inEncryptionKey copy];
		
		inputStream = inCacheFileStream;
		inputStream.delegate = self;
		
		inBuffer = NULL;
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCacheFileData:(NSData *)inCacheFileData
								encryptionKey:(NSData *)inEncryptionKey
{
	NSInputStream *inStream = [NSInputStream inputStreamWithData:inCacheFileData];
	
	self = [self initWithCacheFileStream: inStream
	                       encryptionKey: inEncryptionKey];
	if (self)
	{
		cacheFileData = inCacheFileData;
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
 */
- (id)copyWithZone:(NSZone *)zone
{
	CacheFile2CleartextInputStream *copy = nil;
	
	if (cacheFileURL)
	{
		copy = [[[self class] alloc] initWithCacheFileURL:cacheFileURL encryptionKey:encryptionKey];
	}
	else if (cacheFileData)
	{
		copy = [[[self class] alloc] initWithCacheFileData:cacheFileData encryptionKey:encryptionKey];
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
			copy =  [[[self class] alloc] initWithCacheFileStream:inputStreamCopy encryptionKey:encryptionKey];
		}
	}
	
	if (copy)
	{
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

- (Cipher_Algorithm)cipherAlgorithm
{
	switch (encryptionKey.length * 8) // numBytes * 8 == numBits
	{
		case 256  : return kCipher_Algorithm_3FISH256;
		case 512  : return kCipher_Algorithm_3FISH512;
		case 1024 : return kCipher_Algorithm_3FISH1024;
		default   : return kCipher_Algorithm_Invalid;
	}
}

- (NSNumber *)cleartextFileSize
{
	if (hasReadHeader)
		return @(fileSize);
	else
		return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)seekToPendingOffset
{
	NSAssert(hasReadHeader == YES,      @"Seek request in bad state: !hasReadHeader");
	NSAssert(pendingSeek_offset != nil, @"Seek request in bad state: !pendingSeekOffset");
	
	// Watch out for edge case:
	// Once a normal stream hits EOF, it still allows seeking, but won't allow any more reading.
	// The only way around this is to re-create the underlying stream.
	
	if (inputStream.streamStatus == NSStreamStatusAtEnd)
	{
		{ // limiting scope
			
			NSInputStream *newInputStream = nil;
		
			if (cacheFileURL)
			{
				newInputStream = [NSInputStream inputStreamWithURL:cacheFileURL];
				newInputStream.delegate = self;
			}
			else if ([inputStream conformsToProtocol:@protocol(NSCopying)])
			{
				newInputStream = [inputStream copy];
				newInputStream.delegate = self;
			}
			
			if (!newInputStream)
			{
				NSString *desc = @"Unable to copy underlying stream.";
				
				streamError = [self errorWithDescription:desc];
				streamStatus = NSStreamStatusError;
				[self sendEvent:NSStreamEventErrorOccurred];
				
				return;
			}
			
			inputStream = newInputStream;
		}
		
		[inputStream open];
		
		if (inputStream.streamStatus == NSStreamStatusError)
		{
			streamError = [inputStream streamError];
			streamStatus = NSStreamStatusError;
			// We will automatically forward streamEvent from inputStream
			
			return;
		}
	}
	
	uint64_t requestedCleartextOffset = [pendingSeek_offset unsignedLongLongValue];
	uint64_t requestedCachefileOffset = sizeof(ZDCCacheFileHeader) + requestedCleartextOffset;
	
	uint64_t nearestBlockIndex = (uint64_t)(requestedCachefileOffset / kZDCNode_TweakBlockSizeInBytes);
	uint64_t nearestBlockOffset = nearestBlockIndex * kZDCNode_TweakBlockSizeInBytes;
	
	if (![inputStream setProperty:@(nearestBlockOffset) forKey:NSStreamFileCurrentOffsetKey])
	{
		NSString *desc = @"Unable to seek to desired offset.";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	// Reset all state variables to reflect the new situation
	
	inBufferLength = 0;
	
	overflowBufferOffset = 0;
	overflowBufferLength = 0;
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	decryptionOffset = nearestBlockOffset;
	cursorOffset     = nearestBlockOffset;
	
	pendingSeek_offset = nil;
	
	uint64_t ignore = requestedCachefileOffset - nearestBlockOffset;
	if (ignore > 0) {
		pendingSeek_ignore = @(ignore);
	}
	else {
		// always reset in case of multiple SEEK requests
		pendingSeek_ignore = nil;
	}
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
		NSString *desc = @"Bad parameter: cacheFileStream || cacheFileURL.";
		
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
	
	streamError = nil;
	streamStatus = NSStreamStatusOpen;
	[self sendEvent:NSStreamEventOpenCompleted];
	
	// Now we read the first block of the stream.
	// This will allow us to calculate the cleartextFileSize.
	//
	// Note: The read:maxLength: method explicitly supports being called with a zero maxLength
	//       parameter if hasReadHeader is false. (i.e. this situation here)
	
	uint8_t ignore[0];
	[self read:ignore maxLength:0];
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

	decryptionOffset = 0;
	cursorOffset = 0;
	
	[inputStream close];
	streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(NSString *)key
{
	if ([key isEqualToString:NSStreamFileCurrentOffsetKey])
	{
		uint64_t cursor = 0;
		
		if (pendingSeek_offset != nil) {
			cursor = pendingSeek_offset.unsignedLongLongValue;
		}
		else {
			cursor = cursorOffset;
		}
		
		size_t headerSize = sizeof(ZDCCacheFileHeader);
		if (cursor <= headerSize)
			return @(0);
		else
			return @(cursor - headerSize);
	}
	
	return [super propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
	if ([key isEqualToString:NSStreamFileCurrentOffsetKey])
	{
		if (![property isKindOfClass:[NSNumber class]]) return NO;
		
		NSNumber *oldOffset = [self propertyForKey:NSStreamFileCurrentOffsetKey];
		NSNumber *newOffset = (NSNumber *)property;
		
		if (oldOffset && newOffset && [oldOffset isEqual:newOffset])
		{
			// Ignore spurious request
			return YES;
		}
		
		pendingSeek_offset = newOffset;
		pendingSeek_ignore = nil;
		
		if (streamStatus == NSStreamStatusOpen) {
			[self seekToPendingOffset];
		}
		
		return YES;
	}
	
	return [super setProperty:property forKey:key];
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
	
	if ((requestBufferMallocSize == 0) && hasReadHeader)
	{
		// I tested this scenario with a normal NSInputStream.
		//
		// Calling read with a maxLength of zero simply returns 0,
		// and does not modify streamStatus or streamError.
		//
		// It also doesn't broadcast NSStreamEventErrorOccurred.
		
		return 0;
	}
	
	S4Err err = kS4Err_NoErr;
	NSUInteger keyLength = encryptionKey.length;
	NSUInteger requestBufferOffset = 0;
	
	BOOL requestComplete = NO;
	
	// Drain the overflowBuffer first (if available)
	
	uint64_t overflowAvailable = overflowBufferLength - overflowBufferOffset;
	
	if (overflowAvailable > 0)
	{
		size_t bytesToCopy = (size_t) MIN(requestBufferMallocSize, overflowAvailable);
		
		memcpy((requestBuffer + requestBufferOffset), (overflowBuffer + overflowBufferOffset), bytesToCopy);
		
		requestBufferOffset  += bytesToCopy;
		overflowBufferOffset += bytesToCopy;
		cursorOffset         += bytesToCopy;
		
		// Did we drain the overflowBuffer ?
		
		if (overflowBufferOffset >= overflowBufferLength)
		{
			overflowBufferOffset = 0;
			overflowBufferLength = 0;
		}
		
		if (requestBufferOffset >= requestBufferMallocSize)
		{
			// Don't return here !
			// The overflowBuffer may contain padding that we still need to strip.
			
			requestComplete = YES;
		}
	}
	
	// Calculate how many bytes we're actually going to read from the underlying stream.
	//
	// bytesToRead:
	// - we need at least keyLength bytes (64) in order to decrypt something
	// - we prefer to read in multiples of kZDCNode_TweakBlockSizeInBytes (1024),
	//   and then store the excess in the overflowBuffer
	//
	// minBytesToRead
	// - don't output zero to the reader unless we're actually at EOF
	// - unless reader asked for zero bytes (as is the case when called from open method)
	
	NSUInteger bytesToRead = 0;
	NSUInteger minBytesToRead = 0;
	
	{ // scope limiting
		
		// Note: We invoke this method with (requestBufferMallocSize == 0) from our open method.
		// We do this to force read the fileSize.
		//
		// So we have to make sure that if (requestBufferMallocSize == 0),
		// and we haven't read from the stream yet,
		// then we read at least a block.
		
		bytesToRead = requestBufferMallocSize - requestBufferOffset;
		minBytesToRead = (bytesToRead == 0 ? 0 : 1);
		
		if (!hasReadHeader)
		{
			// We need to read the entire header.
			// We don't output the header to the reader.
			NSUInteger increment = sizeof(ZDCCacheFileHeader);
			
			bytesToRead    += increment;
			minBytesToRead += increment;
		}
		if (pendingSeek_ignore != nil)
		{
			// We don't output ignored bytes to the reader.
			NSUInteger increment = [pendingSeek_ignore unsignedIntegerValue];
			
			bytesToRead    += increment;
			minBytesToRead += increment;
		}
		
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
	
	// Read from the inputStream
	
	NSInteger bytesRead = 0;
	
	if ((bytesToRead > 0) && !requestComplete)
	{
		BOOL readEOF = NO;
		BOOL readPartial = NO;
		
		while ((bytesRead < bytesToRead) && !readEOF && !readPartial)
		{
			NSUInteger loopBytesToRead = (bytesToRead - bytesRead);
			NSInteger loopBytesRead = [inputStream read:(inBuffer + inBufferLength) maxLength:loopBytesToRead];
			
			if (loopBytesRead < 0)
			{
				streamError = [inputStream streamError];
				streamStatus = NSStreamStatusError;
				[self sendEvent:NSStreamEventErrorOccurred];
				
				if (requestBufferOffset > 0)
					return requestBufferOffset;
				else
					return bytesRead;
			}
			else
			{
				bytesRead += loopBytesRead;
				inBufferLength += loopBytesRead;
				
				if (loopBytesRead == 0)
				{
					readEOF = YES;
				}
				if (inBufferLength >= minBytesToRead)
				{
					// We read from the inputStream once, and it gave us data.
					// However, it may not have given us as much data as we wanted.
					//
					// If this is the case, then we can stop reading IF
					// we have enough data to output something to the reader.
					//
					// We need to avoid returning a zero at the end of this method,
					// which is the indicator for EOF. (Even though we're not EOF.)
					
					readPartial = YES;
				}
			}
		}
	}
	
	// Decrypt as much data as we can.
 	//
	// Note:
	// - we can only decrypt in keyLength size chunks (generally 64 bytes)
	// - every "block size" we tweek the encryption (generally 1024 bytes)
	
	NSUInteger bytesDecrypted = 0;
	
	while ((bytesDecrypted < inBufferLength) && ((inBufferLength - bytesDecrypted) >= keyLength))
	{
		// Set/Reset Tweakable Block Cipher (TBC) if:
		//
		// - we're on a block boundary
		// - we just initialized the TBC
		//
		BOOL needsSetTweak = NO;
		if (!TBC_ContextRefIsValid(TBC))
		{
			err = TBC_Init([self cipherAlgorithm], encryptionKey.bytes,encryptionKey.length, &TBC); CKS4ERR;
			needsSetTweak = YES;
		}
		else
		{
			needsSetTweak = ((decryptionOffset % kZDCNode_TweakBlockSizeInBytes) == 0);
		}
		
		if (needsSetTweak)
		{
			uint64_t tweakBlockNum = (uint64_t)(decryptionOffset / kZDCNode_TweakBlockSizeInBytes);
			uint64_t tweak[2] = {tweakBlockNum,0};
			
			err = TBC_SetTweek(TBC, tweak, sizeof(tweak)); CKS4ERR;
		}
		
		uint64_t requestBufferSpace = requestBufferMallocSize - requestBufferOffset;
		
		if ((requestBufferSpace >= keyLength) && hasReadHeader && (pendingSeek_ignore == nil))
		{
			// Decrypt directly into requester's buffer
			
			err = TBC_Decrypt(TBC, (inBuffer + bytesDecrypted), (requestBuffer + requestBufferOffset)); CKS4ERR;
			
			bytesDecrypted      += keyLength;
			decryptionOffset    += keyLength;
			requestBufferOffset += keyLength;
			cursorOffset        += keyLength;
		}
		else
		{
			// At least one of the following is true:
			// - not enough space in the requestBuffer for the entire chunk
			// - we haven't read & processed the header yet
			// - we have to ignore some of the decrypted bytes (due to previous seek request)
			//
			// So we decrypt into overflow buffer first.
			// And then we can later copy into the request buffer.
			
			NSAssert((sizeof(overflowBuffer) - overflowBufferLength) >= keyLength,
			         @"Unexpected state: overflowBuffer doesn't have space");
			
			err = TBC_Decrypt(TBC, (inBuffer + bytesDecrypted), (overflowBuffer + overflowBufferLength)); CKS4ERR;
			
			bytesDecrypted       += keyLength;
			decryptionOffset     += keyLength;
			overflowBufferLength += keyLength;
			
			// The first few bytes of the file are reserved for the cache file header.
			// We need to remove this from the stream (as it's internal data).
			
			if (!hasReadHeader)
			{
				NSAssert(sizeof(ZDCCacheFileHeader) <= kZDCNode_TweakBlockSizeInBytes, @"This code won't work.");
				
				uint8_t *p = overflowBuffer + overflowBufferOffset;
                
				uint64_t magic = S4_Load64(&p);
				if (magic != kZDCCacheFileContextMagic)
				{
					NSString *desc = @"File doesn't appear to be a cache File (header magic incorrect)";
					
					streamError = [self errorWithDescription:desc];
					streamStatus = NSStreamStatusError;
					[self sendEvent:NSStreamEventErrorOccurred];
					
					return -1;
				}
				
				fileSize = S4_Load64(&p);
				
				uint8_t reserved[kZDCCacheFileReservedBytes];
				S4_LoadArray(reserved, sizeof(reserved), &p, NULL);
				
				overflowBufferOffset += sizeof(ZDCCacheFileHeader);
				cursorOffset         += sizeof(ZDCCacheFileHeader);
				hasReadHeader = YES;
				
				if (pendingSeek_offset != nil)
				{
					// We need to jump to elsewhere in the file.
					
					[self seekToPendingOffset];
					return [self read:requestBuffer maxLength:requestBufferMallocSize];
				}
			}
			
			// Check to see if we need to ignore any bytes (due to seek)
			
			if (pendingSeek_ignore != nil)
			{
				uint64_t pendingIgnore = [pendingSeek_ignore unsignedLongLongValue];
				uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
				
				uint64_t bytesToIgnore = MIN(pendingIgnore, overflowSize);
				
				overflowBufferOffset += bytesToIgnore;
				cursorOffset         += bytesToIgnore;
				
				if (bytesToIgnore == pendingIgnore)
					pendingSeek_ignore = nil;
				else
					pendingSeek_ignore = @(pendingIgnore - bytesToIgnore);
			}
			
			// Copy bytes into the requestBuffer (if possible)
			
			if (requestBufferSpace > 0)
			{
				uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
				
				uint64_t bytesToCopy = MIN(requestBufferSpace, overflowSize);
				
				memcpy((requestBuffer + requestBufferOffset), (overflowBuffer + overflowBufferOffset), (size_t)bytesToCopy);
				
				requestBufferOffset  += bytesToCopy;
				overflowBufferOffset += bytesToCopy;
				cursorOffset         += bytesToCopy;
			}
			
			// Did we drain the overflowBuffer ?
			
			if (overflowBufferOffset >= overflowBufferLength)
			{
				overflowBufferOffset = 0;
				overflowBufferLength = 0;
			}
		}
	}
	
	// Check for leftover bytes in the 'inBuffer' that we couldn't decrypt.
	// For example:
	//
	// The inputStream gave us 69 bytes.
	// We decrypted 64 bytes.
	// So we have 5 bytes leftover.
	//
	// We move any leftover bytes to the beginning of 'inBuffer',
	// and update 'inBufferLength' accordingly.
	
	if (bytesDecrypted > 0)
	{
		NSAssert(inBufferLength >= bytesDecrypted, @"Logic error");
		
		uint64_t leftover = inBufferLength - bytesDecrypted;
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
	
	// Check for padding.
	//
	// Since we do all encryption/decryption in keyLength size chunks (generally 64 bytes),
	// there may be padding at the very end.
	//
	// We know the fileSize because it's encoded in the first 8 bytes of the file.
	// And thus we can detect padding once we've exceeded fileSize bytes.
	
	BOOL foundPadding = NO;
	
	uint64_t cleartextOffset = 0;
	if (hasReadHeader) {
		cleartextOffset = cursorOffset - sizeof(ZDCCacheFileHeader);
	}
	
	if (cleartextOffset > fileSize)
	{
		foundPadding = YES;
		size_t totalPadding = (size_t)(cleartextOffset - fileSize);
		
		if (requestBufferOffset >= totalPadding) {
			requestBufferOffset -= totalPadding;
		}
		else {
			requestBufferOffset = 0;
		}
	}
	
	// Check for EOF
	
	if (requestBufferOffset == 0) // Can't transition to EOF until we return zero to reader !
	{
		BOOL reachedEOF = NO;
		BOOL unexpectedEOF = NO;
		
		if (foundPadding)
		{
			reachedEOF = YES;
		}
		else if ((bytesRead == 0) && ((overflowBufferLength - overflowBufferOffset) == 0))
		{
			reachedEOF = YES;
			unexpectedEOF = cleartextOffset < fileSize;
		}
		
		if (unexpectedEOF)
		{
			// EOF - premature/unexpected
			
			NSString *msg = @"CacheFile ended prematurely";
			NSError *error = [self errorWithDescription:msg code:ZDCStreamUnexpectedFileSize];
			
			if (streamStatus < NSStreamStatusError)
			{
				streamError = error;
				streamStatus = NSStreamStatusError;
				[self sendEvent:NSStreamEventErrorOccurred];
			}
			
			// Don't return 0 as it signifies standard EOF, and this is really an error.
			return -1;
		}
		else if (reachedEOF)
		{
			// EOF - good/expected
			
			if (streamStatus < NSStreamStatusAtEnd)
			{
				streamStatus = NSStreamStatusAtEnd;
				[self stream:self handleEvent:NSStreamEventEndEncountered];
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

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
	// Not appropriate for this kind of stream; return NO.
	return NO;
}

- (BOOL)hasBytesAvailable
{
	if (streamStatus >= NSStreamStatusOpen && streamStatus < NSStreamStatusAtEnd)
		return YES;
	else
		return NO;
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

@end
