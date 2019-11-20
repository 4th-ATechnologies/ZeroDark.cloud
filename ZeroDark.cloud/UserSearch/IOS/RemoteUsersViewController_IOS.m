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
#import "ZDCBadgedBarButtonItem.h"

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
	NSDictionary*            	preferedAuth0IDs;
	
	UIImage*               		defaultUserImage;
	
	BOOL                 		didModifyRecipents;
	int                  		level;
	
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
		level = 1;
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
	
	defaultUserImage = [imageManager.defaultUserAvatar imageWithMaxSize:[RemoteUserTableViewCell avatarSize]];
 
	providerManager = owner.auth0ProviderManager;
	imageManager =  owner.imageManager;
	databaseConnection = owner.databaseManager.uiDatabaseConnection;
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
	
	level--;
	
	if(level == 0)
	{
		[[NSNotificationCenter defaultCenter] addObserver: self
															  selector: @selector(prefsChanged:)
																	name: ZDCLocalPreferencesChangedNotification
																 object: nil];
		
		preferedAuth0IDs =  owner.internalPreferences.preferedAuth0IDs;
	}
	
	[_tblUsers reloadData];
}


-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	if(level == 0)
	{
		[[NSNotificationCenter defaultCenter]  removeObserver:self];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void)prefsChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	NSString *prefs_key = [notification.userInfo objectForKey:ZDCLocalPreferencesChanged_UserInfo_Key];
	
	if ([prefs_key isEqualToString:ZDCprefs_preferedAuth0IDs])
	{
		preferedAuth0IDs =  owner.internalPreferences.preferedAuth0IDs;
		[_tblUsers reloadData];
		
	}
}

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
	
	level++;
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
	//    __weak typeof(self) weakSelf = self;
	
	NSString* userID = [remoteUserIDs objectAtIndex:indexPath.row];
	NSString* auth0ID = nil;
	NSURL *pictureURL = nil;
	
	__block ZDCUser*    user    = nil;
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
	}];
	
	if(user)
	{
		cell.userID = user.uuid;
		auth0ID = user.auth0_preferredID;
		
		if([preferedAuth0IDs objectForKey: userID])
			auth0ID = [preferedAuth0IDs objectForKey: userID];
		
		cell.auth0ID = auth0ID;
		cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;
		
		NSString* displayName  = [user displayNameForAuth0ID:auth0ID];
		cell.lblUserName.text = displayName;
		
		NSArray* comps = [auth0ID componentsSeparatedByString:@"|"];
		NSString* provider = comps.firstObject;
		
		OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:provider] scaledToHeight:[RemoteUserTableViewCell imgProviderHeight]];
		if(providerImage)
		{
			cell.imgProvider.image =  providerImage;
			cell.imgProvider.hidden = NO;
			cell.lblProvider.hidden = YES;
		}
		else
		{
			NSString* providerName =  [providerManager displayNameforProvider:provider];
			if(!providerName)
				providerName = provider;
			cell.lblProvider.text = providerName;
			cell.imgProvider.hidden = YES;
			cell.lblProvider.hidden = NO;
		}
		
		NSString* picture  = [Auth0ProviderManager correctPictureForAuth0ID:auth0ID
																				  profileData:user.auth0_profiles[auth0ID]
																						 region:user.aws_region
																						 bucket:user.aws_bucket];
		if(picture)
			pictureURL = [NSURL URLWithString:picture];
		
		NSDictionary * auth0_profiles = [Auth0Utilities excludeRecoveryProfile:user.auth0_profiles];
		
		if(auth0_profiles.count  < 2)
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
			
			cell.lblBadge.text =  [self badgeTextWithCount: auth0_profiles.count];
			CGSize newSize = [cell.lblBadge sizeThatFits:CGSizeMake(cell.lblBadge.frame.size.width, 18)];
			newSize.width += 8;
			cell.cnstlblBadgeWidth.constant  = MAX(18,newSize.width);
			
		}
		
		cell.showCheckMark     = NO;
		cell.imgAvatar.layer.cornerRadius =  RemoteUserTableViewCell.avatarSize.height / 2;
		cell.imgAvatar.clipsToBounds = YES;
		
		cell.progress.hidden = YES;
		[cell.actAvatar stopAnimating];
		cell.actAvatar.hidden = YES;
		
		if(pictureURL)
		{
			cell.imgAvatar.hidden = YES;
			[cell.actAvatar startAnimating];
			cell.actAvatar.hidden = NO;
			
			CGSize avatarSize = [RemoteUserTableViewCell avatarSize];
			
			[ imageManager fetchUserAvatar: userID
										  auth0ID: auth0ID
										  fromURL: pictureURL
										  options: nil
									processingID: pictureURL.absoluteString
								processingBlock:^UIImage * _Nonnull(UIImage * _Nonnull image)
			 {
				 return [image imageWithMaxSize:avatarSize];
			 }
								  preFetchBlock:^(UIImage * _Nullable image)
			 {
				 if(image)
				 {
					 cell.imgAvatar.hidden = NO;
					 cell.actAvatar.hidden = YES;
					 [cell.actAvatar stopAnimating];
					 cell.imgAvatar.image = image;
				 }
			 }
								 postFetchBlock:^(UIImage * _Nullable image, NSError * _Nullable error)
			 {
				 
				 __strong typeof(self) strongSelf = weakSelf;
				 if(strongSelf == nil) return;
				 
				 // check that the cell is still being used for this user
				 
				 
				 if( [cell.userID isEqualToString: userID])
				 {
					 cell.imgAvatar.hidden = NO;
					 cell.actAvatar.hidden = YES;
					 [cell.actAvatar stopAnimating];
					 
					 if(image)
					 {
						 cell.imgAvatar.image = image;
					 }
					 else
					 {
						 cell.imgAvatar.image = strongSelf->defaultUserImage;
					 }
				 }
			 }];
			
			
		}
		else
		{
			[cell.actAvatar stopAnimating];
			cell.actAvatar.hidden = YES;
			cell.imgAvatar.image = defaultUserImage;
			cell.imgAvatar.hidden = NO;
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
		ZDCSearchUserResult* info = [[ZDCSearchUserResult alloc] initWithUser:user];
		
		if([preferedAuth0IDs objectForKey: user.uuid])
			info.auth0_preferredID  = [preferedAuth0IDs objectForKey: user.uuid];
		
		UserSearchSocialIDViewController_IOS*  remoteSRVC = nil;
		
		remoteSRVC = [[UserSearchSocialIDViewController_IOS alloc]
						  initWithDelegate:(id<UserSearchSocialIDViewControllerDelegate>)self
						  owner:owner
						  localUserID:localUserID
						  searchResultInfo:info];
		
		self.navigationController.navigationBarHidden = NO;
		level++;
		[self.navigationController pushViewController:remoteSRVC animated:YES];
	}
}
#pragma mark -  UserSearchSocialIDViewControllerDelegate

