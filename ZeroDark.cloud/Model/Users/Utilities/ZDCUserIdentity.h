/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates an identity that's attached to the user.
 *
 * For example, a user may attach their Facebook or LinkedIn identity.
 * This is done to improve searchability, and to provide proof that a ZDC account is owned by a particular person
 * (and not an imposter, or somebody else with a similar name).
 */
@interface ZDCUserIdentity : NSObject <NSSecureCoding, NSCopying>

/**
 * Standard initializer
 */
- (instancetype)initWithDictionary:(NSDictionary *)dict;

/**
 *  The identityID is the unique identifier for this identity,
 *  which encodes both the provider_name & provider_userID.
 */
@property (nonatomic, readonly) NSString *identityID;

/**
 *  Name of the identity provider. (e.g. "facebook", "github", ...)
 */
@property (nonatomic, readonly) NSString *provider;

/**
 * The userID within the context of the provider/connection.
 *
 * For example, if the provider is facebook, then the userID will be the unique facebookUserID.
 *
 * @important This is NOT the same as ZDCUser.uuid.
 */
@property (nonatomic, readonly) NSString *userID;

/**
 * If the provider_name is "auth0", this value stores the database connection being used.
 * Otherwise the value is nil.
 */
@property (nonatomic, readonly, nullable) NSString *connection;

/**
 *  Flag that indicates if the identity is `Social`. e.g: Facebook
 */
@property (nonatomic, readonly) BOOL isSocial;

/**
 * The owner-preferred flag may be set by the owner of this identity.
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
@property (nonatomic, readonly) BOOL isOwnerPreferredIdentity;

/**
 * User's profile data, which comes from the identity provider.
 */
@property (nonatomic, readonly) NSDictionary *profileData;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the proper display name, taking into consideration many different things,
 * including the provider & profileData.
 */
@property (nonatomic, readonly) NSString *displayName;

/**
 * Co-op users have a recovery connection created for them automatically.
 *
 * This protects users in the event they're unable to login to their social identity.
 * For example, say their only linked identity is Facebook.
 * And then Facebook decides to kick them off the platform for thought crimes.
 * This would leave them in a situation in which they have no way to login to their account.
 *
 * In such a situation, the Recovery connection can act as way to restore a user's access to their account.
 * ZeroDark will have policies and procedures in place for this situation.
 *
 * Note: Logging into a social account (or recovery account) doesn't allow you to do jack squat
 * unless you have your access key. Without the access key you can't read any data.
 */
@property (nonatomic, readonly) BOOL isRecoveryAccount;

@end

NS_ASSUME_NONNULL_END
