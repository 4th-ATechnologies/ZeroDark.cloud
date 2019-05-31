/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCUser.h"
#import <YapDatabase/YapDatabaseRelationship.h>

extern double const kS4LocalUser_shelflife;     // acceptable time since last update

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a local user in the system.
 *
 * That is, a user who has logged into their account on the device.
 * This is in contrast to a "remote" user, which are instances of ZDCUser.
 */
@interface ZDCLocalUser : ZDCUser <NSCoding, NSCopying, YapDatabaseRelationshipNode>

/**
 * A reference to the ZDCSymmetricKey.uuid that's used to unlock the user's account during sign-in.
 */
@property (nonatomic, copy, readwrite) NSString *accessKeyID;

/**
 * The syncedSalt is used to salt the clone code when no encyption key is specified.
 * Typically a unique string with at least 256 bits of entropy,
 * but it will pass through PKCS-11 anyhow.
 */
@property (nonatomic, copy, readwrite) NSString *syncedSalt;

/**
 * Each AWS server has 3 "stages" which are used to test server-side code.
 * The stages are: "prod", "dev" or "test"
 *
 * - dev : As the ZeroDark.cloud server developers are hacking away, they deploy their untested code to "dev".
 *         In other words, this stage is volatile & unreliable.
 *         If you're working with a ZeroDark.cloud server developer,
 *         they may tell you to activate an account in this stage for testing.
 *
 * - test: One step up from the "dev" stage in terms of reliability.
 *         The server engineers think they've shaken out most of the bugs, but more testing needs to be done.
 *         If you're working with a ZeroDark.cloud developer/support,
 *         they may tell you to activate an account in this stage for testing.
 *
 * - prod: Production ready stage. This is where you want to be.
 */
@property (nonatomic, copy, readwrite) NSString *aws_stage;

/**
 * If set to YES, all network activity for the user will be paused.
 * Nothing will get pushed to the cloud, nor will changes be pulled from the cloud.
 *
 * This is a persistent property, and is meant to be used for persistent changes to the user.
 * For example, if your UI allows the user to explicitly pause syncing for a user.
 * You do NOT need to set this property for temporary situations, such as when the Internet connection is lost.
 */
@property (nonatomic, assign, readwrite) BOOL syncingPaused;

/**
 * If set to YES, the user's account has been suspended due to lack of payment.
 * The user is currently in grace period, and is being given time to make a payment.
 * If they make a payment, their account will be restored to normal.
 * If they don't, their account will be deleted.
 *
 * @see `-[ZDCUser accountDeleted]`
 */
@property (nonatomic, assign, readwrite) BOOL accountSuspended;

/**
 * The previously valid authentication credentials have been revoked.
 * This may happen if a user reports a device as lost/stolen,
 * and the server wipes the associated auth tokens from the server.
 *
 * The user will need to re-login to their account in order to continue accessing the cloud.
 */
@property (nonatomic, assign, readwrite) BOOL accountNeedsA0Token;
@property (nonatomic, assign, readwrite) BOOL isPayingCustomer;

/**
 * All data stored in the cloud is encrypted with keys that only the user knows.
 * The "master key" to this data is called the "access key".
 * The user is the only person who knows the access key,
 * so if they lose the access key, they'll be locked out of their data.
 * This is by design: ZeroDark.cloud == Zero-Knowledge.
 *
 * The implication here is that the user should back up their access key.
 * And the onus is on the app developer (that's YOU) to remind the user to backup their key.
 */
@property (nonatomic, assign, readwrite) BOOL hasBackedUpAccessCode;

@property (nonatomic, strong, readwrite) NSDate *activationDate;

@property (nonatomic, copy, readwrite) NSString *auth0_primary;

#pragma mark Convenience properties

/**
 * Whether or not the user has an assigned region & bucket.
 * The server assigns a user's bucket when the account is activated.
 */
@property (nonatomic, readonly) BOOL hasCompletedActivation;

/**
 * Does the user have a region/bucket AND a private key.
 * In other words, does the user have everything we need to actually use the account?
 */
@property (nonatomic, readonly) BOOL hasCompletedSetup;

/**
 * Indicates whether we can perform user syncing right now.
 *
 * This will return NO if syncing has been explicitly paused (localUser.syncingPaused == YES),
 * or if some other error is currently preventing syncing.
 */
@property (nonatomic, readonly) BOOL canPerformSync;

@end

NS_ASSUME_NONNULL_END
