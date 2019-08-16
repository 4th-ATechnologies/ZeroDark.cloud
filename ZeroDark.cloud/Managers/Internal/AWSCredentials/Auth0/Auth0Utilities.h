/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "Auth0API.h"
#import "A0UserIdentity.h"
#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * ZeroDark.cloud uses Auth0 as an identity broker for our identity system.
 * This class provides various utility methods to assist in the translation between their system & ours.
 */
@interface Auth0Utilities : NSObject

/**
 * Auto-healing missing preferred auth0 ID.
 */
+ (nullable NSString *)firstAvailableAuth0IDFromProfiles:(NSDictionary *)profiles;

/**
 * Returns YES if the username matches the general ruleset for usernames in our system.
 * This is used by the signup screens.
 */
+ (BOOL)isValid4thAUsername:(NSString *)username;

/**
 * Converts from username to corresponding email.
 * E.g.:
 * - username : alice
 * - email    : alice@users.4th-a.com
 *
 * This is used by the signup screens.
 */
+ (nullable NSString *)create4thAEmailForUsername:(NSString *)username;

/**
 * Returns YES if the profile represents a username/password (database) account.
 */
+ (BOOL)isUserAuthProfile:(NSDictionary *)profile;

/**
 * Returns YES if the profile represents a recovery profile.
 *
 * Every user has a recovery identity which can be used to assist the user
 * if they get locked out of their account.
 * Of course, without their access key, they won't be able to read any data...
 *
 * However, there's always the chance a user becomes unable to login to their social identity.
 * (Either because they forgot a password, or because they got booted from the platform for thought crimes.)
 */
+ (BOOL)isRecoveryProfile:(NSDictionary *)profile;

/**
 * Returns YES if the identity is a username/password (database) identity.
 */
+ (BOOL)isUserAuthIdentity:(A0UserIdentity *)identity;

/**
 * Returns YES if the identity is a recovery identity.
 *
 * @see `-isRecoveryProfile:`
 */
+ (BOOL)isRecoveryIdentity:(A0UserIdentity *)identity;

/**
 * Returns YES if email domain is "users.4th-a.com".
 *
 * This indicates the identity is a username/password (database) user identity.
 * In other words, this isn't a social identity.
 */
+ (BOOL)is4thAEmail:(NSString *)email;

/**
 * Returns YES if email domain is "recovery.4th-a.com".
 *
 * @see `-isRecoveryProfile:`
 */
+ (BOOL)is4thARecoveryEmail:(NSString *)email;

/**
 * Extracts the username component from an email.
 *
 * E.g.:
 * - email    : alice@users.4th-a.com
 * - username : alice
 */
+ (nullable NSString *)usernameFrom4thAEmail:(NSString *)email;

/**
 * Extracts the username component from an email.
 *
 * E.g.:
 * - email    : alice@recovery.4th-a.com
 * - username : alice
 *
 * @see `-isRecoveryProfile:`
 */
+ (nullable NSString *)usernameFrom4thARecoveryEmail:(NSString *)email;

/**
 * Handles weird providers (like wordpress)
 *
 * The term 'strategy' comes from the constants in Auth0's Lock framework.
 * E.g. `A0StrategyNameWordpress`
 */
+ (nullable NSString *)correctUserNameForA0Strategy:(NSString *)strategy profile:(NSDictionary *)profile;

/**
 * Handles weird providers.
 */
+ (NSString *)correctDisplayNameForA0Strategy:(NSString *)strategy profile:(NSDictionary *)profile;

/**
 * Returns the picture URL for the given auth0ID.
 */
+ (nullable NSString *)correctPictureForAuth0ID:(NSString *)auth0ID
                                    profileData:(NSDictionary *)profileData
                                         region:(AWSRegion)region
                                         bucket:(NSString *)bucket;



+(NSDictionary*)excludeRecoveryProfile:(NSDictionary*)profilesIn;

@end

NS_ASSUME_NONNULL_END
