/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <TargetConditionals.h>
#import <Foundation/Foundation.h>

#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#endif

#import "AWSRegions.h"

@class ZeroDarkCloud;
@class ZDCAccessKeyBlob;
@class ZDCLocalUser;
@class ZDCLocalUserAuth;
@class ZDCPublicKey;
@class ZDCSymmetricKey;
@class ZDCUserProfile;

typedef NS_ENUM(NSInteger, AccountSetupMode) {
	AccountSetupMode_Unknown                = 0,
	AccountSetupMode_ExistingAccount,
	AccountSetupMode_Trial,
};

typedef NS_ENUM(NSInteger, AccountSetupViewID) {
	AccountSetupViewID_Unknown                = 0,
	AccountSetupViewID_Intro,
 	AccountSetupViewID_Identity,
 	AccountSetupViewID_DBAuth,
 	AccountSetupViewID_DBCreate,
	AccountSetupViewID_SocialAuth,
 	AccountSetupViewID_ScanCloneCode,
 	AccountSetupViewID_UnlockCloneCode,
 	AccountSetupViewID_Region,

	AccountSetupViewID_SocialidMgmt,
	AccountSetupViewID_UserAvatar,

 	AccountSetupViewID_Help,
 	AccountSetupViewID_AddIdentitityProvider,
	AccountSetupViewID_AddSocial,
	AccountSetupViewID_AddDatabase,
	AccountSetupViewID_ReAuthDatabase,
};

typedef NS_ENUM(NSInteger, IdenititySelectionMode) {
	IdenititySelectionMode_Unknown                = 0,
	IdenititySelectionMode_NewAccount,
	IdenititySelectionMode_ExistingAccount,
	IdenititySelectionMode_ReauthorizeAccount,

};

typedef NS_ENUM(NSInteger, AccountState) {
	AccountState_Unknown                = 0,
	AccountState_CreationFail ,
	AccountState_NeedsCloneClode,
	AccountState_Ready,
	AccountState_NeedsRegionSelection,
	AccountState_NeedsReauthentication,

	AccountState_LinkingID,
	AccountState_Reauthorized,
};

NS_ASSUME_NONNULL_BEGIN

@protocol AccountSetup_Protocol
@required

- (void)pushIntro;

- (void)showWait:(NSString *)title
         message:(nullable NSString *)message
 completionBlock:(nullable dispatch_block_t)completionBlock;

- (void)cancelWait;

- (void)showError:(NSString *)title
          message:(nullable NSString *)message
  completionBlock:(nullable dispatch_block_t)completionBlock;

- (void)popFromCurrentView;

- (void)pushCreateAccount;
- (void)pushSignInToAccount;

- (void)pushAccountReady;
- (void)pushScanClodeCode;
- (void)pushUnlockCloneCode:(nullable NSString *)cloneString;

- (void)pushRegionSelection;
- (void)pushIdentity;
- (void)pushDataBaseAuthenticate;
- (void)pushSocialAuthenticate;
- (void)pushDataBaseAccountCreate;
- (void)pushResumeActivationForUserID:(NSString *)userID;
- (void)pushReauthenticateWithUserID:(NSString *)userID;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_OSX
@interface AccountSetup_Base : NSViewController <AccountSetup_Protocol>
#else
@interface AccountSetup_Base : UIViewController <AccountSetup_Protocol>
#endif

@property (nonatomic, readwrite, weak) ZeroDarkCloud *zdc;

// intermediate values we keep until we are established
@property (nonatomic, readwrite)            AccountSetupMode       setupMode;
@property (nonatomic, readwrite)            IdenititySelectionMode identityMode;
@property (nonatomic, readwrite ,nullable)  NSDictionary*          selectedProvider;
@property (nonatomic, readwrite ,nullable)  ZDCUserProfile*        userProfile;
@property (nonatomic, readwrite ,nullable)  NSData *               privKeyData;

@property (nonatomic, readwrite ,nullable)  NSString* activationEmail;

// stuff that can be written into the DB
@property (nonatomic, readwrite ,nullable) ZDCLocalUserAuth*   auth;
@property (nonatomic, readwrite ,nullable) ZDCLocalUser*       user;
@property (nonatomic, readwrite ,nullable) ZDCPublicKey*       privKey;
@property (nonatomic, readwrite ,nullable) ZDCSymmetricKey*    accessKey;

- (void)resetAll;
- (void)handleFail;   // prototype method

// utility functions
-(BOOL)commonInitWithUserID:(NSString* __nonnull)userID error:(NSError **)errorOut;

- (ZDCLocalUser *)createLocalUserFromProfile:(ZDCUserProfile *)profile;

-(BOOL)isAlreadyLinkedError:(NSError*)error;

-(void) handleInternalError:(NSError*)error;

- (nullable NSString *)closestMatchingAuth0IDFromProfile:(ZDCUserProfile *)profile
                                                provider:(NSString *)provider
                                                username:(nullable NSString *)username;

// for an existing account - attempt to login to database account
- (void)databaseAccountLoginWithUsername:(NSString *)username
                                password:(NSString *)password
                         completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock;

// for an new account - attempt to create a database account
-(void) databaseAccountCreateWithUserName:(NSString*)userName
						   password:(NSString*)password
				 completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock;

/**
 * For login using social accounts (facebook, google etc..)
 */
- (void)socialAccountLoginWithAuth:(ZDCLocalUserAuth *)localUserAuth
                           profile:(ZDCUserProfile *)profile
                  preferredAuth0ID:(NSString *)preferedAuth0ID
                   completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock;

// resume activation given any state
-(void) resumeActivationForUserID:(NSString*)userID
			  cancelOperationFlag:(BOOL*_Nullable)cancelOperationFlag
				  completionBlock:(void (^)(NSError *error))completionBlock;

// unlocking the user with clone code
-(void)unlockUserWithAccessKey:(NSData *)accessKey
					completionBlock:(void (^)(NSError *_Nullable error))completionBlock;

// region selection
-(void) selectRegionForUserID:(NSString*)userID
						  region:(AWSRegion) region
				  completionBlock:(void (^)(NSError *_Nullable error))completionBlock;

// profile link and unlink
- (void)linkProfile:(ZDCUserProfile *)profile
      toLocalUserID:(NSString *)localUserID
    completionQueue:(nullable dispatch_queue_t)completionQueue
    completionBlock:(nullable void (^)(NSError *_Nullable error))completionBlock;

- (void)unlinkAuth0ID:(NSString *)auth0ID
      fromLocalUserID:(NSString *)localUserID
      completionQueue:(nullable dispatch_queue_t)completionQueue
      completionBlock:(nullable void (^)(NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
