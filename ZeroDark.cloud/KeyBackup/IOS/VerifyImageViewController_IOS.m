
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "VerifyImageViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"

#import "ZDCUserAccessKeyManager.h"
#import "ZDCAccessCode.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCSound.h"

#import "SCShapeView.h"
#import "QRcodeView.h"

// Categories
#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"
#import "UIButton+Activation.h"
#import "NSError+S4.h"
#import "UIImageViewPasteable.h"

// Libraries
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

@import CoreImage;
@import ImageIO;
#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)



@implementation VerifyImageViewController_IOS
{

    QRcodeView  *   _overlayView;
    IBOutlet __weak UILabel*    _lblTitle;
    IBOutlet __weak UIImageViewPasteable *   _imgPasteOverlay;
    IBOutlet __weak UIView *   _viewPreview;
    IBOutlet __weak UIView *   _portalPlaceholderView;
    IBOutlet __weak UIImageView* _imgNoCamera;
    IBOutlet __weak UILabel*    _lblStatus;
    IBOutlet __weak UIButton*   _btnStatus;

    SCShapeView *   _boundingBox;
    NSTimer *       _boxHideTimer;
    
    IBOutlet  __weak UIButton   *_btnPhoto;
    IBOutlet  __weak UIButton   *_btnPaste;

    UIDocumentPickerViewController *docPicker;
    UIImagePickerController     *photoPicker;
    
    AVCaptureSession *          captureSession;
    AVCaptureVideoPreviewLayer *videoPreviewLayer;
    
    NSString*           lastQRCode;
    BOOL                isReading;
    BOOL                hasCamera;
    BOOL                isUsingCarmera;

    YapDatabaseConnection *         databaseConnection;

	UISwipeGestureRecognizer 				*swipeRight;

}


@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

    void (^TintButtonImage)(UIButton *) = ^(UIButton *button){

        UIImage *image = [button imageForState:UIControlStateNormal];
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

        [button setImage:image forState: UIControlStateNormal];
        button.tintColor = self.view.tintColor;
    };

    TintButtonImage(_btnPaste);
    TintButtonImage(_btnPhoto);
    
    _imgPasteOverlay.delegate =  (id<UIImageViewPasteableDelegate>)self;
    _imgPasteOverlay.canPaste = YES;
}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;

	self.navigationItem.title = @"Verify Image Backup";

	UIImage* image = [[UIImage imageNamed:@"backarrow"
								 inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																 style:UIBarButtonItemStylePlain
																target:self
																action:@selector(handleNavigationBack:)];

	self.navigationItem.leftBarButtonItem = backItem;

	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];
 
    
    _btnStatus.hidden = YES;
    
    [self setCameraStatusString:NSLocalizedString(@"Checking camera access…",
                                                  @"Checking camera access…")
                       isButton:NO
                          color:UIColor.whiteColor];
    
    _imgNoCamera.hidden = YES;
    
	[self refreshView];
    [self refreshCloneCodeView];

}


-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    BOOL canPaste = [[UIPasteboard generalPasteboard] image] != nil;
    _btnPaste.enabled = canPaste;
    
 }

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;

    isUsingCarmera = NO;
    [self stopReading];

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}


-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
 		[self handleNavigationBack:NULL];
 }

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}



- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;

}


-(void) refreshView
{

}

#pragma mark - camera

-(void)hideNoCamera:(BOOL)shouldHide
         completion:(dispatch_block_t)completion
{
	__weak typeof(self) weakSelf = self;

    [UIView animateWithDuration:0.1 animations:^{
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

        if(shouldHide)
        {
            strongSelf->_imgNoCamera.alpha = 0.0;
        }
        else
        {
            strongSelf->_imgNoCamera.alpha = 1.0;
            
        }
        
    } completion:^(BOOL finished) {
        if(completion)
            completion();
    }];
}

