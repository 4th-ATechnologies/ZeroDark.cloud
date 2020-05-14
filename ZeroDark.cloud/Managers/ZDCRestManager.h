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
#import "ZDCCloudLocator.h"
#import "ZDCLocalUser.h"
#import "ZDCLocalUserAuth.h"
#import "ZDCMerkleTree.h"
#import "ZDCPublicKey.h"
#import "ZDCUser.h"
#import "ZDCUserBill.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZDCDomain) {
	ZDCDomain_Public,
	ZDCDomain_UserCoop,
	ZDCDomain_UserPartner
};

/**
 * Facilitates access to the REST API of the ZeroDark.cloud servers.
 */
@interface ZDCRestManager : NSObject

#pragma mark API Gateway v0

/**
 * API Gateway URLS have the following form:
 * - https://{apiGatewayID}.execute-api.{region}.amazonaws.com/{stage}
 *
 * This method returns the API Gateway ID that matches the region & stage.
 * 
 * For example: "rsuraaljlh"
 */
- (nullable NSString *)apiGatewayIDV0ForRegion:(AWSRegion)region stage:(NSString *)stage;

/**
 * API Gateway URLS have the following form:
 * - https://{apiGatewayID}.execute-api.{region}.amazonaws.com/{stage}/{path}
 *
 * This method fills out the URL for you, and returns a (configurable) NSURLComponents instance.
 */
- (nullable NSURLComponents *)apiGatewayV0ForRegion:(AWSRegion)region stage:(NSString *)stage path:(NSString *)path;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark API Gateway v1
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * API Gateway URLS have the following form:
 * - https://{apiGatewayID}.execute-api.{region}.amazonaws.com
 *
 * This method returns the API Gateway ID that matches the region & stage.
 *
 * For example: "xx08iqr297"
 */
- (nullable NSString *)apiGatewayIDV1ForRegion:(AWSRegion)region stage:(NSString *)stage;

/**
 * API Gateway URLS have the following form:
 * - https://{apiGatewayID}.execute-api.{region}.amazonaws.com/v1/{domain}/{path}
 *
 * This method fills out the URL for you, and returns a (configurable) NSURLComponents instance.
 */
- (nullable NSURLComponents *)apiGatewayV1ForRegion:(AWSRegion)region
                                              stage:(NSString *)stage
                                             domain:(ZDCDomain)domain
                                               path:(NSString *)path;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches configuration information from the server.
 *
 * This is a JSON file that describes information such as the list of supported social providers.
 */
- (void)fetchCoopConfigWithCompletionQueue:(nullable dispatch_queue_t)completionQueue
                            completionBlock:(void(^)(NSDictionary *_Nullable config,
                                                     NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Account Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Configures the user's account, which includes tasks such as creating the user's bucket.
 *
 * This method is used during user setup & activation.
 * As such, it does not require the given ZDCLocalUser or ZDCLocalUserAuth to be stored in the database.
 *
 * @param localUser
 *   The localUser we're setting up.
 *
 * @param auth
 *   Valid authentication for the localUser.
 *
 * @param treeIDs
 *   A list of treeID's that we're activating for the user.
 *
 * @param completionQueue
 *   The dispatch queue on which to invoke the completionBlock.
 *   If not specified, the main thread is used.
 *
 * @param completionBlock
 *   The block to invoke with the results of the request.
 */
- (void)setupAccountForLocalUser:(ZDCLocalUser *)localUser
                        withAuth:(ZDCLocalUserAuth *)auth
                         treeIDs:(NSArray<NSString*> *)treeIDs
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSString *_Nullable bucket,
														 NSString *_Nullable stage,
                                           NSString *_Nullable syncedSalt,
                                           NSDate *_Nullable activationDate,
                                           NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Registers the given iOS/macOS pushToken with the server.
 *
 * This method is invoked during account setup.
 */
- (void)registerPushTokenForLocalUser:(ZDCLocalUser *)localUser
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSURLResponse *_Nullable response,
                                                           id  _Nullable responseObject,
                                                      NSError *_Nullable error))completion;

/**
 * Unregisters the given iOS/macOS pushToken with the server.
 *
 * This method is invoked:
 * - when deleting a localUser from the device
 * - if we ever receive a push notification for an unknown localUserID
 */
- (void)unregisterPushToken:(NSString *)pushToken
                  forUserID:(NSString *)userID
                     region:(AWSRegion)region
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(nullable void (^)(NSURLResponse *response, NSError *_Nullable error))completion;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Users
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the user's info from the server, which includes:
 * 
 * - region      (NSString)
 * - bucket      (NSString)
 * - stage       (NSString)
 * - created     (NSDate)
 * 
 * Uses ephemeralSessionConfiguration.
 * Does not require the given ZDCLocalUser or ZDCLocalUserAuth to be stored in the database.
 */
