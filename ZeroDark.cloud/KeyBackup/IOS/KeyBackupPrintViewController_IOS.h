/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
