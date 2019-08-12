/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "BackupIntroViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCSplitKey.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "UIColor+Crayola.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)



@interface BackupIntroViewControllerCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView    *imgCell;
@property (nonatomic, weak) IBOutlet UILabel        *lblName;
@property (nonatomic, weak) IBOutlet UILabel        *lblInfo;
@end

@implementation BackupIntroViewControllerCell

- (void)awakeFromNib {
	[super awakeFromNib];
	// Initialization code
}

@end

@implementation BackupIntroViewController_IOS
{
	IBOutlet __weak UIImageView            *_imgAvatar;
	IBOutlet __weak UILabel                *_lblDisplayName;
	IBOutlet __weak UIImageView            *_imgProvider;
	IBOutlet __weak UILabel                *_lblProvider;

	IBOutlet __weak UITableView             *_tblButtons;

	UISwipeGestureRecognizer 				*swipeRight;

	YapDatabaseConnection *         databaseConnection;
	Auth0ProviderManager*			providerManager;
    ZDCImageManager*                imageManager;
    
	UIImage* 						cloneCodeImage;
	UIImage* 						cloneWordsImage;
    UIImage*                        socialBackupImage;
	
	BOOL registered;
}


@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;
	providerManager = keyBackupVC.owner.auth0ProviderManager;
	imageManager =  keyBackupVC.owner.imageManager;

	_imgAvatar.layer.cornerRadius = 50 / 2;
	_imgAvatar.clipsToBounds = YES;

	_tblButtons.estimatedSectionHeaderHeight = 0;
	_tblButtons.estimatedSectionFooterHeight = 0;

	_tblButtons.estimatedRowHeight = 85;
	_tblButtons.rowHeight = UITableViewAutomaticDimension;

	_tblButtons.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 44, 0, 0); // top, left, bottom, right

	cloneCodeImage = [[UIImage imageNamed:@"clonecode-tabbar"
								  inBundle:[ZeroDarkCloud frameworkBundle]
			 compatibleWithTraitCollection:nil]
					  maskWithColor:self.view.tintColor];

	cloneWordsImage = [[UIImage imageNamed:@"clonewords-tabbar"
								   inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil]
					   maskWithColor:self.view.tintColor];

    
    socialBackupImage = [[UIImage imageNamed:@"puzzle"
                                    inBundle:[ZeroDarkCloud frameworkBundle]
               compatibleWithTraitCollection:nil]
                         maskWithColor:self.view.tintColor];
	registered = NO;
	self.navigationItem.hidesBackButton = YES;
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(databaseConnectionDidUpdate:)
																name:UIDatabaseConnectionDidUpdateNotification
															 object:nil];
	

	self.navigationItem.title = @"Key Backup";

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

	[self refreshUserNameandIcon];
	[_tblButtons reloadData];

}


-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}


- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
	BOOL hasChanges = NO;
	
	hasChanges = [databaseConnection hasChangeForCollection:kZDCCollection_SplitKeys
														 inNotifications:notifications];
	
	if(hasChanges)
	{
		__weak typeof(self) weakSelf = self;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			[strongSelf->_tblButtons reloadData];
		});
	}
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



 - (NSUInteger)countSplits
{
	__block NSUInteger count = 0;
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		YapDatabaseViewTransaction *viewTransaction = [transaction ext:Ext_View_SplitKeys];
		count = [viewTransaction numberOfItemsInGroup:keyBackupVC.user.uuid];
	#pragma clang diagnostic pop
	}];
	
	return count;
}

- (void)refreshUserNameandIcon
{
 	if (!keyBackupVC.user) return;
	
	__weak typeof(self) weakSelf = self;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: [strongSelf->imageManager defaultUserAvatar];
	};
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: [strongSelf->imageManager defaultUserAvatar];
	};

	[imageManager fetchUserAvatar: keyBackupVC.user
	                preFetchBlock: preFetchBlock
	               postFetchBlock: postFetchBlock];
	
	NSString* displayName = keyBackupVC.user.displayName;
	_lblDisplayName.text = displayName;

	NSArray* comps = [keyBackupVC.user.auth0_preferredID componentsSeparatedByString:@"|"];
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


#pragma mark - Buttons Tableview

#define USE_COMBO 1

