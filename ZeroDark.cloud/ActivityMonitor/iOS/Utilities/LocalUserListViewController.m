/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "LocalUserListViewController.h"

#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSString+ZeroDark.h"
#import "OSImage+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

@interface LocalUserListUITableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView * userAvatar;
@property (nonatomic, weak) IBOutlet UILabel     * lblTitle;
@property (nonatomic, copy) NSString *userID;

+ (CGFloat)heightForCell;
+ (CGSize)avatarSize;

@end

@implementation LocalUserListUITableViewCell

@synthesize userAvatar;
@synthesize lblTitle;
@synthesize userID;

+ (CGSize)avatarSize
{
	return CGSizeMake(28, 28);
}

+ (CGFloat)heightForCell
{
	return 30;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation LocalUserListViewController_IOS
{
	IBOutlet __weak UITableView             *_tblButtons;
	IBOutlet __weak NSLayoutConstraint      *_cnstTblButtonsHeight;
	
	ZeroDarkCloud *zdc;
	YapDatabaseConnection *uiDatabaseConnection;
	
	NSString *selectedUserID;
	NSArray<ZDCUserDisplay *> *sorted;
}

@synthesize delegate = delegate;

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner
                     delegate:(nullable id <LocalUserListViewController_Delegate>)inDelegate
               selectedUserID:(NSString *)inSelectedUserID
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LocalUserListViewController_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"LocalUserListViewController"];
	if (self)
	{
		zdc = owner;
		delegate = inDelegate;
		selectedUserID = [inSelectedUserID copy];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
	ZDCLogAutoTrace();
	[super viewDidLoad];
	
	_tblButtons.estimatedSectionHeaderHeight = 0;
	_tblButtons.estimatedSectionFooterHeight = 0;
	_tblButtons.estimatedRowHeight = 0;
	_tblButtons.rowHeight = UITableViewAutomaticDimension;
	
	_tblButtons.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	if (@available(iOS 11.0, *)) {
		_tblButtons.separatorInsetReference = UITableViewSeparatorInsetFromCellEdges;
	}
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 40, 0, 0); // top, left, bottom, right
	
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	
	uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	[self reloadUserTable];
}

- (void)updateViewConstraints
{
	[super updateViewConstraints];
 	_cnstTblButtonsHeight.constant = _tblButtons.contentSize.height;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	
	self.preferredContentSize = (CGSize){
		.width = self.preferredWidth,
		.height = _tblButtons.frame.origin.y + _tblButtons.contentSize.height -1
	};
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (CGFloat)preferredWidth
{
	CGFloat width = 250.0f;	// use default
	
	if ([ZDCConstants isIPad])
	{
		width = 300.0f;
	}
	
	return width;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIPresentationController Delegate methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
																					traitCollection:(UITraitCollection *)traitCollection {
	return UIModalPresentationNone;
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
{
	return UIModalPresentationNone;
}

- (UIViewController *)presentationController:(UIPresentationController *)controller
  viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style
{
	UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller.presentedViewController];
	return navController;
}

- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popoverPresentationController;
{
	//	if ([self.delegate  respondsToSelector:@selector(languageListViewController:didSelectLanguage:)])
	//	{
	//		[self.delegate languageListViewController:self didSelectLanguage:NULL ];
	//	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Refresh
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)reloadUserTable
{
	ZDCLogAutoTrace();
	
	NSMutableArray *localUsers = [NSMutableArray array];
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		[zdc.localUserManager enumerateLocalUsersWithTransaction: transaction
		                                              usingBlock:^(ZDCLocalUser *localUser, BOOL *stop)
		{
			if (localUser.hasCompletedSetup
			 && !localUser.accountDeleted
			 && !localUser.accountSuspended
			 && !localUser.accountNeedsA0Token)
			{
				[localUsers addObject:localUser];
			}
		 }];
	#pragma clang diagnostic pop
	}];
	
	sorted = [zdc.userManager sortedUnambiguousNamesForUsers:localUsers];
	[_tblButtons reloadData];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if (sorted.count == 1) {
		return 1;
	} else {
		return sorted.count + 1;
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCUserDisplay *localUserDisplay = nil;
	
	if (sorted.count == 1) {
		localUserDisplay = sorted[indexPath.row];
	}
	else {
		if (indexPath.row > 0) {
			localUserDisplay = sorted[indexPath.row - 1];
		}
	}
	
	if (localUserDisplay) {
		return [self cellForUser:localUserDisplay];
	} else {
		return [self cellForAllUsers];
	}
}

- (LocalUserListUITableViewCell *)cellForAllUsers
{
	LocalUserListUITableViewCell *cell = (LocalUserListUITableViewCell *)
	  [_tblButtons dequeueReusableCellWithIdentifier:@"LocalUserListUITableViewCell"];
	
	cell.userAvatar.layer.cornerRadius = LocalUserListUITableViewCell.avatarSize.height / 2;
	cell.userAvatar.clipsToBounds = YES;
	
	cell.lblTitle.text = @"All users";
	cell.lblTitle.textColor = UIColor.blackColor;
	cell.userID = nil;
	
	cell.userAvatar.image = [self->zdc.imageManager defaultMultiUserAvatar];
	
	return cell;
}

- (LocalUserListUITableViewCell *)cellForUser:(ZDCUserDisplay *)localUserDisplay
{
	LocalUserListUITableViewCell *cell = (LocalUserListUITableViewCell *)
	  [_tblButtons dequeueReusableCellWithIdentifier:@"LocalUserListUITableViewCell"];

	cell.userAvatar.layer.cornerRadius = LocalUserListUITableViewCell.avatarSize.height / 2;
	cell.userAvatar.clipsToBounds = YES;
	
	NSString *localUserID = localUserDisplay.userID;
	NSString *displayName = localUserDisplay.displayName;
	
	__block ZDCLocalUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	cell.lblTitle.text = displayName;
	cell.lblTitle.textColor = UIColor.blackColor;
	cell.userID = localUserID;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns
		
		if (image) {
			cell.userAvatar.image = image;
		} else {
			cell.userAvatar.image = [self->zdc.imageManager defaultUserAvatar];
		}
	};
	
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetchBlock is invoked LATER, possibly after downloading.
		
		if (image)
		{
			// Ensure the cell hasn't been recycled
			if ([cell.userID isEqualToString:localUserID]) {
				cell.userAvatar.image = image;
			}
		}
	};
		
	[zdc.imageManager fetchUserAvatar: localUser
		                   withOptions: nil
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	
	ZDCUserDisplay *selected = nil;
	
	if (sorted.count == 1) {
		selected = sorted[indexPath.row];
	} else {
		if (indexPath.row > 0) {
			selected = sorted[indexPath.row - 1];
		}
	}

	selectedUserID = selected.userID;
	
	NSArray<NSIndexPath *>* indexPaths = tableView.indexPathsForSelectedRows;
	[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * iPath, NSUInteger idx, BOOL * _Nonnull stop) {
		
		if (![iPath isEqual:indexPath]) {
			[tableView deselectRowAtIndexPath:iPath animated:NO];
		}
	}];

	if ([self.delegate respondsToSelector:@selector(localUserListViewController:didSelectUserID:)])
	{
		[self.delegate localUserListViewController:self didSelectUserID:selectedUserID];
	}
}

@end
