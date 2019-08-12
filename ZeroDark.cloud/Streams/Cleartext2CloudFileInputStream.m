#import "Cleartext2CloudFileInputStream.h"

#import "CacheFile2CleartextInputStream.h"
#import "ZDCConstants.h"
#import "ZDCCloudFileHeader.h"
#import "ZDCInterruptingInputStream.h"
#import "ZDCLogging.h"
#import "ZDCNode.h"

#import "NSData+S4.h"
#import "NSError+S4.h"
#import "NSError+POSIX.h"

#import <CoreFoundation/CoreFoundation.h>
#import <S4Crypto/S4Crypto.h>

#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@interface ZDCInputStream (Private)

- (NSError *)errorWithDescription:(NSString *)description;
+ (NSError *)errorWithDescription:(NSString *)description;
- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;
+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;

- (void)sendEvent:(NSStreamEvent)streamEvent;
- (void)notifyDelegateOfEvent:(NSStreamEvent)streamEvent;

@end

#define CKS4ERR  if ((err != kS4Err_NoErr)) { goto done; }


typedef NS_ENUM(NSInteger, ZDCCloudFileEncryptState) {
	ZDCCloudFileEncryptState_Init       = 0,
	ZDCCloudFileEncryptState_Open,
	ZDCCloudFileEncryptState_Metadata,
	ZDCCloudFileEncryptState_Thumbnail,
	ZDCCloudFileEncryptState_Data,
	ZDCCloudFileEncryptState_Pad,
	ZDCCloudFileEncryptState_Done,
};

@implementation Cleartext2CloudFileInputStream
{
	// Variables explanation:
	//
	// We place cleartext into the `inBuffer`.
	// This includes the unencrypted header, unencrypted metadata, unencrypted thumbnail,
	// cleartext from the underlying inputStream, and also the padding.
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
	
	NSData *                 encryptionKey;
	
	NSData *                 metaData;
	NSData *                 thumbData;
	
	uint8_t *                inBuffer;
	NSUInteger               inBufferMallocSize;
	uint64_t                 inBufferLength;
	
	uint8_t                  overflowBuffer[kZDCNode_TweakBlockSizeInBytes];
	uint64_t                 overflowBufferOffset;
	uint64_t                 overflowBufferLength;
	
	ZDCCloudFileEncryptState encryptState;
	TBC_ContextRef           TBC;
	
	uint64_t                 stateOffset;      // bytes processed per state (metadata, thumbnail, data, pad)
	uint64_t                 encryptionOffset; // bytes processed for encryption (for tracking blocks)
	uint64_t                 readerOffset;
	
	NSNumber *               pendingSeek_offset;
	NSNumber *               pendingSeek_ignore;
	
	BOOL                     cleartextFileSizeImplicitlySet;
}

@synthesize cleartextFileURL = cleartextFileURL;
@synthesize cleartextData = cleartextData;

@synthesize rawMetadata = rawMetadata;
@synthesize rawThumbnail = rawThumbnail;

@synthesize cleartextFileSize = cleartextFileSize;
@synthesize cleartextFileSizeUnknown = cleartextFileSizeUnknown;

@dynamic encryptedFileSize;
@dynamic encryptedRangeSize;

/**
 * See header file for description.
 */
