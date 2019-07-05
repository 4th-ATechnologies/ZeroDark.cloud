/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZeroDarkCloud.h"

#import "Auth0APIManager.h"
#import "AWSCredentialsManager.h"
#import "ZDCSessionManager.h"
#import "ZDCNetworkTools.h"
#import "Auth0ProviderManager.h"
#import "ZDCInternalPreferences.h"
#import "ZDCCryptoTools.h"
#import "ZDCUserAccessKeyManager.h"
#import "ZDCBlockchainManager.h"
#import "ZDCSharesManagerPrivate.h"
#import "ZDCPasswordStrengthManagerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZeroDarkCloud (Private)

@property (nonatomic, readonly) Auth0APIManager * auth0APIManager;

@property (nonatomic, readonly, nullable) AWSCredentialsManager      * awsCredentialsManager;
@property (nonatomic, readonly, nullable) ZDCSessionManager          * sessionManager;
@property (nonatomic, readonly, nullable) ZDCNetworkTools            * networkTools;
@property (nonatomic, readonly, nullable) Auth0ProviderManager       * auth0ProviderManager;
@property (nonatomic, readonly, nullable) ZDCInternalPreferences     * internalPreferences;
@property (nonatomic, readonly, nullable) ZDCCryptoTools             * cryptoTools;
@property (nonatomic, readonly, nullable) ZDCUserAccessKeyManager    * userAccessKeyManager;
@property (nonatomic, readonly, nullable) ZDCBlockchainManager       * blockchainManager;
@property (nonatomic, readonly, nullable) ZDCSharesManager           * sharesManager;
@property (nonatomic, readonly, nullable) ZDCPasswordStrengthManager * passwordStrength;

@property (nonatomic, readonly, nullable) S4KeyContextRef storageKey;

- (void)registerPushTokenForLocalUsersIfNeeded;

/**
 * Invoked by ZDCSessionManager.
 */
- (void)invokeCompletionHandlerForBackgroundURLSession:(NSString *)sessionIdentifier;

@end

NS_ASSUME_NONNULL_END
