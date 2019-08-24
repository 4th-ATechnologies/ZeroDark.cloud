/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "LocalUserListViewController.h"

#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

// Categories
#import "NSString+ZeroDark.h"
#import "OSImage+ZeroDark.h"

static NSString *const k_userID      = @"userID";
static NSString *const k_displayName = @"displayName";

@interface LocalUserListUITableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView		*userAvatar;
@property (nonatomic, weak) IBOutlet UILabel        	*lblTitle;
@property (nonatomic, copy) NSString *uuid;	// optional value


+ (CGFloat)heightForCell;
+ (CGSize)avatarSize;
@end

@implementation LocalUserListUITableViewCell
@synthesize userAvatar;
@synthesize lblTitle;
@synthesize uuid;


+ (CGSize)avatarSize
{
	return CGSizeMake(28, 28);
}

+ (CGFloat)heightForCell
{
	return 30;
}

@end

@implementation LocalUserListViewController_IOS
{
	IBOutlet __weak UITableView             *_tblButtons;
	IBOutlet __weak NSLayoutConstraint      *_cnstTblButtonsHeight;

	NSString								* currentUserID;
	NSArray <NSDictionary*> 		* sortedLocalUserInfo;
	ZeroDarkCloud*              	owner;
	ZDCImageManager         *imageManager;
	YapDatabaseConnection 	*databaseConnection;


}
@synthesize delegate = delegate;

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
							delegate:(nullable id <LocalUserListViewController_Delegate>)inDelegate
					 currentUserID:(NSString*)currentUserIDIn
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LocalUserListViewController_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"LocalUserListViewController"];
	if (self)
	{
		owner = inOwner;
		delegate = inDelegate;
		currentUserID = currentUserIDIn?:@"";
	}
	return self;

}


- (void)viewDidLoad {
	[super viewDidLoad];
 	_tblButtons.estimatedSectionHeaderHeight = 0;
	_tblButtons.estimatedSectionFooterHeight = 0;
	_tblButtons.estimatedRowHeight = 0;
	_tblButtons.rowHeight = UITableViewAutomaticDimension;
	
	_tblButtons.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
	//
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 80, 0, 0); // top, left, bottom, right
	
	imageManager = owner.imageManager;
	databaseConnection = owner.databaseManager.uiDatabaseConnection;

	sortedLocalUserInfo = NULL;
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reloadUserTable];
}

-(void) updateViewConstraints
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



-(CGFloat) preferedWidth
{
	CGFloat width = 250.0f;	// use default
	
	if([ZDCConstants isIPad])
	{
		width = 300.0f;
	}
	
	return width;
}

#pragma mark - UIPresentationController Delegate methods

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

// MARK: Tableview

-(void) reloadUserTable
{
	__weak typeof(self) weakSelf = self;

	__block NSMutableArray <ZDCLocalUser *> * _localUsers = NSMutableArray.array;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		
		[self->owner.localUserManager enumerateLocalUsersWithTransaction:transaction
																				usingBlock:^(ZDCLocalUser * _Nonnull localUser, BOOL * _Nonnull stop)
		 {
			 if (localUser.hasCompletedSetup
				  && !localUser.accountDeleted
				  && !localUser.accountSuspended
				  && !localUser.accountNeedsA0Token)
				 [_localUsers addObject:localUser];
			 
		 }];
	}];
#pragma clang diagnostic pop
	
	NSMutableArray <NSDictionary*>  * _sortedLocalUserInfo = NSMutableArray.array;
	
	if(_localUsers.count > 1)
	{
		[_sortedLocalUserInfo addObject:@{
			k_userID      : @"",
			k_displayName : NSLocalizedString( @"All Users", @"All Users")
		}];
	}
	
	[_sortedLocalUserInfo addObjectsFromArray:
	 [owner.localUserManager sortedUnambiguousUserInfoWithLocalUsers:_localUsers]];
	
	sortedLocalUserInfo = _sortedLocalUserInfo;
	
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
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return sortedLocalUserInfo.count;
}



- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	__weak typeof(self) weakSelf = self;
	
	LocalUserListUITableViewCell *cell =   [tableView dequeueReusableCellWithIdentifier:@"LocalUserListUITableViewCell"];

	cell.userAvatar.layer.cornerRadius =  LocalUserListUITableViewCell.avatarSize.height / 2;
	cell.userAvatar.clipsToBounds = YES;

	NSDictionary<NSString *, NSString *> *localUserInfo = [sortedLocalUserInfo objectAtIndex:indexPath.row];
	
	NSString* displayName = localUserInfo[k_displayName];
	NSString* uuid = localUserInfo[k_userID];
	
	if ([uuid isEqualToString:@""])
	{
		cell.lblTitle.text = displayName;
		cell.lblTitle.textColor = self.view.tintColor;
		cell.uuid = uuid;
		cell.userAvatar.image  = [imageManager defaultMultiUserAvatar];
	}
	else
	{
		__block ZDCLocalUser *user = nil;
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			user = [transaction objectForKey:uuid inCollection:kZDCCollection_Users];
			
		#pragma clang diagnostic pop
		}];
		
		cell.lblTitle.text = displayName;
		cell.lblTitle.textColor = UIColor.blackColor;
		cell.uuid = uuid;
 
		void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
			
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			cell.userAvatar.image  = image ?: [strongSelf->imageManager defaultUserAvatar];
		};
		
		void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
			
			__strong typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			
			cell.userAvatar.image = image ?: [strongSelf->imageManager defaultUserAvatar];
		};
		
		[imageManager fetchUserAvatar: user
							 preFetchBlock: preFetchBlock
							postFetchBlock: postFetchBlock];
	}

	return cell;
}


#define UITableViewCellEditingStyleMultiSelect (3)

-(UITableViewCellEditingStyle)tableView:(UITableView*)tv editingStyleForRowAtIndexPath:(NSIndexPath*)indexPath {
	
	// apple doesnt support this and might reject it, but the alternative  style UITableViewCellEditingStyleDelete is ugly
	return UITableViewCellEditingStyleMultiSelect;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPathIn
{
//	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	
	NSDictionary<NSString *, NSString *> *localUserInfo = [sortedLocalUserInfo objectAtIndex:indexPathIn.row];
	NSString *userID = localUserInfo[k_userID];

	currentUserID = userID;
	
	NSArray<NSIndexPath *>* indexPaths = tableView.indexPathsForSelectedRows;
	[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * iPath, NSUInteger idx, BOOL * _Nonnull stop) {
		
		if(![iPath isEqual:indexPathIn])
			[tableView deselectRowAtIndexPath:iPath animated:NO];
	}];

	if ([self.delegate  respondsToSelector:@selector(localUserListViewController:didSelectUserID:)])
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
