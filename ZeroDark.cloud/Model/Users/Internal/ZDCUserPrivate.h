/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCUser ()

@property (nonatomic, assign, readwrite) AWSRegion aws_region;
@property (nonatomic, copy, readwrite, nullable) NSString *aws_bucket;

/**
 * A random uuid for the user that doesn't match the user's external userID.
 * This is used to prevent leaking information when storing the user's avatar to disk.
 */
@property (nonatomic, copy, readonly) NSString *random_uuid;

/**
 * A random encryption key used when storing the user's avatar to disk.
 */
@property (nonatomic, copy, readonly) NSData *random_encryptionKey;

@end

NS_ASSUME_NONNULL_END
