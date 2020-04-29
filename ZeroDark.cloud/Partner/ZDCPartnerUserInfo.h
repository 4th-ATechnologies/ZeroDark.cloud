/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import <Foundation/Foundation.h>

#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Container to hold the parameters needed to initialize a user.
 * This is used for ZeroDark partners, who supply their own user authentication solution.
 *
 * See the [docs](https://zerodarkcloud.readthedocs.io/en/latest/client/partners/) for more information.
 */
@interface ZDCPartnerUserInfo : NSObject

/**
 * Initializes an instance with all the required parameters.
 *
 * See the [docs](https://zerodarkcloud.readthedocs.io/en/latest/client/partners/) for more information.
 */
- (instancetype)initWithUserID:(NSString *)userID
                        region:(AWSRegion)region
                        bucket:(NSString *)bucket
                         stage:(NSString *)stage
                          salt:(NSString *)salt
                  refreshToken:(NSString *)refreshToken
                     accessKey:(NSData *)accessKey;

/**
 * This value comes from the ZeroDark API: /v1/authdBizSrv/users/create
 */
@property (nonatomic, copy, readonly) NSString *userID;

/**
 * This value comes from the ZeroDark API: /v1/authdBizSrv/users/create
 */
@property (nonatomic, assign, readonly) AWSRegion region;

/**
 * This value comes from the ZeroDark API: /v1/authdBizSrv/users/create
 */
@property (nonatomic, copy, readonly) NSString *bucket;

/**
 * This value comes from the ZeroDark API: /v1/authdBizSrv/users/create
 */
@property (nonatomic, copy, readonly) NSString *stage;

/**
 * This value comes from the ZeroDark API: /v1/authdBizSrv/users/create
 */
@property (nonatomic, copy, readonly) NSString *salt;

/**
 * This value comes from the ZeroDark API: /v1/authdBizSrv/users/createRefreshToken
 */
@property (nonatomic, copy, readonly) NSString *refreshToken;

/**
 * Every user account has a public/private key pair.
 *
 * The public key is stored in the cloud and is accessible to other users.
 * The public key is also verifiable via the blockchain for trusted independent verification.
 *
 * The private key is encrypted with the given accessKey,
 * and then the encrypted version is stored in the user's bucket.
 * This is used to sync the private key across a user's various devices.
 *
 * In order for ZeroDark to provide a zero-knowledge cloud, it must never know the user's privateKey.
 * Therefore ZeroDark must never know the accessKey, and you're required to provide it for each user.
 *
 * Typically partners store a user's accessKey on their own servers.
 * And the accessKey is then sent to the user after a successful login.
 *
 * Note: If you're interested in having the user manage their own accessKey,
 *       then you probably want to be a ZeroDark Friend, as opposed to a Partner.
 */
@property (nonatomic, copy, readonly) NSData *accessKey;

@end

NS_ASSUME_NONNULL_END
