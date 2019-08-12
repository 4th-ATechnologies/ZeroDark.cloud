/**
 * Storm4
 * https://www.storm4.cloud
**/

#import "ZDCInterruptingInputStream.h"

#import "ZDCFileChecksum.h"
#import "ZDCFilesystemMonitor.h"
#import "ZDCLogging.h"

#import "NSData+S4.h"

#import <libkern/OSAtomic.h>
#import <S4Crypto/S4Crypto.h>

#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelInfo; // | ZDCLogFlagTrace;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

/* extern */ NSInteger const ZDCFileModifiedDuringRead = 1000;

static const HASH_Algorithm chunk_algorithm = kHASH_Algorithm_MD5;
static const NSUInteger chunk_size = 1024 * 1024; // in bytes


@interface ZDCInputStream (Private)

- (NSError *)errorWithDescription:(NSString *)description;
+ (NSError *)errorWithDescription:(NSString *)description;
- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;
+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;

- (void)sendEvent:(NSStreamEvent)streamEvent;
- (void)notifyDelegateOfEvent:(NSStreamEvent)streamEvent;

@end

@implementation ZDCInterruptingInputStream {
@private
	
	uint64_t startingByteOffset;
	uint64_t currentByteOffset;
	HASH_ContextRef currentHashRef;
	
	ZDCFilesystemMonitor *monitor;
	NSProgress *checksumProgress;
	
	dispatch_queue_t queue;
	
	dispatch_queue_t checksumsQueue;
	dispatch_semaphore_t checksumsSemaphore;
	NSMutableDictionary<NSNumber *, NSData *> *checksums;
	int checksumsTask;
	BOOL checksumsCalculationFinished;
}

@synthesize fileURL = fileURL;
@synthesize fileSize = fileSizeNum;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init & Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Designated initializer.
**/
- (instancetype)initWithFileURL:(NSURL *)inFileURL
{
	if ((self = [super init]))
	{
		fileURL = inFileURL;
		
		inputStream = [NSInputStream inputStreamWithURL:fileURL];
		inputStream.delegate = self;
		
		checksumsQueue = dispatch_queue_create("S4InterruptingStream.checksums", DISPATCH_QUEUE_SERIAL);
		checksumsSemaphore = dispatch_semaphore_create(0);
		checksums = [[NSMutableDictionary alloc] init];
		
		queue = dispatch_queue_create("S4InterruptingStream", DISPATCH_QUEUE_SERIAL);
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
	ZDCInterruptingInputStream *copy = [[[self class] alloc] initWithFileURL:fileURL];
	
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
#pragma mark Hash Storage
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoke this before starting the calculations.
 * The returned int will be a required parameter for all other methods.
**/
- (int)resetChecksums
{
	__block int task = 0;
	
	dispatch_sync(checksumsQueue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		checksumsTask++;
		task = checksumsTask;
		
		[checksums removeAllObjects];
		checksumsCalculationFinished = NO;
		
	#pragma clang diagnostic pop
	});
	
	return task;
}

/**
 * Returns the checksum for the given chunkIndex. (Use NSUIntegerMax for the checksum of the entire file.)
 *
 * If needed, this method will block until the async process completes the checksum calculation.
 * Although this is almost never required, as the file IO + checksum calculation is generally
 * an order of magnitude faster than the network IO.
**/
- (BOOL)getChecksum:(NSData **)outChecksum forChunkIndex:(NSUInteger)chunkIndex
{
	__block NSData *checksum = nil;
	__block BOOL isFinished = NO;
	do
	{
		dispatch_sync(checksumsQueue, ^{
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			checksum = checksums[@(chunkIndex)];
			
			if (checksumsCalculationFinished)
				isFinished = YES;
			
		#pragma clang diagnostic pop
		});
		
		if (!checksum && !isFinished) {
			dispatch_semaphore_wait(checksumsSemaphore, DISPATCH_TIME_FOREVER);
		}
		
	} while (!checksum && !isFinished);
	
	if (outChecksum){
		if (checksum)
			*outChecksum = checksum;
		else
			*outChecksum = nil;
	}
	return (checksum != nil);
}

/**
 * Stores the checksum for the given chunkIndex. (Use NSUIntegerMax for the checksum of the entire file.)
**/
- (void)setChecksum:(NSData *)checksum forChunkIndex:(NSUInteger)chunkIndex withTask:(int)task
{
	dispatch_sync(checksumsQueue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (checksumsTask == task)
		{
			checksums[@(chunkIndex)] = checksum;
		}
		
	#pragma clang diagnostic pop
	});
	
	dispatch_semaphore_signal(checksumsSemaphore);
}