-(void)setCameraStatusString:(NSString*)string
                    isButton:(BOOL)isButton
                       color:(UIColor*)color
{
    if(isButton)
    {
        _lblStatus.hidden = YES;
        _btnStatus.hidden = NO;
        [_btnStatus setTitle:string forState:UIControlStateNormal];
        [_btnStatus.titleLabel  setTextAlignment: NSTextAlignmentCenter];
        [_btnStatus.titleLabel setTextColor:color];
    }
    else
    {
        _lblStatus.text = string;
        _lblStatus.textColor = color;
        _lblStatus.hidden = NO;
        _btnStatus.hidden = YES;
    }
}

-(void)displayInstructions:(NSString*)message withColor:(OSColor*)color forSeconds:(NSTimeInterval) seconds
{
    _btnStatus.hidden = YES;
    _lblStatus.hidden = NO;
    
    if([message isEqualToString:_lblStatus.text])
        return;
    
    NSString* savedMessage = _lblStatus.text;
    OSColor* savedColor = _lblStatus.textColor;
    
    [self setCameraStatusString:message
                       isButton:NO color:color];
    //    _lblStatus.text =  message;
    //    _lblStatus.textColor = color;
    
    CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulseAnimation.duration = 0.25;
    pulseAnimation.toValue = [NSNumber numberWithFloat:1.2F];
    pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    pulseAnimation.autoreverses = YES;
    pulseAnimation.repeatCount = 1;
    [_lblStatus.layer addAnimation:pulseAnimation forKey:nil];
    
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        
        [self setCameraStatusString:savedMessage
                           isButton:NO color:savedColor];
        
        //        _lblStatus.text =  savedMessage;
        //        _lblStatus.textColor = savedColor;
    });
}


-(void) refreshCloneCodeView
{
	__weak typeof(self) weakSelf = self;
	

    lastQRCode = NULL;
    
    if(ZDCConstants.appHasCameraPermission)
    {
        hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];
        
        if(hasCamera)
        {
            // check camera authorization status
            AVAuthorizationStatus cameraAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
            
            switch (cameraAuthStatus) {
                    
                case AVAuthorizationStatusAuthorized: { // camera authorized
                    
                    [self hideNoCamera:YES completion:^{
                        [self startReading];
                    }];
                }
                    break;
                    
					case AVAuthorizationStatusNotDetermined: { // request authorization
						
						[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
							dispatch_async(dispatch_get_main_queue(), ^{
								
								__strong typeof(self) strongSelf = weakSelf;
								if(!strongSelf) return;
								
								
								if(granted) {
									[strongSelf hideNoCamera:YES completion:^{
										[strongSelf startReading];
									}];
									
								} else {
									
									strongSelf->_imgNoCamera.hidden = NO;
									
									[strongSelf setCameraStatusString:
									 NSLocalizedString(@"This device cannot scan access key because camera access is denied.",
															 @"camera access is denied")
																	 isButton:YES
																		 color:self.view.tintColor];
								}
							});
						}];
					}
                    break;
                    
                default:
                {
                    
                    _imgNoCamera.hidden = NO;
                    [self setCameraStatusString:NSLocalizedString(@"This device cannot scan access key, camera access is denied.",
                                                                  @"camera access is denied")
                                       isButton:YES
                                          color:UIColor.redColor];
                    
                }
            }
        }
        else
        {
            _imgNoCamera.hidden = NO;
            
            NSString* message =   NSLocalizedString(@"Camera is not available on this device.",
                                                    @"Camera is not available on this device");
            if(ZDCConstants.isSimulator)
                message = NSLocalizedString(@"Camera is not available on the simulator.",
                                            @"Camera is not available on the simulator");
            

            [self setCameraStatusString:message
                               isButton:NO
                                  color:UIColor.redColor];
            
            
        }
    }
    else
    {
        _imgNoCamera.hidden = NO;
        [self setCameraStatusString:NSLocalizedString(@"This device cannot scan access key, camera access is not enabled by this application.",
                                                      @"camera access is not enabled by this application")
                           isButton:NO
                              color:UIColor.redColor];
    }
}


#pragma  mark - check QRcode


