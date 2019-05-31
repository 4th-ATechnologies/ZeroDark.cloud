/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCUser.h"

@interface ZDCUser ()

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
