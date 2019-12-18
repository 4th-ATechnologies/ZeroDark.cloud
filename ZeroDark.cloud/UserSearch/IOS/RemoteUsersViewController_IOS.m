/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/


#import "RemoteUsersViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "UserSearchViewController_IOS.h"
#import "UserSearchSocialIDViewController_IOS.h"
#import "Auth0Utilities.h"
#import "RemoteUserTableViewCell.h"
#import "EmptyTableViewCell.h"

#import "Auth0ProviderManager.h"

#import "ZDCLogging.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "NSDate+ZeroDark.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@implementation RemoteUsersViewController_IOS
{
	
	IBOutlet __weak UITableView*  	 _tblUsers;
	
	UIBarButtonItem* 						bbnSave;
	
	ZeroDarkCloud*  				owner;
	YapDatabaseConnection*		databaseConnection;
	Auth0ProviderManager* 		providerManager;
	ZDCImageManager*      		imageManager;
	
	NSString*             		localUserID;
	NSSet<NSString*>*     		originalRemoteUserSet;
	NSArray<NSString*>*   		remoteUserIDs;
	
	NSString* 						optionalTitle;
	
	UIImage*               		defaultUserImage;
	
	BOOL                 		didModifyRecipents;
	
	SharedUsersViewCompletionHandler	completionHandler;
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
						localUserID:(NSString *)inLocalUserID
					 remoteUserIDs:(NSSet<NSString*> *_Nullable)inRemoteUserIDs
								title:(NSString *_Nullable)title
				completionHandler:(SharedUsersViewCompletionHandler)inCompletionHandler
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"RemoteUsersViewController_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"RemoteUsersViewController"];
	if (self)
	{
		owner = inOwner;
		completionHandler = inCompletionHandler;
		localUserID = inLocalUserID;
		
		// filter out localUserID if its in the remoteUserIDs
		if( [inRemoteUserIDs containsObject:localUserID])
		{
			NSMutableSet* newRemoteUserIDs = inRemoteUserIDs.mutableCopy;
			[newRemoteUserIDs removeObject:localUserID];
			originalRemoteUserSet = newRemoteUserIDs;
		}
		else
		{
			originalRemoteUserSet = inRemoteUserIDs;
		}
		remoteUserIDs = originalRemoteUserSet.allObjects;
		optionalTitle = title;
		
		didModifyRecipents = NO;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	
	[RemoteUserTableViewCell registerViewsforTable:_tblUsers
														 bundle:[ZeroDarkCloud frameworkBundle]];
	
	[EmptyTableViewCell registerViewsforTable:_tblUsers
												  bundle:[ZeroDarkCloud frameworkBundle]];
	
	_tblUsers.separatorInset = UIEdgeInsetsMake(0, 58, 0, 0); // top, left, bottom, right
	//    _tblUsers.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblUsers.frame.size.width, 1)];
	
	_tblUsers.allowsSelection = YES;
	_tblUsers.estimatedRowHeight = 0;
	_tblUsers.estimatedSectionHeaderHeight = 0;
	_tblUsers.estimatedSectionFooterHeight = 0;
	//  _tblUsers.touchDelegate    =  (id <UITableViewTouchDelegate>) self;
	
	providerManager = owner.auth0ProviderManager;
	imageManager =  owner.imageManager;
	databaseConnection = owner.databaseManager.uiDatabaseConnection;
	
	defaultUserImage =
	  [imageManager.defaultUserAvatar scaledToSize: [RemoteUserTableViewCell avatarSize]
	                                   scalingMode: ScalingMode_AspectFill];
	
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	if(optionalTitle)
		self.navigationItem.title = optionalTitle;
	else
		self.navigationItem.title = NSLocalizedString(@"Recipients", @"Recipients");
	
	
	UIBarButtonItem* cancelItem = [[UIBarButtonItem alloc]
											 initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
											 target:self action:@selector(cancelButtonTapped:)];
	
	self.navigationItem.leftBarButtonItems = @[cancelItem];
	
	
	UIBarButtonItem* addItem = [[UIBarButtonItem alloc]
										 initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
										 target:self
										 action:@selector(didTapAddItemButton:)];
	
	bbnSave = [[UIBarButtonItem alloc]
				  initWithBarButtonSystemItem:UIBarButtonSystemItemSave
				  target:self action:@selector(doneButtonTapped:)];
	
	self.navigationItem.rightBarButtonItems = @[bbnSave, addItem];
	bbnSave.enabled = didModifyRecipents;
	
	[_tblUsers reloadData];
}


-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)doneButtonTapped:(id)sender
{
	if (completionHandler)
	{
		NSSet<NSString*> *addedUserIDs = nil;
		NSSet<NSString*> *removedUserIDs = nil;
		
		if (didModifyRecipents)
		{
			NSMutableSet<NSString *> *added = [NSMutableSet setWithArray:remoteUserIDs];
			[added minusSet:originalRemoteUserSet];
			
			NSMutableSet<NSString *> *removed = [originalRemoteUserSet mutableCopy];
			[removed minusSet:[NSSet setWithArray:remoteUserIDs]];
			
			addedUserIDs = [added copy];
			removedUserIDs = [removed copy];
		}
		
		if (addedUserIDs == nil) addedUserIDs = [NSSet set];
		if (removedUserIDs == nil) removedUserIDs = [NSSet set];
		
		completionHandler(addedUserIDs, removedUserIDs);
	}
	
	[self.navigationController popViewControllerAnimated:YES];
	
}