- (void)setQRCodeWithImage:(UIImage *)image
{
	__weak typeof(self) weakSelf = self;

    NSString *qrString = image.QRCodeString;
    
    BOOL isValid = [ZDCAccessCode isValidCodeString:qrString
                                          forUserID:keyBackupVC.user.uuid];
    
    dispatch_async(dispatch_get_main_queue(), ^{
		 
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

        if(isValid)
        {
            strongSelf->lastQRCode = qrString;
            
            strongSelf->isUsingCarmera = NO;
            [strongSelf stopReading];
            [strongSelf foundCloneString:strongSelf->lastQRCode];
        }
        else
        {
            [strongSelf displayInstructions:NSLocalizedString(@"This is not the correct code for this user.",
                                                        @"This is not the correct code for this user.")
                            withColor:[OSColor redColor]
                           forSeconds:2];
        }
    });
}


-(void) foundCloneString:(NSString*)cloneString
{
    NSError* error = NULL;
     __weak typeof(self) weakSelf = self;
	
	NSData* salt = [keyBackupVC.user.syncedSalt dataUsingEncoding:NSUTF8StringEncoding];

    // try and unlock it with built in code
    NSData* accessKeyData = [ZDCAccessCode accessKeyDataFromString:cloneString
                                                      withPasscode:keyBackupVC.user.syncedSalt
																				  salt:salt
                                                             error:&error];
    
    
    if(!error
       && accessKeyData
       && [accessKeyData isEqual:keyBackupVC.accessKeyData])
    {
         // good key
        [keyBackupVC  setBackupVerifiedForUserID:keyBackupVC.user.uuid
                                 completionBlock:^
         {
             __strong typeof(self) ss = weakSelf;
             if (!ss) return;
             [ss->keyBackupVC pushBackupSuccess];
         }];
    }
    else
    {
        // BAD KEY
        NSString* errorString =  error.localizedDescription;
        
        if([error.domain isEqualToString:S4FrameworkErrorDomain]
           && error.code == kS4Err_BadIntegrity)
        {
          // needs unlock
            [self stopReading];
            [keyBackupVC pushUnlockAccessCode:cloneString];
        }
        else
        {
            [self displayInstructions:errorString
                            withColor:UIColor.redColor
                           forSeconds:2];
            
            [self startReading];

        }
     }
}
#pragma mark - IBActions


- (IBAction)pasteButtonTapped:(id)sender
{
    ZDCLogAutoTrace();
    UIImage *image = [[UIPasteboard generalPasteboard] image];
    if (image)
    {
        [self setQRCodeWithImage:image];
    }
    
}

-(void)displayCodeImportMenu:(id)sender
             canAccessPhotos:(BOOL)canAccessPhotos
          shouldAccessPhotos:(BOOL)shouldAccessPhotos

