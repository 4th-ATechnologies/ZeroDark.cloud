#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates the information necessary to authenticate the localUser with various systems.
 */
@interface ZDCLocalUserAuth : ZDCObject <NSCoding, NSCopying>

/**
 * Matches ZDDLocalUser.uuid, which is the global userID for the user throughout the ZeroDark ecosystem.
 */
@property (nonatomic, copy, readwrite) NSString * localUserID;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite, nullable) NSString * aws_accessKeyID;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite, nullable) NSString * aws_secret;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite, nullable) NSString * aws_session;

/**
 * The AWS credentials are only valid for a short period of time. (usually just a few hours)
 * This property stores when they expire, so we know if we can re-use them, or if we need to refresh them.
 */
@property (nonatomic, copy, readwrite, nullable) NSDate * aws_expiration;

/**
 * The refreshToken is a long-lived token which can be regularly exchanged for a fresh JWT.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *coop_refreshToken;

/**
 * The JWT is used for authentication with the various ZeroDark API.
 * The JWT JWT can also be used to fetch AWS credentials.
 *
 * A JWT is a JSON Web Token.
 * JWT's have an expiration date, and therefore need to be regularly refreshed.
 */
@property (nonatomic, copy, readwrite, nullable) NSString * coop_jwt;

/**
 * The refreshToken is a long-lived token which can be regularly exchanged for a fresh JWT.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *partner_refreshToken;

/**
 * The JWT is used for authentication with the various ZeroDark API.
 * The JWT JWT can also be used to fetch AWS credentials.
 *
 * A JWT is a JSON Web Token.
 * JWT's have an expiration date, and therefore need to be regularly refreshed.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *partner_jwt;

/**
 * Returns YES if coop_refreshToken is non-nil.
 */
@property (nonatomic, readonly) BOOL isCoop;

/**
 * Returns either to coop_jwt or partner_jwt.
 * Value is guaranteed to match `isCoop` property.
 */
@property (nonatomic, readonly, nullable) NSString *jwt;

@end

NS_ASSUME_NONNULL_END
