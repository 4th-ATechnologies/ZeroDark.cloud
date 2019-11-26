/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import "ZDCUserIdentity.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates the user's profile, which is made up of one or more linked identities.
 */
@interface ZDCUserProfile : NSObject <NSSecureCoding>

/**
 * Attempts to parse the given dictionary into a ZDCUserProfile instance.
 */
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

/**
 * Attempts to parse the given (filtered) dictionary into a ZDCUserProfile instance.
 *
 * A filtered profile is what the ZeroDark.cloud servers return.
 * It strips any potentially sensitive information from the user's profile info.
 */
//- (instancetype)initWithFilteredProfileDictionary:(NSDictionary *)dict;

/**
 * A unique identifier for the profile.
 */
@property (nonatomic, readonly) NSString *userID;

/** User's name */
@property (nonatomic, readonly) NSString *name;

/** User's nickname */
@property (nonatomic, readonly) NSString *nickname;

/** User's email */
@property (nonatomic, readonly, nullable) NSString *email;

/** User's avatar picture URL. */
@property (nonatomic, readonly) NSURL *picture;

/** User's creation date */
@property (nonatomic, readonly) NSDate *createdAt;

/** User's identities from other identity providers, e.g.: Facebook */
@property (nonatomic, readonly) NSArray<ZDCUserIdentity *> *identities;

/** Extra user information stored in Auth0. */
@property (nonatomic, readonly) NSDictionary *extraInfo;

/** Values stored under `app_metadata` */
@property (nonatomic, readonly) NSDictionary *appMetadata;

/** Values stored under `user_metadata`. */
@property (nonatomic, readonly) NSDictionary *userMetadata;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/** As specified in appMetadata. */
@property (nonatomic, readonly, nullable) NSString *appMetadata_awsID;

/** As specified in appMetadata. */
@property (nonatomic, readonly, nullable) NSString *appMetadata_region;

/** As specified in appMetadata. */
@property (nonatomic, readonly, nullable) NSString *appMetadata_bucket;

/**
 * As specified in userMetadata.
 */
@property (nonatomic, readonly, nullable) NSString *userMetadata_preferredIdentityID;

/**
 * Utility to test if the given user profile indicates that the user has been set up or not
 */
@property (nonatomic, readonly) BOOL isUserBucketSetup;

/**
 * Returns the identity (from within the identities array) that matches the given ID.
 */
- (nullable ZDCUserIdentity *)identityWithID:(NSString *)identityID;

@end

NS_ASSUME_NONNULL_END
