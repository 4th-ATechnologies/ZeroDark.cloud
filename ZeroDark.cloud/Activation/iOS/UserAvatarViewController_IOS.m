/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "UserAvatarViewController_IOS.h"

#import "UIImageViewPasteable.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCFileConversion.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCUIToolsPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "OSImage+ZeroDark.h"

// Libraries
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


typedef NS_ENUM(NSInteger, ZDCButton) {
	ZDCButton_Camera   = 0,
	ZDCButton_Photos ,
	ZDCButton_Documents ,
	ZDCButton_Paste,
	ZDCButton_Remove,
	
	ZDCButton_Last,
};

@implementation UserAvatarViewController_IOS
{
	IBOutlet __weak UIImageViewPasteable   *_imgAvatar;
	IBOutlet __weak UILabel                *_lblDisplayName;
	IBOutlet __weak UIImageView 				*_imgProvider;
	IBOutlet __weak UILabel     				*_lblProvider;
	
	IBOutlet __weak UITableView             *_tblButtons;
	IBOutlet __weak NSLayoutConstraint      *_cnstTblButtonsHeight;
	
	YapDatabaseConnection 				*databaseConnection;
	ZDCImageManager						*imageManager;
	Auth0ProviderManager					*providerManager;
	ZDCUITools								*uiTools;
	
	UIImage*        defaultUserImage;
	UIImage*        cameraImage;
	UIImage*        photosImage;
	UIImage*        pasteImage;
	UIImage*        documentsImage;
	UIImage*        removeImage;
	
	OSImage*        newUserImage;
	OSImage*        currentUserImage;
	BOOL            deleteUserImage;
	BOOL            hasChanges;
	
	BOOL             hasCamera;
	UIDocumentPickerViewController  *docPicker;
	UIImagePickerController         *photoPicker;
	
	UIViewController                *currentVC;      // currently posted view controller, used for removing on passcode lock
	
}

@synthesize accountSetupVC = accountSetupVC;
@synthesize userID = userID;
@synthesize auth0ID = auth0ID;

