#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "ZDCLocalUser.h"
#import "ZDCLocalUserAuth.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Facilitates access to the REST API of the ZeroDark.cloud server.
 */
@interface ZDCWebManager : NSObject

/**
 * API Gateway URLS have the following form:
 * - https://[apiGatewayID].execute-api.[region].amazonaws.com/[stage]
 *
 * This method returns the API Gateway ID that matches the region & stage.
 * 
 * E.g.: rsuraaljlh
 */
- (nullable NSString *)apiGatewayIDForRegion:(AWSRegion)region stage:(NSString *)stage;

/**
 * API Gateway URLS have the following form:
 * - https://[apiGatewayID].execute-api.[region].amazonaws.com/[stage]
 *
 * This method fills out the URL for you, and returns a (configurable) NSURLComponents instance.
 * 
 * Your path property should NOT include the stage component.
 * This will be added for you automatically.
 */
- (nullable NSURLComponents *)apiGatewayForRegion:(AWSRegion)region stage:(NSString *)stage path:(NSString *)path;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches ID4 configuration information from the server.
 *
 * This is a JSON file that describes information such as the list of supported social providers.
 */
- (void)fetchConfigWithCompletionQueue:(nullable dispatch_queue_t)completionQueue
                       completionBlock:(void(^)(NSDictionary *_Nullable config,
                                                NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Account Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Configures the user's account, which includes tasks such as creating the user's bucket.
 *
 * Does not require the given ZDCLocalUser or ZDCLocalUserAuth to be stored in the database.
 *
 * @param localUser
 *   The localUser we're setting up. (Not required to be stored in the database.)
 *
 * @param auth
 *   Valid authentication for the localUser. (Not required to be stored in the database.)
 *
 * @param zAppIDs
 *   A list of zAppID's that we're activating for the user.
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
                         zAppIDs:(NSArray<NSString*> *)zAppIDs
                 completionQueue:(nullable dispatch_queue_t)completionQueue
                 completionBlock:(void (^)(NSString *_Nullable bucket,
														 NSString *_Nullable stage,
                                           NSString *_Nullable syncedSalt,
                                           NSDate *_Nullable activationDate,
                                           NSError *_Nullable error))completionBlock;


/**
 * Documentation ?
**/
- (void)updateMetaDataForLocalUser:(ZDCLocalUser *)user
                          metaData:(NSDictionary*)metaData
                   completionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(NSDictionary *_Nullable response,
                                             NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Registers iOS/macOS pushtoken with the server.
 *
 * Invoke this method during account setup.
**/
- (void)registerPushTokenForLocalUser:(ZDCLocalUser *)localUser
                      completionQueue:(nullable dispatch_queue_t)completionQueue
                      completionBlock:(void (^)(NSURLResponse *_Nullable response,
                                                id _Nullable responseObject,
                                                NSError *_Nullable error))completion;

/**
 * Unregister iOS/macOS pushtoken with the server.
 *
 * Invoke this method:
 * - when deleting a localUser from the device
 * - if you ever receive a push notification for an unknown localUserID
**/
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
**/
- (void)fetchInfoForLocalUser:(ZDCLocalUser *)user
                     withAuth:(ZDCLocalUserAuth *)auth
              completionQueue:(nullable dispatch_queue_t)completionQueue
              completionBlock:(void (^)(NSDictionary *_Nullable response, NSError *_Nullable error))completionBlock;


/**
 * Documentation ?
**/
- (void)fetchAuth0ProfileForLocalUserID:(NSString*) localUserID
					  completionQueue:(dispatch_queue_t)completionQueue
					  completionBlock:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionBlock;

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
 * Use's server API for atomic upload of priv/pub key pair.
 *
 * - The privKey data should be a PBKDF2 wrapped private key (requires access key to unlock).
 *   The privKey file is only readable by the owner.
 * - The pubKey is JSON, and is world-readable.
 * - The files are in the root of the user's bucket, and are named ".privKey" & ".pubKey".
 *
 * This method is used during user setup & activation.
 * As such, it does not require the given ZDCLocalUser or ZDCLocalUserAuth to be stored in the database.
**/
- (void)uploadPrivKey:(NSData *)privKey
               pubKey:(NSData *)pubKey
         forLocalUser:(ZDCLocalUser *)user
             withAuth:(ZDCLocalUserAuth *)auth
      completionQueue:(nullable dispatch_queue_t)completionQueue
      completionBlock:(void (^)(NSData *_Nullable data,
                                NSURLResponse *_Nullable response,
                                NSError *_Nullable error))completionBlock;

/**
 * Atomically update the existing the priv and pub Key file to the user's bucket & region.
 *
 * This method is used when updating the social IDs.
**/
- (void)updatePrivKey:(NSData *)privKey
               pubKey:(NSData *)pubKey
       forLocalUserID:(NSString *)localUserID
      completionQueue:(nullable dispatch_queue_t)completionQueue
      completionBlock:(void (^)(NSURLResponse *_Nullable response, id _Nullable responseObject, NSError *_Nullable error))completionBlock;

#pragma mark Avatar

/**
 * Updates a user's avatar on the server, either by uploading a new avatar or deleting whatever is there.
 *
 * This only works for non-social identities.
 * That is, a user can link multiple identities to their account, including Facebook, LinkedIn, etc.
 * All of these social identities (such as Facebook) have their own system for managing avatars.
 * However, the user is also allowed to create a "traditional" account using only a username/password.
 * This traditional account is referred to as a non-social account.
 * And it's these non-social accounts that this method is designed for.
 * It allows the user to associate an avatar with the non-social account.
 *
 * @param avatarData
 *   The raw image data (serialized in PNG, JPEG, or some other commonly supported image format).
 *   You're encouraged to stick with image formats that will be supported on every major OS.
 *
 * @param contentType
 *   The HTTP-style "Content-Type" for the image data.
 *   Common values include "image/png", "image/jpg", etc.
 *
 * @param previousETag
 *   The server will only allow you to update the avatar if you know the previous eTag value.
 *   This acts as a simple sync mechanism, and ensures that your
 *   app is up-to-date before replacing the current avatar.
 *
 * @param localUserID
 *   The user for which we're replacing the avatar.
 *   This must be a user that's logged in (i.e. there's a valid ZDCLocalUser & ZDCLocalUserAuth in the database).
 *
 * @param auth0ID
 *   The identifier of the non-social account.
 *   The string is expected to be of the form "auth0|<identifier_goes_here>"
 *
 * @param completionQueue
 *   The dispatch queue on which to invoke the completion block.
 *   If unspecified, the main thread is used.
 *
 * @param completionBlock
 *   Invoked with the raw response from the server.
 */
- (void)updateAvatar:(nullable NSData *)avatarData
         contentType:(NSString *)contentType
        previousETag:(nullable NSString *)previousETag
      forLocalUserID:(NSString *)localUserID
             auth0ID:(NSString *)auth0ID
     completionQueue:(nullable dispatch_queue_t)completionQueue
     completionBlock:(void (^)(NSURLResponse *_Nullable response,
                               id _Nullable responseObject,
                               NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark S3
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Downloads the file into memory.
 * 
 * If canBackground is set to YES, then on iOS a download task will be used,
 * and the downloaded file will be automatically read into memory for the completionBlock.
 * 
 * The 'responseObject' will be the downloaded data (on sucess).
 */
- (void)downloadDataAtPath:(NSString *)remotePath
                  inBucket:(NSString *)bucket
                    region:(AWSRegion)region
                  withETag:(nullable NSString *)eTag
                     range:(nullable NSValue *)range
               requesterID:(NSString *)localUserID
             canBackground:(BOOL)canBackground
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completion;

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
                                  appPrefix:(NSString *)appPrefix
                                     pullID:(NSString *)pullID
                             continuationID:(nullable NSString *)continuationID
                         continuationOffset:(nullable NSNumber *)continuationOffset
                          continuationToken:(nullable NSString *)continuationToken
                                   inBucket:(NSString *)bucket
                                     region:(AWSRegion)region
                             forLocalUserID:(NSString *)localUserID
                                   withAuth:(ZDCLocalUserAuth *)auth;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Download
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)downloadFileFromURL:(NSURL *)sourceURL
               andSaveToURL:(NSURL *)destinationURL
                       eTag:(nullable NSString *)eTag
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSString *_Nullable eTag, NSError *_Nullable error))completionBlock;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth0
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fetches the user's public info (whitelisted identity info) via the API Gateway.
 * This information includes:
 * - userID (official ZeroDark.cloud userID, as opposed to auth0 social identity ID)
 * - user's region
 * - user's bucket
 */
- (void)fetchFilteredAuth0Profile:(NSString *)remoteUserID
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
                 zAppID:(NSString *)zAppID
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
**/
- (void)fetchCurrentBilling:(NSString *)localUserID
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSDictionary *_Nullable billing, NSError *_Nullable error))completionBlock;

- (void)fetchPreviousBilling:(NSString *)localUserID
                    withYear:(int)year
                       month:(int)month
             completionQueue:(nullable dispatch_queue_t)completionQueue
             completionBlock:(void (^)(NSDictionary *_Nullable billing, NSError *_Nullable error))completionBlock;


- (void)productPurchasedByUser:(NSString *)localUserID
			 productIdentifier:(NSString *)productIdentifier
		 transactionIdentifier:(NSString *)transactionIdentifier
			   appStoreReceipt:(NSData 	*) appStoreReceipt
			   completionQueue:(nullable dispatch_queue_t)completionQueue
			   completionBlock:(void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completionBlock;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Blockchain
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fetchMerkleTreeFile:(NSString *)root
                requesterID:(NSString *)localUserID
            completionQueue:(nullable dispatch_queue_t)inCompletionQueue
            completionBlock:(void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))inCompletionBlock;

@end

NS_ASSUME_NONNULL_END
