/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "SocialidentityManagementViewController_IOS.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "IdentityProviderTableViewCell.h"
#import "SocialIDUITableViewCell.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLocalUserManagerPrivate.h"
#import "ZDCLocalUserPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZeroDarkCloudPrivate.h"

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
@property (nonatomic, assign, readwrite) BOOL isPrimaryIdentity;
@property (nonatomic, assign, readwrite) BOOL isPreferredIdentity;

@property (nonatomic, strong, readwrite) ZDCUserIdentity *identity;
@property (nonatomic, copy, readwrite) NSString *providerName;

@end


@implementation SocialIdentityManagementVC_RowItem

@synthesize isRealCell;
@synthesize isPrimaryIdentity;
@synthesize isPreferredIdentity;

@synthesize identity;
@synthesize providerName;

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
	BOOL needsRefreshProviders;
	BOOL viewDidLoad;
	
	SCLAlertView * warningAlert;
}

@synthesize accountSetupVC = accountSetupVC;
@synthesize localUserID = localUserID;

- (void)setLocalUserID:(NSString *)inLocalUserID
{
	localUserID = [inLocalUserID copy];
	if (viewDidLoad)
	{
		[self refreshView];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
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

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	
	[nc addObserver: self
	       selector: @selector(reachabilityChanged:)
	           name: AFNetworkingReachabilityDidChangeNotification
	         object: nil /* notification doesn't assign object ! */];
	
	[nc addObserver: self
	       selector: @selector(databaseConnectionDidUpdate:)
	           name: UIDatabaseConnectionDidUpdateNotification
	         object: nil];
		
	hasInternet = zdc.reachability.isReachable;
	needsRefreshProviders = YES;
	
	[self refreshView];
	[self refreshProviders];
	
	viewDidLoad = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
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

/**
 * Invoked when the reachability changes.
 * That is, when the circumstances of our Internet access has changed.
 */
- (void)reachabilityChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Notification invoked on non-main thread !");
	
	BOOL oldHasInternet = hasInternet;
	hasInternet = zdc.reachability.isReachable;
	
	if (!oldHasInternet && hasInternet)
	{
		// Refresh the visible tableView cells.
		//
		// This is because they're showing avatars, which may need to be downloaded.
		// The download would have previously failed, but now it may succeed.
		
		[_tblProviders reloadRowsAtIndexPaths: [_tblProviders indexPathsForVisibleRows]
		                     withRowAnimation: UITableViewRowAnimationNone];
		
	}
	
	if (hasInternet && needsRefreshProviders)
	{
		[self refreshProviders];
	}
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
		  [zdc.imageManager.defaultUserAvatar scaledToSize: [SocialIDUITableViewCell avatarSize]
		                                       scalingMode: ScalingMode_AspectFill];
	}
	
	return _defaultUserImage_mustUseLazyGetter;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Refresh
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)refreshProviders
{
	ZDCLogAutoTrace();

	if (!hasInternet) {
		return;
	}
	
	__weak typeof(self) weakSelf = self;
	
	ZDCLocalUserManager *localUserManager = accountSetupVC.zdc.localUserManager;
	[localUserManager refreshAuth0ProfilesForLocalUserID: localUserID
	                                     completionQueue: dispatch_get_main_queue()
													 completionBlock:^(NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		if (!error) {
			strongSelf->needsRefreshProviders = NO;
		}
		
		// UI refresh not needed because:
		//
		// - the `refreshAuth0Profiles` method will update the localUser in the database
		// - this will trigger a databaseDidUpdate notification
		// - which we listen for, and automatically refresh the tableView as needed
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
	
	NSMutableArray<SocialIdentityManagementVC_RowItem *> *newRowItems = [NSMutableArray array];

	for (ZDCUserIdentity *identity in localUser.identities)
	{
		if (identity.isRecoveryAccount)
		{
			// Skip the recovery identity
			continue;
		}
		
		NSString *identityID = identity.identityID;
		
		BOOL isPrimary = [localUser.auth0_primary isEqualToString:identityID];
		BOOL isPreferred = [localUser.preferredIdentityID isEqualToString:identityID];
		
		SocialIdentityManagementVC_RowItem *rowItem = [[SocialIdentityManagementVC_RowItem alloc] init];
		
		rowItem.isRealCell = YES;
		rowItem.isPrimaryIdentity = isPrimary;
		rowItem.isPreferredIdentity = isPreferred;
		
		rowItem.identity = identity;
		rowItem.providerName = [zdc.auth0ProviderManager displayNameForProvider:identity.provider];
		
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
	[self scrollToPreferredProvider];
}

- (void)scrollToPreferredProvider
{
	for (NSUInteger row = 0; row < rowItems.count; row++)
	{
		SocialIdentityManagementVC_RowItem *rowItem = rowItems[row];
		if (rowItem.isPreferredIdentity)
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
	
	ZDCUserIdentity *identity = rowItem.identity;
	
	cell.uuid = localUserID;
	cell.identityID = identity.identityID;
	
	cell.lblUserName.hidden = NO;
	cell.lblUserName.textColor = [UIColor blackColor];
	cell.lblUserName.text = identity.displayName;
	
	cell.lbLeftTag.textColor = self.view.tintColor;
	if (rowItem.isPreferredIdentity) {
		cell.lbLeftTag.text = @"✓";
	}
	else if (rowItem.isPrimaryIdentity) {
		cell.lbLeftTag.text = @"⚬";
	}
	else {
		cell.lbLeftTag.text = @"";
	}
	
	if ([identity.provider isEqualToString:A0StrategyNameAuth0]) {
		[cell showRightButton:YES];
	}
	else {
		[cell showRightButton:NO];
	}
	
	NSString *provider = rowItem.identity.provider;
	OSImage *providerImage =
	  [[zdc.auth0ProviderManager iconForProvider: provider
	                                        type: Auth0ProviderIconType_Signin]
	                              scaledToHeight: [SocialIDUITableViewCell imgProviderHeight]];
		
	if (providerImage)
	{
		cell.imgProvider.image = providerImage;
		cell.imgProvider.hidden = NO;
		cell.lbProvider.hidden = YES;
	}
	else
	{
		cell.lbProvider.text = rowItem.providerName;
		cell.lbProvider.hidden = NO;
		cell.imgProvider.hidden = YES;
	}
	
	CGSize avatarSize = [SocialIDUITableViewCell avatarSize];
	
	cell.imgAvatar.hidden = NO;
	cell.imgAvatar.clipsToBounds = YES;
	cell.imgAvatar.layer.cornerRadius = avatarSize.height / 2;
	
	ZDCImageProcessingBlock processingBlock = ^OSImage* (OSImage *image) {
		
		return [image scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
	};
	
	void (^preFetch)(OSImage*, BOOL) = ^(OSImage *image, BOOL willFetch) {
		
		// The preFetch is invoked BEFORE the fetchUserAvatar method returns.
		
		cell.imgAvatar.image = image ?: [self defaultUserImage];
	};
	
	void (^postFetch)(OSImage*, NSError*) = ^(OSImage *image, NSError *error) {
		
		// The postFetch is invoked LATER, possibly after downloading the image.
		
		if (image)
		{
			// Check that the cell hasn't been recycled (is still being used for this identityID)
			if ([cell.identityID isEqual:rowItem.identity.identityID]) {
				cell.imgAvatar.image =  image;
			}
		}
	};
	
	ZDCFetchOptions *options = [[ZDCFetchOptions alloc] init];
	options.identityID = rowItem.identity.identityID;
	
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
	if (rowItem.identity.isRecoveryAccount) {
		return;
	}

	NSString *_localUserID = [localUserID copy];
	NSString *selectedIdentityID = rowItem.identity.identityID;
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

		ZDCLocalUser *updatedUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		if (updatedUser)
		{
			updatedUser = [updatedUser copy];
			updatedUser.preferredIdentityID = selectedIdentityID;
			updatedUser.needsUserMetadataUpload = YES;
			
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
	                                   identityID: cell.identityID
	                         navigationController: self.navigationController];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Provider actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)verifyDeleteItem:(SocialIdentityManagementVC_RowItem *)rowItem atIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	NSString *provider = rowItem.identity.provider;
	NSString *providerName = [zdc.auth0ProviderManager displayNameForProvider:provider];
	
	NSString *warningText = [NSString stringWithFormat:
	  @"Are you sure you wish to unlink the social identity with %@?",
	  providerName
	];

	if (rowItem.isPrimaryIdentity)
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
	NSString *identityID = rowItem.identity.identityID;
	
	NSUInteger index = rowItems.count;
	for (NSUInteger i = 0; i < rowItems.count; i++)
	{
		SocialIdentityManagementVC_RowItem *currentRowItem = rowItems[i];
		
		if ([currentRowItem.identity.identityID isEqualToString:identityID])
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
	
	[self.accountSetupVC unlinkAuth0ID: identityID
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
			if (rowItem.isPrimaryIdentity)
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