- (void)fetchInfoForLocalUser:(ZDCLocalUser *)user
                     withAuth:(ZDCLocalUserAuth *)auth
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(void (^)(NSDictionary *_Nullable response, NSError *_Nullable error))completionBlock;


/**
 * Fetches the remote user's info from the server, which includes:
 *
 * - region (NSString)
 * - bucket (NSString)
**/
- (void)fetchInfoForRemoteUserID:(NSString *)remoteUserID
                     requesterID:(NSString *)localUserID
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSDictionary *_Nullable response, NSError *_Nullable error))completionBlock;

/**
 * Queries the server to see if the given user still exists.
 * Returns NO if the user has been deleted from the system.
 * E.g. user's free trial expired (without becoming a customer), or user stopped paying their bill.
**/
- (void)fetchUserExists:(NSString *)userID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(BOOL exists, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Priv/Pub Key
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Downloads & parses the given user's publicKey file from the server.
 *
 * @param user
 *   The user whose publicKey you wish to fetch.
 *
 * @param localUserID
 *   The localUser with which to perform the HTTP request.
 *
 * @param completionQueue
 *   The dispatch_queue to use when invoking the completionBlock
 *   If you pass nil, the main thread will automatically be used.
 *
 * @param completionBlock
 *   Invoked with the result of the request.
 */
- (void)fetchPubKeyForUser:(ZDCUser *)user
               requesterID:(NSString *)localUserID
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(void (^)(ZDCPublicKey *_Nullable pubKey, NSError *_Nullable error))completionBlock;

/**
 * Attempts to set the user's privateKey/publicKey pair.
 * If the user doesn't already have a set of keys, the server will accept the pair.
 * Otherwise, the server will reject the request, and return the existing pair.
 *
 * - The privKey file is a PBKDF2 wrapped private key (i.e. requires accessKey to decrypt)
 * - The pubKey file is JSON
 * - The files get stored in the root of the user's bucket, and are named ".privKey" & ".pubKey".
 *
 * In terms of S3 permissions:
 * - The ".privKey" file is only readable by the bucket owner
 * - The ".pubKey" file is world-readable
 *
 * This method is used during user setup & activation.
 * As such, it does not require the given ZDCLocalUser or ZDCLocalUserAuth to be stored in the database.
 *
 * @param privKey
 *   Serialzed PBKDF2 wrapped private key (i.e. requires accessKey to decrypt)
 *
 * @param pubKey
 *   Serialized JSON that contains public key information.
 *
 * @param localUser
 *   The localUser for which we should upload the key pairs.
 *
 * @param auth
 *   A valid authentication instance - required to authenticate the request.
 *
 * @param completionQueue
 *   The dispatch_queue to use when invoking the completionBlock
 *   If you pass nil, the main thread will automatically be used.
 *
 * @param completionBlock
 *   Invoked with the result of the request.
 */
- (void)uploadEncryptedPrivKey:(NSData *)privKey
                        pubKey:(NSData *)pubKey
                  forLocalUser:(ZDCLocalUser *)localUser
                      withAuth:(ZDCLocalUserAuth *)auth
               completionQueue:(nullable dispatch_queue_t)completionQueue
               completionBlock:(void (^)(NSData *_Nullable data,
                                         NSURLResponse *_Nullable response,
                                         NSError *_Nullable error))completionBlock;

/**
 * Update the publicKey for the user.
 *
 * This method is used when updating the list of attached social identities.
 * The list is signed by the private key, and added to the pubKey JSON file.
 * 
 * Note:
 *   The server allows us to update this (signed) list,
 *   but doesn't allow us to actually change the publicKey value.
 */
- (void)updatePubKeySigs:(NSData *)pubKey
          forLocalUserID:(NSString *)localUserID
         completionQueue:(nullable dispatch_queue_t)completionQueue
         completionBlock:(void (^)(NSURLResponse *_Nullable response,
                                              id  _Nullable responseObject,
                                         NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sync
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Multipart-complete proxy, facilitated by ZeroDark server.
 *
 * Sending a multipart complete command directly to the server is problematic.
 * If multipart was being used, the assumption is that the file is pretty big,
 * and it took a considerable amount of time to upload to the server.
 * And you only get one shot with S3's multipart complete command.
 * That is, invoking it a second time will result in an error code from the server.
 * And the error code is indistinguishable from other errors, such as an expired multipart.
 *
 * This edge case doesn't sit well with us, so we take a different approch.
 * We use the server to cache multipart complete requests,
 * so that we can get the same response code for subsequent requests.
 */
- (NSMutableURLRequest *)multipartComplete:(NSString *)key
                              withUploadID:(NSString *)uploadID
                                     eTags:(NSArray<NSString*> *)eTags
                                  inBucket:(NSString *)bucket
                                    region:(AWSRegion)region
                            forLocalUserID:(NSString *)localUserID
                                  withAuth:(ZDCLocalUserAuth *)auth;

/**
 * The permissions on S3 only allow the bucket's owner to list the items within the bucket.
 * That is, only Alice has permission to list all the items in her bucket. Bob does not.
 * So if Alice shares a directory with Bob, then Bob needs some mechanism to get the list of items
 * within Alice's bucket. That mechanism is the server's list-proxy service, which will return
 * a list of item's within Alice's bucket for which Bob has permission.
 *
 * This list-proxy request is rooted at a particular node.
 * So Bob must first know the node path for which he has read permissions.
 * And the server will then recursively enumerate the sub-nodes for which Bob has read access.
 */
- (NSMutableURLRequest *)listProxyWithPaths:(NSArray<NSString *> *)paths
                                     treeID:(NSString *)treeID
                                     pullID:(NSString *)pullID
                             continuationID:(nullable NSString *)continuationID
                         continuationOffset:(nullable NSNumber *)continuationOffset
                          continuationToken:(nullable NSString *)continuationToken
                                   inBucket:(NSString *)bucket
                                     region:(AWSRegion)region
                             forLocalUserID:(NSString *)localUserID
                                   withAuth:(ZDCLocalUserAuth *)auth;

/**
 * Used during grafting if the target node cannot be located.
 *
 * In some cases, a node may get renamed or moved, which results in its cloudPath changing as well.
 * When this happens, previously issued collaboration requests would contain an out-of-date cloudPath.
 * However, the server keeps an partial index that maps from cloudID to cloudPath.
 * So the client can ask the server to lookup the correct cloudPath.
 *
 * The server will return a result if:
 * - the node still exists in the given bucket
 * - the requester has read-permission for the node
 *
 * @param cloudID
 *   The correct cloudID for the target node.
 *
 * @param bucket
 *   The correct bucket that contains the target node.
 *
 * @param region
 *   The correct region for the bucket.
 *
 * @param localUserID
 *   The localUserID that will be used to send the request.
 *   The request will be authenticated with this user's information.
 *
 * @param completionQueue
 *   The dispatch queue on which to invoke the completion block.
 *   If unspecified, the main thread is used.
 *
 * @param completionBlock
 *   Invoked with the raw response from the server.
 */
- (void)lostAndFound:(NSString *)cloudID
              bucket:(NSString *)bucket
              region:(AWSRegion)region
         requesterID:(NSString *)localUserID
     completionQueue:(nullable dispatch_queue_t)completionQueue
     completionBlock:(void (^)(NSURLResponse *response,
                                id  _Nullable responseObject,
                           NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth0
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the user's co-op profile.
 *
 * This information includes:
 * - userID
 * - user's region
 * - user's bucket
 * - list of linked identities
 *
 * If the given userID matches the localUserID, then the user's FULL profile is retrieved.
 * Otherwise the user's FILTERED profile is retrieved, which contains only a subset of the full profile.
 */
- (void)fetchAuth0Profile:(NSString *)userID
              requesterID:(NSString *)localUserID
          completionQueue:(nullable dispatch_queue_t)completionQueue
          completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completion;

/**
 * User search API.
 *
 * @param queryString
 *   The search query.
 *
 * @param provider
 *   Pass a non-nil value if you want to limit your search query to a specific provider.
 *   For example, you could search only for matches within Facebook.
 *   Pass nil if you'd like to search across all providers.
 *
 * @param localUserID
 *   A local user is required to perform the search.
 *   The user's authentication info will be used to sign the request.
 *
 * @param completionQueue
 *   The dispatch queue on which to invoke the completionBlock.
 *   If non is specified, the main thread will be used.
 *
 * @param completionBlock
 *   Will be invoked with the result.
 */
- (void)searchUserMatch:(NSString *)queryString
               provider:(nullable NSString *)provider
                 treeID:(NSString *)treeID
            requesterID:(NSString *)localUserID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completionBlock;

/**
 * REST API to link a normal auth0 identity to a recovery profile.
 *
 * Known response codes:
 * - 200 : OK
 *         The linking was successful.
 *
 * - 400 : Bad request
 *         Detailed information will be in response.
 *
 * - 401 : Unauthorized
 *         Permissions problem.
 *
 * - 404 : Not found
 *         Either the recovery or standard auth_id doesn't appear to exist.
 */
- (void)linkAuth0ID:(NSString *)linkAuth0ID
       toRecoveryID:(NSString *)recoveryAuth0ID
            forUser:(NSString *)localUserID
    completionQueue:(nullable dispatch_queue_t)completionQueue
    completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completion;

/**
 * Uses the server API to link a secondary auth0 identity to the user's auth0 profile.
 * 
 * - If response is non-nil:
 *   - response[@"statusCode"] contains an HTTP statusCode
 *
 *     - 200 - OK
 *       The linking was successful.
 *     
 *     - 400 - Bad request
 *       User doesn't own primary auth0_id, or
 *       secondary auth0_id is already linked to another account.
 *
 *     - 401 - Unauthorized
 *       Permissions problem.
 *       
 *     - 404 - Not found
 *       Either the primary or secondary auth_id doesn't exist.
 */
- (void)linkAuth0ID:(NSString *)linkAuth0ID
            forUser:(ZDCLocalUser *)user
    completionQueue:(nullable dispatch_queue_t)completionQueue
    completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completion;

/**
 * Uses the server API to unlink a secondary auth0 identity from the user's auth0 profile.
 */
- (void)unlinkAuth0ID:(NSString *)unlinkAuth0ID
              forUser:(ZDCLocalUser *)user
      completionQueue:(nullable dispatch_queue_t)completionQueue
      completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completion;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Billing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Queries the server to see if the user has transitioned from "free user" to "paying customer".
 * 
 * @note The server also sends a push notification for this change.
 */
- (void)fetchIsCustomer:(NSString *)localUserID
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(BOOL isPayingCustomer, NSError *_Nullable error))completionBlock;

/**
 * Queries the server for the current balance of the user.
 *
 * Note: The server also sends a push notification for this change.
 * But if push notifications are disabled, this method should be consulted on-demand.
 */
- (void)fetchCurrentBalance:(NSString *)localUserID
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(double credit, NSError *_Nullable error))completionBlock;

/**
 * Queries the server for the user's billing info.
 *
 * The result will include billing & usage information for the user's account,
 * as well as detailed information on a per-app basis.
 */
- (void)fetchCurrentBilling:(NSString *)localUserID
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(ZDCUserBill *_Nullable bill, NSError *_Nullable error))completionBlock;

/**
 * Queries the server for the user's billing info.
 *
 * The result will include billing & usage information for the user's account,
 * as well as detailed information on a per-app basis.
 */
- (void)fetchPreviousBilling:(NSString *)localUserID
                    withYear:(NSInteger)year
                       month:(NSInteger)month
             completionQueue:(nullable dispatch_queue_t)completionQueue
             completionBlock:(void (^)(ZDCUserBill *_Nullable bill, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Purchases
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)productPurchasedByUser:(NSString *)localUserID
             productIdentifier:(NSString *)productIdentifier
         transactionIdentifier:(NSString *)transactionIdentifier
               appStoreReceipt:(NSData *)appStoreReceipt
               completionQueue:(nullable dispatch_queue_t)completionQueue
               completionBlock:(void (^)(NSURLResponse *response,
                                         id _Nullable responseObject,
                                         NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Blockchain
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Downloads the merkle tree JSON file from the server.
 * This is part of the flow of verifying a user's publicKey:
 *
 * - Query the Ethereum blockchain for a specific userID
 * - If the response includes a merkleTreeRoot, then
 * - Download the corresponding merkleTreeFile
 * - Verify the publicKey in the merkleTreeFile matches what you expect
 * - Verify the merkleTreeFile itself
 *
 * More detailed information on how this works can be found here:
 * https://zerodarkcloud.readthedocs.io/en/latest/overview/ethereum/
 *
 * @param merkleTreeRoot
 *   A merkleTreeRoot value, as returned from the blockchain.
 *   This is typically a sha256 string, in hex format. For example:
 *   "0xcd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1"
 *
 * @param completionQueue
 *   The dispatch_queue on which to invoke the completionBlock.
 *
 * @param completionBlock
 *   Invoked with the results of the query.
 *   If the merkleTree parameter is non-nil, you'll want to (1) verify the included publicKey info,
 *   and (2) verify the merkleTree file itself (via `merkleTree.hashAndVerify()`).
 */
- (void)fetchMerkleTreeFile:(NSString *)merkleTreeRoot
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSURLResponse *_Nullable response,
                                      ZDCMerkleTree *_Nullable merkleTree,
                                      NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
