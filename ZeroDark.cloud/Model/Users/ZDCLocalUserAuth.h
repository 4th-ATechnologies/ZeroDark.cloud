#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

/**
 * Encapsulates the information necessary to authenticate the localUser with various systems.
 */
@interface ZDCLocalUserAuth : ZDCObject <NSCoding, NSCopying>

/**
 * Matches ZDDLocalUser.uuid, which is the global userID for the user throughout the ZeroDark ecosystem.
 */
@property (nonatomic, copy, readwrite) NSString * aws_userID;

/**
 * The user's unique ID within the AWS system.
 */
@property (nonatomic, copy, readwrite) NSString * aws_userARN;

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
 * The AWS credentials are only valid for a short period of time. (usualy just a few hours)
 * This property stores when the expire, so we know if we can re-use them, or if we need to refresh them.
 */
@property (nonatomic, copy, readwrite) NSDate * aws_expiration;

/**
 * Used for Auth0 stuff.
 * (Auth0 acts as our identity broker - for now).
 */
@property (nonatomic, copy, readwrite) NSString	* auth0_refreshToken;

@end