{
    __weak typeof(self) weakSelf = self;
    
    UIButton* btn = sender;
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Import Access Code"
                                                                             message:NULL
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIImage *photoImage = [[UIImage imageNamed:@"photos"
                                      inBundle:[ZeroDarkCloud frameworkBundle]
                 compatibleWithTraitCollection:nil]  scaledToHeight:32];
    
    UIImage *documentsImage = [[UIImage imageNamed:@"files"
                                          inBundle:[ZeroDarkCloud frameworkBundle]
                     compatibleWithTraitCollection:nil]  scaledToHeight:32];
    
    UIAlertAction *photoAction =
    [UIAlertAction actionWithTitle: NSLocalizedString(@"Photos", @"Photos")
                             style:UIAlertActionStyleDefault
                           handler:^(UIAlertAction *action)
     {
         
         __strong typeof(self) strongSelf = weakSelf;
         if (strongSelf) {
             [strongSelf showPhotoPicker];
         }
     }];
    [photoAction setValue:[photoImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                   forKey:@"image"];
    
    UIAlertAction *noPhotoAction =
    [UIAlertAction actionWithTitle: NSLocalizedString(@"Photos Access Off", @"Photos Access Off")
                             style:UIAlertActionStyleDefault
                           handler:^(UIAlertAction *action)
	{
		if (UIApplicationOpenSettingsURLString != nil)
		{
			NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
			NSDictionary *options = @{};
			[[UIApplication sharedApplication] openURL:url options:options completionHandler:nil];
		}
	}];
	
	[noPhotoAction setValue:[photoImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                     forKey:@"image"];
    
    
    UIAlertAction *documentsAction =
    [UIAlertAction actionWithTitle:NSLocalizedString(@"Documents", @"Documents action")
                             style:UIAlertActionStyleDefault
                           handler:^(UIAlertAction * _Nonnull action) {
                               
                               __strong typeof(self) strongSelf = weakSelf;
                               if (strongSelf) {
                                   [strongSelf showDocPicker];
                               }
                               
                           }];
    [documentsAction setValue:[documentsImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                       forKey:@"image"];
    
    UIAlertAction *cancelAction =
    [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action")
                             style:UIAlertActionStyleCancel
                           handler:^(UIAlertAction * _Nonnull action) {
                               
                           }];
    if(canAccessPhotos)
    {
        if(shouldAccessPhotos)
            [alertController addAction:photoAction];
        else
            [alertController addAction:noPhotoAction];
    }
    
    [alertController addAction:documentsAction];
    [alertController addAction:cancelAction];
    
    if(ZDCConstants.isIPad)
    {
        alertController.popoverPresentationController.sourceRect = btn.bounds;
        alertController.popoverPresentationController.sourceView = btn;
        alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
    }
    
    [self presentViewController:alertController animated:YES
                     completion:^{
                     }];
    
}

- (IBAction)photosButtonTapped:(id)sender
{
    ZDCLogAutoTrace();
    
    if(ZDCConstants.appHasPhotosPermission)
    {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                switch (status) {
                        
                    case PHAuthorizationStatusAuthorized:
                        [self displayCodeImportMenu:sender
                                    canAccessPhotos:YES
                                 shouldAccessPhotos:YES];
                        break;
                        
                    case PHAuthorizationStatusRestricted:
                    {
                        [self displayCodeImportMenu:sender
                                    canAccessPhotos:YES
                                 shouldAccessPhotos:NO];
                    }
                        break;
                        
                    case PHAuthorizationStatusDenied:
                    {
                        [self displayCodeImportMenu:sender
                                    canAccessPhotos:YES
                                 shouldAccessPhotos:NO];
                    }
                        break;
                    default:
                        break;
                }
            });
            
        }];
        
    }else
    {
        [self displayCodeImportMenu:sender
                    canAccessPhotos:NO
                 shouldAccessPhotos:NO];
        
    }
}

- (IBAction)statusButtonTapped:(id)sender
{
	if (UIApplicationOpenSettingsURLString != nil)
	{
		NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
		NSDictionary *options = @{};
		[[UIApplication sharedApplication] openURL:url options:options completionHandler:nil];
	}
}

- (void)showPhotoPicker
{
    ZDCLogAutoTrace();
    
    photoPicker = [[UIImagePickerController alloc] init];
    photoPicker.delegate      = (id <UINavigationControllerDelegate, UIImagePickerControllerDelegate>)self;
    photoPicker.sourceType    = UIImagePickerControllerSourceTypePhotoLibrary;
    photoPicker.allowsEditing = NO;
    
    [self presentViewController:photoPicker animated:YES completion:NULL];
    
}

- (void)showDocPicker
{
    ZDCLogAutoTrace();
    docPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ (__bridge NSString *)kUTTypeImage]
                                                                       inMode:UIDocumentPickerModeImport];
    
    docPicker.delegate = (id <UIDocumentPickerDelegate>) self;
    [self presentViewController:docPicker animated:YES completion:NULL];
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIDocumentPickerViewControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)documentPicker:(UIDocumentPickerViewController *)documentPicker didPickDocumentAtURL:(NSURL *)url
{
    ZDCLogAutoTrace();
    
    if (url)
    {
        UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:url]];
        
        [self setQRCodeWithImage:image];
        
    }
    
    docPicker = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    ZDCLogAutoTrace();
    
    docPicker = nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIImagePickerControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)sender
{
    ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;
   [self dismissViewControllerAnimated:YES completion:^{
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

        if (strongSelf->photoPicker == sender) {
            strongSelf->photoPicker = nil;
        }
    }];
}