enum
{
#if USE_COMBO
	kButton_Combo,
#else
	kButton_Mnemonic,
	kButton_QRCode,
#endif

	kButton_Social,
	kButton_Last,
	
};


-(void)setAccessoryViewForCell:(BackupIntroViewControllerCell*)cell
								 count:(NSUInteger)count
{
	
	
	// Count > 0, show count
	if (count > 0) {
		
		// Create label
		CGFloat fontSize = 12;
		UILabel *label = [[UILabel alloc] init];
		label.font = [UIFont systemFontOfSize:fontSize];
		label.textAlignment = NSTextAlignmentCenter;
		label.textColor = [UIColor whiteColor];
		label.backgroundColor =  UIColor.crayolaDenimColor;
		
		// Add count to label and size to fit
		label.text = [NSString stringWithFormat:@"%@", @(count)];
		[label sizeToFit];
		
		// Adjust frame to be square for single digits or elliptical for numbers > 9
		CGRect frame = label.frame;
		frame.size.height += (int)(0.4*fontSize);
		frame.size.width = (count <= 9) ? frame.size.height : frame.size.width + (int)fontSize;
		label.frame = frame;
		
		// Set radius and clip to bounds
		label.layer.cornerRadius = frame.size.height/2.0;
		label.clipsToBounds = true;
		
		// Show label in accessory view and remove disclosure
		cell.accessoryView = label;
		cell.accessoryType = UITableViewCellAccessoryNone;
		
	}
	// Count = 0, show disclosure
	else {
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
 }

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
	BackupIntroViewControllerCell *cell = (BackupIntroViewControllerCell *)[tableView dequeueReusableCellWithIdentifier:@"BackupIntroViewControllerCell"];

	NSUInteger count = 0;
	
	switch(indexPath.row)
	{
#if USE_COMBO
		case kButton_Combo:
			
			cell.lblName.text = NSLocalizedString(@"Backup Access Key",
															  @"Backup Access Key");
			cell.lblInfo.text =  NSLocalizedString( @"The key will be displayed as text and QRCode. You can save it as a file, print it, write it down, store it in a password manager, etc.", @"Backup as Cpmbo description");
			
			cell.imgCell.image = cloneWordsImage;
			break;
			
#else
		case kButton_Mnemonic:
			cell.lblName.text = NSLocalizedString(@"Backup as Text (mnemonic)",
															  @"Backup as Text (mnemonic)");
			cell.lblInfo.text =  NSLocalizedString( @"The key will be displayed as text. You can write it down, store it in a password manager, etc.", @"Backup as Text description");
			
			cell.imgCell.image = cloneWordsImage;
			
			break;
			
		case kButton_QRCode:
			cell.lblName.text = NSLocalizedString(@"Backup as Image (qr code)",
															  @"Backup as Image (qr code)");
			cell.lblInfo.text = NSLocalizedString( @"The key will be displayed as an image. You can save it as a file, print it, etc.", @"Backup as Image description");
			
			cell.imgCell.image = cloneCodeImage;
			break;
#endif
			
		case kButton_Social:
			cell.lblName.text = NSLocalizedString(@"Social Key Backup",
															  @"Social Key Backup");
			cell.lblInfo.text = NSLocalizedString( @"The key will be split into multiple parts, and then you can save or share these parts with others. Only a subset of the parts are needed to restore your key. (for example: 2-of-3).", @"Social Key Backup description");
			
			cell.imgCell.image = socialBackupImage;
			
			count = [self countSplits];
			
			break;
			
		default:;
	}

	cell.textLabel.font = [UIFont systemFontOfSize:20];
	cell.textLabel.adjustsFontSizeToFitWidth = YES;
	
	[self setAccessoryViewForCell:cell count:count];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];


	switch(indexPath.row)
	{
#if USE_COMBO
		case kButton_Combo:
			[keyBackupVC pushBackupAsCombo];
			break;
#else
		case kButton_Mnemonic:
			[keyBackupVC pushBackupAsText];
			break;

		case kButton_QRCode:
			[keyBackupVC pushBackupAsImage];
			break;
#endif
        case kButton_Social:
            [keyBackupVC pushBackupSocial];
            break;

		default:
			break;
	}
};





@end