/**
 * Invoke this when the async checksum calculation finishes, regardless of errors.
 * This ensures that edge cases, such as a file size increase, won't deadlock the stream.
**/
- (void)setChecksumsCalculationFinishedWithTask:(int)task
{
	dispatch_sync(checksumsQueue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (checksumsTask == task)
		{
			checksumsCalculationFinished = YES;
		}
		
	#pragma clang diagnostic pop
	});
	
	dispatch_semaphore_signal(checksumsSemaphore);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Modification Detection
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)monitorFile
{
	monitor = [[ZDCFilesystemMonitor alloc] initWithFileURL:fileURL];
	
	__weak typeof(self) weakSelf = self;
	BOOL monitorStarted = [monitor monitorWithMask: [ZDCFilesystemMonitor vnode_flags_all]
	                                         queue: queue
	                                         block:^(dispatch_source_vnode_flags_t mask)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			[strongSelf signalFileModified];
		}
	}];
	
	if (!monitorStarted)
	{
		[self signalFileModified];
	}
}

- (void)calculateChecksums
{
	int task = [self resetChecksums];
	
	NSUInteger range_location = 0;
	NSUInteger range_length = NSUIntegerMax;
	
	NSNumber *offset = [self propertyForKey:NSStreamFileCurrentOffsetKey];
	if (offset != nil) {
		range_location = [offset unsignedIntegerValue];
	}
	
	if (fileMaxOffset != nil) {
		range_length = [fileMaxOffset unsignedIntegerValue] - range_location;
	}
	
	NSRange range = NSMakeRange(range_location, range_length);
	
	ZDCLogVerbose(@"ZDCInterruptingInputStream<%p> task<%d>: range = %@", self, task, NSStringFromRange(range));
	
	__weak typeof(self) weakSelf = self;
	ZDCFileChecksumCallbackBlock chunkBlock = ^(NSData *checksum, uint64_t chunkIndex, BOOL done, NSError *error) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		if (done)
		{
			ZDCLogVerbose(@"ZDCInterruptingInputStream<%p> task<%d>: done", strongSelf, task);
			[strongSelf setChecksumsCalculationFinishedWithTask:task];
		}
		else
		{
			ZDCLogVerbose(@"ZDCInterruptingInputStream<%p> task<%d>: [%llu] = %@",
			      strongSelf, task, (unsigned long long)chunkIndex, checksum);
			
			[strongSelf setChecksum:checksum forChunkIndex:(NSUInteger)chunkIndex withTask:task];
		}
	};
	
	ZDCFileChecksumInstruction *instruction = [[ZDCFileChecksumInstruction alloc] init];
	instruction.algorithm = chunk_algorithm;
	instruction.chunkSize = @(chunk_size);
	instruction.range = [NSValue valueWithRange:range];
	instruction.callbackQueue = queue;
	instruction.callbackBlock = chunkBlock;
	
	NSError *paramError = nil;
	checksumProgress = [ZDCFileChecksum checksumFileURL:fileURL withInstructions:@[instruction] error:&paramError];
}

- (void)signalFileModified
{
	ZDCLogAutoTrace();
	ZDCLogInfo(@"File modified: %@", [fileURL lastPathComponent]);
	
	// Edge case bug (hard to reproduce too):
	//
	// The documentation for [NSURL getResourceValue:forKey:error:]
	// mentions that NSURL uses an internal caching system to avoid hitting the disk.
	//
	// > This method first checks if the URL object already caches the resource value.
	// > If so, it returns the cached resource value to the caller.
	// > If not, then this method synchronously obtains the resource value from the
	// > backing store, adds the resource value to the URL object's cache,
	// > and returns the resource value to the caller.
	//
	// The documentation for [NSURL removeCachedResourceValueForKey:] states:
	//
	// > The caching behavior of the NSURL and CFURL APIs differ. For NSURL, all
	// > cached values (not temporary values) are automatically removed after each pass
	// > through the run loop. You only need to call the removeCachedResourceValueForKey:
	// > method when you want to clear the cache within a single execution of the run loop.
	//
	// Well... I'm calling BS (about the flusing after run loop stuff).
	//
	// Maybe the docs are no longer true.
	// Or maybe it doesn't apply to us because we're not on the main thread,
	// Or maybe it's because we're using GCD, and not inside a normal run loop.
	//
	// Whatever the case may be, we've definitely witnessed situations in which
	// our NSURL instance has a bad value cached for NSURLFileSizeKey.
	//
	// And the end result is that ZDCInterruptingInputStream continuously fails,
	// all due to the fact that it has a bad `fileSizeNum` value.
	//
	// So we need to manually flush this value from the cache to prevent the loop.
	//
	[fileURL removeCachedResourceValueForKey:NSURLFileSizeKey];
	
	NSString *desc = @"File modified during read.";
	NSError *fileModifiedError = [self errorWithDescription:desc code:ZDCFileModifiedDuringRead];
	
	streamError = fileModifiedError;
	streamStatus = NSStreamStatusError;
	[self sendEvent:NSStreamEventErrorOccurred];
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
	
	if (!inputStream)
	{
		NSString *desc = @"Bad parameter: fileURL";
		
		streamError = [self errorWithDescription:desc];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return;
	}
	
	[inputStream open];
	
	streamStatus = [inputStream streamStatus];
	streamError = [inputStream streamError];
	
	if (streamStatus != NSStreamStatusOpen)
	{
		return;
	}
	
	NSNumber *fileSizeValue = nil;
	if ([fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:nil]) {
		fileSizeNum = fileSizeValue;
	}
	else {
		fileSizeNum = @(0);
	}
	
	if (fileMinOffset != nil)
	{
		uint64_t min = [fileMinOffset unsignedLongLongValue];
		if (min > 0)
		{
			[self setProperty:fileMinOffset forKey:NSStreamFileCurrentOffsetKey];
		}
	}
	
	[self monitorFile];
	[self calculateChecksums];
}

