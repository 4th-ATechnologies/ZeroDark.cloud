#import "ZDCFileReader.h"

#import "CacheFile2CleartextInputStream.h"
#import "CloudFile2CleartextInputStream.h"
#import "ZDCLogging.h"

#import "NSError+POSIX.h"
#import "NSError+S4.h"


#if DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

@implementation ZDCFileReader
{
	NSData *encryptionKey;
	NSInputStream * stream;
}

/**
 * See header file for description.
 */
- (instancetype)initWithCryptoFile:(ZDCCryptoFile *)cryptoFile
{
	return [self initWithFileURL: cryptoFile.fileURL
	                      format: cryptoFile.fileFormat
	               encryptionKey: cryptoFile.encryptionKey
	                 retainToken: cryptoFile.retainToken];
}

/**
 * See header file for description.
 */
- (instancetype)initWithFileURL:(NSURL *)fileURL
                         format:(ZDCCryptoFileFormat)format
                  encryptionKey:(NSData *)inEncryptionKey
                    retainToken:(nullable id)retainToken;
{
	if ((self = [super init]))
	{
		encryptionKey = [inEncryptionKey copy]; // mutable data protection
		
		if (fileURL)
		{
			if (format == ZDCCryptoFileFormat_CacheFile)
			{
				CacheFile2CleartextInputStream *s;
				
				s = [[CacheFile2CleartextInputStream alloc] initWithCacheFileURL:fileURL encryptionKey:encryptionKey];
				s.retainToken = retainToken;
				
				stream = s;
			}
			else if (format == ZDCCryptoFileFormat_CloudFile)
			{
				CloudFile2CleartextInputStream *s;
				
				s = [[CloudFile2CleartextInputStream alloc] initWithCloudFileURL:fileURL encryptionKey:encryptionKey];
				s.retainToken = retainToken;
				
				[s setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
				stream = s;
			}
		}
	}
	return self;
}

- (void)dealloc
{
	[self close];
}

- (NSNumber *)cleartextFileSize
{
	if ([stream isKindOfClass:[CacheFile2CleartextInputStream class]])
	{
		return [(CacheFile2CleartextInputStream *)stream cleartextFileSize];
	}
	if ([stream isKindOfClass:[CloudFile2CleartextInputStream class]])
	{
		return [(CloudFile2CleartextInputStream *)stream cleartextFileSize];
	}
	
	return @(0);
}

/**
 * See header file for description.
 */
- (BOOL)openFileWithError:(NSError **)errorOut
{
	if (stream == nil)
	{
		if (errorOut) *errorOut = [self streamNilError];
		return NO;
	}
	
	if (stream.streamStatus != NSStreamStatusNotOpen)
	{
		// No need to open again
		
		if (errorOut) *errorOut = nil;
		return YES;
	}
	
	[stream open];
	
	NSStreamStatus streamStatus = stream.streamStatus;
	if (streamStatus == NSStreamStatusClosed || streamStatus == NSStreamStatusError)
	{
		NSError *error = stream.streamError;
		if (error == nil) // shouldn't happen, but let's code defensively
		{
			NSString *msg = @"Error opening underlying stream.";
			NSInteger code = 1001;
			
			error = [self errorWithDescription:msg code:code];
		}
		
		if (errorOut) *errorOut = error;
		return NO;
	}
	else
	{
		if (errorOut) *errorOut = nil;
		return YES;
	}
}

/**
 * See header file for description.
 */
- (ssize_t)getBytes:(void *)buffer range:(NSRange)range error:(NSError **)errorOut
{
	if (stream == nil)
	{
		if (errorOut) *errorOut = [self streamNilError];
		return -1;
	}
	
	// Watch out for edge case:
	// Once a normal stream hits EOF, it still allows seeking, but won't allow any more reading.
	// The only way around this is to re-create the underlying stream.
	
	if (stream.streamStatus == NSStreamStatusAtEnd)
	{
		NSInputStream *streamCopy = nil;
		
		if ([stream conformsToProtocol:@protocol(NSCopying)])
		{
			streamCopy = [stream copy];
		}
		
		if (streamCopy == nil)
		{
			NSString *desc = @"Unable to copy underlying stream.";
			NSError *error = [self errorWithDescription:desc code:1002];
			
			if (errorOut) *errorOut = error;
			return -1;
		}
		
		stream = streamCopy;
		[stream open];
		
		if (stream.streamStatus == NSStreamStatusError)
		{
			if (errorOut) *errorOut = stream.streamError;
			return -1;
		}
		
		if ([stream isKindOfClass:[CloudFile2CleartextInputStream class]])
		{
			[stream setProperty:@(ZDCCloudFileSection_Data) forKey:ZDCStreamCloudFileSection];
		}
	}
	
	NSUInteger fileOffset = range.location;
	[stream setProperty:@(fileOffset) forKey:NSStreamFileCurrentOffsetKey];
	
	NSInteger result = [stream read:(uint8_t *)buffer maxLength:range.length];
	
	if (errorOut)
	{
		if (result < 0)
			*errorOut = stream.streamError;
		else
			*errorOut = nil;
	}
	
	return (ssize_t)result;
}

- (void)close
{
	[stream close];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)streamNilError
{
	NSString *msg = @"Unable to open a stream for this file.";
	NSInteger code = 1000;
	
	return [self errorWithDescription:msg code:code];
}

- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

@end
