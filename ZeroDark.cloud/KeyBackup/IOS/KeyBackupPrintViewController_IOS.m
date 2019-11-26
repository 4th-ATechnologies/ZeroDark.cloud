/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "KeyBackupPrintViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"

#import "ZDCUserAccessKeyManager.h"
#import "ZDCAccessCode.h"
#import "ZDCConstantsPrivate.h"
#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"
#import "NSString+ZeroDark.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation KeyBackupPrintViewController_IOS
{
	IBOutlet __weak UIView 			*_vwContainer;
	
	IBOutlet __weak UILabel 		*_lblTitle;
	IBOutlet __weak UILabel 	 	*_lblInfo;
	IBOutlet __weak UILabel 	 	*_lblPasscodeInfo;

	IBOutlet __weak UIView  		*_vwUser;

	IBOutlet __weak UIImageView  *_imgAvatar;
	IBOutlet __weak UILabel    	*_lblDisplayName;
	IBOutlet __weak UIImageView	*_imgProvider;
	IBOutlet __weak UILabel     	*_lblProvider;
	
	IBOutlet __weak UIImageView 	*_imgQRCode;
	
	NSString*  lblPasscodeInfoText;
}

@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];
	
	_imgAvatar.layer.cornerRadius = 50 / 2;
	_imgAvatar.clipsToBounds = YES;
	
	lblPasscodeInfoText = _lblPasscodeInfo.text;
	
}


-(void) refreshViewWithQRCodeString:(NSString * _Nullable)qrCodeString
									 hasPassCode:(BOOL)hasPassCode
							completion:(void (^)(NSError *_Nullable error ))completionBlock

{
	NSAssert(NO, @"Not implemented"); // finish refactoring
	
/*
	__weak typeof(self) weakSelf = self;
	
	Auth0ProviderManager	 * providerManager= self.keyBackupVC.owner.auth0ProviderManager;
	ZDCImageManager  * imageManager= self.keyBackupVC.owner.imageManager;
	ZDCLocalUser* localUser = self.keyBackupVC.user;
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:localUser.uuid options:0];
	NSString* userIDb58  = [NSString base58WithData:data];
	
	_lblTitle.text = [NSString stringWithFormat:
							NSLocalizedString(@"Key Backup for UserID: %@", @"Key Backup for UserID: %@"),
							userIDb58];
	
	_imgQRCode.image = [OSImage QRImageWithString:qrCodeString
													 withSize:CGSizeMake(400, 400)];
	
	//TODO: code here to inform user that there is a passode
	if(hasPassCode)
	{
		_lblPasscodeInfo.hidden = NO;
		_lblPasscodeInfo.text = lblPasscodeInfoText;
	}
	else
	{
		_lblPasscodeInfo.hidden = YES;
		_lblPasscodeInfo.text = @"";;
	}
	
	[_lblPasscodeInfo sizeToFit];
	
	NSString* displayName = localUser.displayName;
	_lblDisplayName.text = displayName;
	
	NSArray* comps = [localUser.auth0_preferredID componentsSeparatedByString:@"|"];
	NSString* provider = comps.firstObject;
	
	OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin
															  forProvider:provider] scaledToHeight:_imgProvider.frame.size.height];
	if(providerImage)
	{
		_imgProvider.hidden = NO;
		_imgProvider.image = providerImage;
		_lblProvider.hidden = YES;
	}
	else
	{
		_imgProvider.hidden = YES;
		_lblProvider.text = provider;
		_lblProvider.hidden = NO;
	}
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: imageManager.defaultUserAvatar;
		
		if (!willFetch)
		{
			if (completionBlock) {
				completionBlock(nil);
			}
		}
	};
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: imageManager.defaultUserAvatar;
		
		if (completionBlock) {
			completionBlock(nil);
		}
	};
	
	[imageManager fetchUserAvatar: localUser
	                  withOptions: nil
	                preFetchBlock: preFetchBlock
	               postFetchBlock: postFetchBlock];
*/
}

-(void)createBackupDocumentWithQRCodeString:(NSString * _Nullable)qrCodeString
										  hasPassCode:(BOOL)hasPassCode
									 completionBlock:(void (^_Nullable)(NSURL *_Nullable url,
																					UIImage* _Nullable image,
																					NSError *_Nullable error ))completionBlock
{
	
	__weak typeof(self) weakSelf = self;
	
	ZDCLocalUser* localUser = self.keyBackupVC.user;
	NSData* data = [[NSData alloc] initWithBase64EncodedString:localUser.uuid options:0];
	NSString* userIDb58  = [NSString base58WithData:data];

	
	NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
	NSURL *fileURL = [[tempDir URLByAppendingPathComponent:userIDb58 isDirectory:NO]
							URLByAppendingPathExtension:@"pdf" ];
	
	self.view.frame = CGRectMake(0, 0, 792, 1102);
	
	NSMutableData* pdfData = NSMutableData.data;
	__block UIImage *shareImage = nil;
	
	[self refreshViewWithQRCodeString:qrCodeString
								 hasPassCode:hasPassCode
							 completion:^(NSError * _Nullable error)
	{
	 
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		if(error)
		{
			if(completionBlock)
				completionBlock(nil,nil,error);
			return;
		}
		
 		[strongSelf.view setNeedsLayout];
		[strongSelf.view layoutIfNeeded];
 
		UIGraphicsBeginImageContextWithOptions(strongSelf->_vwContainer.frame.size, NO, 1.0);
		[strongSelf->_vwContainer.layer renderInContext:UIGraphicsGetCurrentContext()];
		shareImage = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		
		UIGraphicsBeginPDFContextToData(pdfData, strongSelf.view.bounds, nil);
		UIGraphicsBeginPDFPage();
		CGContextRef pdfContext = UIGraphicsGetCurrentContext();
		[strongSelf.view.layer renderInContext:pdfContext];
		UIGraphicsEndPDFContext();
		
		[pdfData writeToURL:fileURL
						options:NSDataWritingAtomic error:&error];
		
		if(completionBlock)
		{
			if(error)
				completionBlock(nil,nil,error);
			else
				completionBlock(fileURL,shareImage,error);
		}
		
	}];
}


@end
