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
#import <S4Crypto/S4Crypto.h>

@class ZeroDarkCloud;
@class ZDCLocalUser;
@class ZDCSplitKey;
@class YapDatabaseReadTransaction;

typedef NS_ENUM(NSInteger, KeyBackupViewID) {
	KeyBackupViewID_Unknown                = 0,

	KeyBackupViewID_BackupIntro,
	KeyBackupViewID_BackupAsText,
	KeyBackupViewID_BackupAsCombo,
	KeyBackupViewID_VerifyText,
	KeyBackupViewID_BackupAsImage,
	KeyBackupViewID_VerifyImage,
    KeyBackupViewID_UnlockAccessCode,
    KeyBackupViewID_Success,
    KeyBackupViewID_Social_Intro,
	KeyBackupViewID_Print,
	KeyBackupViewID_CloneDevice,
};

@protocol KeyBackup_Base_Protocol
@required

-(void) showWait:(NSString* __nonnull)title
		 message:(NSString* __nullable)message
 completionBlock:(dispatch_block_t __nullable)completionBlock;

-(void) cancelWait;

-(void) showError:(NSString* __nonnull)title
		  message:(NSString* __nullable)message
  completionBlock:(dispatch_block_t __nullable)completionBlock;

//- (void)pushBackupWithUserID:(NSString* _Nonnull)userID;
- (void)pushBackupAsText;
- (void)pushBackupAsImage;
- (void)pushBackupAsCombo;
- (void)pushVerifyText;
- (void)pushVerifyImage;
- (void)pushBackupSocial;
- (void)pushBackupSuccess;
- (void)pushUnlockAccessCode:(NSString* __nullable)cloneString;

- (void)popFromCurrentView;

- (void)handleDone;

@end


#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
@interface KeyBackup_Base : UIViewController <KeyBackup_Base_Protocol>
#else
#import <Cocoa/Cocoa.h>
@interface KeyBackup_Base : NSViewController <KeyBackup_Base_Protocol>
#endif

NS_ASSUME_NONNULL_BEGIN
@property (nonatomic, readwrite, weak)		ZeroDarkCloud*	owner;
@property (nonatomic, readwrite, strong)	NSString* 		currentLanguageId;
@property (nonatomic, readonly, nullable)	NSArray<NSString*> *  currentBIP39WordList;

@property (nonatomic, readonly	)			NSData* 		accessKeyData;

// stuff that can be written into the DB
@property (nonatomic, readwrite ,nullable) ZDCLocalUser*       user;

-(void)commonInit;

-(NSString *)accessKeyStringWithPasscode:(NSString * _Nullable )passcode
									 p2kAlgorithm:(P2K_Algorithm)p2kAlgorithm
								   error:(NSError *_Nullable *_Nullable) outError;

-(void) createSplitKeyWithTotalShares:(NSUInteger)totalShares
									 threshold:(NSUInteger)threshold
						  shareKeyAlgorithm:(Cipher_Algorithm)shareKeyAlgorithm
										comment:(NSString *_Nullable)comment
							 completionQueue:(nullable dispatch_queue_t)completionQueue
							 completionBlock:(nullable void (^)( ZDCSplitKey *_Nullable splitKey,
																			NSDictionary<NSString *, NSString *>*_Nullable shareDict,
																			NSDictionary<NSString *, NSData *>*_Nullable shareKeys,
																			NSError *_Nullable error))completionBlock;

-(void)didSendShareID:(NSString*)shareID
		  forSplitKeyID:(NSString*)splitkeyID
		completionBlock:(dispatch_block_t)completionBlock;
 
-(void)removeSplitKeyID:(NSString*)splitkeyID
		  completionBlock:(dispatch_block_t)completionBlock;

-(NSUInteger)numberOfSplitsWithTransAction:(YapDatabaseReadTransaction*)transaction;

-(void) handleFail;   // prototype method

-(void) handleInternalError:(NSError*)error;

-(BOOL)commonInitWithUserID:(NSString* __nonnull)userID error:(NSError **)errorOut;

- (NSError *)errorWithDescription:(NSString *)description statusCode:(NSUInteger)statusCode;

-(void) setBackupVerifiedForUserID:(NSString*)userID
                   completionBlock:(dispatch_block_t)completionBlock;


@end

NS_ASSUME_NONNULL_END

