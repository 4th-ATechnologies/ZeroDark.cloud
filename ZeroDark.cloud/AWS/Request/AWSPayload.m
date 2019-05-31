#import "AWSPayload.h"

#import "AWSRegions.h"
#import "NSData+AWSUtilities.h"

#import <CommonCrypto/CommonDigest.h>


@implementation AWSPayload

/**
 * Signs (SHA256 hash) the given payload.
 *
 * Returns the signature in (lowercase) hexadecimal.
 * The result
**/
+ (NSString *)signatureForPayload:(NSData *)dataToHash
{
	if (dataToHash == nil) return @"";
	
	CC_SHA256_CTX ctx;
	CC_SHA256_Init(&ctx);
	
	CC_SHA256_Update(&ctx, dataToHash.bytes, (CC_LONG)dataToHash.length);
	
	int hashLength = CC_SHA256_DIGEST_LENGTH;
	uint8_t hashBytes[hashLength];
	
	CC_SHA256_Final(hashBytes, &ctx);
	
	NSData *data = [NSData dataWithBytesNoCopy:(void *)hashBytes length:hashLength freeWhenDone:NO];
	
	return [data lowercaseHexString];
}

/**
 * See header file for description.
 */
+ (void)signatureForPayloadWithFile:(NSURL *)fileURL
                    completionQueue:(dispatch_queue_t)completionQueue
                    completionBlock:(void (^)(NSString *sha256HashInLowercaseHex, NSError *error))completionBlock
{
	if (completionBlock == nil) return;
	
	if (completionQueue == nil)
		completionQueue = dispatch_get_main_queue();
	
	NSString *filepath = [fileURL path];
	if (filepath == nil)
	{
		NSError *error = [self errorWithDescription:@"Bad parameter: fileURL"];
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			
			completionBlock(nil, error);
		}});
		
		return;
	}
	
	// The 'cleanup_queue' parameter is required, even when it's not needed, due to a bug:
	// http://www.openradar.me/15160726
	//
	dispatch_queue_t io_queue = dispatch_queue_create("AWSPayload-SignPayloadWithFile", DISPATCH_QUEUE_SERIAL);
	
	dispatch_io_t channel =
	  dispatch_io_create_with_path(DISPATCH_IO_STREAM,
	                               [filepath UTF8String],
	                               O_RDONLY,                // flags to pass to the open function
	                               0,                       // mode to pass to the open function
	                               io_queue,                // queue for cleanup block
											 ^(int error){});         // clenaup block
	
	// If the file channel could not be created, just abort.
	if (channel == NULL)
	{
		NSError *error = [self errorWithDescription:@"Unable to open file."];
		dispatch_async(completionQueue, ^{ @autoreleasepool {
			
			completionBlock(0, error);
		}});
		
		return;
	}
	
	// Ask the system for an optimum IO size
	
	uint64_t chunksize = 0;
	{
		NSNumber *number = nil;
		[fileURL getResourceValue:&number forKey:NSURLPreferredIOBlockSizeKey error:nil];
		
		if (number != nil) {
			chunksize = [number unsignedIntegerValue];
		}
		else {
			chunksize = (1024 * 32); // Pick a sane default chunk size
		}
	}
	
	// Configure chunksize on the channel.
	
	dispatch_io_set_low_water(channel, (size_t)chunksize);
	dispatch_io_set_high_water(channel, (size_t)chunksize);
	
	// Start reading
	
	__block CC_SHA256_CTX ctx;
	CC_SHA256_Init(&ctx);
	
	dispatch_io_read(channel, 0, SIZE_MAX, io_queue, ^(bool done, dispatch_data_t data, int error){ @autoreleasepool {
		
		size_t dataSize = dispatch_data_get_size(data);
		if (dataSize > 0)
		{
			dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
				
				CC_SHA256_Update(&ctx, buffer, (CC_LONG)size);
				return true;
			});
		}
		
		if (done)
		{
			int hashLength = CC_SHA256_DIGEST_LENGTH;
			uint8_t hashBytes[hashLength];
			
			CC_SHA256_Final(hashBytes, &ctx);
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)hashBytes length:hashLength freeWhenDone:NO];
			NSString *result = [data lowercaseHexString];
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock(result, nil);
			}});
		}
		
	}});
}

/**
 * See header file for description.
 */
