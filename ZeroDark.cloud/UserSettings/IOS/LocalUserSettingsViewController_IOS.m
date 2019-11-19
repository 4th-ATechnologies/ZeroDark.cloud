/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "LocalUserSettingsViewController_IOS.h"
#import "ZeroDarkCloudPrivate.h"

#import "AccountSetupViewController_IOS.h"
#import "KeyBackupViewController_IOS.h"
#import "VerifyPublicKey_IOS.h"
#import "ActivityMonitor_IOS.h"

#import "ZDCLocalUser.h"

#import "ZDCLogging.h"

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


@interface LocalUserSettingsUICell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView    *imgCell;
@property (nonatomic, weak) IBOutlet UILabel        *lblTitle;
@property (nonatomic, weak)  IBOutlet NSLayoutConstraint  *lblTitleCenterConstraint;

@property (nonatomic, weak) IBOutlet UILabel        *lblInfo;
@end

@implementation LocalUserSettingsUICell

- (void)awakeFromNib {
	[super awakeFromNib];
	// Initialization code
}


@end


@implementation LocalUserSettingsViewController_IOS
{
	
	IBOutlet __weak UILabel*    	 	_lblDisplayName;
	IBOutlet __weak UIImageView* 		_imgAvatar;
	IBOutlet __weak UIImageView* 		_imgProvider;
	IBOutlet __weak UILabel*			_lblProvider;
	IBOutlet __weak UITableView* 		_tblButtons;
	IBOutlet __weak NSLayoutConstraint* 		_cnstTblButtonsHeight;

	YapDatabaseConnection * 	databaseConnection;
	Auth0ProviderManager*		providerManager;
	ZDCImageManager*       		imageManager;
	
	
	UIImage*                 	socialImage;
	UIImage*							cloneImage;
	
	UIImage*               		backupImage;
	UIImage*                	keysImage;
	UIImage*							activityImage;
	UIImage*                	logoutImage;
	UIImage*                	pauseImage;
	UIImage*                	resumeImage;

	ZDCLocalUser* localUser;

}

@synthesize owner =  owner;
@synthesize localUserID = localUserID;


- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
							localUserID:(NSString* __nonnull)inLocalUserID;
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LocalUserSettings_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"LocalUserSettingsViewController_IOS"];
	if (self)
	{
		owner = inOwner;
		localUserID = inLocalUserID;
	}
	return self;
}


- (void)viewDidLoad {
	[super viewDidLoad];
	
	_imgAvatar.layer.cornerRadius = 50 / 2;
	_imgAvatar.clipsToBounds = YES;
	
	_tblButtons.estimatedSectionHeaderHeight = 0;
	_tblButtons.estimatedSectionFooterHeight = 0;
	
	_tblButtons.estimatedRowHeight = 85;
	_tblButtons.rowHeight = UITableViewAutomaticDimension;
	
	_tblButtons.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 44, 0, 0); // top, left, bottom, right
	
	CGSize imageSize = (CGSize){
		.width = 32,
		.height = 32
	};
	
	socialImage =  [[UIImage imageNamed:@"social"
										inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageByScalingProportionallyToSize:imageSize];
	
	keysImage =  [[UIImage imageNamed:@"circle-check"
									 inBundle:[ZeroDarkCloud frameworkBundle]
		 compatibleWithTraitCollection:nil]imageByScalingProportionallyToSize:imageSize];
	
	cloneImage =  [[UIImage imageNamed:@"clonecode-tabbar"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil]imageByScalingProportionallyToSize:imageSize];
	
	activityImage =  [[UIImage imageNamed:@"storm4_28"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil]imageByScalingProportionallyToSize:imageSize];
	
	backupImage =  [[UIImage imageNamed:@"keys"
										inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil]imageByScalingProportionallyToSize:imageSize];
	
	logoutImage =  [[UIImage imageNamed:@"logout"
										inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageByScalingProportionallyToSize:imageSize];

	pauseImage =  [[UIImage imageNamed:@"pause-round-24"
										inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageByScalingProportionallyToSize:imageSize];

	resumeImage =  [[UIImage imageNamed:@"play-round-24"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil] imageByScalingProportionallyToSize:imageSize];
	
	self.navigationItem.hidesBackButton = YES;
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	databaseConnection = owner.databaseManager.uiDatabaseConnection;
	providerManager = owner.auth0ProviderManager;
	imageManager =  	owner.imageManager;
	
	self.navigationItem.title = NSLocalizedString(@"Settings", @"Settings");
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																					 style:UIBarButtonItemStylePlain
																					target:self
																					action:@selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
	
	[self refreshView];
	[_tblButtons reloadData];
	
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_cnstTblButtonsHeight.constant = _tblButtons.contentSize.height;
	
}


-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}


- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}


- (void)refreshView
{
	[self refreshUserNameandIcon];
}

- (void)refreshUserNameandIcon
{
	if (!localUserID) return;

	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	if(!localUser) return;
	
	ZeroDarkCloud *zdc = owner;
	__weak typeof(self) weakSelf = self;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: [zdc.imageManager defaultUserAvatar];
	};
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: [zdc.imageManager defaultUserAvatar];
	};
	
	[imageManager fetchUserAvatar: localUser
	                  withOptions: nil
	                preFetchBlock: preFetchBlock
	               postFetchBlock: postFetchBlock];
	
	NSString* displayName = localUser.displayName;
	_lblDisplayName.text = displayName;
	
	NSArray* comps = [localUser.auth0_preferredID componentsSeparatedByString:@"|"];
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
}