- (IBAction)cancelButtonTapped:(id)sender
{
	if (completionHandler)
	{
		NSSet *empty = [NSSet set];
		completionHandler(empty, empty);
	}
	
	[self.navigationController popViewControllerAnimated:YES];
}


- (void)didTapAddItemButton:(UIButton *)backButton
{
	UserSearchViewController_IOS* vc = [[UserSearchViewController_IOS alloc]
													initWithDelegate:(id <UserSearchViewControllerDelegate>)self
													owner:owner
													localUserID:localUserID
													sharedUserIDs:remoteUserIDs];
	
	[self.navigationController pushViewController:vc animated:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)badgeTextWithCount:(NSUInteger)count
{
	NSString *result = nil;
	
	if (count == 0) {
		result = @"";
	}
	else if (count > 99) {
		result = @"99+";
	}
	else {
		result = [NSString stringWithFormat:@"%lu", (unsigned long)count];
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark EmptyTableViewCell
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)tableView:(UITableView * _Nonnull)tv emptyCellButtonTappedAtCell:(EmptyTableViewCell* _Nonnull)cell
{
	if(tv == _tblUsers)
	{
		[self didTapAddItemButton:cell.btn];
	}
}


#pragma mark - tableview


- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	NSInteger result = 0;
	
	if(tv == _tblUsers)
	{
		result = remoteUserIDs.count?remoteUserIDs.count:1;
	}
	
	return result;
}


- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	CGFloat result = 0;
	
	if(tv == _tblUsers)
	{
		if(remoteUserIDs.count )
			result =  [RemoteUserTableViewCell heightForCell];
		else
			result = [EmptyTableViewCell heightForCell];
	}
	
	return result;
}


- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell* cell = nil;
	
	if(remoteUserIDs.count)
		cell = [self tableView:tv remoteUserCellForRowAtIndexPath:indexPath];
	else
		cell = [self tableView:tv emptyTablecellForRowAtIndexPath:indexPath];
	
	return cell;
}


- (UITableViewCell *)tableView:(UITableView *)tv emptyTablecellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	EmptyTableViewCell *etvc = (EmptyTableViewCell *)[tv dequeueReusableCellWithIdentifier:kEmptyTableViewCellIdentifier];
	
	etvc.lblText.hidden = YES;
	[etvc.btn setTitle:NSLocalizedString(@"Add a recipient", @"Add a recipient") forState:UIControlStateNormal];
	etvc.delegate = (id<EmptyTableViewCellDelegate>)self;
	
	return etvc;
}


