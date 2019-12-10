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
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	//
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 80, 0, 0); // top, left, bottom, right
	
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
	
	self.preferredContentSize =   (CGSize){
		.width = self.preferedWidth,
		.height = _tblButtons.frame.origin.y + _tblButtons.contentSize.height -1
	};
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (CGFloat)preferedWidth
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
	
/*
	[CATransaction begin];
	[_tblButtons reloadData];
	
	[_tblButtons setEditing:YES];
	_tblButtons.allowsMultipleSelection = NO;
	_tblButtons.allowsMultipleSelectionDuringEditing = NO;
	
	[CATransaction setCompletionBlock:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;

		__block NSUInteger foundIdx = NSNotFound;
		[strongSelf->sortedLocalUserInfo enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
		
 			NSString *userID = dict[k_userID];
			if ([userID isEqualToString:strongSelf->currentUserID])
			{
				foundIdx = idx;
				*stop = YES;
			}
 		}];
	
		if(foundIdx != NSNotFound)
		{
			NSIndexPath* indexPath = [NSIndexPath indexPathForRow:foundIdx inSection:0];
			[strongSelf->_tblButtons selectRowAtIndexPath: indexPath
			                                     animated: NO
			                               scrollPosition: UITableViewScrollPositionMiddle];
		}
	}];
	[CATransaction commit];
*/
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return sorted.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	LocalUserListUITableViewCell *cell = (LocalUserListUITableViewCell *)
	  [tableView dequeueReusableCellWithIdentifier:@"LocalUserListUITableViewCell"];

	cell.userAvatar.layer.cornerRadius = LocalUserListUITableViewCell.avatarSize.height / 2;
	cell.userAvatar.clipsToBounds = YES;

	ZDCUserDisplay *userDisplay = sorted[indexPath.row];
	
	NSString *userID = userDisplay.userID;
	NSString *displayName = userDisplay.displayName;
	
	__block ZDCLocalUser *user = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	cell.lblTitle.text = displayName;
	cell.lblTitle.textColor = UIColor.blackColor;
	cell.userID = userID;
	
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
			if ([cell.userID isEqualToString:userID]) {
				cell.userAvatar.image = image;
			}
		}
	};
		
	[zdc.imageManager fetchUserAvatar: user
		                   withOptions: nil
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];

	return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView*)tv editingStyleForRowAtIndexPath:(NSIndexPath*)indexPath {
	
	// Apple doesn't support this, but the alternative style UITableViewCellEditingStyleDelete is ugly.
	//
	// UITableViewCellEditingStyleMultiSelect = 3
	//
	return (UITableViewCellEditingStyle)(3);
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	
	ZDCUserDisplay *userDisplay = sorted[indexPath.row];
	NSString *userID = userDisplay.userID;

	selectedUserID = userID;
	
	NSArray<NSIndexPath *>* indexPaths = tableView.indexPathsForSelectedRows;
	[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * iPath, NSUInteger idx, BOOL * _Nonnull stop) {
		
		if (![iPath isEqual:indexPath]) {
			[tableView deselectRowAtIndexPath:iPath animated:NO];
		}
	}];

	if ([self.delegate respondsToSelector:@selector(localUserListViewController:didSelectUserID:)])
	{
		[self.delegate localUserListViewController:self didSelectUserID:userID];
	}
}


// prevent deselection - in effect we have radio buttons
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
	return nil;
}

@end
