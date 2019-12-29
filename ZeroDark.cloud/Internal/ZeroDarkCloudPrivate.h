/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZeroDarkCloud.h"

#import "Auth0APIManager.h"
#import "Auth0ProviderManager.h"
#import "ZDCBlockchainManager.h"
#import "AWSCredentialsManager.h"
#import "ZDCCryptoTools.h"
#import "ZDCInternalPreferences.h"
#import "ZDCNetworkTools.h"
#import "ZDCSharesManager.h"
#import "ZDCSessionManager.h"
#import "ZDCUserAccessKeyManager.h"

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

@property (nonatomic, readonly, nullable) S4KeyContextRef storageKey;

- (void)registerPushTokenForLocalUsersIfNeeded;

/**
 * Invoked by ZDCSessionManager.
 */
- (void)invokeCompletionHandlerForBackgroundURLSession:(NSString *)sessionIdentifier;

#if TARGET_OS_IOS
/**
 * Returns the result of calling:
 * `[UIImage imageNamed:name inBundle:[ZeroDarkCloud frameworkBundle] compatibleWithTraitCollection:nil]`
 */
+ (nullable UIImage *)imageNamed:(NSString *)name;
#endif

@end

NS_ASSUME_NONNULL_END