- (UITableViewCell *)tableView:(UITableView *)tv remoteUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	__weak typeof(self) weakSelf = self;
	
	RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)[tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];
	cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;

	NSString* userID = [remoteUserIDs objectAtIndex:indexPath.row];
 
	__block ZDCUser*    user    = nil;
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
	}];

	CGSize avatarSize = [RemoteUserTableViewCell avatarSize];
	
	cell.showCheckMark     = NO;
	cell.imgAvatar.hidden = NO;
	cell.imgAvatar.clipsToBounds = YES;
	cell.imgAvatar.layer.cornerRadius = avatarSize.height / 2;

	if(user)
	{
		cell.userID = user.uuid;

		NSString* displayName  = [user displayName];
		cell.lblUserName.text = displayName;

		ZDCUserIdentity *displayIdentity = user.displayIdentity;
		
		NSString *provider = displayIdentity.provider;
		
		OSImage *providerImage =
				  [[providerManager iconForProvider: provider
																	type: Auth0ProviderIconType_Signin]
													  scaledToHeight: cell.lblProvider.frame.size.height];
		if(providerImage)
			{
				cell.imgProvider.image =  providerImage;
				cell.imgProvider.hidden = NO;
				cell.lblProvider.hidden = YES;
			}
			else
			{
				NSString* providerName =  [providerManager displayNameForProvider:provider];
				cell.lblProvider.text = providerName;
				cell.imgProvider.hidden = YES;
				cell.lblProvider.hidden = NO;
			}

		ZDCImageProcessingBlock processingBlock = ^OSImage* (OSImage *image) {
			
			return [image scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
		};
		
		void (^preFetch)(OSImage*, BOOL) = ^(OSImage *image, BOOL willFetch) {
			
			// The preFetch is invoked BEFORE the fetchUserAvatar method returns.
			cell.imgAvatar.image = image ?:  self->defaultUserImage;
		};
		
		void (^postFetch)(OSImage*, NSError*) = ^(OSImage *image, NSError *error) {
			
			// The postFetch is invoked LATER, possibly after downloading the image.
				 __strong typeof(self) strongSelf = weakSelf;
					 if(strongSelf == nil) return;
			
			if (image)
			{
				// Check that the cell hasn't been recycled (is still being used for this identityID)
				if ([cell.userID isEqual: user.uuid]) {
					cell.imgAvatar.image =  image;
				}
			}
		};
		
		
		[imageManager fetchUserAvatar: user
									 withOptions: nil
									processingID: NSStringFromClass([self class])
								processingBlock: processingBlock
								  preFetchBlock: preFetch
								 postFetchBlock: postFetch];
 
			if(user.identities.count  < 2)
			{
				cell.lblBadge.hidden = YES;
			}
			else
			{
				// a lot of work to make the badge look pretty
				cell.lblBadge.hidden = NO;
				cell.lblBadge.backgroundColor = self.view.tintColor;
				cell.lblBadge.clipsToBounds = YES;
				cell.lblBadge.font = [UIFont systemFontOfSize:14];
				cell.lblBadge.layer.cornerRadius = cell.lblBadge.frame.size.height/2;
				cell.lblBadge.textAlignment = NSTextAlignmentCenter;
				cell.lblBadge.edgeInsets = (UIEdgeInsets) {    .top = 0,
					.left = 4,
					.bottom = 0,
					.right = 3};
				
				cell.lblBadge.text =  [self badgeTextWithCount: user.identities.count];
				CGSize newSize = [cell.lblBadge sizeThatFits:CGSizeMake(cell.lblBadge.frame.size.width, 18)];
				newSize.width += 8;
				cell.cnstlblBadgeWidth.constant  = MAX(18,newSize.width);
				
			}
	}
	
	cell.accessoryView  = [[UIView alloc]initWithFrame: (CGRect)
								  {
									  .origin.x = 0,
									  .origin.y = 0,
									  .size.width = 4,
									  .size.height = 0
								  } ];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}


