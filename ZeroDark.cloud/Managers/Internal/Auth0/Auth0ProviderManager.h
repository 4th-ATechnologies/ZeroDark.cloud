#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "OSPlatform.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const Auth0ProviderManagerErrorDomain;
extern NSString *const Auth0ProviderManagerDidUpdateNotification;

extern NSString *const kAuth0ProviderInfo_Key_ID;
extern NSString *const kAuth0ProviderInfo_Key_Type;
extern NSString *const kAuth0ProviderInfo_Key_DisplayName;
extern NSString *const kAuth0ProviderInfo_Key_SigninURL;
extern NSString *const kAuth0ProviderInfo_Key_64x64URL;
extern NSString *const kAuth0ProviderInfo_Key_SigninEtag;
extern NSString *const kAuth0ProviderInfo_Key_64x64Etag;


typedef NS_ENUM(NSInteger, Auth0ProviderIconType) {
    Auth0ProviderIconType_64x64,
    Auth0ProviderIconType_Signin
 };

typedef NS_ENUM(NSInteger, Auth0ProviderType) {

	Auth0ProviderType_Social = 0,
	/**
	 *  Username and Password
	 */
	Auth0ProviderType_Database,
	/**
	 *  LDAP, Sharepoint, IP, etc.
	 */
	Auth0ProviderType_Enterprise,
	/**
	 *  Passwordless authentication like SMS or Email
	 */
	Auth0ProviderType_Passwordless
};


@interface Auth0ProviderManager : NSObject

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

@property (nonatomic, readonly) NSDictionary *providersInfo;
@property (nonatomic, readonly) NSArray      *ordererdProviderKeys;

@property (nonatomic, readonly) BOOL isUpdated;

#if !TARGET_EXTENSION
- (void)updateProviderCache:(BOOL)forceUpdate;
#endif

- (OSImage *)iconForProvider:(NSString *)provider type:(Auth0ProviderIconType)type;

/**
 * Converts from provider key name ("google-oauth") to appropriate displayName ("Google").
 *
 * If the given provider is unknown, returns the given provider parameter.
 */
- (NSString *)displayNameforProvider:(NSString *)provider;

- (NSUInteger)numberOfMatchingProviders:(NSDictionary*)profile provider:(NSString*)provider;

/**
 *
 */
- (void)fetchSupportedProviders:(void (^)(NSArray<NSString*> *_Nullable providerKeys,
                                          NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
