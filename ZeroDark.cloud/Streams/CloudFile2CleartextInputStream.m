#import "CloudFile2CleartextInputStream.h"

#import "ZDCConstants.h"
#import "ZDCLogging.h"

#import "NSError+S4.h"

#import <S4Crypto/S4Crypto.h>

#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

/* extern */ NSString *const ZDCStreamCloudFileSection = @"ZDCStreamCloudFileSection";


@interface ZDCInputStream (Private)

- (NSError *)errorWithDescription:(NSString *)description;
+ (NSError *)errorWithDescription:(NSString *)description;
- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;
+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;

- (void)sendEvent:(NSStreamEvent)streamEvent;
- (void)notifyDelegateOfEvent:(NSStreamEvent)streamEvent;

@end

#define CKS4ERR  if ((err != kS4Err_NoErr)) { goto done; }


@implementation CloudFile2CleartextInputStream
{
	NSURL *                cloudFileURL;
	NSData *               cloudFileData;
	NSData *               encryptionKey;
	
	ZDCCloudFileHeader     cloudFileHeader;
	ZDCCloudFileSection    cloudFileSection;
	NSNumber *             cloudFileSection_explicitlySet;
	
	uint8_t *              inBuffer;
	uint64_t               inBufferMallocSize;
	uint64_t               inBufferLength;
	
	uint8_t                overflowBuffer[kZDCNode_TweakBlockSizeInBytes];
	uint64_t               overflowBufferOffset;
	uint64_t               overflowBufferLength;
	
	TBC_ContextRef         TBC;
	
	BOOL                   hasReadHeader;
	
	uint64_t               sectionBytesLength;
	uint64_t               sectionBytesOffset;
	uint64_t               totalBytesOutToReader;
	uint64_t               totalBytesDecrypted;
	
	NSNumber *             pendingSeek_offset;
	NSNumber *             pendingSeek_ignore;
	
	NSNumber *             pendingSeek_section;
}

@dynamic cleartextFileSize;
@dynamic cloudFileHeader;
@synthesize cloudFileSection = cloudFileSection;

