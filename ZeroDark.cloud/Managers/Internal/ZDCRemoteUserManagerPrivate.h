/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCRemoteUserManager.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCRemoteUserManager (Private)

/**
 * Standard initialization from ZeroDarkCloud, called during database unlock.
 */
- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Used by search UI, to pre-fetch public keys for users that might not exist in the database.
 */
- (void)fetchPublicKeyForRemoteUserID:(NSString *)remoteUserID
                          requesterID:(NSString *)localUserID
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(ZDCPublicKey *_Nullable pubKey, NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
