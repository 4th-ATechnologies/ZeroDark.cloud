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
 * Auth0 user profile information.
 * This class wraps the JSON dictionary returned from the servers.
 *
 * Part of this code is courtesy of Auth0.
 */
@interface A0UserProfile : NSObject <NSSecureCoding>

/**
 * Parses the given dictionary into an A0UserProfile instance.
 */
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

/**
 * Parses the given (filtered) dictionary into an A0UserProfile instance.
 *
 * A filtered profile is what the ZeroDark.cloud servers return.
 * It strips any potentially sensitive information from the user's profile info.
 */
+ (instancetype)profileFromFilteredProfileDict:(NSDictionary *)dict;


/** User's ID within Auth0 */
@property (readonly, nonatomic) NSString *userId;

/** User's name */
@property (readonly, nonatomic) NSString *name;

/** User's nickname */
@property (readonly, nonatomic) NSString *nickname;

/** User's email */
@property (readonly, nonatomic, nullable) NSString *email;

/** User's avatar picture URL. */
@property (readonly, nonatomic) NSURL *picture;

/** User's creation date */
@property (readonly, nonatomic) NSDate *createdAt;

/** Extra user information stored in Auth0. */
@property (readonly, nonatomic) NSDictionary *extraInfo;

/** User's identities from other identity providers, e.g.: Facebook */
@property (readonly, nonatomic) NSArray *identities;

/** Values stored under `user_metadata`. */
@property (readonly, nonatomic) NSDictionary *userMetadata;

/** Values stored under `app_metadata` */
@property (readonly, nonatomic) NSDictionary *appMetadata;

/**
 * Utility to test if the given user profile indicates that the user has been set up or not
 */
@property (readonly, nonatomic) BOOL isUserBucketSetup;

@end

NS_ASSUME_NONNULL_END
