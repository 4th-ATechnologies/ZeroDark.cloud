/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <TargetConditionals.h>
#import <Foundation/Foundation.h>
#import "AWSRegions.h"

@class ZeroDarkCloud;
@class ZDCLocalUser;
@class ZDCLocalUserAuth;
@class A0UserProfile;
@class ZDCPublicKey;
@class ZDCSymmetricKey;
@class ZDCAccessKeyBlob;

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

@protocol AccountSetup_Protocol
@required

- (void)pushIntro;

-(void) showWait:(NSString* __nonnull)title
		 message:(NSString* __nullable)message
 completionBlock:(dispatch_block_t __nullable)completionBlock;

-(void) cancelWait;

-(void) showError:(NSString* __nonnull)title
		  message:(NSString* __nullable)message
  completionBlock:(dispatch_block_t __nullable)completionBlock;

- (void)popFromCurrentView;

-(void)pushCreateAccount;
-(void)pushSignInToAccount;


- (void)pushAccountReady;
- (void)pushScanClodeCode;
- (void)pushUnlockCloneCode:(NSString* _Nonnull)cloneString;

- (void)pushRegionSelection;
- (void)pushIdentity;
- (void)pushDataBaseAuthenticate;
- (void)pushSocialAuthenticate;
- (void)pushDataBaseAccountCreate;
- (void)pushResumeActivationForUserID:(NSString* _Nonnull)userID;
- (void)pushReauthenticateWithUserID:(NSString* __nonnull)userID;

@end


#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
@interface AccountSetup_Base : UIViewController <AccountSetup_Protocol>
#else
#import <Cocoa/Cocoa.h>
@interface AccountSetup_Base : NSViewController <AccountSetup_Protocol>
#endif

NS_ASSUME_NONNULL_BEGIN
@property (nonatomic, readwrite, weak)		ZeroDarkCloud*        owner;

// intermediate values we keep until we are established
@property (nonatomic, readwrite)            AccountSetupMode        setupMode;
@property (nonatomic, readwrite)            IdenititySelectionMode   identityMode;
@property (nonatomic, readwrite ,nullable)  NSDictionary*      selectedProvider;
@property (nonatomic, readwrite ,nullable)  A0UserProfile*     userProfile;
@property (nonatomic, readwrite ,nullable)  NSData *           privKeyData;

@property (nonatomic, readwrite ,nullable)  NSString*          activationEmail;

// stuff that can be written into the DB
@property (nonatomic, readwrite ,nullable) ZDCLocalUserAuth*   auth;
@property (nonatomic, readwrite ,nullable) ZDCLocalUser*       user;
@property (nonatomic, readwrite ,nullable) ZDCPublicKey*       privKey;
@property (nonatomic, readwrite ,nullable) ZDCSymmetricKey*    accessKey;

-(void)resetAll;
-(void) handleFail;   // prototype method


// utility functions
-(BOOL)commonInitWithUserID:(NSString* __nonnull)userID error:(NSError **)errorOut;

- (ZDCLocalUser *)createLocalUserFromProfile:(A0UserProfile *)profile;

-(BOOL)isAlreadyLinkedError:(NSError*)error;

-(void) handleInternalError:(NSError*)error;

-(nullable NSString*) closestMatchingAuth0IDFromProfile:(A0UserProfile *)profile
                                               provider:(NSString*)provider
                                               userName:(nullable NSString*)userName;

// for an existing account - attempt to login to database account
-(void) databaseAccountLoginWithUserName:(NSString*)userName
						password:(NSString*)password
				 completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock;

// for an new account - attempt to create a database account
-(void) databaseAccountCreateWithUserName:(NSString*)userName
						   password:(NSString*)password
				 completionBlock:(void (^)(AccountState accountState, NSError *_Nullable error))completionBlock;

// for login using social accounts (facebook, google etc..)
-(void) socialAccountLoginWithAuth:(ZDCLocalUserAuth *)localUserAuth
                          profile:(A0UserProfile *)profile
                  preferedAuth0ID:(NSString* __nonnull)preferedAuth0ID
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
- (void)linkProfile:(A0UserProfile *)profile
	  toLocalUserID:(NSString *)localUserID
	completionQueue:(nullable dispatch_queue_t)completionQueue
	completionBlock:(nullable void (^)(NSError *_Nullable error))completionBlock;

- (void)unlinkAuth0ID:(NSString *)auth0ID
	  fromLocalUserID:(NSString *)localUserID
	  completionQueue:(nullable dispatch_queue_t)completionQueue
	  completionBlock:(nullable void (^)(NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