- (void)imagePickerController:(UIImagePickerController *)sender didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    ZDCLogAutoTrace();
 	__weak typeof(self) weakSelf = self;
    UIImage *image = nil;
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    
    if (UTTypeConformsTo((__bridge CFStringRef)mediaType, kUTTypeImage))
    {
        image = [info objectForKey:UIImagePickerControllerOriginalImage];
    }
    
    [self dismissViewControllerAnimated:YES  completion:^{
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(!strongSelf) return;

        if (strongSelf->photoPicker == sender) {
            strongSelf->photoPicker = nil;
        }
        
        if (image)
        {
            [strongSelf setQRCodeWithImage:image];
        }
    }];
}



- (void)startReading
{
    NSError *error;
    
    isReading  = YES;
    
    
    // Get an instance of the AVCaptureDevice class to initialize a device object and provide the video
    // as the media type parameter.
    AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    // Get an instance of the AVCaptureDeviceInput class using the previous device object.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    
    if(error)
    {
        //        [S4IOSSettingsManager displayCameraAccessSettingsAlert];
        return;
    }
    
    // Initialize the captureSession object.
    captureSession = [[AVCaptureSession alloc] init];
    // Set the input device on the capture session.
    [captureSession addInput:input];
    
    
    // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
    AVCaptureMetadataOutput *captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [captureSession addOutput:captureMetadataOutput];
    
    // Create a new serial dispatch queue.
    //    dispatch_queue_t dispatchQueue;
    //    dispatchQueue = dispatch_queue_create("myQueue", NULL);
    [captureMetadataOutput setMetadataObjectsDelegate:(id<AVCaptureMetadataOutputObjectsDelegate>)self
                                                queue:dispatch_get_main_queue()];
    [captureMetadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:AVMetadataObjectTypeQRCode]];
    
    // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
    videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [videoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [videoPreviewLayer setFrame:_viewPreview.layer.bounds];
    [_viewPreview.layer addSublayer:videoPreviewLayer];
    _viewPreview.layer.cornerRadius    = 8.0f;
    _viewPreview.layer.masksToBounds    = YES;
    
    // Add the view to draw the bounding box for the UIView
    _boundingBox = [[SCShapeView alloc] initWithFrame:_viewPreview.bounds];
    _boundingBox.backgroundColor = [UIColor clearColor];
    _boundingBox.hidden = YES;
    [_viewPreview addSubview:_boundingBox];
    
    //
    _overlayView = [[QRcodeView alloc] initWithFrame:_viewPreview.bounds];
    _overlayView.backgroundColor = [UIColor clearColor];
    _overlayView.portalRect = _portalPlaceholderView.frame;
    _overlayView.hidden = NO;
    [_viewPreview addSubview:_overlayView];
    
    // Start video capture.
    [captureSession startRunning];
    //
    //    _btnStatus.hidden = YES;
    //    _lblStatus.text = NSLocalizedString(@"Place the code in the center of the screen. It will be scanned automatically.", @"Place the code in the center of the screen. It will be scanned automatically.");
    //    _lblStatus.hidden = NO;
    
    [self setCameraStatusString:@"Place the code in the center of the screen. It will be scanned automatically."
                       isButton:NO
                          color:UIColor.whiteColor];
    
    isUsingCarmera = YES;
}


-(void)stopReading{
    
    if(captureSession)
    {
        // Stop video capture and make the capture session object nil.
        [captureSession stopRunning];
        captureSession = nil;
    }
    
    // Remove the video preview layer from the viewPreview view's layer.
    if(videoPreviewLayer)
        [videoPreviewLayer removeFromSuperlayer];
}