- (void) userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
								 didSelectAuth0ID:(NSString*)selectedAuth0ID
										  forUserID:(NSString*)userID
{
	__weak typeof(self) weakSelf = self;
	
	[owner.databaseManager.rwDatabaseConnection
	 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		 
		 ZDCLocalUser *updatedUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		 
		 if(updatedUser)
		 {
			 updatedUser                 = updatedUser.copy;
			 updatedUser.auth0_preferredID = selectedAuth0ID;
			 [transaction setObject:updatedUser forKey:updatedUser.uuid inCollection:kZDCCollection_Users];
		 }
		 
	 }completionBlock:^{
		 __strong typeof(self) strongSelf = weakSelf;
		 if (strongSelf == nil) return;
		 
		 [strongSelf->owner.internalPreferences setPreferedAuth0ID:selectedAuth0ID userID:userID];
		 //        [strongSelf->_tblUsers reloadData];
	 }];
	
}

#pragma mark -  UserSearchViewControllerDelegate

- (void)userSearchUserViewController:(id)sender
						selectedRecipients:(NSArray <NSArray* /* [userID , auth0ID ]>*/> * )recipientsIn
{
	NSMutableSet* _recipSet = [NSMutableSet setWithArray:remoteUserIDs];
	NSMutableDictionary* _preferedAuth0IDs = [NSMutableDictionary dictionaryWithDictionary:preferedAuth0IDs];
	
	[recipientsIn enumerateObjectsUsingBlock:^(NSArray * entry, NSUInteger idx, BOOL * _Nonnull stop) {
		NSString *userID = entry[0];
		NSString *auth0ID = entry[1];
		[_recipSet addObject:userID];
		
		if(auth0ID)
			[_preferedAuth0IDs setObject:auth0ID forKey:userID];
	}];
	
	// update the prefered dictionary here.
	preferedAuth0IDs = _preferedAuth0IDs;
	
	remoteUserIDs = _recipSet.allObjects;
	didModifyRecipents = YES;
	bbnSave.enabled = didModifyRecipents;
	
}


- (void)userSearchUserViewController:(id)sender
						 removedRecipients:(NSArray <NSString* /* [userID */> * )recipients
{
	NSMutableArray* _remoteUserIDs = [NSMutableArray arrayWithArray:remoteUserIDs];
	[_remoteUserIDs removeObjectsInArray:recipients];
	remoteUserIDs = _remoteUserIDs;
	
	didModifyRecipents = YES;
	bbnSave.enabled = didModifyRecipents;
	
}


@end