- (void)close
{
	ZDCLogAutoTrace();
	
	if (streamStatus == NSStreamStatusClosed) return;
	
	[inputStream close];
	streamStatus = NSStreamStatusClosed;
	
	monitor = nil;
	
	[checksumProgress cancel];
	checksumProgress = nil;
}

- (id)propertyForKey:(NSStreamPropertyKey)key
{
	if ([key isEqualToString:NSStreamFileCurrentOffsetKey])
	{
		return [inputStream propertyForKey:NSStreamFileCurrentOffsetKey];
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
		
		if (![inputStream setProperty:property forKey:key])
		{
			NSString *desc = @"Unable to seek to desired offset.";
			
			streamError = [self errorWithDescription:desc];
			streamStatus = NSStreamStatusError;
			[self sendEvent:NSStreamEventErrorOccurred];
			
			return NO;
		}
		
		startingByteOffset = [newOffset unsignedLongLongValue];
		currentByteOffset = startingByteOffset;
		
		if (currentHashRef != kInvalidHASH_ContextRef) {
			HASH_Free(currentHashRef);
			currentHashRef = kInvalidHASH_ContextRef;
		}
		
		if (checksumProgress)
		{
			[checksumProgress cancel];
			checksumProgress = nil;
			
			[self calculateChecksums];
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
	
	uint64_t bytesLeftInRange = UINT64_MAX;
	if (fileMaxOffset != nil)
	{
		uint64_t max = [fileMaxOffset unsignedLongLongValue];
		bytesLeftInRange = max - currentByteOffset;
	}
	
	uint64_t bytesToRead = MIN(bytesLeftInRange, (uint64_t)requestBufferMallocSize);
	
	NSInteger result = [inputStream read:requestBuffer maxLength:(NSUInteger)bytesToRead];
	if (result < 0)
	{
		streamError = [inputStream streamError];
		streamStatus = NSStreamStatusError;
		[self sendEvent:NSStreamEventErrorOccurred];
		
		return result;
	}
	
	uint64_t fileSize = [fileSizeNum unsignedLongLongValue];
	
	if ((currentByteOffset + result) > fileSize)
	{
		[self signalFileModified];
		return -1;
	}
	
	BOOL eof = (result == 0);
	
	uint64_t processed = 0;
	BOOL checksumMismatch = NO;
	do {
		
		uint64_t hashOffset = currentByteOffset - startingByteOffset;
		
		if ((hashOffset % chunk_size) == 0)
		{
			HASH_Init(chunk_algorithm, &currentHashRef);
		}
		
		NSAssert(currentHashRef != kInvalidHASH_ContextRef, @"Logic error");
		
		uint64_t bytesLeftInRead = result - processed;
		uint64_t bytesLeftInHash = chunk_size - (hashOffset % chunk_size);
		
		uint64_t bytesToHash = MIN(bytesLeftInRead, bytesLeftInHash);
		HASH_Update(currentHashRef, (requestBuffer + processed), (size_t)bytesToHash);
		
		processed += bytesToHash;
		hashOffset += bytesToHash;
		currentByteOffset += bytesToHash;
		
		BOOL fullChunk = (hashOffset % chunk_size) == 0;
		
		// Edge case:
		// File size is exact multiple of hashBlockSize.
		// This would make the last read empty,
		// and we'd end up comparing an empty hash to the previous chunkIndex.
		//
		// So we really want a logical XOR:
		//
		// if (fullChunk XOR eof)
		// 
		if ((fullChunk || eof) && !(fullChunk && eof))
		{
			size_t bufferSize = 0;
			HASH_GetSize(currentHashRef, &bufferSize);
			
			void *buffer = malloc(bufferSize);
			HASH_Final(currentHashRef, buffer);
			
			NSData *checksum = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];
			
			HASH_Free(currentHashRef);
			currentHashRef = kInvalidHASH_ContextRef;
			
			NSData *preChecksum = nil;
			uint64_t chunkIndex = (uint64_t)(hashOffset / chunk_size);
			if (fullChunk) {
				chunkIndex--;
			}
			
			if ([self getChecksum:&preChecksum forChunkIndex:(NSUInteger)chunkIndex])
			{
				if (![preChecksum isEqualToData:checksum])
				{
					checksumMismatch = YES;
				}
			}
		}
		
	} while (!checksumMismatch && (processed < result));
	
	if (checksumMismatch)
	{
		[self signalFileModified];
		return -1;
	}
	
	if (eof) // eof means: 'result == 0'
	{
		streamStatus = NSStreamStatusAtEnd;
		[self stream:self handleEvent:NSStreamEventEndEncountered];
		
		return result;
	}
	
	return result;
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

@end
