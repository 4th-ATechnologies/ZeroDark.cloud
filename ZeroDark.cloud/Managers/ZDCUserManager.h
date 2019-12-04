/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "ZDCUser.h"
#import "ZDCPublicKey.h"

@class ZDCUserDisplay;

NS_ASSUME_NONNULL_BEGIN

/**
 * The UserManager handles various tasks involving ZDCUser's.
 *
 * @note There is also a LocalUserManager, which handles various tasks specific to ZDCLocalUser's.
 */
@interface ZDCUserManager : NSObject

/**
 * Fetches the ZDCUser from the database. If missing, automatically downloads the user.
 *
 * The download involves the following steps:
 * - Fetching the user's general information (region & bucket)
 * - Fetching the user's linked identities
 * - Fetching the user's public key
 * - Checking the user's public key against the blockchain
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
- (void)fetchUserWithID:(NSString *)remoteUserID
            requesterID:(NSString *)localUserID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock;

/**
 * In some situations, a user's public key may be missing.
 *
 * In general, the framework handles this aspect for you automatically.
 * That is, if the framework needs the user's publicKey, it will fetch it automatically.
 * However, you can use this method to fetch it manually as needed.
 *
 * The download involves the following steps:
 * - Fetching the user's public key
 * - Checking the user's public key against the blockchain
 */
- (void)fetchPublicKey:(ZDCUser *)remoteUser
           requesterID:(NSString *)localUserID
       completionQueue:(nullable dispatch_queue_t)completionQueue
       completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock;

/**
 * Refreshes the user's list of linked identities.
 */
- (void)refreshIdentities:(ZDCUser *)remoteUser
              requesterID:(NSString *)localUserID
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock;

/**
 * Checks the blockchain for proof of the user's publicKey.
 *
 * If the blockchain contains a proof for this user,
 * the system performs the calculations to verify the validity of the locally stored publicKey.
 */
- (void)recheckBlockchain:(ZDCUser *)remoteUser
              requesterID:(NSString *)localUserID
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(nullable void (^)(ZDCUser *_Nullable remoteUser, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Given an array of ZDCUser's, this will produce an array of unambiguous displayNames.
 *
 * For example, if there are 2 users with the displayName of "Vinnie Moscaritolo",
 * then this method will attempt to disambiguate them by appending information to the displayName.
 *
 * ```
 * [
 *   {
 *     displayName = "Vinnie Moscaritolo (Amazon)";
 *     userID = 641ihdfw7qf5pj78pfxbunwkkwonu5rg;
 *   },
 *   {
 *     displayName = "Vinnie Moscaritolo (Facebook)";
 *     userID = 7gzeud1d9iam5b1d31j8sk6pnnktosut;
 *   }
 * ]
 * ```
*/
- (NSArray<ZDCUserDisplay*> *)sortedUnambiguousNamesForUsers:(NSArray<ZDCUser*> *)users;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCUserDisplay : NSObject

@property (nonatomic, readonly) NSString *userID;
@property (nonatomic, readonly) NSString *displayName;

@end

NS_ASSUME_NONNULL_END