- (void)viewDidLoad {
	[super viewDidLoad];
	
	defaultUserImage = [imageManager.defaultUserAvatar imageWithMaxSize:_imgAvatar.frame.size];
	
	_imgAvatar.delegate = (id<UIImageViewPasteableDelegate> )self;
	
	_imgAvatar.layer.cornerRadius = 100 / 2;
	_imgAvatar.clipsToBounds = YES;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	
	cameraImage = [[UIImage imageNamed:@"camera"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	photosImage = [[UIImage imageNamed:@"photos"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	pasteImage = [[UIImage imageNamed:@"paste"
									 inBundle:[ZeroDarkCloud frameworkBundle]
		 compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	documentsImage = [[UIImage imageNamed:@"files"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	removeImage = [[UIImage imageNamed:@"circle-minus"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	
	newUserImage = NULL;
	currentUserImage = NULL;
	deleteUserImage = NO;
	
}


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	accountSetupVC.btnBack.hidden = YES;
	
	databaseConnection = accountSetupVC.zdc.databaseManager.uiDatabaseConnection;
	imageManager =  accountSetupVC.zdc.imageManager;
	providerManager = accountSetupVC.zdc.auth0ProviderManager;
	uiTools = accountSetupVC.zdc.uiTools;
	
	self.navigationItem.title = @"Social Identities";
	
	UIBarButtonItem* cancelItem = [[UIBarButtonItem alloc]
											 initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
											 target:self action:@selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItems = @[cancelItem];
	
	
	UIBarButtonItem* doneItem = [[UIBarButtonItem alloc]
										  initWithBarButtonSystemItem:UIBarButtonSystemItemDone
										  target:self action:@selector(doneButtonTapped:)];
	
	self.navigationItem.rightBarButtonItems = @[doneItem];
	
	self.navigationItem.title = @"Update Profile Picture";
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(databaseConnectionDidUpdate:)
																name:UIDatabaseConnectionDidUpdateNotification
															 object:nil];
	
	[_tblButtons reloadData];
	[self refreshView];
	
}

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	
	[[NSNotificationCenter defaultCenter] removeObserver:self  ];
	
	[super viewWillDisappear:animated];
	
	
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}



- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return NO;
	
}

- (void)updateViewConstraints
{
	[super updateViewConstraints];
	_cnstTblButtonsHeight.constant = _tblButtons.contentSize.height;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
	BOOL hasUserChanges = NO;
	
	if(userID)
	{
		hasUserChanges =  [databaseConnection hasChangeForKey:userID
															  inCollection:kZDCCollection_Users
														  inNotifications:notifications];
		
	}
	if(hasUserChanges)
	{
		[self refreshView];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Refresh View
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)refreshView
{
	if (userID) {
		[self refreshUserNameAndIcon];
	}
}

- (void)refreshUserNameAndIcon
{
	__block ZDCLocalUser *user = nil;;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
#pragma clang diagnostic pop
	}];
	
	if (!user) return;
	
	NSArray* comps = [auth0ID componentsSeparatedByString:@"|"];
	NSString* provider = comps.firstObject;

	OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:provider] scaledToHeight:_imgProvider.frame.size.height];
	
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
	
	NSString* displayName = [user displayNameForAuth0ID:auth0ID];
	
	if (displayName.length)
	{
		_lblDisplayName.text = displayName;
	}
	else
	{
		_lblDisplayName.text = user.displayName.length ? user.displayName : @"";
	}
	
	NSDictionary *profile = [user.auth0_profiles objectForKey:auth0ID];
	NSURL *pictureURL = nil;
	
	NSString *picture =
	[Auth0ProviderManager correctPictureForAuth0ID: auth0ID
												  profileData: profile
														 region: user.aws_region
														 bucket: user.aws_bucket];
	if (picture) {
		pictureURL = [NSURL URLWithString:picture];
	}
	
	CGSize avatarSize = _imgAvatar.image.size;
	
	if (pictureURL)
	{
		ZDCDownloadOptions *opts = [[ZDCDownloadOptions alloc] init];
		opts.savePersistentlyToDiskManager = YES;
		
		UIImage* (^processingBlock)(UIImage *_Nonnull) = ^(UIImage *image) {
			
			return [image imageWithMaxSize:avatarSize];
		};
		
		__weak typeof(self) weakSelf = self;
		void (^preFetchBlock)(UIImage *_Nullable) = ^(UIImage *image){
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			if (image)
			{
				strongSelf->_imgAvatar.image = image;
			}
		};
		
		void (^postFetchBlock)(UIImage *_Nullable, NSError *_Nullable) = ^(UIImage *image, NSError *error){
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			if (image) {
				strongSelf->_imgAvatar.image =  image;
			}
			else {
				strongSelf->_imgAvatar.image = strongSelf->defaultUserImage;
			}
		};
		
		[imageManager fetchUserAvatar: userID
									 auth0ID: auth0ID
									 fromURL: pictureURL
									 options: opts
							  processingID: pictureURL.absoluteString
						  processingBlock: processingBlock
							 preFetchBlock: preFetchBlock
							postFetchBlock: postFetchBlock];
	}
	else
	{
		_imgAvatar.image = defaultUserImage;
	}
	

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: TableView Data Source
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return ZDCButton_Last;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"avatatarSourceCell"];
	
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"avatatarSourceCell"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	
	cell.userInteractionEnabled = YES;
	cell.textLabel.textColor = self.view.tintColor;
	cell.textLabel.font = [UIFont systemFontOfSize:20];
	
	__block ZDCLocalUser *user = nil;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
#pragma clang diagnostic pop
	}];
	
	switch (indexPath.row)
	{
		case ZDCButton_Camera:
		{
			cell.textLabel.text = @"Camera";
			cell.imageView.image = [cameraImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			cell.accessoryType = UITableViewCellAccessoryNone;
			
			BOOL hasCamera = NO;
			
			if(ZDCConstants.appHasCameraPermission)
				hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];
			
			if(!hasCamera)
				cell.textLabel.textColor = [UIColor lightGrayColor];
			
			break;
		}
		case ZDCButton_Photos:
		{
			cell.textLabel.text = @"Photos";
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.imageView.image = [photosImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			
			BOOL hasPhotos = NO;
			
			if(ZDCConstants.appHasPhotosPermission)
				hasPhotos = YES;
			
			if(!hasPhotos)
				cell.textLabel.textColor = [UIColor lightGrayColor];
			
			break;
		}
		case ZDCButton_Documents:
		{
			cell.textLabel.text = @"Documents";
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.imageView.image = [documentsImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			
			break;
		}
		case ZDCButton_Paste:
		{
			cell.textLabel.text = @"Paste";
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.imageView.image = [pasteImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			
			UIImage *image = [[UIPasteboard generalPasteboard] image];
			if(!image)
				cell.textLabel.textColor = [UIColor lightGrayColor];
			
			break;
		}
		case ZDCButton_Remove:
		{
			cell.textLabel.text = @"Remove";
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.imageView.image = [removeImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			
			break;
		}
			
		default:;
	}
	
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath
{
	BOOL shouldHighlight = YES;
	
	switch (indexPath.row)
	{
		case ZDCButton_Camera:
		{
			BOOL hasCamera = NO;
			
			if(ZDCConstants.appHasCameraPermission)
				hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];
			
			shouldHighlight = hasCamera;
			
			break;
		}
		case ZDCButton_Photos:
		{
			BOOL hasPhotos = NO;
			
			if(ZDCConstants.appHasPhotosPermission)
				hasPhotos = YES;
			
			shouldHighlight  = hasPhotos;
			
			break;
		}
		case ZDCButton_Paste:
		{
			UIImage *image = [[UIPasteboard generalPasteboard] image];
			shouldHighlight = image != NULL;
			
			break;
		}
		default:
		{
			shouldHighlight = YES;
			break;
		}
	}
	
	return shouldHighlight;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tv deselectRowAtIndexPath:indexPath animated:YES];
	
	__block ZDCLocalUser *user = nil;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
#pragma clang diagnostic pop
	}];
	
	if(!user.hasCompletedSetup)
		return;
	
	CGRect aFrame = [tv rectForRowAtIndexPath:indexPath];
	aFrame.origin.y += aFrame.size.height/2;
	aFrame.size.height = 1;
	aFrame.size.width =  aFrame.size.width/3;
	
	switch (indexPath.row)
	{
		case ZDCButton_Camera:
		{
			BOOL hasCamera = NO;
			
			if(ZDCConstants.appHasCameraPermission)
				hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];
			
			if(hasCamera)
			{
				[self cameraButtonTapped:self];
			}
			
			break;
		}
		case ZDCButton_Photos:
		{
			if (ZDCConstants.appHasPhotosPermission)
			{
				[self photosButtonTapped: self
								  sourceView: tv
								  sourceRect: aFrame];
			}
			break;
		}
		case ZDCButton_Documents:
		{
			[self documentsButtonTapped: self
								  sourceView: tv
								  sourceRect: aFrame];
			break;
		}
		case ZDCButton_Paste:
		{
			[self pasteButtonTapped:self];
			break;
		}
		case ZDCButton_Remove:
		{
			[self removeButtonTapped:self];
			break;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


- (IBAction)doneButtonTapped:(id)sender
{
	ZDCLogAutoTrace();
	
	if (hasChanges)
	{
		ZDCDiskManager *diskManager = accountSetupVC.zdc.diskManager;
		ZDCLocalUserManager *localUserManager = accountSetupVC.zdc.localUserManager;
		
		NSData *jpegData = nil;
		if (!deleteUserImage && newUserImage)
		{
			UIImage *scaledImage = [newUserImage imageWithMaxSize:CGSizeMake(512, 512)];
			jpegData = [scaledImage dataWithJPEGCompression:0.9];
		}
		
		__block ZDCLocalUser *localUser = nil;
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
			
			localUser = [transaction objectForKey:self.userID inCollection:kZDCCollection_Users];
		}];
		
		// Now we need to get the previous eTag
		
		ZDCDiskExport *export = [diskManager userAvatar:localUser forAuth0ID:self.auth0ID];
		if (export.cryptoFile)
		{
			NSString *_auth0ID = [self.auth0ID copy];
			
			[ZDCFileConversion decryptCryptoFileIntoMemory: export.cryptoFile
													 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
													 completionBlock:^(NSData *cleartext, NSError *error)
			 {
				 if (error || !cleartext) return;
				 
				 [localUserManager setNewAvatar: jpegData
										 forLocalUser: localUser
												auth0ID: _auth0ID
								 replacingOldAvatar: cleartext];
			 }];
		}
		else
		{
			[localUserManager setNewAvatar: jpegData
									forLocalUser: localUser
										  auth0ID: self.auth0ID
							replacingOldAvatar: nil];
		}
	}
	
	[self.navigationController popViewControllerAnimated:YES];
}


- (IBAction)removeButtonTapped:(id)sender
{
	
	_imgAvatar.image = defaultUserImage;
	
	if(newUserImage)
	{
		// restore old image
		if(currentUserImage)
		{
			_imgAvatar.image = currentUserImage;
			hasChanges = NO;
		}
		else
		{
			hasChanges = YES;
		}
		
		newUserImage = NULL;
	}
	else
	{
		deleteUserImage = YES;
		hasChanges = YES;
	}
	
}


- (IBAction)pasteButtonTapped:(id)sender
{
	ZDCLogAutoTrace();
	
	UIImage *image = [[UIPasteboard generalPasteboard] image];
	if (image)
	{
		newUserImage = image;
		_imgAvatar.image = image;
		hasChanges = YES;
	}
}


- (IBAction)cameraButtonTapped:(id)sender
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;
	
	// check camera authorization status
	AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
	
	switch (authStatus) {
			
		case AVAuthorizationStatusDenied:
		{
			[uiTools displayCameraAccessSettingsAlert];
		}
			break;
			
		case AVAuthorizationStatusAuthorized:  // camera authorized
		{
			[self presentCamera];
		}
			break;
			
		case AVAuthorizationStatusNotDetermined: // request authorization
		{
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
				dispatch_async(dispatch_get_main_queue(), ^{
					
					__strong typeof(self) strongSelf = weakSelf;
					if (strongSelf) {
						[strongSelf presentCamera];
					}
				});
			}];
		}
			break;
			
		default:;
			
	};
	
}




