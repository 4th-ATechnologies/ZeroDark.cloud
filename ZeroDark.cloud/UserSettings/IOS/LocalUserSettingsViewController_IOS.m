/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "LocalUserSettingsViewController_IOS.h"

#import "AccountSetupViewController_IOS.h"
#import "ActivityMonitor_IOS.h"
#import "KeyBackupViewController_IOS.h"
#import "VerifyPublicKey_IOS.h"
#import "ZDCLocalUser.h"
#import "ZDCLogging.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "OSImage+ZeroDark.h"

// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

static NSString *const kLocalUserSettingsUICellIdentifier = @"LocalUserSettingsUICell";

typedef NS_ENUM(NSInteger, TblRow) {
	
	TblRow_SocialIDMgmt,
	TblRow_Clone,
	TblRow_BackupKey,
	TblRow_VerifyPublicKey,
	TblRow_PauseSync,
	TblRow_Activity,

#if DEBUG
	TblRow_Logout,
	TblRow_Last
#else
	TblRow_Last,
	TblRow_Logout
#endif
};


@interface LocalUserSettingsUICell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView *imgCell;
@property (nonatomic, weak) IBOutlet UILabel     *lblTitle;
@property (nonatomic, weak) IBOutlet UILabel     *lblInfo;

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *lblTitleCenterConstraint;

@end

@implementation LocalUserSettingsUICell
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation LocalUserSettingsViewController_IOS
{
	IBOutlet __weak UILabel*    	 	_lblDisplayName;
	IBOutlet __weak UIImageView* 		_imgAvatar;
	IBOutlet __weak UIImageView* 		_imgProvider;
	IBOutlet __weak UILabel*			_lblProvider;
	IBOutlet __weak UITableView* 		_tblButtons;

	YapDatabaseConnection *uiDatabaseConnection;
	ZDCLocalUser *localUser;
	
	UIImage * socialImage;
	UIImage * cloneImage;
	UIImage * backupImage;
	UIImage * keysImage;
	UIImage * activityImage;
	UIImage * logoutImage;
	UIImage * pauseImage;
	UIImage * resumeImage;
}

