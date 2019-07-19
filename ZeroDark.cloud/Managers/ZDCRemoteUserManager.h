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
 * Fetches the ZDCUser from the database. If missing, automatically downloads the user.
 *
 * The download involves several steps:
 * - Fetching the general user information from the ZeroDark servers
 * - Fetching the user's profile (linked social identity information)
 * - Fetching the user's public key
 *
 * @param remoteUserID
 *   The userID of the user to fetch.
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
- (void)fetchRemoteUserWithID:(NSString *)remoteUserID
                  requesterID:(NSString *)localUserID
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
