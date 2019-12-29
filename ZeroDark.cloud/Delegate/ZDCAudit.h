/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * You're always welcome to audit your user data stored in the cloud.
 *
 * You can find instructions in the docs:
 * https://zerodarkcloud.readthedocs.io/en/latest/overview/audit/
 *
 * This class exposes the AWS credentials needed to inspect the cloud.
 */
@interface ZDCAudit : NSObject

/**
 * The target of the audit.
 */
@property (nonatomic, copy, readonly) NSString *localUserID;

/**
 * The name of the region in which the S3 belongs.
 * For example: "us-west-2" or "eu-west-1"
 */
@property (nonatomic, copy, readonly) NSString *aws_region;

/**
 * The name of the bucket in AWS S3.
 */
@property (nonatomic, copy, readonly) NSString *aws_bucket;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite) NSString *aws_accessKeyID;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite) NSString * aws_secret;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite) NSString * aws_session;

/**
 * The AWS credentials are only valid for a short period of time. (usualy just a few hours)
 * This property tells us when they expire.
 */
@property (nonatomic, copy, readwrite) NSDate * aws_expiration;

@end

NS_ASSUME_NONNULL_END
