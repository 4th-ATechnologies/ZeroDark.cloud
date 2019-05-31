#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Utility methods for calcuating the signature for a payload.
 * Payload == HTTP request body.
 *
 * The payload signature is needed when calculating the request signature.
 * @see `AWSSignature`
 */
@interface AWSPayload : NSObject

/**
 * Returns the signature (SHA256 hash in lowercase hexadecimal) for the given payload data.
 */
+ (NSString *)signatureForPayload:(NSData *)data;

/**
 * Calculates the signature (SHA256 hash in lowercase hexadecimal) for the given file.
 *
 * @param fileURL
 *   A reference to the file that will be the body of the HTTP request (the payload).
 *
 * @param completionQueue
 *   The dispatch_block on which to invoke the completionQueue.
 *   If nil, the main thread will be used.
 *
 * @param completionBlock
 *   The block to invoke upon completion.
 *   The block will be invoked asynchronously on the completionQueue.
 */
+ (void)signatureForPayloadWithFile:(NSURL *)fileURL
                    completionQueue:(nullable dispatch_queue_t)completionQueue
                    completionBlock:(void (^)(NSString *_Nullable sha256HashInLowercaseHex, NSError *_Nullable error))completionBlock;

/**
 * Calculates the signature (SHA256 hash in lowercase hexadecimal) for the given stream.
 *
 * @param stream
 *   A stream that representes the body of the HTTP request (the payload).
 *
 * @param completionQueue
 *   The dispatch_block on which to invoke the completionQueue.
 *   If nil, the main thread will be used.
 *
 * @param completionBlock
 *   The block to invoke upon completion.
 *   The block will be invoked asynchronously on the completionQueue.
**/
+ (void)signatureForPayloadWithStream:(NSInputStream *)stream
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSString *_Nullable sha256HashInLowercaseHex, NSError *_Nullable error))completionBlock;

#pragma mark Legacy

/**
 * There are some API's which still require a "Content-MD5" header.
 * For example: S3 Delete Multiple Objects
 */
+ (NSData *)rawMD5HashForPayload:(NSData *)data;

/**
 * There are some API's which still require a "Content-MD5" header.
 * For example: S3 Delete Multiple Objects
 *
 * The hash is returned as a base64 encoded string.
 */
+ (NSString *)md5HashForPayload:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
