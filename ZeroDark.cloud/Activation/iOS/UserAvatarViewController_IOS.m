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


typedef NS_ENUM(NSInteger, TblRow) {
	TblRow_Camera = 0,
	TblRow_Photos,
	TblRow_Documents,
	TblRow_Paste,
	TblRow_Remove,
	
	TblRow_Last,
};

@implementation UserAvatarViewController_IOS
{
	IBOutlet __weak UIImageViewPasteable * _imgAvatar;
	IBOutlet __weak UILabel              * _lblDisplayName;
	IBOutlet __weak UIImageView          * _imgProvider;
	IBOutlet __weak UILabel              * _lblProvider;
	
	IBOutlet __weak UITableView          * _tblButtons;
	IBOutlet __weak NSLayoutConstraint   * _cnstTblButtonsHeight;
	
	ZeroDarkCloud         * zdc;
	YapDatabaseConnection * uiDatabaseConnection;
	
	UIImage * cameraImage;
	UIImage * photosImage;
	UIImage * pasteImage;
	UIImage * documentsImage;
	UIImage * removeImage;
	UIImage * _defaultUserImage_mustUseLazyGetter;
	
	OSImage * newUserImage;
	OSImage * currentUserImage;
	BOOL      deleteUserImage;
	BOOL      hasChanges;
	
	BOOL hasCamera;
	UIDocumentPickerViewController  *docPicker;
	UIImagePickerController         *photoPicker;
	
	// currently posted view controller, used for removing on passcode lock
	UIViewController                *currentVC;
}