- (IBAction)documentsButtonTapped:(id)sender
							  sourceView:(UIView*)sourceView
							  sourceRect:(CGRect)sourceRect

{
	ZDCLogAutoTrace();
	[self showDocPicker];
}

- (IBAction)photosButtonTapped:(id)sender
						  sourceView:(UIView*)sourceView
						  sourceRect:(CGRect)sourceRect

{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;
	
	if(ZDCConstants.appHasPhotosPermission)
	{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			
			dispatch_async(dispatch_get_main_queue(), ^{
				
				__strong typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				
				switch (status) {
						
					case PHAuthorizationStatusAuthorized:
						[strongSelf showPhotoPicker];
						break;
						
					case PHAuthorizationStatusRestricted:
						break;
						
					case PHAuthorizationStatusDenied:
						[strongSelf->uiTools displayPhotoAccessSettingsAlert];
						break;
						
					default:
						break;
				}
			});
		}];
	}
}

// MARK: present pickers


- (void)presentCamera
{
	ZDCLogAutoTrace();
	
	photoPicker = [[UIImagePickerController alloc] init];
	photoPicker.delegate      = (id <UINavigationControllerDelegate, UIImagePickerControllerDelegate>)self;
	photoPicker.sourceType    = UIImagePickerControllerSourceTypeCamera;
	photoPicker.allowsEditing = NO;
	
	[self presentViewController:photoPicker animated:YES completion:NULL];
	
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
		
		if (image)
		{
			newUserImage = image;
			_imgAvatar.image = image;
			hasChanges = YES;
		}
		
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
		if(strongSelf == nil) return;
		
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
		if(strongSelf == nil) return;
		
		if (strongSelf->photoPicker == sender) {
			strongSelf->photoPicker = nil;
		}
		
		if (image)
		{
			strongSelf->newUserImage = image;
			strongSelf->_imgAvatar.image = image;
			strongSelf->hasChanges = YES;
		}
	}];
}


@end