/**
 * See header file for description.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile
{
	if (cryptoFile) {
		NSParameterAssert(cryptoFile.fileFormat == ZDCCryptoFileFormat_CloudFile);
	}
	
	self = [self initWithCloudFileURL: cryptoFile.fileURL
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
- (instancetype)initWithCloudFileURL:(NSURL *)inCloudFileURL
                       encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		cloudFileURL = inCloudFileURL;
		
		inputStream = [NSInputStream inputStreamWithURL:cloudFileURL];
		inputStream.delegate = nil;
		
		encryptionKey = [inEncryptionKey copy];
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCloudFileStream:(NSInputStream *)cloudFileStream
                          encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		inputStream = cloudFileStream;
		inputStream.delegate = self;
		
		encryptionKey = [inEncryptionKey copy];
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCloudFileData:(NSData *)inCloudFileData
                        encryptionKey:(NSData *)inEncryptionKey
{
	NSInputStream *inStream = [NSInputStream inputStreamWithData:inCloudFileData];
	
	self = [self initWithCloudFileStream: inStream
								  encryptionKey: inEncryptionKey];
	if (self)
	{
		cloudFileData = inCloudFileData;
	}
	return self;
}

- (void)dealloc
{
	ZDCLogAutoTrace();
	
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
	CloudFile2CleartextInputStream *copy = nil;
	
	if (cloudFileURL)
	{
		copy = [[[self class] alloc] initWithCloudFileURL:cloudFileURL encryptionKey:encryptionKey];
	}
	else if (cloudFileData)
	{
		copy = [[[self class] alloc] initWithCloudFileData:cloudFileData encryptionKey:encryptionKey];
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
			copy = [[[self class] alloc] initWithCloudFileStream:inputStreamCopy encryptionKey:encryptionKey];
		}
	}
	
	if (copy)
	{
		if (cloudFileSection_explicitlySet) {
			[self setProperty:cloudFileSection_explicitlySet forKey:ZDCStreamCloudFileSection];
		}
		
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

- (NSNumber *)cleartextFileSize
{
	return @(cloudFileHeader.dataSize);
}

- (ZDCCloudFileHeader)cloudFileHeader
{
	ZDCCloudFileHeader copy;
	memcpy(&copy, &cloudFileHeader, sizeof(ZDCCloudFileHeader));
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)seekToPendingOffset
{
	ZDCLogAutoTrace();
	
	NSAssert(hasReadHeader,       @"Seek request in bad state: !hasReadHeader");
	NSAssert(pendingSeek_section || pendingSeek_offset, @"Seek request in bad state: !pendingSeek_action");
	
	// Watch out for edge case:
	// Once a normal stream hits EOF, it still allows seeking, but won't allow any more reading.
	// The only way around this is to re-create the underlying stream.
	
	if (inputStream.streamStatus == NSStreamStatusAtEnd)
	{
		{ // limiting scope
			
			NSInputStream *newInputStream = nil;
			
			if (cloudFileURL)
			{
				newInputStream = [NSInputStream inputStreamWithURL:cloudFileURL];
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
	
	// Calculate requestedOffset
	
	ZDCCloudFileSection requestedSection = cloudFileSection;
	NSRange requestedSectionRange;
	uint64_t requestedCloudFileOffset = 0;
	
	if (pendingSeek_section != nil)
	{
		// Jump to a specific section
		
		requestedSection = (ZDCCloudFileSection)pendingSeek_section.integerValue;
		requestedSectionRange = [self rangeForSection:requestedSection];
		
		requestedCloudFileOffset = requestedSectionRange.location;
	}
	
	if (pendingSeek_offset != nil)
	{
		requestedSectionRange = [self rangeForSection:requestedSection];
		
		requestedCloudFileOffset =
		  requestedSectionRange.location
		+ MIN(requestedSectionRange.length, pendingSeek_offset.unsignedIntegerValue);
	}
	
	uint64_t nearestBlockIndex = (uint64_t)(requestedCloudFileOffset / kZDCNode_TweakBlockSizeInBytes);
	uint64_t nearestBlockOffset = nearestBlockIndex * kZDCNode_TweakBlockSizeInBytes;
	
	if (![inputStream setProperty:@(nearestBlockOffset) forKey:NSStreamFileCurrentOffsetKey])
	{
		NSString *desc = @"Unable to seek to desired offset.";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	// We may not have been able to jump to the correct section,
	// since we had to round down to the nearest block.
	
	ZDCCloudFileSection actualSection;
	NSRange actualSectionRange;
	[self getSection:&actualSection range:&actualSectionRange forLocation:nearestBlockOffset];
	
	// Reset all state variables to reflect the new situation
	
	cloudFileSection = actualSection;
	
	inBufferLength = 0;
	
	overflowBufferOffset = 0;
	overflowBufferLength = 0;
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	sectionBytesLength = actualSectionRange.length;
	sectionBytesOffset = nearestBlockOffset - actualSectionRange.location;
	
	totalBytesOutToReader = actualSectionRange.location + sectionBytesOffset;
	totalBytesDecrypted = totalBytesOutToReader;
	
	pendingSeek_offset = nil;
	
	uint64_t ignore = requestedCloudFileOffset - nearestBlockOffset;
	if (ignore > 0) {
		pendingSeek_ignore = @(ignore);
	}
	else {
		// always reset in case of multiple SEEK requests
		pendingSeek_ignore = nil;
	}
	
	pendingSeek_section = nil;
	
	// If we're not in the right section yet, read until we get there
	
	if (cloudFileSection < requestedSection)
	{
		uint8_t ignore[kZDCNode_TweakBlockSizeInBytes];
		do {
			NSInteger bytesRead = [self read:ignore maxLength:sizeof(ignore)];
			
			if (bytesRead < 0) {
				break;
			}
			
		} while(cloudFileSection < requestedSection);
	}
}

- (void)nextCloudFileSection
{
	if (cloudFileSection >= ZDCCloudFileSection_EOF)
	{
		sectionBytesOffset = 0;
		sectionBytesLength = 0;
		return;
	}
	
	BOOL done = NO;
	do {
	
		cloudFileSection++;
		sectionBytesOffset = 0;
		sectionBytesLength = [self rangeForSection:cloudFileSection].length;
		
		// The metadataSize and/or thumbnailSize may be zero.
		
		done = (sectionBytesLength > 0) || (cloudFileSection >= ZDCCloudFileSection_EOF);
		
	} while (!done);
}

- (NSRange)rangeForSection:(ZDCCloudFileSection)section
{
	uint64_t offset = 0;
	uint64_t length = 0;
	
	if (section >= ZDCCloudFileSection_Header)
	{
		length = sizeof(ZDCCloudFileHeader);
	}
	if (section >= ZDCCloudFileSection_Metadata)
	{
		offset += length;
		length = cloudFileHeader.metadataSize;
	}
	if (section >= ZDCCloudFileSection_Thumbnail)
	{
		offset += length;
		length = cloudFileHeader.thumbnailSize;
	}
	if (section >= ZDCCloudFileSection_Data)
	{
		offset += length;
		length = cloudFileHeader.dataSize;
	}
	if (section >= ZDCCloudFileSection_EOF)
	{
		offset += length;
		length = 0;
	}
	
	return NSMakeRange((NSUInteger)offset, (NSUInteger)length);
}

- (void)getSection:(ZDCCloudFileSection *)sectionPtr range:(NSRange *)rangePtr forLocation:(uint64_t)location
{
	ZDCCloudFileSection section = ZDCCloudFileSection_Header;
	NSRange range = [self rangeForSection:section];
	
	while ((range.length == 0 || location >= NSMaxRange(range)) && section != ZDCCloudFileSection_EOF)
	{
		section++;
		range = [self rangeForSection:section];
	}
	
	if (sectionPtr) *sectionPtr = section;
	if (rangePtr) *rangePtr = range;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSStream subclass overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)open
{
	ZDCLogAutoTrace();
	
	if (streamStatus != NSStreamStatusNotOpen) {
		return;
	}
	
	// check for valid encyptionKey
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
	
	cloudFileSection = ZDCCloudFileSection_Header;
	sectionBytesOffset = 0;
	sectionBytesLength = sizeof(ZDCCloudFileHeader);
	
	NSAssert(sectionBytesLength <= 64, @"Programmer doesn't understand byte alignment");
	
	streamError = nil;
	streamStatus = NSStreamStatusOpen;
	[self sendEvent:NSStreamEventOpenCompleted];
	
	// Now we read the first block of the stream.
	// This will allow us to read the header.
	//
	// Note: The read:maxLength: method explicitly supports being called with a zero maxLength
	//       parameter if hasReadFileHeader is false. (i.e. this situation here)
	
	uint8_t ignore[0];
	[self read:ignore maxLength:0];
}

- (void)close
{
	ZDCLogAutoTrace();
	
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
	
	sectionBytesLength    = 0;
	sectionBytesOffset    = 0;
	totalBytesOutToReader = 0;
	totalBytesDecrypted   = 0;
	
	pendingSeek_offset = nil;
	pendingSeek_ignore = nil;
	pendingSeek_section = nil;
	
	[inputStream close];
	streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(NSString *)key
{
	if ([key isEqualToString:ZDCStreamCloudFileSection])
	{
		if (pendingSeek_section != nil)
		{
			return pendingSeek_section;
		}
		else
		{
			return @(cloudFileSection);
		}
	}
	
	if ([key isEqualToString:NSStreamFileCurrentOffsetKey])
	{
		if (pendingSeek_offset || pendingSeek_ignore)
		{
			uint64_t offset = (pendingSeek_offset != nil) ? pendingSeek_offset.unsignedLongLongValue : totalBytesOutToReader;
			uint64_t ignore = (pendingSeek_ignore != nil) ? pendingSeek_ignore.unsignedLongLongValue : 0;
			
			return @(offset + ignore);
		}
		else
		{
			return @(totalBytesOutToReader);
		}
	}
	
	return [super propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key
{
	if ([key isEqualToString:ZDCStreamCloudFileSection])
	{
		if (![property isKindOfClass:[NSNumber class]]) {
			return NO;
		}
		
		NSInteger requestedSection = [(NSNumber *)property integerValue];
		if (requestedSection < ZDCCloudFileSection_Header ||
			 requestedSection > ZDCCloudFileSection_EOF)
		{
			return NO;
		}
		
		if (requestedSection == cloudFileSection)
		{
			// Ignore spurious request
			return YES;
		}
		
		pendingSeek_section = (NSNumber *)property;
		pendingSeek_offset  = nil; // seeking to section implicitly cancels seeking to offset
		pendingSeek_ignore  = nil;
		
		if (streamStatus == NSStreamStatusOpen) {
			[self seekToPendingOffset];
		}
		
		cloudFileSection_explicitlySet = property;
		return YES;
	}
	
	if ([key isEqualToString:NSStreamFileCurrentOffsetKey])
	{
		if (![property isKindOfClass:[NSNumber class]]) {
			return NO;
		}
		
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
	ZDCLogAutoTrace();
	
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
	
	BOOL sectionComplete = (sectionBytesOffset >= sectionBytesLength);
	
	// Drain the overflowBuffer first (if available)
	
	if ((overflowBufferLength - overflowBufferOffset) > 0)
	{
		if (pendingSeek_ignore != nil)
		{
			uint64_t pendingIgnore = [pendingSeek_ignore unsignedLongLongValue];
			
			uint64_t leftInSection = sectionBytesLength - sectionBytesOffset;
			uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
			
			uint64_t bytesToIgnore = MIN(leftInSection, MIN(pendingIgnore, overflowSize));
			
			overflowBufferOffset  += bytesToIgnore;
			sectionBytesOffset    += bytesToIgnore;
			totalBytesOutToReader += bytesToIgnore;
			
			if (bytesToIgnore == pendingIgnore)
				pendingSeek_ignore = nil;
			else
				pendingSeek_ignore = @(pendingIgnore - bytesToIgnore);
		}
		
		{ // scope limiting
			
			uint64_t leftInSection = sectionBytesLength - sectionBytesOffset;
			uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
			
			uint64_t bytesToCopy = MIN(requestBufferMallocSize, MIN(leftInSection, overflowSize));
			
			memcpy((requestBuffer + requestBufferOffset), (overflowBuffer + overflowBufferOffset), (size_t)bytesToCopy);
			
			requestBufferOffset   += bytesToCopy;
			overflowBufferOffset  += bytesToCopy;
			sectionBytesOffset    += bytesToCopy;
			totalBytesOutToReader += bytesToCopy;
		}
		
		if (overflowBufferOffset >= overflowBufferLength)
		{
			overflowBufferOffset = 0;
			overflowBufferLength = 0;
		}
		
		if (sectionBytesOffset >= sectionBytesLength)
		{
			sectionComplete = YES;
		}
		
		// Don't return here !
		// The overflowBuffer may contain padding that we still need to strip.
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
	
	uint64_t bytesToRead = 0;
	uint64_t minBytesToRead = 0;
	
	{ // scope limiting
		
		// Calculate how much is left in the current section.
		// And then round to a multiple of blockSize.
		
		uint64_t leftInSection = sectionBytesLength - sectionBytesOffset;
		
		// Calculate out how much space is left in the requestBuffer.
		
		uint64_t requestBufferSpace = requestBufferMallocSize - requestBufferOffset;
		
		// Use the smaller of the 2 values.
		
		bytesToRead = MIN(leftInSection, requestBufferSpace);
		minBytesToRead = (bytesToRead == 0 ? 0 : 1);
		
		if (!hasReadHeader)
		{
			// We need to read the entire header.
			// We DO (YES) output the header to the reader.
			
			if (bytesToRead < leftInSection) {
				bytesToRead = leftInSection;
			}
			if (minBytesToRead < leftInSection) {
				minBytesToRead = leftInSection;
			}
		}
		if (pendingSeek_ignore != nil)
		{
			// We don't output ignored bytes to the reader.
			NSUInteger increment = [pendingSeek_ignore unsignedIntegerValue];
			
			bytesToRead    += increment;
			minBytesToRead += increment;
		}
		
		// We have to ensure that we don't attempt to read too much.
		// This can happen when sections and offsets are involved.
		//
		// For example, the user is trying to seek to an offset within data.
		// But we were forced to jump somewhere towards the end of the thumbnail section.
		//
		// So, although the pendingSeek_ignore is indicating we're to throw away a bunch of bytes,
		// we're going to be forced to to end our output at the section break.
		
		if (bytesToRead > leftInSection)
			bytesToRead = leftInSection;
		
		if (minBytesToRead > leftInSection)
			minBytesToRead = leftInSection;
		
		// Round to proper blockSize multiplier
		
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
	
	if ((bytesToRead > 0) && (cloudFileSection != ZDCCloudFileSection_EOF) && !sectionComplete)
	{
		BOOL readEOF = NO;
		BOOL readPartial = NO;
		
		while ((bytesRead < bytesToRead) && !readEOF && !readPartial)
		{
			uint64_t loopBytesToRead = (bytesToRead - bytesRead);
			NSInteger loopBytesRead = [inputStream read:(inBuffer + inBufferLength) maxLength:(NSUInteger)loopBytesToRead];
			
			if (loopBytesRead < 0)
			{
				streamError = [inputStream streamError];
				streamStatus = NSStreamStatusError;
				[self sendEvent:NSStreamEventErrorOccurred];
				
				if (requestBufferOffset > 0)
					return requestBufferOffset;
				else
					return loopBytesRead;
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
			needsSetTweak = ((totalBytesDecrypted % kZDCNode_TweakBlockSizeInBytes) == 0);
		}
		
		if (needsSetTweak)
		{
			uint64_t tweakBlockNum = (uint64_t)(totalBytesDecrypted / kZDCNode_TweakBlockSizeInBytes);
			uint64_t tweak[2] = {tweakBlockNum, 0};
			
			err = TBC_SetTweek(TBC, tweak, sizeof(tweak)); CKS4ERR;
		}
		
		uint64_t leftInSection = sectionBytesLength - sectionBytesOffset;
		uint64_t requestBufferSpace = requestBufferMallocSize - requestBufferOffset;
		
		if ((leftInSection >= keyLength) && (requestBufferSpace >= keyLength)
		 && hasReadHeader && (pendingSeek_ignore == nil) && !sectionComplete)
		{
			// Decrypt directly into requester's buffer
			
			err = TBC_Decrypt(TBC, (inBuffer + bytesDecrypted), (requestBuffer + requestBufferOffset)); CKS4ERR;
			
			bytesDecrypted        += keyLength;
			totalBytesDecrypted   += keyLength;
			requestBufferOffset   += keyLength;
			sectionBytesOffset    += keyLength;
			totalBytesOutToReader += keyLength;
		}
		else
		{
			// At least one of the following is true:
			// - there is more data being decrypted than is left in section
			// - not enough space in the requestBuffer for the entire chunk
			// - we haven't read the header info yet
			// - we have to ignore some of the decrypted bytes (due to previous seek request)
			// - we completed the section, so all newly decrypted data needs to be saved next section
			//
			// So we decrypt into overflow buffer first.
			// And then we can later copy into the request buffer.
			
			NSAssert((sizeof(overflowBuffer) - overflowBufferLength) >= keyLength,
			         @"Unexpected state: overflowBuffer doesn't have space");
			
			err = TBC_Decrypt(TBC, (inBuffer + bytesDecrypted), (overflowBuffer + overflowBufferLength)); CKS4ERR;
			
			bytesDecrypted       += keyLength;
			totalBytesDecrypted  += keyLength;
			overflowBufferLength += keyLength;
			
			// The first 64 bytes of the file are reserved for the header.
			// We need to read this info from the stream.
			
			if (!hasReadHeader)
			{
				uint8_t *p = overflowBuffer + overflowBufferOffset;
				
				cloudFileHeader.magic = S4_Load64(&p);
				if (cloudFileHeader.magic != kZDCCloudFileContextMagic)
				{
					NSString *desc = @"File signature incorrect.";
					
					streamError = [self errorWithDescription:desc];
					streamStatus = NSStreamStatusError;
					[self sendEvent:NSStreamEventErrorOccurred];
					
					return -1;
				}
				
				cloudFileHeader.metadataSize  = S4_Load64(&p);
				cloudFileHeader.thumbnailSize = S4_Load64(&p);
				cloudFileHeader.dataSize      = S4_Load64(&p);
				
				cloudFileHeader.thumbnailxxHash64 = S4_Load64(&p);
				
				cloudFileHeader.version = S4_Load8(&p);
				
				hasReadHeader = YES;
				
				// Note: We do NOT modify overflowBufferOffset here.
				// This is because we're going to send the header to the reader.
				// The reader is in section ZDCCloudFileSection_Header, and so expects to read the header.
				
				if (pendingSeek_section || pendingSeek_offset)
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
				
				uint64_t bytesToIgnore = MIN(leftInSection, MIN(pendingIgnore, overflowSize));
				
				overflowBufferOffset  += bytesToIgnore;
				sectionBytesOffset    += bytesToIgnore;
				totalBytesOutToReader += bytesToIgnore;
				
				leftInSection         -= bytesToIgnore; // update for next `if` statement
				
				if (bytesToIgnore == pendingIgnore)
					pendingSeek_ignore = nil;
				else
					pendingSeek_ignore = @(pendingIgnore - bytesToIgnore);
			}
			
			// Copy bytes into the requestBuffer (if possible)
			
			if ((requestBufferSpace > 0) && (leftInSection > 0) && !sectionComplete)
			{
				uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
				
				uint64_t bytesToCopy = MIN(leftInSection, MIN(requestBufferSpace, overflowSize));
				
				memcpy(/* dst: */(requestBuffer + requestBufferOffset),
				       /* src: */(overflowBuffer + overflowBufferOffset),
				       /* num: */(size_t)bytesToCopy);
				
				requestBufferOffset   += bytesToCopy;
				overflowBufferOffset  += bytesToCopy;
				sectionBytesOffset    += bytesToCopy;
				totalBytesOutToReader += bytesToCopy;
			}
			
			// Did we drain the overflowBuffer ?
			
			if (overflowBufferOffset >= overflowBufferLength)
			{
				overflowBufferOffset = 0;
				overflowBufferLength = 0;
			}
		}
		
		// Did we finish the section ?
		
		if (sectionBytesOffset >= sectionBytesLength)
		{
			sectionComplete = YES;
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
	
	// Note: There's no need to check for padding.
	//
	// We only copy bytes into the requestBuffer if we haven't exceeded sectionLength.
	// And we don't copy bytes after the data section.
	//
	// In other words, padding bytes are never copied into the requestBuffer in the first place.
	
	// Jump to the next section if needed.
	
	if (sectionComplete && (requestBufferOffset == 0))
	{
		[self nextCloudFileSection];
	}
	
	// Check for EOF
	
	if (requestBufferOffset == 0) // Can't transition to EOF until we return zero to reader !
	{
		if (cloudFileSection == ZDCCloudFileSection_EOF)
		{
			// EOF - good/expected
			
			if (streamStatus < NSStreamStatusAtEnd)
			{
				streamStatus = NSStreamStatusAtEnd;
				[self sendEvent:NSStreamEventEndEncountered];
			}
		}
		else if ((bytesRead == 0) &&
		         ((overflowBufferLength - overflowBufferOffset) == 0) &&
		         !sectionComplete)
		{
			// EOF - premature/unexpected
			
			NSString *msg = @"CloudFile ended prematurely";
			NSError *error = [self errorWithDescription:msg code:ZDCStreamUnexpectedFileSize];
			
			if (streamStatus < NSStreamStatusError)
			{
				streamError = error;
				streamStatus = NSStreamStatusError;
				[self sendEvent:NSStreamEventErrorOccurred];
				
				// Don't return 0 as it signifies standard EOF, and this is really an error.
				return -1;
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
				ZDCLogVerbose(@"Ignoring inputStream.NSStreamEventOpenCompleted: We handle this ourself");
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
				ZDCLogVerbose(@"Ignoring inputStream.NSStreamEventEndEncountered: We handle this ourself");
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
#pragma mark Decrypt Metadata
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (BOOL)decryptCloudFileStream:(CloudFile2CleartextInputStream *)inputStream
                        header:(ZDCCloudFileHeader *)headerPtr
                   rawMetadata:(NSData **)metadataPtr
                  rawThumbnail:(NSData **)thumbnailPtr
                         error:(NSError **)errorPtr
{
	BOOL result = NO;
	NSError *error = nil;
	
	BOOL needsReadThumbnail = (thumbnailPtr != NULL);
	BOOL needsReadMetadata  = (metadataPtr  != NULL) || needsReadThumbnail;
	BOOL needsReadHeader    = (headerPtr    != NULL) || needsReadMetadata;
	
	ZDCCloudFileHeader header;
	NSData *metadata = nil;
	NSData *thumbnail = nil;
	
	uint8_t *buffer = NULL;
	uint64_t bufferMallocSize = 0;
	
	bzero(&header, sizeof(header));
	
	if (inputStream == nil) // potential infinite loop ahead without this check
	{
		error = [self errorWithDescription:@"Invalid parameter: cloudFileStream is nil"];
		goto done;
	}
	
	[inputStream open];
	
	error = [inputStream streamError];
	if (error) {
		goto done;
	}
	
	if (needsReadHeader)
	{
		uint8_t ignore[kZDCNode_TweakBlockSizeInBytes];
		
		while (inputStream.cloudFileSection == ZDCCloudFileSection_Header)
		{
			NSInteger bytesRead = [inputStream read:ignore maxLength:sizeof(ignore)];
			if (bytesRead < 0)
			{
				error = [inputStream streamError];
				goto done;
			}
			else if (bytesRead == 0)
			{
				break;
			}
		}
		
		header = inputStream.cloudFileHeader;
	}
	
	if (needsReadMetadata || needsReadThumbnail)
	{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wambiguous-macro"
		
		uint64_t maxSize = MAX(header.metadataSize, header.thumbnailSize);
		uint64_t multipler = (maxSize / kZDCNode_TweakBlockSizeInBytes) + 1;
		
	#pragma clang diagnostic pop
		
		bufferMallocSize = multipler * kZDCNode_TweakBlockSizeInBytes;
		buffer = malloc((size_t)bufferMallocSize);
	}
	
	if (needsReadMetadata)
	{
		uint64_t bufferLength = 0;
		
		while (inputStream.cloudFileSection == ZDCCloudFileSection_Metadata)
		{
			// This shouldn't be needed.
			// But we'd rather prevent buffer overflow.
			//
			uint64_t bufferSpace = bufferMallocSize - bufferLength;
			if (bufferSpace == 0) {
				
				bufferMallocSize += kZDCNode_TweakBlockSizeInBytes;
				buffer = reallocf(buffer, (size_t)bufferMallocSize);
			}
			
			NSInteger bytesRead = [inputStream read:(buffer + bufferLength)
			                              maxLength:(NSUInteger)(bufferMallocSize - bufferLength)];
			if (bytesRead < 0)
			{
				error = [inputStream streamError];
				goto done;
			}
			else if (bytesRead == 0)
			{
				break;
			}
			else
			{
				bufferLength += bytesRead;
			}
		}
		
		if (bufferLength > 0)
		{
			metadata = [NSData dataWithBytes:buffer length:(NSUInteger)bufferLength];
		}
	}
	
	if (needsReadThumbnail)
	{
		uint64_t bufferLength = 0;
		
		while (inputStream.cloudFileSection == ZDCCloudFileSection_Thumbnail)
		{
			// This shouldn't be needed.
			// But we'd rather prevent buffer overflow.
			//
			uint64_t bufferSpace = bufferMallocSize - bufferLength;
			if (bufferSpace == 0) {
				
				bufferMallocSize += kZDCNode_TweakBlockSizeInBytes;
				buffer = reallocf(buffer, (size_t)bufferMallocSize);
			}
			
			NSInteger bytesRead = [inputStream read:(buffer + bufferLength)
			                              maxLength:(NSUInteger)(bufferMallocSize - bufferLength)];
			if (bytesRead < 0)
			{
				error = [inputStream streamError];
				goto done;
			}
			else if (bytesRead == 0)
			{
				break;
			}
			else
			{
				bufferLength += bytesRead;
			}
		}
		
		if (bufferLength > 0)
		{
			thumbnail = [NSData dataWithBytes:buffer length:(NSUInteger)bufferLength];
		}
	}
	
	result = YES;
	
done:
	
	[inputStream close];
	
	if (buffer) {
		ZERO(buffer, bufferMallocSize);
		free(buffer);
	}
	
	if (headerPtr) *headerPtr = header;
	if (metadataPtr) *metadataPtr = metadata;
	if (thumbnailPtr) *thumbnailPtr = thumbnail;
	if (errorPtr) *errorPtr = error;
	
	return result;
}

/**
 * See header for documentation
 */
+ (BOOL)decryptCloudFileData:(NSData *)cloudFileData
           withEncryptionKey:(NSData *)encryptionKey
                      header:(ZDCCloudFileHeader *)headerPtr
                 rawMetadata:(NSData **)metadataPtr
                rawThumbnail:(NSData **)thumbnailPtr
                       error:(NSError **)errorPtr
{
	if (cloudFileData.length == 0)
	{
		NSError *error = [self errorWithDescription:@"Zero length cloudFileData cannot be decrypted"];
		
		ZDCCloudFileHeader headerInfo;
		bzero(&headerInfo, sizeof(headerInfo));
		
		if (headerPtr) *headerPtr = headerInfo;
		if (metadataPtr) *metadataPtr = nil;
		if (thumbnailPtr) *thumbnailPtr = nil;;
		if (errorPtr) *errorPtr = error;
		
		return NO;
	}
	
	CloudFile2CleartextInputStream *inputStream =
	  [[CloudFile2CleartextInputStream alloc] initWithCloudFileData: cloudFileData
	                                                  encryptionKey: encryptionKey];
	
	return [self decryptCloudFileStream: inputStream
	                             header: headerPtr
	                        rawMetadata: metadataPtr
	                       rawThumbnail: thumbnailPtr
	                              error: errorPtr];
}

/**
 * See header for documentation
 */
+ (BOOL)decryptCloudFileURL:(NSURL *)cloudFileURL
          withEncryptionKey:(NSData *)encryptionKey
                     header:(ZDCCloudFileHeader *)headerPtr
                rawMetadata:(NSData **)metadataPtr
               rawThumbnail:(NSData **)thumbnailPtr
                      error:(NSError **)errorPtr
{
	CloudFile2CleartextInputStream *inputStream =
	  [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL: cloudFileURL
	                                                 encryptionKey: encryptionKey];
	
	return [self decryptCloudFileStream: inputStream
	                             header: headerPtr
	                        rawMetadata: metadataPtr
	                       rawThumbnail: thumbnailPtr
	                              error: errorPtr];
}

/**
 * See header file for description.
 */
+ (NSData *)decryptCloudFileBlocks:(NSData *)cloudFileBlocks
                    withByteOffset:(uint64_t)byteOffset
                     encryptionKey:(NSData *)encryptionKey
                             error:(NSError **)errorPtr
{
	NSError *error = nil;
	
	S4Err err = kS4Err_NoErr;
	TBC_ContextRef TBC = kInvalidTBC_ContextRef;
	
	const Cipher_Algorithm algo = [self cipherAlgorithm:encryptionKey];
	const NSUInteger keyLength = encryptionKey.length;
	
	const void *const inBuffer = cloudFileBlocks.bytes;
	const NSUInteger inBufferLength = cloudFileBlocks.length;
	
	void *outBuffer = NULL;
	const uint64_t outBufferMallocSize = inBufferLength;
	
	NSUInteger inOutBufferOffset = 0; // for both inBuffer & outBuffer (they move together)
	
	void *decryptBuffer = NULL;
	const uint64_t decryptBufferMallocSize = keyLength;
	
	if (cloudFileBlocks.length == 0)
	{
		error = [self errorWithDescription:@"Zero length cloudFileData cannot be decrypted"];
		goto done;
	}
	
	if (algo == kCipher_Algorithm_Invalid)
	{
		error = [self errorWithDescription:@"Invalid encryptionKey: no matching cipher algorithm"];
		goto done;
	}
	
	if ((cloudFileBlocks.length % keyLength) != 0)
	{
		error = [self errorWithDescription:@"cloudFileBlocks.length must be a multiple of encryptionKey.length"];
		goto done;
	}
	
	if ((byteOffset % kZDCNode_TweakBlockSizeInBytes) != 0)
	{
		error = [self errorWithDescription:@"byteOffset must be a multiple of kZDCNode_TweakBlockSizeInBytes"];
		goto done;
	}
	
	decryptBuffer = malloc((size_t)decryptBufferMallocSize);
	outBuffer = malloc((size_t)outBufferMallocSize);
	
	err = TBC_Init(algo, encryptionKey.bytes, encryptionKey.length, &TBC); CKS4ERR;
	
	do {
		
		BOOL needsSetTweak = NO;
		if (inOutBufferOffset == 0)
		{
			needsSetTweak = YES;
		}
		else
		{
			needsSetTweak = (((byteOffset + inOutBufferOffset) % kZDCNode_TweakBlockSizeInBytes) == 0);
		}
		
		if (needsSetTweak)
		{
			uint64_t tweakBlockNum = (uint64_t)((byteOffset + inOutBufferOffset) / kZDCNode_TweakBlockSizeInBytes);
			uint64_t tweak[2] = {tweakBlockNum, 0};
			
			err = TBC_SetTweek(TBC, tweak, sizeof(tweak)); CKS4ERR;
		}
	
		err = TBC_Decrypt(TBC, (inBuffer + inOutBufferOffset), decryptBuffer); CKS4ERR;
	
		memcpy(outBuffer + inOutBufferOffset, decryptBuffer, keyLength);
		
		inOutBufferOffset += keyLength;
		
	} while (inOutBufferOffset < inBufferLength);
	
done:
	
	if (decryptBuffer) {
		ZERO(decryptBuffer, decryptBufferMallocSize);
		free(decryptBuffer);
	}
	
	if (err != kS4Err_NoErr) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	if (errorPtr) *errorPtr = error;
	if (error)
	{
		if (outBuffer) {
			ZERO(outBuffer, outBufferMallocSize);
			free(outBuffer);
		}
		return nil;
	}
	else
	{
		return [NSData dataWithBytesNoCopy:outBuffer length:(NSUInteger)outBufferMallocSize freeWhenDone:YES];
	}
}

@end
