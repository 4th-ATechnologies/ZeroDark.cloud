/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "SocialidentityManagementViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCImageManagerPrivate.h"

#import "ZDCLogging.h"

#import "SocialIDUITableViewCell.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "IdentityProviderTableViewCell.h"
#import "SCLAlertView.h"
#import "SCLAlertViewStyleKit.h"

// Categories
#import "OSImage+ZeroDark.h"

// Libraries
#import <stdatomic.h>

// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@interface SocialIdentityManagementVC_RowItem: NSObject

@property (nonatomic, assign, readwrite) BOOL isRealCell;
@property (nonatomic, assign, readwrite) BOOL isUserAuthProfile;
@property (nonatomic, assign, readwrite) BOOL isPrimaryProfile;
@property (nonatomic, assign, readwrite) BOOL isPreferredProfile;

@property (nonatomic, copy, readwrite) NSString *auth0ID;
@property (nonatomic, copy, readwrite) NSString *provider;
@property (nonatomic, copy, readwrite) NSString *providerName;
@property (nonatomic, copy, readwrite) NSString *connection;
@property (nonatomic, copy, readwrite) NSString *displayName;

@end


@implementation SocialIdentityManagementVC_RowItem

@synthesize isRealCell;
@synthesize isUserAuthProfile;
@synthesize isPrimaryProfile;
@synthesize isPreferredProfile;

@synthesize auth0ID;
@synthesize provider;
@synthesize providerName;
@synthesize connection;
@synthesize displayName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation SocialidentityManagementViewController_IOS
{
	IBOutlet __weak UITableView * _tblProviders;
	IBOutlet __weak UIView      * _vwAddMoreLoser;

	ZeroDarkCloud         * zdc;
	YapDatabaseConnection * uiDatabaseConnection;

	NSArray<SocialIdentityManagementVC_RowItem *> * rowItems;
	
	UIImage *_defaultUserImage_mustUseLazyGetter;
    
	BOOL hasInternet;
	BOOL isViewVisible;
	
	SCLAlertView * warningAlert;
}

@synthesize accountSetupVC = accountSetupVC;
@synthesize localUserID = localUserID;

- (void)setLocalUserID:(NSString *)inLocalUserID
{
	localUserID = [inLocalUserID copy];
	if (isViewVisible)
	{
		[self refreshView];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	[super viewDidLoad];

	zdc = accountSetupVC.zdc;
	uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;

	[SocialIDUITableViewCell registerViewsforTable:_tblProviders bundle:[ZeroDarkCloud frameworkBundle]];
	_vwAddMoreLoser.hidden = YES;

	// make the left inset line up with the cell text
	_tblProviders.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblProviders.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0); // top, left, bottom, right

	_tblProviders.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblProviders.frame.size.width, 1)];

	self.navigationItem.hidesBackButton = YES;
	
	hasInternet = zdc.reachability.isReachable;

	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(reachabilityChanged:)
	                                             name: AFNetworkingReachabilityDidChangeNotification
	                                           object: nil /* notification doesn't assign object ! */];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(databaseConnectionDidUpdate:)
	                                             name: UIDatabaseConnectionDidUpdateNotification
	                                           object: nil];
	
	[self refreshView];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	accountSetupVC.btnBack.hidden = YES;
  
	self.navigationItem.title = @"Social Identities";

	UIImage *backImage = [[UIImage imageNamed: @"backarrow"
	                                 inBundle: [ZeroDarkCloud frameworkBundle]
	            compatibleWithTraitCollection: nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIBarButtonItem *backItem =
	  [[UIBarButtonItem alloc] initWithImage: backImage
	                                   style: UIBarButtonItemStylePlain
	                                  target: self
	                                  action: @selector(handleNavigationBack:)];

	self.navigationItem.leftBarButtonItem = backItem;

	UIBarButtonItem *addItem =
	  [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemAdd
	                                                target: self
	                                                action: @selector(btnAddSocialTapped:)];

	self.navigationItem.rightBarButtonItem = addItem;
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	isViewVisible = YES;
	
	[self refreshProviders];
}


- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	isViewVisible = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AccountSetupViewController_IOS_Child_Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
		[self refreshView];
	}
}

/**
 * Invoked when the reachability changes.
 * That is, when the circumstances of our Internet access has changed.
 */