- (instancetype)initWithCleartextFileURL:(NSURL *)inCleartextFileURL
                           encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		cleartextFileURL = inCleartextFileURL;
		
		inputStream = [NSInputStream inputStreamWithURL:cleartextFileURL];
		inputStream.delegate = self;
		
		encryptionKey = [inEncryptionKey copy];
		
		encryptState  = ZDCCloudFileEncryptState_Init;
		TBC = kInvalidTBC_ContextRef;
	}
	return self;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCleartextFileStream:(NSInputStream *)cleartextFileStream
                              encryptionKey:(NSData *)inEncryptionKey
{
	if ((self = [super init]))
	{
		inputStream = cleartextFileStream;
		inputStream.delegate = self;
		
		encryptionKey = [inEncryptionKey copy];
		
		encryptState  = ZDCCloudFileEncryptState_Init;
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
		cleartextFileSize = @(inCleartextData.length);
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
	Cleartext2CloudFileInputStream *copy = nil;
	
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
		copy->rawMetadata = rawMetadata;
		copy->rawThumbnail = rawThumbnail;
		
		if (!cleartextFileSizeImplicitlySet) {
			copy->cleartextFileSize = cleartextFileSize;
		}
		copy->cleartextFileSizeUnknown = cleartextFileSizeUnknown;
		
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

- (NSData *)rawMetadata
{
	if (rawMetadata)
		return rawMetadata;
	else
		return metaData;
}

- (NSData *)rawThumbnail
{
	if (rawThumbnail)
		return rawThumbnail;
	else
		return thumbData;
}

- (NSNumber *)encryptedFileSize
{
	if (cleartextFileSize == nil) {
		return nil;
	}
	
	uint64_t totalFileSize = 0;
	
	totalFileSize += sizeof(ZDCCloudFileHeader);
	totalFileSize += metaData.length;
	totalFileSize += thumbData.length;
	totalFileSize += [cleartextFileSize unsignedLongLongValue];
	totalFileSize += [self padLength];
	
	return @(totalFileSize);
}

- (NSNumber *)encryptedRangeSize
{
	NSNumber *total = self.encryptedFileSize;
	if (total == nil) {
		return nil;
	}
	
	uint64_t totalFileSize = [total unsignedLongLongValue];
	uint64_t result = totalFileSize;
	
	if (fileMaxOffset != nil)
	{
		uint64_t max = [fileMaxOffset unsignedLongLongValue];
		
		if (max < totalFileSize)
			result -= (totalFileSize - max);
	}
	if (fileMinOffset != nil)
	{
		uint64_t min = [fileMinOffset unsignedLongLongValue];
		
		if (min > 0)
			result -= min;
	}
	
	return @(result);
}

- (NSUInteger)padLength
{
	if (cleartextFileSize == nil) {
		return 0;
	}
	
	NSUInteger padLength = 0;
	NSUInteger keyLength = encryptionKey.length;
	
	if (keyLength > 0) // watch out for EXC_ARITHMETIC
	{
		uint64_t total = 0;
		
		total += sizeof(ZDCCloudFileHeader);
		total += metaData.length;
		total += thumbData.length;
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
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)seekToPendingOffset
{
	NSAssert(streamStatus != NSStreamStatusNotOpen,  @"Seek request in bad state: NSStreamStatusNotOpen");
	NSAssert(pendingSeek_offset != nil,              @"Seek request in bad state: !pendingSeekOffset");
	
	// Watch out for edge case:
	// Once a normal stream hits EOF, it still allows seeking, but won't allow any more reading.
	// The only way around this is to re-create the underlying stream.
	
	if (inputStream.streamStatus == NSStreamStatusAtEnd)
	{
		{ // limiting scope
			
			NSInputStream *newInputStream = nil;
			
			if (cleartextFileURL)
			{
				newInputStream = [NSInputStream inputStreamWithURL:cleartextFileURL];
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
	
	// Calculate nearest block index
	
	uint64_t requestedCloudFileOffset = [pendingSeek_offset unsignedLongLongValue];
	
	NSNumber *encryptedFileSize = self.encryptedFileSize;
	if (encryptedFileSize == nil)
	{
		NSString *desc = @"Unable to seek when cleartextFileSize is unknown.";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	uint64_t maxFileOffset = [encryptedFileSize unsignedLongLongValue];
	if (requestedCloudFileOffset > maxFileOffset) {
		requestedCloudFileOffset = maxFileOffset;
	}
	
	uint64_t nearestBlockIndex = (uint64_t)(requestedCloudFileOffset / kZDCNode_TweakBlockSizeInBytes);
	uint64_t nearestBlockOffset = nearestBlockIndex * kZDCNode_TweakBlockSizeInBytes;
	
	// Calculate new state
	
	NSRange headerRange = NSMakeRange(0, sizeof(ZDCCloudFileHeader));
	NSRange metaRange   = NSMakeRange(NSMaxRange(headerRange), metaData.length);
	NSRange thumbRange  = NSMakeRange(NSMaxRange(metaRange), thumbData.length);
	NSRange fileRange   = NSMakeRange(NSMaxRange(thumbRange), [cleartextFileSize unsignedIntegerValue]);
	NSRange padRange    = NSMakeRange(NSMaxRange(fileRange), [self padLength]);
	
	if (nearestBlockOffset < NSMaxRange(headerRange))
	{
		encryptState = ZDCCloudFileEncryptState_Open;
		stateOffset = nearestBlockOffset - headerRange.location;
	}
	else if (nearestBlockOffset < NSMaxRange(metaRange))
	{
		encryptState = ZDCCloudFileEncryptState_Metadata;
		stateOffset = nearestBlockOffset - metaRange.location;
	}
	else if (nearestBlockOffset < NSMaxRange(thumbRange))
	{
		encryptState = ZDCCloudFileEncryptState_Thumbnail;
		stateOffset = nearestBlockOffset - thumbRange.location;
	}
	else if (nearestBlockOffset < NSMaxRange(fileRange))
	{
		encryptState = ZDCCloudFileEncryptState_Data;
		stateOffset = nearestBlockOffset - fileRange.location;
		
		if (![inputStream setProperty:@(stateOffset) forKey:NSStreamFileCurrentOffsetKey])
		{
			NSString *desc = @"Unable to seek to desired offset.";
			
			streamError = [self errorWithDescription:desc];
			streamStatus = NSStreamStatusError;
			[self sendEvent:NSStreamEventErrorOccurred];
			
			return;
		}
	}
	else if (nearestBlockOffset < NSMaxRange(padRange))
	{
		encryptState = ZDCCloudFileEncryptState_Pad;
		stateOffset = nearestBlockOffset - padRange.location;
	}
	else
	{
		encryptState = ZDCCloudFileEncryptState_Done;
		stateOffset = 0;
	}
	
	encryptionOffset = nearestBlockOffset;
	readerOffset     = nearestBlockOffset;
	
	// Reset all state variables to reflect the new situation
	
	inBufferLength = 0;
	
	overflowBufferOffset = 0;
	overflowBufferLength = 0;
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	pendingSeek_offset = nil;
	
	uint64_t ignore = requestedCloudFileOffset - nearestBlockOffset;
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
	ZDCLogAutoTrace();
	
	if (streamStatus != NSStreamStatusNotOpen) {
		return;
	}
	
	// Sanity checks
	
	if ([self cipherAlgorithm] == kCipher_Algorithm_Invalid)
	{
		NSString *desc = @"Unsupported keysize";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	// Get metadata data for cloud file
	
	if (rawMetadata) {
		metaData = [rawMetadata copy]; // ensure data isn't changed during stream operation
	}
	else {
		metaData = [NSData data];
	}
	
	// Get thumbnail data for cloud file
	
	if (rawThumbnail) {
		thumbData = [rawThumbnail copy]; // ensure data isn't changed during stream operation
	}
	else {
		thumbData = [NSData data];
	}
	
	// Open underlying inputStream
	
	if (!inputStream)
	{
		NSString *desc = NSLocalizedString(@"Bad parameter: cleartextFileURL || cleartextFileStream", nil);
		
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
	
	// If possible, automatically set the cleartextFileSize property (if needed)
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
	
	encryptState  = ZDCCloudFileEncryptState_Open;
	
	streamError = nil;
	streamStatus = NSStreamStatusOpen;
	[self sendEvent:NSStreamEventOpenCompleted];
	
	// Handle pending seek operations
	
	if (pendingSeek_offset != nil)
	{
		[self seekToPendingOffset];
	}
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
	
	stateOffset = 0;
	encryptionOffset = 0;
	
	[inputStream close];
	streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(NSString *)key
{
	if ([key isEqualToString:NSStreamFileCurrentOffsetKey])
	{
		if (pendingSeek_offset || pendingSeek_ignore)
		{
			uint64_t offset = (pendingSeek_offset != nil) ? pendingSeek_offset.unsignedLongLongValue : readerOffset;
			uint64_t ignore = (pendingSeek_ignore != nil) ? pendingSeek_ignore.unsignedLongLongValue : 0;
			
			return @(offset + ignore);
		}
		else
		{
			return @(readerOffset);
		}
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
			@" but then you'll also have to re-write the CloudFile header afterwards. "
			@" See [Cleartext2CloudFileInputstream updateCloudFileHeader:withCleartextFileSize:encryptionKey:]";
		
		streamError = [self errorWithDescription:desc];
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return -1;
	}
	
	S4Err err = kS4Err_NoErr;
	NSUInteger const keyLength = encryptionKey.length;
	NSUInteger requestBufferOffset = 0;
	
	// Check maxFileOffset
	
	if (fileMaxOffset != nil)
	{
		uint64_t max = [fileMaxOffset unsignedLongLongValue];
		uint64_t cur = readerOffset;
		
		if (cur >= max)
		{
			if (streamStatus < NSStreamStatusAtEnd)
			{
				streamStatus = NSStreamStatusAtEnd;
				[self sendEvent:NSStreamEventEndEncountered];
			}
			
			return 0;
		}
		else
		{
			uint64_t leftInRange = max - cur;
			if (requestBufferMallocSize > leftInRange)
			{
				requestBufferMallocSize = (NSUInteger)leftInRange;
			}
		}
	}
	
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
		
		if (requestBufferOffset >= requestBufferMallocSize)
		{
			return requestBufferOffset;
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
	// - unless reader asked for zero bytes
	
	NSUInteger bytesToRead = 0;
	NSUInteger minBytesToRead = 0;
	
	{ // scope limiting for various variables
		
		NSUInteger neededToFillRequest = requestBufferMallocSize - requestBufferOffset;
		NSUInteger neededToReturnNonZero = (requestBufferOffset > 0) ? 0 : 1;
		
		if (pendingSeek_ignore)
		{
			// There was a recent seek (to the nearest block),
			// and we're going to have to throw away several bytes.
			// So we actually need to read more.
			
			NSAssert(!overflowAvailable, @"Unexpected state: pendingSeek_ignore + overflowAvailable");
			
			NSUInteger const offset = pendingSeek_ignore.unsignedIntegerValue;
			neededToFillRequest += offset;
			
			if (neededToReturnNonZero > 0) {
				neededToReturnNonZero += offset;
			}
			else {
				// We do NOT need to increment the value.
				// Because we've already copied some bytes into the requestBuffer.
				// And this satisfies our requirement of returning a positive value to the caller.
			}
		}
		
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
			inBuffer = reallocf(inBuffer, inBufferMallocSize);
		else
			inBuffer = malloc(inBufferMallocSize);
		
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
	
	while ((bytesRead < bytesToRead) && (encryptState != ZDCCloudFileEncryptState_Done) && !readPartial)
	{
		switch (encryptState)
		{
			case ZDCCloudFileEncryptState_Open:
			{
				uint64_t headerSize = sizeof(ZDCCloudFileHeader);
				NSAssert(headerSize <= 64, @"Programmer doesn't understand byte alignment");
				
				NSAssert((inBufferMallocSize - inBufferLength) >= headerSize, @"Bad buffer");
				
				uint64_t metaDataSize  = metaData.length;
				uint64_t thumbnailSize = thumbData.length;
				uint64_t inStreamSize  = [cleartextFileSize unsignedLongLongValue];
				
				uint64_t thumbnailxxHash64 = 0;
				if (thumbData.length > 0) {
					thumbnailxxHash64 = [thumbData xxHash64];
				}
				
				// write header
				uint8_t *p0 = inBuffer + inBufferLength;
				uint8_t *p = p0;
				S4_Store64(kZDCCloudFileContextMagic,      &p);
				S4_Store64(metaDataSize,                   &p);
				S4_Store64(thumbnailSize,                  &p);
				S4_Store64(inStreamSize,                   &p);
				S4_Store64(thumbnailxxHash64,              &p);
				S4_Store8(0,                               &p); // version
				S4_StorePad(0, kZDCCloudFileReservedBytes, &p); // reserved
				
				NSAssert((p - p0) == headerSize, @"Missing bytes in header ?");
				
				bytesRead      += headerSize;
				inBufferLength += headerSize;
				
				stateOffset = 0;
				encryptState = ZDCCloudFileEncryptState_Metadata;
				
				break;
			}
			case ZDCCloudFileEncryptState_Metadata:
			{
				uint64_t metaDataToWrite = MIN((metaData.length - stateOffset), (bytesToRead - bytesRead));
				
				NSAssert((inBufferMallocSize - inBufferLength) >= metaDataToWrite, @"Bad buffer");
				
				uint8_t *p = inBuffer + inBufferLength;
				S4_StoreArray((void *)(metaData.bytes + stateOffset), (size_t)metaDataToWrite, &p);
				
				bytesRead      += metaDataToWrite;
				inBufferLength += metaDataToWrite;
				stateOffset    += metaDataToWrite;
				
				if (stateOffset >= metaData.length)
				{
					stateOffset = 0;
					encryptState = ZDCCloudFileEncryptState_Thumbnail;
				}
				
				break;
			}
			case ZDCCloudFileEncryptState_Thumbnail:
			{
				uint64_t thumbDataToWrite = MIN((thumbData.length - stateOffset), (bytesToRead - bytesRead));
				
				NSAssert((inBufferMallocSize - inBufferLength) >= thumbDataToWrite, @"Bad buffer");
				
				uint8_t *p = inBuffer + inBufferLength;
				S4_StoreArray((void *)(thumbData.bytes + stateOffset), (size_t)thumbDataToWrite, &p);
				
				bytesRead      += thumbDataToWrite;
				inBufferLength += thumbDataToWrite;
				stateOffset    += thumbDataToWrite;
				
				if (stateOffset >= thumbData.length)
				{
					stateOffset = 0;
					encryptState = ZDCCloudFileEncryptState_Data;
				}
				
				break;
			}
			case ZDCCloudFileEncryptState_Data:
			{
				NSUInteger maxLength = bytesToRead - bytesRead;
				
				NSAssert((inBufferMallocSize - inBufferLength) >= maxLength, @"Bad buffer");
				
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
					inFromStream = [inputStream read:(inBuffer + inBufferLength) maxLength:maxLength];
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
				
				bytesRead      += inFromStream;
				inBufferLength += inFromStream;
				stateOffset    += inFromStream;
				
				BOOL inputStreamEOF = (inFromStream == 0) && shouldRead;
				
				if (cleartextFileSize)
				{
					uint64_t expectedFileSize = [cleartextFileSize unsignedLongLongValue];
					
					if ((stateOffset < expectedFileSize) && inputStreamEOF)
					{
						// File is smaller than expected !
			
						NSString *desc =
						  [NSString stringWithFormat:@"Unexpected cleartextFileSize: found(%llu) < expected(%llu)",
						    stateOffset, expectedFileSize];
			
						streamError = [self errorWithDescription:desc code:ZDCStreamUnexpectedFileSize];
						streamStatus = NSStreamStatusError;
						[self sendEvent:NSStreamEventErrorOccurred];
			
						return -1;
					}
					else if (stateOffset > expectedFileSize)
					{
						// File is bigger than expected !
			
						NSString *desc =
						  [NSString stringWithFormat:@"Unexpected cleartextFileSize: found(%llu) > expected(%llu)",
						    stateOffset, expectedFileSize];
			
						streamError = [self errorWithDescription:desc code:ZDCStreamUnexpectedFileSize];
						streamStatus = NSStreamStatusError;
						[self sendEvent:NSStreamEventErrorOccurred];
			
						return -1;
					}
					else if ((stateOffset == expectedFileSize) && inputStreamEOF)
					{
						stateOffset = 0;
						encryptState = ZDCCloudFileEncryptState_Pad;
					}
				}
				else // if (cleartextFileSize == nil)
				{
					// We didn't know what the cleartextFileSize would be in advance.
					
					if (inputStreamEOF)
					{
						cleartextFileSize = @(stateOffset);
						
						stateOffset = 0;
						encryptState = ZDCCloudFileEncryptState_Pad;
					}
				}
				
				if ((encryptState != ZDCCloudFileEncryptState_Pad) && !readPartial)
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
			case ZDCCloudFileEncryptState_Pad:
			{
				NSUInteger padLength = [self padLength];
				uint64_t bytesToPad = MIN((padLength - stateOffset), (bytesToRead - bytesRead));
				
				NSAssert((inBufferMallocSize - inBufferLength) >= bytesToPad, @"Bad buffer");
				
				uint64_t padNumber = padLength;
				while (padNumber > UINT8_MAX) {
					padNumber -= UINT8_MAX;
				}
				
				uint8_t *p = inBuffer + inBufferLength;
				S4_StorePad((uint8_t)padNumber, (size_t)bytesToPad, &p);
				
				bytesRead        += bytesToPad;
				inBufferLength   += bytesToPad;
				stateOffset      += bytesToPad;
				
				if (stateOffset >= padLength)
				{
					stateOffset = 0;
					encryptState = ZDCCloudFileEncryptState_Done;
				}
				
				break;
			}
			default: { break; }
		}
	}
	
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
			err = TBC_Init([self cipherAlgorithm], encryptionKey.bytes,encryptionKey.length, &TBC); CKS4ERR;
			needsSetTweak = YES;
		}
		else
		{
			needsSetTweak = ((encryptionOffset % kZDCNode_TweakBlockSizeInBytes) == 0);
		}
		
		if (needsSetTweak)
		{
			uint64_t tweakBlockNum = (uint64_t)(encryptionOffset / kZDCNode_TweakBlockSizeInBytes);
			uint64_t tweak[2] = {tweakBlockNum, 0};
			
			err = TBC_SetTweek(TBC, tweak, sizeof(tweak)); CKS4ERR;
		}
		
		NSUInteger requestBufferSpace = requestBufferMallocSize - requestBufferOffset;
		
		if ((requestBufferSpace >= keyLength) && (pendingSeek_ignore == nil))
		{
			// Encrypt directly into requestBuffer
			
			err = TBC_Encrypt(TBC, (inBuffer + bytesEncrypted), (requestBuffer + requestBufferOffset)); CKS4ERR;
			
			bytesEncrypted      += keyLength;
			encryptionOffset    += keyLength;
			requestBufferOffset += keyLength;
			readerOffset        += keyLength;
		}
		else // if (requestBufferSpace < keyLength)
		{
			// At least one of the following is true:
			// - not enough space in the requestBuffer for the entire chunk
			// - we have to ignore some of the encrypted bytes (due to previous seek request)
			// 
			// So we decrypt into overflow buffer first.
			// And then we can later copy into the request buffer.
			
			NSAssert((sizeof(overflowBuffer) - overflowBufferLength) >= keyLength,
			         @"Unexpected state: overflowBuffer doesn't have space");
			
			err = TBC_Encrypt(TBC, (inBuffer + bytesEncrypted), (overflowBuffer + overflowBufferLength)); CKS4ERR;
			
			bytesEncrypted       += keyLength;
			encryptionOffset     += keyLength;
			overflowBufferLength += keyLength;
			
			// Check to see if we need to ignore any bytes (due to seek)
			
			if (pendingSeek_ignore != nil)
			{
				uint64_t pendingIgnore = [pendingSeek_ignore unsignedLongLongValue];
				uint64_t overflowSize = overflowBufferLength - overflowBufferOffset;
				
				uint64_t bytesToIgnore = MIN(pendingIgnore, overflowSize);
				
				overflowBufferOffset += bytesToIgnore;
				readerOffset         += bytesToIgnore;
				
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
				
				memcpy((requestBuffer + requestBufferOffset), (overflowBuffer + overflowBufferOffset), bytesToCopy);
				
				requestBufferOffset  += bytesToCopy;
				overflowBufferOffset += bytesToCopy;
				readerOffset         += bytesToCopy;
			}
			
			// Did we drain the overflowBuffer ?
			
			if (overflowBufferOffset >= overflowBufferLength)
			{
				overflowBufferOffset = 0;
				overflowBufferLength = 0;
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
		if (fileMaxOffset != nil)
		{
			uint64_t max = [fileMaxOffset unsignedLongLongValue];
			uint64_t cur = readerOffset;
			
			if (cur >= max)
			{
				if (streamStatus < NSStreamStatusAtEnd)
				{
					streamStatus = NSStreamStatusAtEnd;
					[self sendEvent:NSStreamEventEndEncountered];
				}
			}
		}
		
		if (encryptState == ZDCCloudFileEncryptState_Done)
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
	
	if (pendingSeek_ignore || pendingSeek_offset)
	{
		// Difficult to tell for sure.
		// A read may be required to find out.
		return YES;
	}
	
	if ((overflowBufferLength - overflowBufferOffset) > 0)
	{
		// We have data in the overflowBuffer.
		// That is, data we've already encrypted, but didn't fit into the reader's last `read:maxLength:` request.
		
		return YES;
	}
	
	if (encryptState == ZDCCloudFileEncryptState_Open)
	{
		// We can always generate the header.
		return YES;
	}
	
	if (encryptState == ZDCCloudFileEncryptState_Metadata)
	{
		if (rawMetadata.length > 0) return YES;
		if (rawThumbnail.length > 0) return YES;
		
		return [inputStream hasBytesAvailable];
	}
	
	if (encryptState == ZDCCloudFileEncryptState_Pad)
	{
		// We can always generate the padding.
		return YES;
	}
	
	if (encryptState == ZDCCloudFileEncryptState_Data)
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
 * Subclasses should return YES if these properties are supported.
 * Otherwise ZDCInputStream will refuse to set them, and return NO in `setProperty:forKey:`.
**/
- (BOOL)supportsFileMinMaxOffset
{
	return YES;
}

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
#pragma mark Header Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (nullable NSError *)updateCloudFileHeader:(NSURL *)cloudFileURL
                      withCleartextFileSize:(uint64_t)cleartextFileSize
                              encryptionKey:(NSData *)encryptionKey
{
	NSError *error = nil;
	
	Cipher_Algorithm algo = [self cipherAlgorithm:encryptionKey];
	NSUInteger const keyLength = encryptionKey.length;
	
	NSAssert(keyLength == sizeof(ZDCCloudFileHeader), @"Lazy programmer");
	
	int const flags = O_RDWR;
	int fd = -1;
	
	ssize_t encryptedBufferOffset = 0;
	void *encryptedBuffer = NULL;
	void *decryptedBuffer = NULL;
	
	S4Err err = kS4Err_NoErr;
	TBC_ContextRef TBC = kInvalidTBC_ContextRef;
	
	fd = open(cloudFileURL.path.UTF8String, flags);
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
	if (magic != kZDCCloudFileContextMagic)
	{
		NSString *desc = @"File doesn't appear to be a cache File (header magic incorrect)";
		error = [self errorWithDescription:desc];
		goto cleanup;
	}
	
	(void) S4_Load64(&p); // metadata size
	(void) S4_Load64(&p); // thumbnail size
	
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

/**
 * See header file for description.
 */
+ (nullable NSData *)encryptCloudFileHeader:(ZDCCloudFileHeader)header
                          withEncryptionKey:(NSData *)encryptionKey
                                      error:(NSError *_Nullable *_Nullable)errorPtr
{
	NSData *result = nil;
	NSError *error = nil;
	
	S4Err err = kS4Err_NoErr;
	TBC_ContextRef TBC = kInvalidTBC_ContextRef;
	
	const Cipher_Algorithm algo = [self cipherAlgorithm:encryptionKey];
	
	const size_t headerSize = sizeof(ZDCCloudFileHeader);
	NSAssert(headerSize == 64, @"Programmer doesn't understand byte alignment");
	
	uint8_t inBuffer[headerSize];
	uint8_t outBuffer[headerSize];
	
	if (algo == kCipher_Algorithm_Invalid)
	{
		error = [self errorWithDescription:@"Invalid encryptionKey: no matching cipher algorithm"];
		goto done;
	}
	
	// Serialize header to inBuffer
	
	uint8_t *p = inBuffer;
	S4_Store64(kZDCCloudFileContextMagic,      &p);
	S4_Store64(header.metadataSize,            &p);
	S4_Store64(header.thumbnailSize,           &p);
	S4_Store64(header.dataSize,                &p);
	S4_Store64(header.thumbnailxxHash64,       &p);
	S4_Store8(0,                               &p); // version
	S4_StorePad(0, kZDCCloudFileReservedBytes, &p); // reserved
	
	NSAssert((p - inBuffer) == headerSize, @"Missing bytes in header ?");
	
	err = TBC_Init(algo, encryptionKey.bytes, encryptionKey.length, &TBC); CKS4ERR;
	
	uint64_t tweakBlockNum = 0;
	uint64_t tweak[2] = {tweakBlockNum, 0};
	
	err = TBC_SetTweek(TBC, tweak, sizeof(tweak)); CKS4ERR;
	
	err = TBC_Encrypt(TBC, inBuffer, outBuffer); CKS4ERR;
	
	result = [NSData dataWithBytes:outBuffer length:headerSize];
	
done:
	
	if (err != kS4Err_NoErr) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (TBC_ContextRefIsValid(TBC)) {
		TBC_Free(TBC);
		TBC = kInvalidTBC_ContextRef;
	}
	
	ZERO(inBuffer, headerSize);
	ZERO(outBuffer, headerSize);
	
	if (errorPtr) *errorPtr = error;
	return result;
}

@end
