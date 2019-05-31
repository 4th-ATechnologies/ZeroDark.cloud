#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "AWSServices.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Utility class to calculate AWS Signature's (v4).
 */
@interface AWSSignature : NSObject

/**
 * The the workflow for most AWS requests is this:
 * 
 * - Create a mutable request
 * - Modify the request as needed
 * - Sign the request using one of the methods below
 * - Send the request to Amazon
 *
 * @important You MUST NOT modify the request after it's been signed.
 *            Doing so will invalidate the signature, and AWS will then reject the request.
 *
 * @param request
 *   The request to sign.
 *   The request may optionally contain an HTTPBody.
 *
 * @param region
 *   The region to which the request will be sent
 *
 * @param service
 *   The service which will be handling the request
 *
 * @param accessKeyID
 *   Component of AWS credentials
 *
 * @param secret
 *   Component of AWS credentials
 *
 * @param session
 *   Component of AWS credentials (may be nil for IAM registered users)
 *
 * @return YES if the signature was added to the request.
 *         NO if one of the parameters was invalid.
 */
+ (BOOL)signRequest:(NSMutableURLRequest *)request
         withRegion:(AWSRegion)region
            service:(AWSService)service
        accessKeyID:(NSString *)accessKeyID
             secret:(NSString *)secret
            session:(nullable NSString *)session;

/**
 * The the workflow for most AWS requests is this:
 *
 * - Create a mutable request
 * - Modify the request as needed
 * - Sign the request using one of the methods below
 * - Send the request to Amazon
 *
 * @important You MUST NOT modify the request after it's been signed.
 *            Doing so will invalidate the signature, and AWS will then reject the request.
 *
 * @param request
 *   The request to sign.
 *   The request may optionally contain an HTTPBody (but the payloadSig parameter takes precedence).
 *
 * @param region
 *   The region to which the request will be sent
 *
 * @param service
 *   The service which will be handling the request
 *
 * @param accessKeyID
 *   Component of AWS credentials
 *
 * @param secret
 *   Component of AWS credentials
 *
 * @param session
 *   Component of AWS credentials (may be nil for IAM registered users)
 *
 * @return YES if the signature was added to the request.
 *         NO if one of the parameters was invalid.
 */
+ (BOOL)signRequest:(NSMutableURLRequest *)request
         withRegion:(AWSRegion)region
            service:(AWSService)service
        accessKeyID:(NSString *)accessKeyID
             secret:(NSString *)secret
            session:(nullable NSString *)session
         payloadSig:(nullable NSString *)sha256HashInLowercaseHex;

/**
 * The 'Content-Type' header is required in order for some requests to work properly.
 * The code is cleanest when this is done automatically, if needed, within the signature code.
 *
 * However, although this is beneficial for real world code, it makes it difficult for unit testing.
 * That is, there are several examples from Amazon where the example request doesn't contain this header.
 * So we make it possible to disable the functionality, primarily for unit testing purposes.
 */
+ (void)setContentTypeHeaderAutomatically:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END
