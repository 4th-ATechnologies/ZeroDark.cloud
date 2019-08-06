/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "ZDCConstants.h"

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

extern NSString *const kZDCUser_metadataKey;
extern NSString *const kZDCUser_metadata_preferedAuth0ID;

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
@property (nonatomic, copy, readwrite, nullable) NSString *blockchainTransaction;

#pragma mark AWS

/**
 * Every user account is tied to a specific region where their data is stored.
 *
 * @note Users are allowed to reside in different regions.
 *       There are no problems communicating between users in different regions.
 */
@property (nonatomic, assign, readwrite) AWSRegion aws_region;

/**
 * The name of a user's AWS S3 bucket.
 * This has the form: "com.4th-a.user.{userID}-{a few chars of randomness}"
 */
@property (nonatomic, copy, readwrite, nullable) NSString *aws_bucket;

#pragma mark Status

/**
 * If the user's account gets deleted, this value gets set to YES.
 *
 * Since the user may still be referenced through the permissions of various nodes,
 * the ZDCUser instance isn't immediately deleted from the database.
 * Instead, this flag gets set, and the framework ignores the dead account going forward.
 */
@property (nonatomic, assign, readwrite) BOOL accountDeleted;

/**
 * A marker used to refresh the user's information from the server periodically.
 */
@property (nonatomic, strong, readwrite) NSDate *lastUpdated;

#pragma mark Auth0

/**
 * Contains information about the social identities linked to the user's account.
**/
@property (nonatomic, copy, readwrite) NSDictionary * auth0_profiles;
@property (nonatomic, copy, readwrite, nullable) NSString * auth0_preferredID;
@property (nonatomic, copy, readwrite, nullable) NSDate   * auth0_lastUpdated;

@property (nonatomic, readonly) NSDictionary * preferredProfile;
@property (nonatomic, readonly) NSString     * displayName;

- (nullable NSString *)displayNameForAuth0ID:(nullable NSString *)auth0ID;

#pragma mark Convenience properties

/** Shorthand way to check if this is an instance of ZDCLocalUser. */
@property (nonatomic, readonly) BOOL isLocal;

/** Shorthand way to check if this is NOT an instance of ZDCLocalUser. */
@property (nonatomic, readonly) BOOL isRemote;

/** Shorthand way to check if there's a valid aws_region & aws_bucket property.  */
@property (nonatomic, readonly) BOOL hasRegionAndBucket;

/// Alternative copy methods

/**
 * Used when migrating between ZDCUser and ZDCLocalUser.
 */
- (void)copyTo:(ZDCUser *)copy;

#pragma mark Class Utilities

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
