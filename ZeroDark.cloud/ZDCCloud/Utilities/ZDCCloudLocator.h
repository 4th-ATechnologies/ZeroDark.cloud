/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "ZDCCloudPath.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates all the information required to locate a file in the cloud:
 *
 * - AWS region (e.g. us-west-2)
 * - AWS S3 bucket name
 * - AWS s3 keypath (in standardized/parsed form)
 *
 * Instances of this class are immutable.
 */
@interface ZDCCloudLocator : NSObject <NSCoding, NSCopying>

/**
 * Creates an (immutable) locator instance.
 *
 * @param region
 *   The AWS region where the bucket is located.
 *
 * @param bucket
 *   The name of the AWS S3 bucket.
 *
 * @param cloudPath
 *   The keypath to the file within the S3 bucket.
 */
- (instancetype)initWithRegion:(AWSRegion)region
                        bucket:(NSString *)bucket
                     cloudPath:(ZDCCloudPath *)cloudPath;

/** The AWS region where the S3 bucket is located. */
@property (nonatomic, assign, readonly) AWSRegion region;

/** The name of the AWS S3 bucket. */
@property (nonatomic, copy, readonly) NSString * bucket;

/**
 * Extracts the userID component from the bucket name.
 */
@property (nonatomic, readonly, nullable) NSString *bucketOwner;

/**
 * Represents the keypath to the file within the S3 bucket.
 */
@property (nonatomic, copy, readonly) ZDCCloudPath * cloudPath;

/**
 * Returns a copy with a new cloudPath.
 * I.e. same region, same bucket, new S3 keypath.
 */
- (instancetype)copyWithCloudPath:(ZDCCloudPath *)newCloudPath;

/**
 * Returns a copy with an alternative filename extension.
 * Pass nil to strip the filename extension.
 */
- (instancetype)copyWithFileNameExt:(nullable NSString *)newFileNameExt;

/**
 * Returns YES if the two cloudLocator's are an exact match.
 */
- (BOOL)isEqualToCloudLocator:(ZDCCloudLocator *)another;

/**
 * Returns YES if the two cloudLocator's refer to the same node.
 * That is, everything matches except the filename extension.
 */
- (BOOL)isEqualToCloudLocatorIgnoringExt:(ZDCCloudLocator *)another;

/**
 * Performs a detailed comparison between two cloudLocator's.
 * For example, you could check to see if they belong to the same zAppID, or the same dirPrefix (same "folder").
 */
- (BOOL)isEqualToCloudLocator:(ZDCCloudLocator *)another components:(ZDCCloudPathComponents)components;

@end

NS_ASSUME_NONNULL_END