@synthesize accountSetupVC = accountSetupVC;
@synthesize localUserID = localUserID;
@synthesize identityID = identityID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	_imgAvatar.delegate = (id <UIImageViewPasteableDelegate>)self;
	
	_imgAvatar.layer.cornerRadius = 100 / 2;
	_imgAvatar.clipsToBounds = YES;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	
	NSBundle *zdcBundle = [ZeroDarkCloud frameworkBundle];
	
	cameraImage = [[UIImage imageNamed: @"camera"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	photosImage = [[UIImage imageNamed: @"photos"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	pasteImage = [[UIImage imageNamed: @"paste"
	                         inBundle: zdcBundle
	    compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	documentsImage = [[UIImage imageNamed: @"files"
	                             inBundle: zdcBundle
	        compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	removeImage = [[UIImage imageNamed: @"circle-minus"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	newUserImage = nil;
	currentUserImage = nil;
	deleteUserImage = NO;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	accountSetupVC.btnBack.hidden = YES;
	
	zdc = accountSetupVC.zdc;
	uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;
	
	self.navigationItem.title = @"Social Identities";
	
	UIBarButtonItem *cancelItem =
	  [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemCancel
	                                                target: self
	                                                action: @selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItems = @[cancelItem];
	
	UIBarButtonItem *doneItem =
	  [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone
	                                                target: self
	                                                action: @selector(doneButtonTapped:)];
	
	self.navigationItem.rightBarButtonItems = @[doneItem];
	
	self.navigationItem.title = @"Update Profile Picture";
	
	[self refreshUserNameAndIcon];
	[_tblButtons reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super viewWillDisappear:animated];
}

- (void)updateViewConstraints
{
	[super updateViewConstraints];
	_cnstTblButtonsHeight.constant = _tblButtons.contentSize.height;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AccountSetupViewController_IOS_Child_Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Refresh View
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (UIImage *)defaultUserImage
{
	if (_defaultUserImage_mustUseLazyGetter == nil)
	{
		_defaultUserImage_mustUseLazyGetter =
		  [zdc.imageManager.defaultUserAvatar zdc_scaledToSize: _imgAvatar.frame.size
		                                       scalingMode: ScalingMode_AspectFill];
	}
	
	return _defaultUserImage_mustUseLazyGetter;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Refresh View
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)refreshUserNameAndIcon
{
	ZDCLogAutoTrace();
	
	__block ZDCLocalUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	if (!localUser || !localUser.isLocal) {
		return;
	}
	
	ZDCUserIdentity *identity = [localUser identityWithID:identityID];
	Auth0ProviderManager *providerManager = zdc.auth0ProviderManager;
	
	
	NSString *provider = identity.provider;
	OSImage *providerImage =
	  [[providerManager iconForProvider: provider
	                               type: Auth0ProviderIconType_Signin]
	                     scaledToHeight: _imgProvider.frame.size.height];
	
	if (providerImage)
	{
		_imgProvider.hidden = NO;
		_imgProvider.image = providerImage;
		_lblProvider.hidden = YES;
	}
	else
	{
		NSString *providerName = [providerManager displayNameForProvider:provider];
		
		_imgProvider.hidden = YES;
		_lblProvider.text = providerName;
		_lblProvider.hidden = NO;
	}
	
	NSString *displayName = identity.displayName;
	_lblDisplayName.text = displayName;
	
	CGSize avatarSize = _imgAvatar.frame.size;
	
	UIImage* (^processingBlock)(UIImage *_Nonnull) = ^(UIImage *image) {
		
		return [image zdc_scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
	};
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetch is invoked BEFORE the fetchUserAvatar method returns.
		
		self->_imgAvatar.image = image ?: [self defaultUserImage];
	};
	
	__weak typeof(self) weakSelf = self;
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetch is invoked LATER, possibly after a download.
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf && image) {
			strongSelf->_imgAvatar.image = image;
		}
	};
	
	ZDCFetchOptions *options = [[ZDCFetchOptions alloc] init];
	options.identityID = identityID;
	
	[zdc.imageManager fetchUserAvatar: localUser
	                      withOptions: options
	                     processingID: NSStringFromClass([self class])
	                  processingBlock: processingBlock
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];
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
	return TblRow_Last;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString *const reuseID = @"avatatarSourceCell";
	
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
	if (cell == nil)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseID];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	
	cell.userInteractionEnabled = YES;
	cell.textLabel.textColor = self.view.tintColor;
	cell.textLabel.font = [UIFont systemFontOfSize:20];
	
	__block ZDCLocalUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	switch (indexPath.row)
	{
		case TblRow_Camera:
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
		case TblRow_Photos:
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
		case TblRow_Documents:
		{
			cell.textLabel.text = @"Documents";
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.imageView.image = [documentsImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			
			break;
		}
		case TblRow_Paste:
		{
			cell.textLabel.text = @"Paste";
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.imageView.image = [pasteImage imageByScalingProportionallyToSize:CGSizeMake(32, 32)];
			
			UIImage *image = [[UIPasteboard generalPasteboard] image];
			if(!image)
				cell.textLabel.textColor = [UIColor lightGrayColor];
			
			break;
		}
		case TblRow_Remove:
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
		case TblRow_Camera:
		{
			BOOL hasCamera = NO;
			
			if(ZDCConstants.appHasCameraPermission)
				hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];
			
			shouldHighlight = hasCamera;
			
			break;
		}
		case TblRow_Photos:
		{
			BOOL hasPhotos = NO;
			
			if(ZDCConstants.appHasPhotosPermission)
				hasPhotos = YES;
			
			shouldHighlight = hasPhotos;
			
			break;
		}
		case TblRow_Paste:
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
	
	__block ZDCLocalUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	if (!localUser.hasCompletedSetup) {
		return;
	}
	
	CGRect aFrame = [tv rectForRowAtIndexPath:indexPath];
	aFrame.origin.y += aFrame.size.height/2;
	aFrame.size.height = 1;
	aFrame.size.width =  aFrame.size.width/3;
	
	switch (indexPath.row)
	{
		case TblRow_Camera:
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
		case TblRow_Photos:
		{
			if (ZDCConstants.appHasPhotosPermission)
			{
				[self photosButtonTapped: self
								  sourceView: tv
								  sourceRect: aFrame];
			}
			break;
		}
		case TblRow_Documents:
		{
			[self documentsButtonTapped: self
								  sourceView: tv
								  sourceRect: aFrame];
			break;
		}
		case TblRow_Paste:
		{
			[self pasteButtonTapped:self];
			break;
		}
		case TblRow_Remove:
		{
			[self removeButtonTapped:self];
			break;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

- (IBAction)doneButtonTapped:(id)sender
{
	ZDCLogAutoTrace();
	
	if (hasChanges)
	{
		ZDCDiskManager *diskManager = zdc.diskManager;
		ZDCLocalUserManager *localUserManager = zdc.localUserManager;
		
		NSString *_localUserID = self.localUserID;
		NSString *_identityID = self.identityID;
		
		NSData *jpegData = nil;
		if (!deleteUserImage && newUserImage)
		{
			UIImage *scaledImage = [newUserImage imageWithMaxSize:CGSizeMake(512, 512)];
			jpegData = [scaledImage dataWithJPEGCompression:0.9];
		}
		
		__block ZDCLocalUser *localUser = nil;
		[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
			
			localUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		}];
		
		// Now we need to get the previous eTag
		
		ZDCDiskExport *export = [diskManager userAvatar:localUser forIdentityID:_identityID];
		if (export.cryptoFile)
		{
			[ZDCFileConversion decryptCryptoFileIntoMemory: export.cryptoFile
													 completionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
													 completionBlock:^(NSData *cleartext, NSError *error)
			{
				if (error || !cleartext) return;
				
				[localUserManager setNewAvatar: jpegData
				                  forLocalUser: localUser
				                    identityID: _identityID
				            replacingOldAvatar: cleartext];
			}];
		}
		else
		{
			[localUserManager setNewAvatar: jpegData
			                  forLocalUser: localUser
			                    identityID: _identityID
			            replacingOldAvatar: nil];
		}
	}
	
	[self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)removeButtonTapped:(id)sender
{
	_imgAvatar.image = [self defaultUserImage];
	
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
	
	AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
	switch (authStatus)
	{
		case AVAuthorizationStatusDenied:
		{
			[zdc.uiTools displayCameraAccessSettingsAlert];
			break;
		}
		case AVAuthorizationStatusAuthorized:  // camera authorized
		{
			[self showCamera];
			break;
		}
		case AVAuthorizationStatusNotDetermined: // request authorization
		{
			__weak typeof(self) weakSelf = self;
			dispatch_block_t block = ^{
				
				[weakSelf showCamera];
			};
			
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
				
				if ([NSThread isMainThread]) {
					block();
				} else {
					dispatch_async(dispatch_get_main_queue(), block);
				}
			}];
			break;
		}
		default:;
	}
}

- (IBAction)documentsButtonTapped:(id)sender
							  sourceView:(UIView *)sourceView
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
	
	if (ZDCConstants.appHasPhotosPermission == NO) {
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	void (^block)(PHAuthorizationStatus) = ^(PHAuthorizationStatus status){
		
		switch (status)
		{
			case PHAuthorizationStatusAuthorized:
				[weakSelf showPhotoPicker];
				break;
				
			case PHAuthorizationStatusRestricted:
				break;
				
			case PHAuthorizationStatusDenied:
				[weakSelf displayPhotoAccessSettingsAlert];
				break;
				
			default:
				break;
		}
	};
	
	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			
		if ([NSThread isMainThread]) {
			block(status);
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{
				block(status);
			});
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Show UI
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)displayPhotoAccessSettingsAlert
{
	[zdc.uiTools displayPhotoAccessSettingsAlert];
}

- (void)showCamera
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
