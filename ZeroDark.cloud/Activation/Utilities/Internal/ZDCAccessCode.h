//
//  ZDCAccessCode.h
//  ZeroDarkCloud
//
//  Created by vinnie on 3/12/19.
//

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>
#import "OSPlatform.h"



NS_ASSUME_NONNULL_BEGIN

@class ZDCSplitKey;
extern NSString *const kZDCSplitKeyProp_ShareNum;

@interface ZDCAccessCode : NSObject

+ (BOOL)isValidCodeString:(NSString *)codeString
				forUserID:(NSString *)userID;

+ (BOOL)isValidShareString:(NSString *)codeString
					 forUserID:(NSString *)userID;

+ (NSData*)accessKeyDataFromString:(NSString *)cloneString
							 withPasscode:(NSString *)passcode
										salt:(NSData*)salt
									  error:(NSError *_Nullable *_Nullable) outError;

+ (NSString*)accessKeyStringFromData:(NSData*)accessKeyData
								withPasscode:(NSString *_Nullable)passcode
								p2kAlgorithm:(P2K_Algorithm)p2kAlgorithm
										userID:(NSString* __nonnull)userID
										  salt:(NSData* _Nullable)salt
										 error:(NSError *_Nullable *_Nullable) outError;

+ (NSString* _Nullable)splitKeyStringFromData:(NSData*)accessKeyData
											 totalShares:(NSUInteger)totalShares
												threshold:(NSUInteger)threshold
								 additionalProperties:(NSDictionary<NSString *, NSObject *> *_Nullable)additionalProperties
													shares:(NSDictionary<NSString *, NSString *>*_Nullable *_Nullable) outShares
													 error:(NSError *_Nullable *_Nullable) outError;

// Use this to create a QRcode
+ (NSString* _Nullable)shareDataStringFromShare:(NSString*)shareIn
												 localUserID:(NSString*)localUserID
														 error:(NSError *_Nullable *_Nullable) outError;

+ (NSData* _Nullable)exportableShareDataFromShare:(NSString*)shareIn
												localUserID:(NSString*)localUserID
														error:(NSError *_Nullable *_Nullable) outError;

+(NSData* _Nullable)dataFromShareDataString:(NSString*)shareString
												  error:(NSError *_Nullable *_Nullable) outError;


+ (NSString* _Nullable)shareCodeEntryFromShare:(NSString*)shareIn
												 algorithm:(Cipher_Algorithm)algorithm
											 encyptionKey:(NSData*_Nullable *_Nullable) encyptionKeyOut
													  error:(NSError *_Nullable *_Nullable) outError;

+ (NSString* _Nullable)decryptShareWithShareCodeEntry:(NSString*)entry
													 decryptionKey:(NSData*) decryptionKey
																error:(NSError *_Nullable *_Nullable) outError;

+ (NSData* _Nullable) accessKeyDataFromSplit:(NSString *)splitKey
											 withShares:(NSArray<NSString *>*)shares
													error:(NSError *_Nullable *_Nullable) outError;

+ (NSString*) stringFromShareNum:(NSNumber*)shareNum;

//+( NSAttributedString*) attributedStringFromShareNum:(NSNumber*)shareNum;

+(void) attributedStringFromShareNum:(NSNumber*)shareNum
										string:(NSAttributedString*_Nullable *_Nullable )outString
									  bgColor:(OSColor*_Nullable *_Nullable)outbgColor;

/// debug tool
+(BOOL)compareEncodedShareString:(NSString*)encodedString
					  shareDictString:(NSString*)shareDictString
							localUserID:(NSString *)localUserID
									error:(NSError *_Nullable *_Nullable) outError;

@end


NS_ASSUME_NONNULL_END
