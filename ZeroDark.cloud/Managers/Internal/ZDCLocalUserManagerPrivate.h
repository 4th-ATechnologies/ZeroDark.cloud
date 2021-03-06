/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCLocalUserManager.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCLocalUserManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Standardized routine for creating all the container nodes.
 */
- (void)createTrunkNodesForLocalUser:(ZDCLocalUser *)localUser
                       withAccessKey:(ZDCSymmetricKey *)accessKey
                         transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Create or download the public/private keypair for the user.
 *
 * Here's how this works:
 * - The public key is stored on the server in cleartext (JSON).
 *   The public key is accessible to the world.
 * - The private key is stored on the server in an encrypted form.
 *   The private key is only accessible to the localUser.
 *   The private key can only be unlocked with the user's accessKey, which only the user has access to.
 *   The accessKey is the thing the user backs up.
 * - Neither of these files are directly writable by the user because the 2 files need to be set in an atomic fashion.
 *   So, instead, the user goes through the REST API.
 * - The REST API checks to see if there's already a pair of files setup by the user,
 *   and if so, it returns those to the caller.
 * - Otherwise it accepts the posted pair (cleartext pubKey + encrypted privKey),
 *   and stores those for the user.
 *
 * (The server uses a locking mechanism to ensure multiple simulataneous attempts are ordered in a serial fashion.)
 */
- (void)setupPubPrivKeyForLocalUser:(ZDCLocalUser *)localUser
                           withAuth:(ZDCLocalUserAuth *)auth
                    completionQueue:(nullable dispatch_queue_t)completionQueue
                    completionBlock:(void (^)(NSData *pKToUnlock,  NSError *error))completionBlock;

/**
 * Setup the recovery connection for the user.
 * 
 * This is a backup plan in-case the user gets booted from their social platform.
 * E.g. they get banned from Twitter for wrongthink.
 */
- (void)createRecoveryConnectionForLocalUser:(ZDCLocalUser *)localUser
                             completionQueue:(nullable dispatch_queue_t)completionQueue
                             completionBlock:(nullable void (^)(NSError *error))completionBlock;

/**
 * Do this within the atomic transaction that's finishing the account setup for the user.
 */
- (void)finalizeAccountSetupForLocalUser:(ZDCLocalUser *)localUser
                             transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Write some doocumentation here
 *
 */

- (void)refreshAuth0ProfilesForLocalUserID:(NSString *)userID
						   completionQueue:(nullable dispatch_queue_t)completionQueue
						   completionBlock:(nullable void (^)( NSError *error))completionBlock;

/**
 * The ".pubKey" file stored on the server contains a (signed) list of
 * social identities that have been linked to the account.
 * This is an additional security step to protect the user.
 *
 * This method updates the ".pubKey" file, by updated the signed list of identities.
 */
- (void)updatePubKeyForLocalUserID:(NSString *)localUserID
                   completionQueue:(nullable dispatch_queue_t)completionQueue
                   completionBlock:(void (^)(NSError *error))completionBlock;

/**
 * Write some doocumentation here
 *
 */
-(NSDictionary*) createProfilesFromIdentities:(NSArray*)identities
                                       region:(AWSRegion)region
                                       bucket:(NSString *)bucket;

/**
 * Convenience routine for updating a user's avatar.
 * It performs all the requisite tasks, tying together the various components of framework.
 *
 * In particular it:
 * - stores the new avatar in the DiskManager (persistently)
 * - queues a task to update the avatar on the server
 *
 * @param avatarData
 *   The raw avatar data, encoded in either PNG or JPEG format.
 *
 * @param localUser
 *   A reference to the local user for which we're updating the avatar.
 *
 * @param identityID
 *   A reference to the social identity for which we're updating the avatar.
 *   This is a string of the form "<provider_name>|<provider_userID>"
 *
 * @param oldAvatarData
 *   Every single zApp shares the same user avatar.
 *   So think: "com.4th-a.storm4" + "com.4th-a.ZeroDarkTodo" + "com.org.foobar" ...
 *   In light of this, the server forces you to update the avatar in an atomic fashion.
 *   Meaning you have to know the current version of the avatar in order to successfully update it.
 *   If you're out-of-date, then your change will be rejected.
 */
- (void)setNewAvatar:(nullable NSData *)avatarData
        forLocalUser:(ZDCLocalUser *)localUser
          identityID:(NSString *)identityID
  replacingOldAvatar:(nullable NSData *)oldAvatarData;

@end

NS_ASSUME_NONNULL_END