- (void)reachabilityChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Notification invoked on non-main thread !");
	
	BOOL newHasInternet = zdc.reachability.isReachable;
	
	BOOL needsUpdateUI = NO;
	if (!hasInternet && newHasInternet)
	{
		hasInternet = YES;
		needsUpdateUI = YES;
	}
	else if (hasInternet && !newHasInternet)
	{
		hasInternet = NO;
		needsUpdateUI = YES;
	}
	
	if (needsUpdateUI)
	{
		[self refreshView];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (UIImage *)defaultUserImage
{
	if (_defaultUserImage_mustUseLazyGetter == nil)
	{
		_defaultUserImage_mustUseLazyGetter =
		  [zdc.imageManager.defaultUserAvatar imageWithMaxSize:[SocialIDUITableViewCell avatarSize]];
	}
	
	return _defaultUserImage_mustUseLazyGetter;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

- (IBAction)btnAddSocialTapped:(id)sender
{
	ZDCLogAutoTrace();

	[self addProviderforUserID:localUserID];
}

// MARK: Refresh

- (void)refreshProviders
{
	__weak typeof(self) weakSelf = self;

	if (!hasInternet) {
		return;
	}
	
	[accountSetupVC showWait: @"Please Wait…"
	                 message: @"Checking with server"
	          viewController: self
	         completionBlock: nil];

	ZDCLocalUserManager *localUserManager = accountSetupVC.zdc.localUserManager;
	[localUserManager refreshAuth0ProfilesForLocalUserID: localUserID
	                                     completionQueue: dispatch_get_main_queue()
	                                     completionBlock:^(NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		[strongSelf.accountSetupVC cancelWait];
		if (error)
		{
			[strongSelf.accountSetupVC showError: @"Could not get social identity"
			                              message: error.localizedDescription
			                       viewController: strongSelf
			                      completionBlock: nil];
		}
		else
		{
			[strongSelf refreshView];
		}
	}];
}

- (void)refreshView
{
	ZDCLogAutoTrace();
	
	__block ZDCLocalUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];

	if (localUser == nil)
	{
		rowItems = nil;
		[self reloadTable];
		return;
	}

	Auth0ProviderManager *auth0ProviderManager = zdc.auth0ProviderManager;
	
	NSMutableArray<SocialIdentityManagementVC_RowItem *> *newRowItems = [NSMutableArray array];
	NSDictionary *profiles = localUser.auth0_profiles;

	for (NSString *auth0ID in profiles)
	{
		NSDictionary *profile = profiles[auth0ID];

		if ([Auth0Utilities isRecoveryProfile:profile])
		{
			// Skip the recovery identity
			continue;
		}
		
		NSArray *comps = [auth0ID componentsSeparatedByString:@"|"];
		NSString *provider = comps.firstObject;

		NSDictionary *providerInfo = auth0ProviderManager.providersInfo[provider];
		if (providerInfo == nil)
		{
			continue;
		}
		
		NSString *providerName = providerInfo[kAuth0ProviderInfo_Key_DisplayName];
		NSString *connection = profile[@"connection"];

		BOOL isUserAuthProfile = [Auth0Utilities isUserAuthProfile:profile];
		NSString *displayName = [localUser displayNameForAuth0ID:auth0ID];
            
		SocialIdentityManagementVC_RowItem *rowItem = [[SocialIdentityManagementVC_RowItem alloc] init];
		
		rowItem.isRealCell = YES;
		rowItem.isUserAuthProfile = isUserAuthProfile;
		
		rowItem.auth0ID = auth0ID;
		rowItem.provider = provider;
		rowItem.providerName = providerName;
		rowItem.connection = connection ?: @"";
		rowItem.displayName = displayName;
		
		rowItem.isPrimaryProfile = [profile[@"isPrimaryProfile"] boolValue];
		rowItem.isPreferredProfile = [auth0ID isEqualToString:localUser.auth0_preferredID];
		
		[newRowItems addObject:rowItem];
	}

	// Sort alphanumerically, based on provider name
	
	[newRowItems sortUsingComparator:^NSComparisonResult(id item1, id item2) {

		SocialIdentityManagementVC_RowItem *rowItem1 = (SocialIdentityManagementVC_RowItem *)item1;
		SocialIdentityManagementVC_RowItem *rowItem2 = (SocialIdentityManagementVC_RowItem *)item2;
		
		NSString *id1 = rowItem1.providerName;
		NSString *id2 = rowItem2.providerName;

		return [id1 localizedCaseInsensitiveCompare:id2];
	}];

	_vwAddMoreLoser.hidden = newRowItems.count > 1;

	// We can't get the UITableView to properly show seperators, unless we have multiple cells.
	// After fighting with UITableView, and searching online for too long, we gave up.
	// And we're using this ugly hack instead.
	//
	for (NSUInteger i = newRowItems.count; i < 5 ; i++)
	{
		SocialIdentityManagementVC_RowItem *rowItem = [[SocialIdentityManagementVC_RowItem alloc] init];
		rowItem.isRealCell = NO;

		[newRowItems addObject:rowItem];
	}

	rowItems = [newRowItems copy];
	[self reloadTable];
}

- (void)reloadTable
{
	[_tblProviders reloadData];
	[self scrollToPreferedProvider];
}

- (void)scrollToPreferedProvider
{
	for (NSUInteger row = 0; row < rowItems.count; row++)
	{
		SocialIdentityManagementVC_RowItem *rowItem = rowItems[row];
		if (rowItem.isPreferredProfile)
		{
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
			
			[_tblProviders scrollToRowAtIndexPath: indexPath
			                     atScrollPosition: UITableViewScrollPositionMiddle
			                             animated: YES];
			return;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UITableView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return rowItems.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [SocialIDUITableViewCell heightForCell];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	__block ZDCLocalUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	SocialIDUITableViewCell *cell = (SocialIDUITableViewCell *)
	  [tv dequeueReusableCellWithIdentifier:kSocialIDCellIdentifier];
	
	SocialIdentityManagementVC_RowItem *rowItem = rowItems[indexPath.row];
	
	if (!rowItem.isRealCell)
	{
		cell.imgAvatar.hidden = YES;
		cell.imgProvider.hidden = YES;
		cell.lbProvider.hidden = YES;
		cell.lblUserName.hidden = YES;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.lbLeftTag.text = @"";
		
		return cell;
	}
	
	cell.delegate = (id <SocialIDUITableViewCellDelegate>)self;
	
	cell.uuid = localUserID;
	cell.Auth0ID = rowItem.auth0ID;
	
	cell.lblUserName.hidden = NO;
	cell.lblUserName.textColor = [UIColor blackColor];
	cell.lblUserName.text = rowItem.displayName;
	
	cell.lbLeftTag.textColor = self.view.tintColor;
	if (rowItem.isPreferredProfile) {
		cell.lbLeftTag.text = @"✓";
	}
	else if (rowItem.isPrimaryProfile) {
		cell.lbLeftTag.text = @"⚬";
	}
	else {
		cell.lbLeftTag.text = @"";
	}
	
	if (rowItem.isUserAuthProfile) {
		[cell showRightButton:YES];
	}
	else {
		[cell showRightButton:NO];
	}
	
	OSImage *providerImage =
	  [[zdc.auth0ProviderManager providerIcon: Auth0ProviderIconType_Signin
	                              forProvider: rowItem.provider]
	                           scaledToHeight: [SocialIDUITableViewCell imgProviderHeight]];
		
	if (providerImage)
	{
		cell.imgProvider.image = providerImage;
		cell.imgProvider.hidden = NO;
		cell.lbProvider.hidden = YES;
	}
	else
	{
		cell.lbProvider.text = rowItem.provider;
		cell.lbProvider.hidden = NO;
		cell.imgProvider.hidden = YES;
	}
	
	CGSize avatarSize = [SocialIDUITableViewCell avatarSize];
	
	cell.imgAvatar.hidden = NO;
	cell.imgAvatar.clipsToBounds = YES;
	cell.imgAvatar.layer.cornerRadius = avatarSize.height / 2;
	
	ZDCImageProcessingBlock processingBlock = ^OSImage* (OSImage *image) {
		
		return [image imageWithMaxSize:avatarSize];
	};
	
	void (^preFetch)(OSImage*, BOOL) = ^(OSImage *image, BOOL willFetch) {
		
		// The preFetch is invoked BEFORE the fetchUserAvatar method returns.
		
		cell.imgAvatar.image = image ?: [self defaultUserImage];
	};
	
	void (^postFetch)(OSImage*, NSError*) = ^(OSImage *image, NSError *error) {
		
		if (image)
		{
			// Check that the cell hasn't been recycled (is still being used for this auth0ID)
			if (cell.Auth0ID == rowItem.auth0ID) {
				cell.imgAvatar.image =  image;
			}
		}
	};
	
	ZDCFetchOptions *options = [[ZDCFetchOptions alloc] init];
	options.auth0ID = rowItem.auth0ID;
	
	[zdc.imageManager fetchUserAvatar: localUser
	                      withOptions: options
	                     processingID: NSStringFromClass([self class])
	                  processingBlock: processingBlock
	                    preFetchBlock: preFetch
	                   postFetchBlock: postFetch];
	
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}


- (NSArray *)tableView:(UITableView *)tv editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
	SocialIdentityManagementVC_RowItem *rowItem = rowItems[indexPath.row];
	
	if (!rowItem.isRealCell)
	{
		return @[];
	}
	
	NSUInteger realAccounts = 0;
	for (SocialIdentityManagementVC_RowItem *rowItem in rowItems)
	{
		if (rowItem.isRealCell) {
			realAccounts++;
		}
	}

	if (realAccounts == 0)
	{
		UITableViewRowAction *deleteAction =
		  [UITableViewRowAction rowActionWithStyle: UITableViewRowActionStyleDefault
		                                     title: @"Cannot Remove"
		                                   handler:
		^(UITableViewRowAction *action, NSIndexPath *indexPath)
		{
			  // Nothing to do here
		}];

		deleteAction.backgroundColor = [UIColor lightGrayColor];
		return @[deleteAction];
	}
	
	__weak typeof(self) weakSelf = self;
	
	UITableViewRowAction *deleteAction =
	  [UITableViewRowAction rowActionWithStyle: UITableViewRowActionStyleDefault
	                                     title: @"Remove"
	                                   handler:
	^(UITableViewRowAction *action, NSIndexPath *indexPath)
	{
		[weakSelf verifyDeleteItem:rowItem atIndexPath:indexPath];
	}];

	deleteAction.backgroundColor = [UIColor redColor];
	return @[deleteAction];
}


#if __IPHONE_11_0
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0)
{
	SocialIdentityManagementVC_RowItem *rowItem = rowItems[indexPath.row];

	if (!rowItem.isRealCell)
	{
		return [UISwipeActionsConfiguration configurationWithActions:@[]];
	}
	
	NSUInteger realAccounts = 0;
	for (SocialIdentityManagementVC_RowItem *rowItem in rowItems)
	{
		if (rowItem.isRealCell) {
			realAccounts++;
		}
	}
	
//	if (@available(iOS 11.0, *))
	
	NSMutableArray *actions =  [NSMutableArray arrayWithCapacity:1];

	if (realAccounts == 0)
	{
		UIContextualAction *deleteAction =
		  [UIContextualAction contextualActionWithStyle: UIContextualActionStyleNormal
		                                          title: @"Cannot Remove"
		                                        handler:
		^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL))
		{
			completionHandler(YES);
		}];
		
		deleteAction.backgroundColor = UIColor.lightGrayColor;
		[actions addObject:deleteAction];
	}
	else
	{
		__weak typeof(self) weakSelf = self;
		
		UIContextualAction *deleteAction =
		  [UIContextualAction contextualActionWithStyle: UIContextualActionStyleNormal
		                                          title: @"Remove"
		                                        handler:
		^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL))
		{
			[weakSelf verifyDeleteItem:rowItem atIndexPath:indexPath];
			completionHandler(YES);
		}];
		
		deleteAction.backgroundColor = UIColor.redColor;
		[actions addObject:deleteAction];
	}
			
	UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
	config.performsFirstActionWithFullSwipe = NO;

	return config;
}
#endif


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();

	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	SocialIdentityManagementVC_RowItem *rowItem = rowItems[indexPath.row];

	if (!rowItem.isRealCell) {
		return;
	}

	// Sanity check:
	// Don't allow selection of recovery.
	// This shouldn't be in the list anyway, but just in case.
	//
	if ([rowItem.connection isEqualToString:kAuth0DBConnection_Recovery]) {
		return;
	}

	NSString *_localUserID = [localUserID copy];
	NSString *selectedAuth0ID = rowItem.auth0ID;
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCLocalUser *updatedUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		if (updatedUser)
		{
			updatedUser = [updatedUser copy];
			updatedUser.auth0_preferredID = selectedAuth0ID;
			
			[transaction setObject:updatedUser forKey:updatedUser.uuid inCollection:kZDCCollection_Users];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: SocialIDUITableViewCellDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)tableView:(UITableView *)tableView rightButtonTappedAtCell:(SocialIDUITableViewCell *)cell
{
	ZDCLogAutoTrace();
	
	[self.accountSetupVC pushUserAvatarWithUserID: cell.uuid
	                                      auth0ID: cell.Auth0ID
	                     withNavigationController: self.navigationController];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Provider actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)verifyDeleteItem:(SocialIdentityManagementVC_RowItem *)rowItem atIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	NSString *warningText = [NSString stringWithFormat:
	  @"Are you sure you wish to unlink the social identity with %@?",
	  rowItem.provider
	];

	if (rowItem.isPrimaryProfile)
	{
		// This is only the case if we don't have a recovery identity setup for the user.
		// Which should only happen due to a bug.
		
		warningText = [warningText stringByAppendingString:
		  @"\nSince this is your primary profile, you might be required to sign in again."];
	}

	__weak typeof(self) weakSelf = self;
	
	UIAlertAction *deleteAction =
	  [UIAlertAction actionWithTitle: NSLocalizedString(@"Remove", @"Remove action")
	                           style: UIAlertActionStyleDestructive
	                         handler:^(UIAlertAction *action)
	{
		[weakSelf deleteProviderItem:rowItem];
	}];

	UIAlertAction *cancelAction =
	  [UIAlertAction actionWithTitle: NSLocalizedString(@"Cancel", @"Cancel action")
	                           style: UIAlertActionStyleCancel
	                         handler:^(UIAlertAction *action)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		[strongSelf->_tblProviders setEditing:NO];
	}];

	UIAlertController *alertController =
	  [UIAlertController alertControllerWithTitle: @"Remove Social Identity"
	                                      message: warningText
	                               preferredStyle: UIAlertControllerStyleActionSheet];
	
	[alertController addAction:deleteAction];
	[alertController addAction:cancelAction];

	if ([ZDCConstants isIPad])
	{
		CGRect sourceRect = [_tblProviders rectForRowAtIndexPath:indexPath];
		sourceRect.origin.y += sourceRect.size.height/2;
		sourceRect.size.height = 1;
		sourceRect.size.width =  sourceRect.size.width/3;
		
		alertController.popoverPresentationController.sourceRect = sourceRect;
		alertController.popoverPresentationController.sourceView = _tblProviders;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}

	[self presentViewController: alertController
	                   animated: YES
	                 completion:^{}];
}

