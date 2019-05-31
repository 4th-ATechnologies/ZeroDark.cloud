/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import <UIKit/UIKit.h>
#import "KeyBackupViewController_IOS.h"

@interface KeyBackupPrintViewController_IOS : KeyBackupSubViewController_Base

-(void)createBackupDocumentWithQRCodeString:(NSString * _Nullable)qrCodeString
										  hasPassCode:(BOOL)hasPassCode
									 completionBlock:(void (^_Nullable)(NSURL *_Nullable url,
																					UIImage* _Nullable image,
																					NSError *_Nullable error ))completionBlock;

@end