+ (void)signatureForPayloadWithStream:(NSInputStream *)stream
                      completionQueue:(dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSString *sha256HashInLowercaseHex, NSError *error))completionBlock
{
	if (completionBlock == nil) return;
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		NSError *error = nil;
		NSString *result = [self _signatureForPayloadWithStream:stream error:&error];
		
		dispatch_async(completionQueue?: dispatch_get_main_queue(), ^{ @autoreleasepool {
			completionBlock(result, error);
		}});
	}});
}

/**
 * It's convenient to use 'goto' statements when dealing with streams.
 */
+ (NSString *)_signatureForPayloadWithStream:(NSInputStream *)stream
                                       error:(NSError **)errorPtr
{
	NSError *error = nil;
	NSString *result = nil;
	
	const int hashLength = CC_SHA256_DIGEST_LENGTH;
	uint8_t hashBytes[hashLength];
	
	CC_SHA256_CTX ctx;
	CC_SHA256_Init(&ctx);
	
	uint8_t *buffer = NULL;
	NSUInteger bufferSize = (1024 * 32); // Pick a sane default chunk size
	
	// Open streams
	
	[stream open];
	
	if (stream.streamStatus != NSStreamStatusOpen || stream.streamError)
	{
		error = [self errorOpeningStream:stream];
		goto done;
	}
	
	// Prepare for IO
	
	buffer = malloc((size_t)bufferSize);
	
	// Start IO
	
	BOOL done = NO;
	do {
		
		// Read a chunk from the input stream
		
		NSInteger bytesRead = [stream read:buffer maxLength:bufferSize];
		
		if (bytesRead < 0)
		{
			// Error reading
			
			error = [self errorReadingStream:stream];
			goto done;
		}
		else if (bytesRead == 0)
		{
			// End of stream
			
			done = YES;
		}
		else // if (bytesRead > 0)
		{
			CC_SHA256_Update(&ctx, (const void *)buffer, (CC_LONG)bytesRead);
		}
		
	} while (!done);
	
	CC_SHA256_Final(hashBytes, &ctx);
	
	if (!error)
	{
		NSData *data = [NSData dataWithBytesNoCopy:(void *)hashBytes length:hashLength freeWhenDone:NO];
		result = [data lowercaseHexString];
	}
	
done:
	
	[stream close];
	
	if (buffer) {
		free(buffer);
	}
	
	if (errorPtr) *errorPtr = error;
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Legacy
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
+ (NSData *)rawMD5HashForPayload:(NSData *)dataToHash
{
	if (dataToHash == nil) return nil;
	
	CC_MD5_CTX ctx;
	CC_MD5_Init(&ctx);
	
	CC_MD5_Update(&ctx, dataToHash.bytes, (CC_LONG)dataToHash.length);
	
	int hashLength = CC_MD5_DIGEST_LENGTH;
	uint8_t hashBytes[hashLength];
	
	CC_MD5_Final(hashBytes, &ctx);
	
	return [NSData dataWithBytes:(void *)hashBytes length:hashLength];
}

/**
 * See header file for description.
 */
+ (NSString *)md5HashForPayload:(NSData *)dataToHash
{
	if (dataToHash == nil) return @"";
	
	CC_MD5_CTX ctx;
	CC_MD5_Init(&ctx);
	
	CC_MD5_Update(&ctx, dataToHash.bytes, (CC_LONG)dataToHash.length);
	
	int hashLength = CC_MD5_DIGEST_LENGTH;
	uint8_t hashBytes[hashLength];
	
	CC_MD5_Final(hashBytes, &ctx);
	
	NSData *data = [NSData dataWithBytesNoCopy:(void *)hashBytes length:hashLength freeWhenDone:NO];
	return [data base64EncodedStringWithOptions:0];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

+ (NSError *)errorOpeningStream:(NSStream *)stream
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:5];
	
	userInfo[NSLocalizedDescriptionKey] = @"Error opening stream";
	userInfo[NSUnderlyingErrorKey] = stream.streamError;
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:1002 userInfo:[userInfo copy]];
}

+ (NSError *)errorReadingStream:(NSStream *)stream
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:5];
	
	userInfo[NSLocalizedDescriptionKey] = @"Error reading stream";
	userInfo[NSUnderlyingErrorKey] = stream.streamError;
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:1003 userInfo:[userInfo copy]];
}

@end