//MARK  Buttons Tableview
enum
{
	kButton_SocialIDMgmt,
	kButton_Clone,
	kButton_BackupKey,
	kButton_VerifyPublicKey,
	kButton_PauseSync,
	kButton_Activity,

#if DEBUG
 	kButton_Logout,
	kButton_Last
#else
 	kButton_Last,
	kButton_Logout
#endif

};

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return kButton_Last;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	LocalUserSettingsUICell *cell = (LocalUserSettingsUICell*) [tableView dequeueReusableCellWithIdentifier:kLocalUserSettingsUICellIdentifier];

	NSString* title = @"";
	NSString* info = @"";
	UIImage* image = nil;

	switch(indexPath.row)
	{
		case kButton_SocialIDMgmt:
			title = NSLocalizedString(@"Social Identities", @"Social Identities");
			image = socialImage;
			cell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;
			break;
			
		case kButton_Clone:
			title = NSLocalizedString(@"Setup on another device", @"Setup on another device");
			image = cloneImage;
			cell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;
			break;
			
		case kButton_BackupKey:
			title = NSLocalizedString(@"Backup Access Key", @"Backup Access Key");
			image = backupImage	;
			
			if(!localUser.hasBackedUpAccessCode) {
				info = NSLocalizedString(@"You should backup the access key for the account. "
												 "Without a backup of your access key, you’ll lose access to all your data should you lose this device. "
												 "Backing up your key only takes a few moments."
												 , @"You should backup your Access key.." );
			}
			cell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;
			break;
			
		case kButton_VerifyPublicKey:
			title = NSLocalizedString(@"Verify Public Key", @"Verify Public Key");
			image = keysImage	;
			cell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;

			break;

		case kButton_Activity:
			title = NSLocalizedString(@"Activity", @"Activity");
			image = activityImage	;
			cell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;
			break;
 
		case kButton_PauseSync:
			if(localUser.syncingPaused){
				title = NSLocalizedString(@"Resume Syncing", @"Resume Syncing");
				image = resumeImage;
 			}
			else
			{
				title = NSLocalizedString(@"Pause Syncing", @"Pause Syncing");
				image = pauseImage;
			}
			cell.accessoryType =  UITableViewCellAccessoryNone;
			break;
			
		case kButton_Logout:
			title = @"Log Out";
			image = logoutImage;
			cell.accessoryType =  UITableViewCellAccessoryNone;
			break;
			
		default:;
	}
	
	cell.lblTitle.text = title;
	cell.imgCell.image = image;
	cell.lblTitle.font = [UIFont systemFontOfSize:20];
	cell.lblTitle.textColor = self.view.tintColor;
	
	if(info.length)
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
	__weak typeof(self) weakSelf = self;

	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	
	switch(indexPath.row)
	{
		case kButton_SocialIDMgmt:
		{
			AccountSetupViewController_IOS* vc = [[AccountSetupViewController_IOS alloc]
															  initWithOwner:owner];
			
			[vc pushSocialIdMgmtWithUserID:localUserID
					withNavigationController:self.navigationController];
		}
			break;
			
		case kButton_Clone:
		{
			KeyBackupViewController_IOS* vc = [[KeyBackupViewController_IOS alloc]
														  initWithOwner:owner];
			
			[vc pushCloneDeviceWithUserID:localUserID
				  withNavigationController:self.navigationController];
			
		}
			break;
			
		case kButton_BackupKey:
		{
			KeyBackupViewController_IOS* vc = [[KeyBackupViewController_IOS alloc]
														  initWithOwner:owner];
			
			[vc pushBackupAccessKeyWithUserID:localUserID
						withNavigationController:self.navigationController];
			
		}
			break;
			
		case kButton_VerifyPublicKey:
		{
			VerifyPublicKey_IOS* vc = [[VerifyPublicKey_IOS alloc]
												initWithOwner:owner
												remoteUserID:localUserID
												localUserID:localUserID];
			
			[self.navigationController pushViewController:vc animated:YES];
			
		}
			break;
			
		case kButton_Activity:
		{
			ActivityMonitor_IOS* vc = [[ActivityMonitor_IOS alloc]
												initWithOwner:owner
												localUserID:localUserID];
			
			[self.navigationController pushViewController:vc animated:YES];
			
		}
			break;

			
		case kButton_Logout:
		{
			AWSCredentialsManager *aws = owner.awsCredentialsManager;
			[aws flushAWSCredentialsForUser: localUserID
			             deleteRefreshToken: YES
			                completionQueue: nil
			                completionBlock:
			^{
				[[self navigationController] popViewControllerAnimated:YES];
			}];
			
			break;
		}
		case kButton_PauseSync:
		{
			__block ZDCLocalUser *updatedUser = nil;
			[owner.databaseManager.rwDatabaseConnection
			 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				 
				 __strong typeof(self) strongSelf = weakSelf;
				 if (strongSelf == nil) return;
				 
				 updatedUser = [transaction objectForKey:strongSelf->localUserID inCollection:kZDCCollection_Users];
				 
				 if(updatedUser)
				 {
					 updatedUser = updatedUser.copy;
					 updatedUser.syncingPaused = !updatedUser.syncingPaused;
					 
					 [transaction setObject:updatedUser
										  forKey:updatedUser.uuid
								  inCollection:kZDCCollection_Users];
				 }
				 
			 }completionBlock:^{
				 
				 if(updatedUser)
				 {
					 self->localUser = updatedUser;
					 [tableView reloadRowsAtIndexPaths:@[indexPath]
											withRowAnimation:UITableViewRowAnimationFade];
				 }
			 }];

			break;
		}

		default:
			break;
	}
};


@end
