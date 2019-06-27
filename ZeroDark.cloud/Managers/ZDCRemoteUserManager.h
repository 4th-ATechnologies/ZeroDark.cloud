/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "ZDCUser.h"
#import "ZDCPublicKey.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The RemoteUserManager handles downloading user's & fetching their public key.
 */
@interface ZDCRemoteUserManager : NSObject

/**
 * Attempts to fetch & creates a ZDCUser instance for the given userID.
 * This involves several steps:
 * - Fetching the general user information from the ZeroDark servers
 * - Fetching the auth0 profile (linked social identity information)
 * - Fetching the user's public key
 *
 * @param remoteUserID
 *   The userID of the user to fetch & create.
 *
 * @param localUserID
 *   The localUserID who's making the request.
 *   The network requests need to come from a localUser, as they need to be authenticated.
 *
 * @param completionQueue
 *   The dispatch_queue on which to invoke the completionBlock.
 *   If nil, the main thread will automatically be used.
 *
 * @param completionBlock
 *   The block to invoke when the request is completed.
 */
- (void)createRemoteUserWithID:(NSString *)remoteUserID
                   requesterID:(NSString *)localUserID
               completionQueue:(nullable dispatch_queue_t)completionQueue
               completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock;

/**
 * Write some doocumentation here
 *
 */

- (void)fetchPublicKeyForRemoteUserID:(NSString *)inRemoteUserID
                          requesterID:(NSString *)inLocalUserID
                      completionQueue:(nullable dispatch_queue_t)inCompletionQueue
                      completionBlock:(void (^)(ZDCPublicKey *_Nullable pubKey, NSError *_Nullable error))inCompletionBlock;
@end

NS_ASSUME_NONNULL_END
