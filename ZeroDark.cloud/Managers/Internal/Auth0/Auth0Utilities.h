/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "Auth0Constants.h"
#import "AWSRegions.h"
#import "ZDCUserIdentity.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * ZeroDark.cloud uses Auth0 as an identity broker for our identity system.
 * This class provides various utility methods to assist in the translation between their system & ours.
 */
@interface Auth0Utilities : NSObject

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
 * Returns YES if email domain is "users.4th-a.com".
 *
 * This indicates the identity is a username/password (database) user identity.
 * In other words, this isn't a social identity.
 */
+ (BOOL)is4thAEmail:(NSString *)email;

/**
 * Returns YES if email domain is "recovery.4th-a.com".
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
 * Returns the picture URL for the given auth0ID.
 */
+ (nullable NSURL *)pictureUrlForIdentity:(ZDCUserIdentity *)identity
                                   region:(AWSRegion)region
                                   bucket:(NSString *)bucket;

@end

NS_ASSUME_NONNULL_END
