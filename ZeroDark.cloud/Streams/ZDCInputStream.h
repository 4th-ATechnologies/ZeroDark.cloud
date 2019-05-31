#import <Foundation/Foundation.h>

/**
 * This property is available for some streams.
 * To check for support, see the `-supportsFileMinMaxOffset` method.
 * If supported, you can read/write the value
 * via `-[NSInputStream propertyForKey:]` & `-[NSInputStream setProperty:forKey:]`.
 *
 * When `ZDCStreamFileMinOffset` is set, the stream will seek to the given offset.
 * If the stream is open, the seek will occur immediately.
 * If the stream isn't open, the seek will occur when the stream is opened.
 *
 * The value is in bytes.
 * The default value is nil, meaning there is no min offset.
 *
 * - Setting this property will affect the NSStreamFileCurrentOffset,
 *   if the currentOffset is less than the minOffset.
 * - If you explicitly set ZDCStreamFileMaxOffset to a value smaller than ZDCStreamFileMinOffset,
 *   then the ZDCStreamFileMinOffset property gets set to nil.
 * - If you explicitly set NSStreamFileCurrentOffset to a value smaller than ZDCStreamFileMinOffset,
 *   then the ZDCStreamFileMinOffset property gets set to nil.
 *
 * @see NSStreamFileCurrentOffset
 * @see `ZDCStreamFileMaxOffset`
 *
 * @note If you copy a stream, this value gets copied as well.
 */
extern NSString *const ZDCStreamFileMinOffset;

/**
 * This property is available for some streams.
 * To check for support, see the `-supportsFileMinMaxOffset` method.
 * If supported, you can read/write the value
 * via `-[NSInputStream propertyForKey:]` & `-[NSInputStream setProperty:forKey:]`.
 *
 * When `ZDCStreamFileMaxOffset` is set, the stream will automatically stop reading (report EOF)
 * once it reaches the given offset.
 * 
 * The value is in bytes.
 * The default value is nil, meaning there is no max offset.
 *
 * - Setting this property will not affect the NSStreamFileCurrentOffset.
 *   If the currentOffset is greater than maxOffset, then EOF will be reported on the next read.
 * - If you explicitly set ZDCStreamFileMinOffset to a value bigger than ZDCStreamFileMaxOffset,
 *   then the ZDCStreamFileMaxOffset property gets set to nil.
 * - If you explicitly set NSStreamFileCurrentOffset to a value bigger than ZDCStreamFileMaxOffset,
 *   then the ZDCStreamFileMaxOffset property gets set to nil.
 * 
 * @see NSStreamFileCurrentOffset
 * @see `ZDCStreamFileMinOffset`
 *
 * @note If you copy a stream, this value gets copied as well.
 */
extern NSString *const ZDCStreamFileMaxOffset;

/**
 * This property is available for some streams.
 * To check for support, see the `supportsEOFOnWouldBlock` method.
 *
 * This property is used via the `propertyForKey` & `setProperty:forKey:` methods.
 *
 * In some scenarios a blocking read is undesireable.
 * The caller wants to read what's available, but doesn't mind if there's no data available currently.
 * However this is difficult to achieve for crypto streams because of 2 reasons:
 *
 * First, the encryption/decryption system uses a block cipher.
 * This means we're unable to produce output until we've read at least encryptionKey.length bytes.
 * However, the underlying stream may have less than encryptionKey.length bytes available for us.
 *
 * Second, the NSStream API is quite limited.
 * That is, when `read:maxLength:` is called, only 3 results are officially documented:
 *
 * > A positive number indicates the number of bytes read.
 * > 0 indicates that the end of the buffer was reached.
 * > -1 means that the operation failed; more information about the error can be obtained with streamError.
 *
 * This property allows you to say:
 *
 *   "If you find yourself in a situation where you would block because the underlying stream
 *    doesn't have enough data for you, then just return 0. I will check streamStatus to see
 *    if you actually meant EOF, or if you're just telling me that you'd block."
 */
extern NSString *const ZDCStreamReturnEOFOnWouldBlock;

/**
 * This error code is used when an unexpected cleartext file size is encountered.
 */
extern NSInteger const ZDCStreamUnexpectedFileSize;

/**
 * ZDCInputStream is an abstract NSInputStream that's designed to be subclassed.
 * 
 * Its benefit is that it automatically handles the NSRunLoop/CFRunLoop stuff.
 * That is, it makes it easier to plug a custom NSInputStream into an NSRunLoop or NSURLSessionTask.
 */
@interface ZDCInputStream : NSInputStream <NSStreamDelegate> {
@protected
	
	/** The underlying stream. Exposed to outside world via `underlyingInputStream` (readonly) property. */
	NSInputStream *inputStream;
	
	/** Set this when streamStatus changes. Then use `sendEvent:` if needed.  */
	NSStreamStatus streamStatus;
	
	/** Set this when an error occurs. Then use `sendEvent:` if needed. */
	NSError *      streamError;
	
	/** Every stream has a delegate */
	__weak id <NSStreamDelegate> delegate;
	
	/**
	 * Direct access to configured value.
	 * @see ZDCStreamFileMinOffset
	 * @see supportsFileMinMaxOffset
	 */
	NSNumber *fileMinOffset;
	
	/**
	 * Direct access to configured value.
	 * @see ZDCStreamFileMaxOffset
	 * @see supportsFileMinMaxOffset
	 */
	NSNumber *fileMaxOffset;
	
	/**
	 * Direct access to configured value.
	 * @see ZDCStreamReturnEOFOnWouldBlock
	 * @see supportsEOFOnWouldBlock
	 */
	NSNumber *returnEOFOnWouldBlock;
}

/**
 * The underlying stream that's powering this stream.
 *
 * ZDCInputStream's may have multiple layers of stream / conversions.
 * You can use this property to peel back the layers.
 */
@property (nonatomic, readonly) NSInputStream *underlyingInputStream;

/**
 * The retainToken from CacheManager.
 * Set this property to prevent the CacheManager from deleting the file before we can open it.
 */
@property (nonatomic, strong, readwrite) id retainToken;

/**
 * Subclasses should return YES if the `ZDCStreamFileMinOffset` & `ZDCStreamFileMaxOffset` properties are supported.
 * Otherwise ZDCInputStream will refuse to set them, and return NO in `setProperty:forKey:`.
 */
- (BOOL)supportsFileMinMaxOffset;

/**
 * Subclasses should return YES if the `ZDCStreamReturnEOFOnWouldBlock` property is supported.
 * Otherwise ZDCInputStream will refuse to set it, and will return NO in `setProperty:forKey:`.
 */
- (BOOL)supportsEOFOnWouldBlock;

@end
