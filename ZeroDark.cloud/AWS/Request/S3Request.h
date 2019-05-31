#import <Foundation/Foundation.h>

#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Simple utility class to help create S3 requests.
 */
@interface S3Request : NSObject

#pragma mark Bucket Requests

/**
 * Generates request for listing the contents of a bucket.
 *
 * AWS Docs: https://docs.aws.amazon.com/AmazonS3/latest/API/v2-RESTBucketGET.html
 *
 * @param bucket
 *   The name of the bucket.
 *
 * @param region
 *   The region in which the bucket resides.
 *
 * @param queryItems
 *   Optional list of query items to include with the request.
 *
 * @param outUrlComponents
 *   The NSURLComponents instance that was used to create the returned request.
 *
 * @return A mutable request, ready to be signed (via AWSSignature class).
 */
+ (NSMutableURLRequest *)getBucket:(NSString *)bucket
                          inRegion:(AWSRegion)region
                    withQueryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
                  outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;


#pragma mark Object Requests

+ (NSMutableURLRequest *)headObject:(NSString *)key
                           inBucket:(NSString *)bucket
                             region:(AWSRegion)region
						 outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)getObject:(NSString *)key
                          inBucket:(NSString *)bucket
                            region:(AWSRegion)region
                  outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)putObject:(NSString *)key
                          inBucket:(NSString *)bucket
                            region:(AWSRegion)region
                  outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)deleteObject:(NSString *)key
                             inBucket:(NSString *)bucket
                               region:(AWSRegion)region
                     outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)multiDeleteObjects:(NSArray<NSString *> *)keys
											  inBucket:(NSString *)bucket
												 region:(AWSRegion)region
                           outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)copyObject:(NSString *)srcPath
                      toDestination:(NSString *)dstPath
                           inBucket:(NSString *)bucket
                             region:(AWSRegion)region
                   outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;


#pragma mark Multipart Uploads

+ (NSMutableURLRequest *)multipartInitiate:(NSString *)key
                                  inBucket:(NSString *)bucket
                                    region:(AWSRegion)region
                          outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)multipartUpload:(NSString *)key
                            withUploadID:(NSString *)uploadID
                                    part:(NSUInteger)partNumber
                                inBucket:(NSString *)bucket
                                  region:(AWSRegion)region
                        outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)multipartComplete:(NSString *)key
                              withUploadID:(NSString *)uploadID
                                     eTags:(NSArray<NSString*> *)eTags
                                  inBucket:(NSString *)bucket
                                    region:(AWSRegion)region
                          outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

+ (NSMutableURLRequest *)multipartAbort:(NSString *)key
                           withUploadID:(NSString *)uploadID
                               inBucket:(NSString *)bucket
                                 region:(AWSRegion)region
                       outUrlComponents:(NSURLComponents *_Nonnull *_Nullable)outUrlComponents;

@end

NS_ASSUME_NONNULL_END