- (void)startOverlayHideTimer
{
    // Cancel it if we're already running
    if(_boxHideTimer) {
        [_boxHideTimer invalidate];
    }
    
    // Restart it to hide the overlay when it fires
    _boxHideTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                     target:self
                                                   selector:@selector(foundQRCodeInOverlay:)
                                                   userInfo:nil
                                                    repeats:NO];
}



- (void)foundQRCodeInOverlay:(id)sender
{
	__weak typeof(self) weakSelf = self;
	
    // Hide the box and remove the decoded text
    _boundingBox.hidden = YES;
    
    if (lastQRCode)
    {
        BOOL isValid = [ZDCAccessCode isValidCodeString:lastQRCode
                                              forUserID:keyBackupVC.user.uuid];
        if (isValid)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
					
					__strong typeof(self) strongSelf = weakSelf;
					if(!strongSelf) return;

                [strongSelf foundCloneString:strongSelf->lastQRCode];
            });
        }
    }
}


- (NSArray *)translatePoints:(NSArray *)points fromView:(UIView *)fromView toView:(UIView *)toView
{
    NSMutableArray *translatedPoints = [NSMutableArray new];
    
    // The points are provided in a dictionary with keys X and Y
    for (NSDictionary *point in points) {
        // Let's turn them into CGPoints
        CGPoint pointValue = CGPointMake([point[@"X"] floatValue], [point[@"Y"] floatValue]);
        // Now translate from one view to the other
        CGPoint translatedPoint = [fromView convertPoint:pointValue toView:toView];
        // Box them up and add to the array
        [translatedPoints addObject:[NSValue valueWithCGPoint:translatedPoint]];
    }
    
    return [translatedPoints copy];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AVCaptureMetadataOutputObjectsDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    
    for (AVMetadataObject *metadata in metadataObjects)
    {
        if ([metadata.type isEqualToString:AVMetadataObjectTypeQRCode])
        {
            // Transform the meta-data coordinates to screen coords
            AVMetadataMachineReadableCodeObject *transformed
            = (AVMetadataMachineReadableCodeObject *)[videoPreviewLayer transformedMetadataObjectForMetadataObject:metadata];
            
            // Update the frame on the _boundingBox view, and show it
            _boundingBox.frame = transformed.bounds;
            _boundingBox.hidden = NO;
            
            // Now convert the corners array into CGPoints in the coordinate system
            //  of the bounding box itself
            NSArray *translatedCorners = [self translatePoints:transformed.corners
                                                      fromView:_viewPreview
                                                        toView:_boundingBox];
            
            // Set the corners array
            _boundingBox.corners = translatedCorners;
            
            // Start the timer which will hide the overlay
            [self startOverlayHideTimer];
            
            // only do this once
            if(isReading)
            {
                BOOL isValid = [ZDCAccessCode isValidCodeString:transformed.stringValue
                                                      forUserID:keyBackupVC.user.uuid];
                
                if(isValid)
                {
                    
                    [ZDCSound playBeepSound];
                    
                    // Update the view with the decoded text
                    
                    [self displayInstructions:NSLocalizedString(@"key found",
                                                                @"key found")
                                    withColor:[OSColor greenColor]
                                   forSeconds:2];
                    
                    
                    lastQRCode = transformed.stringValue;
                    
                    // stop capture
                    isUsingCarmera = NO;
                    [self stopReading];
                }
                else
                {
                    [self displayInstructions:NSLocalizedString(@"These are not the clones I am looking for...",
                                                                @"These are not the clones I am looking for...")
                                    withColor:[OSColor redColor]
                                   forSeconds:2];
                    
                }
            }
        }
    }
}

#pragma mark - UIImageViewPasteable
- (void)imageViewPasteable:(UIImageViewPasteable *)sender pasteImage:(UIImage *)image
{
    if (image)
    {
        [self setQRCodeWithImage:image];
    }
}

@end