@synthesize zdc = zdc;
@synthesize localUserID = localUserID;

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner
                  localUserID:(NSString *)inLocalUserID;
{
	NSBundle *zdcBundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LocalUserSettings_IOS" bundle:zdcBundle];
	
	self = [storyboard instantiateViewControllerWithIdentifier:@"LocalUserSettingsViewController_IOS"];
	if (self)
	{
		zdc = owner;
		localUserID = [inLocalUserID copy];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	CGSize avatarSize = _imgAvatar.frame.size;
	_imgAvatar.layer.cornerRadius = avatarSize.width / 2;
	_imgAvatar.clipsToBounds = YES;
	
	_tblButtons.estimatedSectionHeaderHeight = 0;
	_tblButtons.estimatedSectionFooterHeight = 0;
	
	_tblButtons.estimatedRowHeight = 85;
	_tblButtons.rowHeight = UITableViewAutomaticDimension;
	
	_tblButtons.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 44, 0, 0); // top, left, bottom, right
	
	NSBundle *zdcBundle = [ZeroDarkCloud frameworkBundle];
	CGSize imageSize = (CGSize){
		.width = 32,
		.height = 32
	};
	
	socialImage = [[UIImage imageNamed: @"social"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];
	
	keysImage = [[UIImage imageNamed: @"circle-check"
	                        inBundle: zdcBundle
	   compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];
	
	cloneImage = [[UIImage imageNamed: @"clonecode-tabbar"
	                         inBundle: zdcBundle
	    compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];
	
	activityImage = [[UIImage imageNamed: @"storm4_28"
	                            inBundle: zdcBundle
	       compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];
	
	backupImage = [[UIImage imageNamed: @"keys"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];
	
	logoutImage = [[UIImage imageNamed: @"logout"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];

	pauseImage = [[UIImage imageNamed: @"pause-round-24"
	                         inBundle: zdcBundle
	    compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];

	resumeImage = [[UIImage imageNamed: @"play-round-24"
	                          inBundle: zdcBundle
	     compatibleWithTraitCollection: nil] imageByScalingProportionallyToSize:imageSize];
	
	self.navigationItem.hidesBackButton = YES;
	
	[[NSNotificationCenter defaultCenter] addObserver: self
														  selector: @selector(databaseConnectionDidUpdate:)
																name: UIDatabaseConnectionDidUpdateNotification
															 object: nil];
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;
	
	self.navigationItem.title = NSLocalizedString(@"Settings", @"Settings");
	
	UIImage *image = [[UIImage imageNamed: @"backarrow"
	                             inBundle: [ZeroDarkCloud frameworkBundle]
	        compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem *backItem =
	  [[UIBarButtonItem alloc] initWithImage: image
	                                   style: UIBarButtonItemStylePlain
	                                  target: self
	                                  action: @selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
	
	[self refreshUserNameandIcon];
	[_tblButtons reloadData];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];

	BOOL hasUserChanges = NO;
	if (localUserID)
	{
		hasUserChanges =
		  [uiDatabaseConnection hasChangeForKey: localUserID
		                           inCollection: kZDCCollection_Users
		                        inNotifications: notifications];
	}

	if (hasUserChanges)
	{
		[self refreshUserNameandIcon];
		[_tblButtons reloadData];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Refresh
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)refreshUserNameandIcon
{
	ZDCLogAutoTrace();
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	if (!localUser || !localUser.isLocal) return;
	
	__weak typeof(self) weakSelf = self;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns
		
		self->_imgAvatar.image = image ?: [self->zdc.imageManager defaultUserAvatar];
	};
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetchBlock is invoked LATER, possibly after downloading the avatar
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf && image)
		{
			strongSelf->_imgAvatar.image = image;
		}
	};
	
	[zdc.imageManager fetchUserAvatar: localUser
	                      withOptions: nil
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];
	
	_lblDisplayName.text = localUser.displayName;
	
	ZDCUserIdentity *displayIdentity = localUser.displayIdentity;
	OSImage *providerImage =
	  [[zdc.auth0ProviderManager iconForProvider: displayIdentity.provider
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
		_imgProvider.hidden = YES;
		_lblProvider.text = displayIdentity.provider;
		_lblProvider.hidden = NO;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewDataSource
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
	LocalUserSettingsUICell *cell = (LocalUserSettingsUICell *)
	  [tableView dequeueReusableCellWithIdentifier:kLocalUserSettingsUICellIdentifier];

	NSString* title = @"";
	NSString* info = @"";
	UIImage* image = nil;

	switch (indexPath.row)
	{
		case TblRow_SocialIDMgmt:
			title = NSLocalizedString(@"Social Identities", @"Social Identities");
			image = socialImage;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
			
		case TblRow_Clone:
			title = NSLocalizedString(@"Setup on another device", @"Setup on another device");
			image = cloneImage;
			cell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;
			break;
			
		case TblRow_BackupKey:
			title = NSLocalizedString(@"Backup Access Key", @"Backup Access Key");
			image = backupImage;
			
			if (!localUser.hasBackedUpAccessCode)
			{
				info = NSLocalizedString(
					@"You should backup the access key for your account."
					 " Without a backup, you’ll lose access to all your data should you lose this device."
					 " Backing up your key only takes a few moments.",
					@"You should backup your Access key...");
			}
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
			
		case TblRow_VerifyPublicKey:
			title = NSLocalizedString(@"Verify Public Key", @"Verify Public Key");
			image = keysImage;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;

		case TblRow_Activity:
			title = NSLocalizedString(@"Activity", @"Activity");
			image = activityImage;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
 
		case TblRow_PauseSync:
			if (localUser.syncingPaused)
			{
				title = NSLocalizedString(@"Resume Syncing", @"Resume Syncing");
				image = resumeImage;
 			}
			else
			{
				title = NSLocalizedString(@"Pause Syncing", @"Pause Syncing");
				image = pauseImage;
			}
			cell.accessoryType = UITableViewCellAccessoryNone;
			break;
			
		case TblRow_Logout:
			title = @"Log Out";
			image = logoutImage;
			cell.accessoryType = UITableViewCellAccessoryNone;
			break;
			
		default:;
	}
	
	cell.lblTitle.text = title;
	cell.imgCell.image = image;
	cell.lblTitle.font = [UIFont systemFontOfSize:20];
	cell.lblTitle.textColor = self.view.tintColor;
	
	if (info.length)
	{
		cell.lblInfo.text = info;
 		cell.lblTitleCenterConstraint.active = NO;
	}
	else
	{
		cell.lblInfo.text = @"";
  		cell.lblTitleCenterConstraint.active = YES;
	}
	
	[cell.lblInfo sizeToFit];
	
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	
	switch (indexPath.row)
	{
		case TblRow_SocialIDMgmt:
		{
			AccountSetupViewController_IOS *vc =
			  [[AccountSetupViewController_IOS alloc] initWithOwner:zdc];
			
			[vc pushSocialIdMgmtWithUserID: localUserID
			      withNavigationController: self.navigationController];
			break;
		}
		case TblRow_Clone:
		{
			KeyBackupViewController_IOS *vc =
			  [[KeyBackupViewController_IOS alloc] initWithOwner:zdc];
			
			[vc pushCloneDeviceWithUserID: localUserID
			     withNavigationController: self.navigationController];
			break;
		}
		case TblRow_BackupKey:
		{
			KeyBackupViewController_IOS *vc =
			  [[KeyBackupViewController_IOS alloc] initWithOwner:zdc];
			
			[vc pushBackupAccessKeyWithUserID: localUserID
			         withNavigationController: self.navigationController];
			break;
		}
		case TblRow_VerifyPublicKey:
		{
			VerifyPublicKey_IOS *vc =
			  [[VerifyPublicKey_IOS alloc] initWithOwner: zdc
			                                remoteUserID: localUserID
			                                 localUserID: localUserID];
			
			[self.navigationController pushViewController:vc animated:YES];
			break;
		}
		case TblRow_Activity:
		{
			ActivityMonitor_IOS *vc =
			  [[ActivityMonitor_IOS alloc] initWithOwner: zdc
			                                 localUserID: localUserID];
			
			[self.navigationController pushViewController:vc animated:YES];
			break;
		}
		case TblRow_Logout:
		{
			AWSCredentialsManager *aws = zdc.awsCredentialsManager;
			[aws flushAWSCredentialsForUser: localUserID
			             deleteRefreshToken: YES
			                completionQueue: nil
			                completionBlock:
			^{
				[[self navigationController] popViewControllerAnimated:YES];
			}];
			
			break;
		}
		case TblRow_PauseSync:
		{
			NSString *_localUserID = localUserID;
			__block ZDCLocalUser *updatedUser = nil;
			
			YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
			[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				 
				updatedUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
				if (updatedUser)
				{
					updatedUser = [updatedUser copy];
					updatedUser.syncingPaused = !updatedUser.syncingPaused;
					
					[transaction setObject: updatedUser
					                forKey: updatedUser.uuid
					          inCollection: kZDCCollection_Users];
				}
				 
			 } completionBlock:^{
				 
				if (updatedUser)
				{
					self->localUser = updatedUser;
					[tableView reloadRowsAtIndexPaths: @[indexPath]
					                 withRowAnimation: UITableViewRowAnimationFade];
				}
			}];
			break;
		}

		default:
			break;
	}
}

@end