- (void)deleteProviderItem:(SocialIdentityManagementVC_RowItem *)rowItem
{
	NSUInteger index = rowItems.count;
	for (NSUInteger i = 0; i < rowItems.count; i++)
	{
		SocialIdentityManagementVC_RowItem *currentRowItem = rowItems[i];
		
		if ([currentRowItem.auth0ID isEqualToString:rowItem.auth0ID])
		{
			index = i;
			break;
		}
	}
	
	if (index == rowItems.count)
	{
		// Not found ?!?!
		return;
	}
	
	NSMutableArray *newRowItems = [rowItems mutableCopy];
	[newRowItems removeObjectAtIndex:index];
	
	rowItems = [newRowItems copy];
	
	[_tblProviders beginUpdates];
	{
		NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
		[_tblProviders deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	}
	[_tblProviders endUpdates];

	[self.accountSetupVC showWait: @"Updating your user profile…"
	                      message: @"one moment — contacting servers…"
	               viewController: self
	              completionBlock: nil];

	__weak typeof(self) weakSelf = self;
	
	[self.accountSetupVC unlinkAuth0ID: rowItem.auth0ID
	                   fromLocalUserID: localUserID
	                   completionQueue: dispatch_get_main_queue()
	                   completionBlock:^(NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		[strongSelf->_tblProviders setEditing:NO];
		[strongSelf.accountSetupVC cancelWait];

		if (error)
		{
			NSString *message = nil;
		#if DEBUG
			message = error.localizedDescription;
		#else
			message = @"Check internet connection.";
		#endif
			
			[strongSelf.accountSetupVC showError: @"Could not contact server."
			                             message: message
			                     completionBlock:^{ [weakSelf refreshView]; }];
		}
		else
		{
			if (rowItem.isPrimaryProfile)
			{
				[strongSelf.navigationController popToRootViewControllerAnimated:YES];
			}
			else
			{
				[strongSelf refreshProviders];
			}
		}
	}];
}

- (void)addProviderforUserID:(NSString *)userID
{
	[self.accountSetupVC pushAddIdentityWithUserID: userID
	                      withNavigationController: self.navigationController];
}

@end