#if __IPHONE_11_0
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0)
{
	UISwipeActionsConfiguration* config = nil;
	__weak typeof(self) weakSelf = self;

	if(remoteUserIDs.count)
	{
		NSString* remoteUserID = [remoteUserIDs objectAtIndex:indexPath.row];
		
		if (@available(iOS 11.0, *)) {
			
			NSMutableArray* actions =  NSMutableArray.array;
			
			UIContextualAction* deleteAction =
			[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																 title:NSLocalizedString(@"Remove", @"Remove action")
															  handler:
			 ^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL))
			 {
				 __strong typeof(self) strongSelf = weakSelf;
				 if (strongSelf == nil) return;
				 
				 NSMutableArray* _remoteUserIDs = [NSMutableArray arrayWithArray:strongSelf->remoteUserIDs];
				 [_remoteUserIDs removeObject: remoteUserID];
				 strongSelf->remoteUserIDs = _remoteUserIDs;
				 strongSelf->didModifyRecipents = YES;
				 strongSelf->bbnSave.enabled = strongSelf->didModifyRecipents;
				 
				 [strongSelf->_tblUsers reloadData];
				 
				 completionHandler(YES);
			 }];
			deleteAction.backgroundColor = UIColor.redColor;
			[actions addObject:deleteAction];
			
			config = [UISwipeActionsConfiguration configurationWithActions:actions];
			config.performsFirstActionWithFullSwipe = NO;
			
		}
	}
	else
	{
		config = [UISwipeActionsConfiguration configurationWithActions:@[]];
		config.performsFirstActionWithFullSwipe = NO;
		
	}
	
	return config;
}

#endif

#pragma mark - RemoteUserTableViewCellDelegate

- (void)tableView:(UITableView * _Nonnull)tableView disclosureButtonTappedAtCell:(RemoteUserTableViewCell* _Nonnull)cell
{
	NSString*  remoteUserID = cell.userID;
	__block ZDCUser*    user    = nil;
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
	}];
	
	if(user)
	{
		ZDCSearchResult* info = [[ZDCSearchResult alloc] initWithUser:user];
		UserSearchSocialIDViewController_IOS*  remoteSRVC = nil;

		remoteSRVC = [[UserSearchSocialIDViewController_IOS alloc]
						  initWithDelegate:(id<UserSearchSocialIDViewControllerDelegate>)self
						  owner:owner
						  localUserID:localUserID
						  searchResult:info];

		self.navigationController.navigationBarHidden = NO;
		[self.navigationController pushViewController:remoteSRVC animated:YES];
	}
 
}
#pragma mark -  UserSearchSocialIDViewControllerDelegate
- (void)userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
							didSelectIdentityID:(NSString *)identityID
										 forUserID:(NSString *)userID;

{
	__weak typeof(self) weakSelf = self;
	
	[owner.databaseManager.rwDatabaseConnection
	 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCLocalUser *updatedUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
		if(updatedUser)
		{
			updatedUser                 		= updatedUser.copy;
			updatedUser.preferredIdentityID	= identityID;
			[transaction setObject:updatedUser forKey:updatedUser.uuid inCollection:kZDCCollection_Users];
		}
		
	}completionBlock:^{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		//        [strongSelf->_tblUsers reloadData];
	}];
	
}


#pragma mark -  UserSearchViewControllerDelegate

 - (void)userSearchViewController:(id)sender addedRecipient:(ZDCUser *)recipient
{
	 NSMutableSet* _recipSet = [NSMutableSet setWithArray:remoteUserIDs];

	[_recipSet addObject: recipient.uuid];
	remoteUserIDs = _recipSet.allObjects;
 	didModifyRecipents = YES;
 	bbnSave.enabled = didModifyRecipents;

}

- (void)userSearchViewController:(id)sender removedRecipient:(NSString *)userID
{
	NSMutableArray* _remoteUserIDs = [NSMutableArray arrayWithArray:remoteUserIDs];
	[_remoteUserIDs removeObject:userID];
	remoteUserIDs = _remoteUserIDs;
	
	didModifyRecipents = YES;
	bbnSave.enabled = didModifyRecipents;
}

@end
