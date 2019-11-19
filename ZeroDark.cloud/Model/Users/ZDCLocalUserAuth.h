#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

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
@property (nonatomic, copy, readwrite) NSString * aws_accessKeyID;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite) NSString * aws_secret;

/**
 * Part of the credentials used by AWS.
 */
@property (nonatomic, copy, readwrite) NSString * aws_session;

/**
 * The AWS credentials are only valid for a short period of time. (usually just a few hours)
 * This property stores when they expire, so we know if we can re-use them, or if we need to refresh them.
 */
@property (nonatomic, copy, readwrite) NSDate * aws_expiration;

/**
 * Used for Auth0, which is our identity broker (for now).
 *
 * This property can be exchanged for a fresh idToken from Auth0.
 * And idToken is a JWT, that can itself be exchanged for AWS credentials.
 */
@property (nonatomic, copy, readwrite) NSString	* auth0_refreshToken;

/**
 * An idToken is a JWT that can be exchanged for AWS credentials.
 * 
 * These tokens have an expiration date, and therefore need to be regularly refreshed.
 */
@property (nonatomic, copy, readwrite) NSString * auth0_idToken;

@end
