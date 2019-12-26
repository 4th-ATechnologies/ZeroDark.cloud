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
#import "ZDCBlockchainProof.h"
#import "ZDCConstants.h"
#import "ZDCUserProfile.h"
#import "ZDCUserIdentity.h"

#import <YapDatabase/YapDatabaseRelationship.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The userID used to represent non-ZeroDark users within the system.
 *
 * If your app allows non-ZeroDark users to send files/messages to ZDC users,
 * then the sender of these nodes appears using the single instance of an anonymous user.
 *
 * @note Anonymous users can be enabled via the ZeroDark.cloud dashboard.
 */
extern NSString *const kZDCAnonymousUserID;

/**
 * Represents a user in the system.
 *
 * Non-local users will be instances of this class (ZDCUser).
 * Local users will be instances of ZDCLocalUser (which extends ZDCUser).
 */
@interface ZDCUser : ZDCObject <NSCoding, NSCopying, YapDatabaseRelationshipNode>

/**
 * Creates a basic ZDCUser with the given userID.
 *
 * @warning The framework handles creating users for you most of the time.
 *          So you probably will have zero need of ever creating a user manually.
 *
 * @param uuid
 *   The user's userID. This should NOT be a random value.
 *   It needs to match the user's actual userID according to the server.
 */
- (instancetype)initWithUUID:(nullable NSString *)uuid;

/**
 * A user's uuid is commonly referred to as the userID.
 *
 * This property matches a user's external userID.
 * That is, this is the same userID used to identify the user in the cloud.
 * It's always 32 characters long, encoded using zBase32.
 */
@property (nonatomic, copy, readonly) NSString *uuid;

/**
 * References the user's corresponding ZDCPublicKey stored in the database.
 *
 * Specifically, this value represents:
 * - the corresponding ZDCPublicKey.uuid
 * - the key used to fetch it from YapDatabase (within collection kZDCCollection_PublicKeys)
 *
 * If this value is null, it may mean we haven't fetched the publicKey for the user yet.
 * It may also mean the user's account has been deleted, and thus they no longer have a publicKey.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *publicKeyID;

/**
 * If the user's publicKey has been verified using the Ethereum blockchain,
 * this value represents the corresponding transaction in which it was verified.
 */
@property (nonatomic, copy, readwrite, nullable) ZDCBlockchainProof *blockchainProof;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AWS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Every user account is tied to a specific region where their data is stored.
 *
 * @note Users are allowed to reside in different regions.
 *       There are no problems communicating between users in different regions.
 */
@property (nonatomic, assign, readonly) AWSRegion aws_region;

/**
 * The name of a user's AWS S3 bucket.
 * This has the form: "com.4th-a.user.{userID}-{a few chars of randomness}"
 */
@property (nonatomic, copy, readonly, nullable) NSString *aws_bucket;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * If we discover the user's publicKey has been tampered with, this value gets set to YES.
 *
 * All user's have a proof of their publicKey posted to the Ethereum blockchain.
 * If we query the blockchain, and discover the user's publicKey doesn't match the blockchain,
 * then we block the user, and refuse to give them access to nodes.
 */
@property (nonatomic, assign, readwrite) BOOL accountBlocked;

/**
 * If the user's account gets deleted, this value gets set to YES.
 *
 * Since the user may still be referenced through the permissions of various nodes,
 * the ZDCUser instance isn't immediately deleted from the database.
 * Instead, this flag gets set, and the framework ignores the dead account going forward.
 */
@property (nonatomic, assign, readwrite) BOOL accountDeleted;

/**
 * A marker used to refresh the user's information periodically.
 */
@property (nonatomic, strong, readwrite) NSDate *lastRefresh_profile;

/**
* A marker used to refresh the user's information periodically.
*/
@property (nonatomic, strong, readwrite) NSDate *lastRefresh_blockchain;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Profile
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Contains the list of social identities that the user has linked to their account.
 *
 * For example, Alice might link multiple identities to her account:
 * - Facebook
 * - LinkedIn
 * - GitHub
 */
@property (nonatomic, copy, readwrite) NSArray<ZDCUserIdentity*> *identities;

/**
 * Allows a user to control which identity is displayed within the UI.
 *
 * For example, Alice might link multiple identities to her account:
 * - Facebook (for friends & family)
 * - LinkedIn (for work colleagues)
 *
 * Alice might set her LinkedIn profile as her preferred identity.
 * This means that, all else being equal, her LinkedIn name & avatar will be shown to other people.
 *
 * However, this can be overridden by other users.
 * For example, Bob (Alice's friend) may prefer to see Alice's Facebook name & avatar.
 * So Bob can set Alice's ZDCUser.preferredIdentityID to override this value.
 *
 * In other words:
 * - Alice's LinkedIn ZDCUserIdentity.isOwnerPerferredIdentity is TRUE
 * - But Bob has set Alice's ZDCUser.preferredIdentityID to point at her Facebook ZDCUserIdentity
 * - Thus on Bob's system, we display Alice using her Facebook identity
 */
@property (nonatomic, copy, readwrite, nullable) NSString * preferredIdentityID;

/**
 * Extracts an identity for the user from their list of linked identities.
 *
 * The following rules are followed, in order:
 * - If the `preferredIdentityID` is set, returns that identity (if non-nil)
 * - Returns the first ZDCUserIdentity with it's `isOwnerPreferredIdentity` set to true
 * - Returns the first ZDCUserIdentity with it's `isRecoveryAccount` set to false
 * - Returns the first ZDCUserIdentity in the list
 */
@property (nonatomic, readonly, nullable) ZDCUserIdentity * displayIdentity;

/**
 * Extracts a name for the user from their list of linked identities.
 */
@property (nonatomic, readonly) NSString *displayName;

/**
 * Returns the corresponding identity (from the identities array) if it exists.
 */
- (nullable ZDCUserIdentity *)identityWithID:(NSString *)identityID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/** Shorthand way to check if this is an instance of ZDCLocalUser. */
@property (nonatomic, readonly) BOOL isLocal;

/** Shorthand way to check if this is NOT an instance of ZDCLocalUser. */
@property (nonatomic, readonly) BOOL isRemote;

/** Shorthand way to check if there's a valid aws_region & aws_bucket property.  */
@property (nonatomic, readonly) BOOL hasRegionAndBucket;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Copy
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used when migrating between ZDCUser and ZDCLocalUser.
 */
- (void)copyTo:(ZDCUser *)copy;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns YES if the given string is:
 * - 32 characters in zBase32 encoding
 *
 * @note This method returns NO for anonymousID's (which are 16 characters).
 */
+ (BOOL)isUserID:(NSString *)str;

/**
 * Returns YES if the given string is:
 * - 16 characters in zBase32 encoding
 */
+ (BOOL)isAnonymousID:(NSString *)str;

@end

NS_ASSUME_NONNULL_END
