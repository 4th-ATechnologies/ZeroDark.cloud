/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "UserSearchViewController_IOS.h"

#import "Auth0Utilities.h"
#import "IdentityProviderFilterViewController.h"
#import "RemoteUserTableViewCell.h"
#import "UITableViewTouch.h"
#import "UserSearchTableViewHeaderCell.h"
#import "UserSearchSocialIDViewController_IOS.h"
#import "SearchBarWithLoading.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCPopoverTransition.h"
#import "ZDCUserManagerPrivate.h"
#import "ZDCUserPrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "NSDate+ZeroDark.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose | ZDCLogFlagTrace;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif


@interface UserSearchViewController_IOS () <IdentityProviderFilterViewControllerDelegate>
@end

@implementation UserSearchViewController_IOS
{
	IBOutlet __weak SearchBarWithLoading * _searchBar;
	IBOutlet __weak UILabel              * _lblSearchPrompt;
    
	IBOutlet __weak UIButton             * _btnFilter;
	
	IBOutlet __weak UITableViewTouch     * _tblUsers;
	IBOutlet __weak NSLayoutConstraint   * _cnstTbleUserBottomOffset;
	
	IBOutlet __weak UIView*                _vwInfo;
	IBOutlet __weak UILabel*               _lblInfo;
	
	ZeroDarkCloud *zdc;
	
	NSString *localUserID;
	NSSet<NSString *> *sharedUserIDs;
	
	UIImage * defaultUserImage;
	UIImage * threeDots;
	
	NSTimer * queryStartTimer; // So we don't fire a search right away while user is typing.
	
	NSInteger searchId;  // track searches
	NSInteger activeSearchId;
	NSInteger displayedSearchId;

	NSArray<NSString *> *recentRecipients;     // data for _tblUsers (when shouldShowRecentRecipients == YES)
	NSArray<ZDCSearchResult *> *searchResults; // data for _tblUsers (when shouldShowRecentRecipients == NO)
	
	NSMutableDictionary<NSString *,NSString *> *preferredIdentityIDs; // Map: userID => selected identityID
	
	NSString *providerToSearch;
	
	UIViewController *remoteSRVC;
	ZDCPopoverTransition *popoverTransition;
}

@synthesize delegate = delegate;

- (instancetype)initWithDelegate:(id<UserSearchViewControllerDelegate>)inDelegate
                           owner:(ZeroDarkCloud*)inOwner
                     localUserID:(NSString *)inLocalUserID
                   sharedUserIDs:(NSArray<NSString*> *)inSharedUserIDs

{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UserSearchViewController_IOS" bundle:bundle];
    
	self = [storyboard instantiateViewControllerWithIdentifier:@"UserSearchViewController"];
	if (self)
	{
		delegate = inDelegate;
		zdc = inOwner;
		
		localUserID = [inLocalUserID copy];
		sharedUserIDs = [NSSet setWithArray:inSharedUserIDs];
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
	
	self.navigationItem.title = @"Add Recipients";
	
	[RemoteUserTableViewCell registerViewsforTable:_tblUsers bundle:[ZeroDarkCloud frameworkBundle]];
	[UserSearchTableViewHeaderCell registerViewsforTable:_tblUsers bundle:[ZeroDarkCloud frameworkBundle]];
	
	_tblUsers.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0); // top, left, bottom, right
	
	_tblUsers.allowsSelection = YES;
	_tblUsers.estimatedRowHeight = 0;
	_tblUsers.estimatedSectionHeaderHeight = 0;
	_tblUsers.estimatedSectionFooterHeight = 0;
	_tblUsers.touchDelegate    =  (id <UITableViewTouchDelegate>) self;
	
	_lblSearchPrompt.hidden = YES;
	_lblSearchPrompt.text =  NSLocalizedString(@"Type at least 2 characters",
															 @"Type at least 2 characters");
	
	defaultUserImage = [zdc.imageManager.defaultUserAvatar imageWithMaxSize:[RemoteUserTableViewCell avatarSize]];
	
	threeDots = [[UIImage imageNamed: @"3dots"
	                        inBundle: [ZeroDarkCloud frameworkBundle]
	   compatibleWithTraitCollection: nil]
	                   maskWithColor: self.view.tintColor];
	
	[_btnFilter setImage:threeDots forState:UIControlStateNormal];
	
	_searchBar.text = @"";
	
	searchId = 0;
	activeSearchId = -1;
	displayedSearchId = -1;
	
	_vwInfo.layer.cornerRadius = 5;
	_vwInfo.layer.masksToBounds = YES;
	_vwInfo.hidden = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	
	[nc addObserver: self
	       selector: @selector(keyboardWillShow:)
	           name: UIKeyboardWillShowNotification
	         object: nil];
	
	[nc addObserver: self
	       selector: @selector(keyboardWillHide:)
	           name: UIKeyboardWillHideNotification
	         object: nil];
	
	recentRecipients = zdc.internalPreferences.recentRecipients;
	
	[self.tabBarController.tabBar setHidden:YES];
	[self.navigationController setNavigationBarHidden:NO];
	
	self.navigationItem.title = NSLocalizedString(@"Select Recipients", @"Select Recipients");
	
	[_tblUsers reloadData];
	[_searchBar becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillDisappear:animated];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Keyboard Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static inline UIViewAnimationOptions AnimationOptionsFromCurve(UIViewAnimationCurve curve)
{
    UIViewAnimationOptions opt = (UIViewAnimationOptions)curve;
    return opt << 16;
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	// With multitasking on iPad, all visible apps are notified when the keyboard appears and disappears.
	// The value of [UIKeyboardIsLocalUserInfoKey] is YES for the app that caused the keyboard to appear
	// and NO for any other apps.
	//
	BOOL isKeyboardForOurApp = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];
	if (!isKeyboardForOurApp)
	{
		return;
	}
	
	// Extract info from notification
	
	CGRect keyboardEndFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	
	NSTimeInterval animationDuration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationCurve animationCurve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue];
	
	// Perform animation
	
	CGFloat keyboardHeight = keyboardEndFrame.size.height;
	
	__weak typeof(self) weakSelf = self;
	[UIView animateWithDuration: animationDuration
	                      delay: 0.2
	                    options: AnimationOptionsFromCurve(animationCurve)
	                 animations:
	^{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		strongSelf->_cnstTbleUserBottomOffset.constant = -keyboardHeight;
		[strongSelf.view layoutIfNeeded]; // animate constraint change
	
	} completion:^(BOOL finished){
		
		// Nothing to do here
	}];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	
	// With multitasking on iPad, all visible apps are notified when the keyboard appears and disappears.
	// The value of [UIKeyboardIsLocalUserInfoKey] is YES for the app that caused the keyboard to appear
	// and NO for any other apps.
	//
	BOOL isKeyboardForOurApp = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];
	if (!isKeyboardForOurApp)
	{
		return;
	}
	
	// Extract info from notification
	
	NSTimeInterval animationDuration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationCurve animationCurve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue];
	
	// Perform animation
	
	[self _keyboardWillHideWithAnimationDuration:animationDuration animationCurve:animationCurve];
}

- (void)_keyboardWillHideWithAnimationDuration:(NSTimeInterval)animationDuration
                                animationCurve:(UIViewAnimationCurve)animationCurve
{
    
    __weak typeof(self) weakSelf = self;
    
    
    [UIView animateWithDuration:animationDuration
                          delay:0.2
                        options:AnimationOptionsFromCurve(animationCurve)
                     animations:
     ^{
         
         __strong typeof(self) strongSelf = weakSelf;
         if (strongSelf == nil) return;
         
         strongSelf->_cnstTbleUserBottomOffset.constant =  0;
         [strongSelf.view layoutIfNeeded]; // animate constraint change
         
     } completion:^(BOOL finished) {
         
         // Nothing to do
     }];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIViewControllerTransitioningDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source
{
    popoverTransition = [[ZDCPopoverTransition alloc] init];
    popoverTransition.reverse = NO;
    popoverTransition.origin = ZDCPopoverTransitionOrigin_Bottom;
    
    return popoverTransition;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    ZDCPopoverTransition *transition = popoverTransition;
    transition.reverse = YES;
    
    popoverTransition = nil;
    return transition;
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

- (void)fadeView:(UIView *)targetView
      shouldHide:(BOOL)shouldHide
{
	ZDCLogAutoTrace();
	
	if (targetView.isHidden == shouldHide) {
		// Nothing to do
		return;
	}
	
	if (shouldHide)
	{
		[UIView animateWithDuration:0.3 animations:^{
			targetView.alpha = 0;
		} completion: ^(BOOL finished) {
			targetView.hidden = finished;
		}];
	}
	else
	{
		targetView.alpha = 0;
		targetView.hidden = NO;
		[UIView animateWithDuration:0.7 animations:^{
			targetView.alpha = 1;
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)btnFilterTapped:(id)sender
{
	ZDCLogAutoTrace();
	
	UIButton* btn = sender;

	IdentityProviderFilterViewController *ipvc =
	  [[IdentityProviderFilterViewController alloc] initWithDelegate:self owner:zdc];

    ipvc.provider = providerToSearch;
    // this is best presented as a popover on both Iphone and iPad
    ipvc.modalPresentationStyle = UIModalPresentationPopover;
    CGFloat height =  self.view.frame.size.height - btn.frame.origin.y - btn.frame.size.height;

    ipvc.preferredContentSize = (CGSize){ .width = ipvc.preferredWidth, .height = height };

    UIPopoverPresentationController *popover =  ipvc.popoverPresentationController;
    popover.delegate = ipvc;
    popover.sourceView = self.view;
    popover.sourceRect = btn.frame;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;

    [self presentViewController:ipvc animated:YES completion:nil];
}

/**
 * Handles the dismissal of a self presented detailVC with custom Back button
 */
- (void)handleNavigationBack:(UIButton *)backButton
{
	ZDCLogAutoTrace();
	
//	if ([self isEditing]) {
//		[self endEditing:NULL];
//	}
	
	[[self navigationController] popViewControllerAnimated:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Recipient Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setPreferredIdentityID:(NSString *)identityID forUserID:(NSString *)userID
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Invoked on incorrect thread");
	
	if (preferredIdentityIDs == nil) {
		preferredIdentityIDs = [[NSMutableDictionary alloc] init];
	}
	
	if(identityID == nil)
		[preferredIdentityIDs removeObjectForKey:userID];
	else
		[preferredIdentityIDs setObject:identityID forKey:userID];
}

- (void)removeUserFromSharedList:(NSString *)userID
{
	ZDCLogAutoTrace();
	
	NSMutableSet *newSharedUserIDs = [NSMutableSet setWithSet:sharedUserIDs];
	[newSharedUserIDs removeObject:userID];
	sharedUserIDs = [newSharedUserIDs copy];
	
	SEL selector = @selector(userSearchViewController:removedRecipient:);
	if ([delegate respondsToSelector:selector])
	{
		[delegate userSearchViewController:self removedRecipient:userID];
	}
}


- (void)addUserToSharedList:(NSString *)userID
                 identityID:(NSString *)identityID
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Invoked on wrong thread");
	
	// never select yourself
	if ([localUserID isEqualToString:userID]) {
		return;
	}
	
	NSMutableSet *newSharedUserIDs = [NSMutableSet setWithSet:sharedUserIDs];
	[newSharedUserIDs addObject:userID];
	sharedUserIDs = [newSharedUserIDs copy];
 
	[zdc.internalPreferences addRecentRecipient:userID];
}

- (BOOL)shouldShowRecentRecipients
{
	BOOL result = (_searchBar.text.length == 0) && (recentRecipients.count > 0);
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UISearchBar Activity
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)importUser:(ZDCSearchResult *)searchResult
	completionBlock:(void (^)(ZDCUser *user))completionHandler
{
	ZDCLogAutoTrace();
	
	__block ZDCUser *user = nil;
	
	YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
	[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		user = [transaction objectForKey:searchResult.userID inCollection:kZDCCollection_Users];
		if (user == nil)
		{
			user = [[ZDCUser alloc] initWithUUID:searchResult.userID];
			
			user.aws_region = searchResult.aws_region;
			user.aws_bucket = searchResult.aws_bucket;
			user.identities = searchResult.identities;
			user.preferredIdentityID = searchResult.preferredIdentityID;
			
			[transaction setObject:user forKey:user.uuid inCollection:kZDCCollection_Users];
		}
		else if(![user.preferredIdentityID isEqualToString:searchResult.preferredIdentityID])
		{
			user = user.copy;
			user.preferredIdentityID = searchResult.preferredIdentityID;
			[transaction setObject:user forKey:user.uuid inCollection:kZDCCollection_Users];
		}
		
	} 	completionQueue:dispatch_get_main_queue()
								 completionBlock:^{
		if(completionHandler)
		{
			(completionHandler)(user);
		}}];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UISearchBarDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)searchBarCancelButtonClicked:(UISearchBar *)sender
{
	ZDCLogAutoTrace();
	
	_lblSearchPrompt.hidden = YES;
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)sender
{
	ZDCLogAutoTrace();
	
	_lblSearchPrompt.hidden = YES;
	
	// only fire a search when the bar is enabled.
	if (sender.userInteractionEnabled) {
		[self startNewSearchQuery:nil];
	}
}

- (void)searchBar:(UISearchBar *)sender textDidChange:(NSString *)searchText
{
	ZDCLogAutoTrace();
	
	// Hide/show prompt
	if (_searchBar.text.length == 1)
	{
		_lblSearchPrompt.hidden = NO;
		_lblSearchPrompt.alpha = 0;
        
		[UIView animateWithDuration:0.5 animations:^{
			
			self->_lblSearchPrompt.alpha = 1;
			
		} completion:^(BOOL finished) {
      
			// Nothing to do here
		}];
	}
	else
   {
		_lblSearchPrompt.hidden = YES;
	}
	
	const NSTimeInterval kQueryDelay = 0.25;
	if (queryStartTimer)
	{
		ZDCLogVerbose(@"queryStartTimer: changing fire date");
		[queryStartTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kQueryDelay]];
	}
	else
	{
		ZDCLogVerbose(@"queryStartTimer: initializing");
		queryStartTimer =
		  [NSTimer scheduledTimerWithTimeInterval: kQueryDelay
		                                   target: self
		                                 selector: @selector(startNewSearchQuery:)
		                                 userInfo: nil
		                                  repeats: NO];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Search Queries
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startNewSearchQuery:(NSTimer *)sender
{
	ZDCLogAutoTrace();
	
	[self queryForUsersByName:_searchBar.text];
	
	[queryStartTimer invalidate];
	queryStartTimer = nil;
	
	_vwInfo.hidden = YES;
}

- (void)queryForUsersByName:(NSString *)queryString
{
	ZDCLogAutoTrace();
    
	if (queryString.length < 2)
	{
		_searchBar.isLoading = NO;
		searchResults = nil;
		preferredIdentityIDs = nil;
		[_tblUsers reloadData];
		return;
	}
	
	_searchBar.isLoading = YES;
	NSInteger currentSearchId = searchId;
	
	ZDCSearchOptions *options = [[ZDCSearchOptions alloc] init];
	options.providerToSearch = providerToSearch;
	options.searchLocalDatabase = NO;
	options.searchLocalCache = YES;
	options.searchRemoteServer = YES;
	
	__weak typeof(self) weakSelf = self;
	[zdc.searchManager searchForUsersWithQuery: queryString
	                                    treeID: zdc.primaryTreeID
	                               requesterID: localUserID
	                                   options: options
	                           completionQueue: dispatch_get_main_queue()
	                              resultsBlock:
	^(ZDCSearchResultStage stage, NSArray<ZDCSearchResult *> *_Nullable results, NSError *_Nullable error)
	{
		ZDCLogVerbose(@"Search results: stage(%ld) count(%lu)", (long)stage, (unsigned long)results.count);
		
		[weakSelf handleSearchResults: results
		                        stage: stage
		                        error: error
		              currentSearchId: currentSearchId];
	}];
	
	searchId++;
}

- (void)handleSearchResults:(NSArray<ZDCSearchResult*> *)newResults
                      stage:(ZDCSearchResultStage)stage
                      error:(NSError *)error
            currentSearchId:(NSInteger)currentSearchId
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Must be invoked on main thread: `searchResults` isn't thread-safe");
	
	if (currentSearchId <= displayedSearchId) {
		return; // Newer query already displayed
	}
	
	if (activeSearchId < currentSearchId) {
		activeSearchId = currentSearchId; // New query
		searchResults = nil;
	} else if (activeSearchId == currentSearchId) {
		// Continuing newest query
	}
	else { // activeSearchId > currentSearchId
		return; // Newer query already displayed
	}
		 
	if (error)
	{
		_searchBar.isLoading = NO;
		return;
	}
	
	NSMutableDictionary<NSString*, ZDCSearchResult*> *searchDict = [NSMutableDictionary dictionary];
	
	// create a dictionary with existing search results
	for (ZDCSearchResult *entry in searchResults)
	{
		NSString *userID = entry.userID;
		searchDict[userID] = entry;
	}
	
	// update the dictionary with new results
	for (ZDCSearchResult *entry in newResults)
	{
		NSString *userID = entry.userID;
		ZDCSearchResult *existingEntry = searchDict[userID];
		
		if (!existingEntry || stage == ZDCSearchResultStage_Server)
		{
			searchDict[userID] = entry;
		}
	}
	
	// update the searchResults
	searchResults = [searchDict.allValues copy];
	[_tblUsers reloadData];
	
	if (stage == ZDCSearchResultStage_Done)
	{
		// end search indicator;
		
		_searchBar.isLoading = NO;
		displayedSearchId = currentSearchId;
		
		if (searchResults.count == 0)
		{
			[self fadeView:_vwInfo shouldHide:NO];
		}
	}
}

- (ZDCSearchResult *)searchResultsForUserID:(NSString *)userID
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Must be invoked on main thread: `searchResults` isn't thread-safe");
	
	if (userID == nil) {
		return nil;
	}
	ZDCSearchResult *match = nil;
	
	for (ZDCSearchResult *entry in searchResults)
	{
		if ([entry.userID isEqualToString:userID])
		{
			match = entry;
			break;
		}
	}
	
	return match;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableView Header
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section
{
	if (!self.shouldShowRecentRecipients && searchResults == 0) {
		return 0;
	}
	else {
		return [UserSearchTableViewHeaderCell heightForCell];
	}
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section
{
	return 0;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section
{
	UserSearchTableViewHeaderCell *cell = (UserSearchTableViewHeaderCell *)
	  [tv dequeueReusableCellWithIdentifier:kUserSearchTableViewHeaderCellIdentifier];
	
	if (self.shouldShowRecentRecipients)
	{
		// show recents
		cell.lblText.text = @"Recent Recipients";
	}
	else if (searchResults)
	{
		// show results
		cell.lblText.text = @"Search Results";
	}
	
	return cell;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewDataSource
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	NSInteger result = 0;
	
	if (self.shouldShowRecentRecipients)
		result = recentRecipients.count;
	else
		result = searchResults.count;
	
	return result;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	CGFloat result = result =  [RemoteUserTableViewCell heightForCell];
	return result;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = nil;
	if (self.shouldShowRecentRecipients)
		cell = [self tableView:tv recentUserCellForRowAtIndexPath:indexPath];
	else
		cell = [self tableView:tv remoteUserCellForRowAtIndexPath:indexPath];
	
	return cell;
}

- (RemoteUserTableViewCell *)tableView:(UITableView *)tv
       recentUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)
	  [tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];
	
	NSString *userID = [recentRecipients objectAtIndex:indexPath.row];
	
	BOOL isAlreadyShared= [sharedUserIDs containsObject:userID];
	BOOL isMyUserID = [userID isEqualToString:localUserID];
	
	__block ZDCUser *user = nil;
	[zdc.databaseManager.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
	}];
	
	cell.userID = userID;
	cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;
	
	cell.lblUserName.text = user.displayName;

	if (isMyUserID) {
		cell.lblUserName.textColor = UIColor.darkGrayColor;
	}
	else {
		cell.lblUserName.textColor = UIColor.blackColor;
	}
	
	ZDCUserIdentity *displayIdentity = user.displayIdentity;
	
	OSImage *providerImage =
	  [[zdc.auth0ProviderManager iconForProvider: displayIdentity.provider
	                                        type: Auth0ProviderIconType_Signin]
	                              scaledToHeight: [RemoteUserTableViewCell imgProviderHeight]];
	
	if(providerImage)
	{
		cell.imgProvider.image = providerImage;
		cell.imgProvider.layer.opacity = isMyUserID ? 0.4 : 1.0;
		cell.imgProvider.hidden = NO;
		cell.lblProvider.hidden = YES;
	}
	else
	{
		NSString *providerName = [zdc.auth0ProviderManager displayNameForProvider:displayIdentity.provider];
		
		cell.lblProvider.text = providerName;
		cell.imgProvider.hidden = YES;
		cell.lblProvider.hidden = NO;
	}

	NSUInteger nonRecoveryIdentityCount = 0;
	for (ZDCUserIdentity *ident in user.identities)
	{
		if (!ident.isRecoveryAccount) {
			nonRecoveryIdentityCount++;
		}
	}
    
	if (nonRecoveryIdentityCount < 2)
	{
		cell.lblBadge.hidden = YES;
	}
	else
	{
		// a lot of work to make the badge look pretty
		cell.lblBadge.hidden = NO;
		cell.lblBadge.backgroundColor = isMyUserID ? UIColor.lightGrayColor : self.view.tintColor;
		cell.lblBadge.clipsToBounds = YES;
		cell.lblBadge.font = [UIFont systemFontOfSize:14];
		cell.lblBadge.layer.cornerRadius = cell.lblBadge.frame.size.height/2;
		cell.lblBadge.textAlignment = NSTextAlignmentCenter;
		cell.lblBadge.edgeInsets = (UIEdgeInsets){
			.top = 0,
			.left = 4,
			.bottom = 0,
			.right = 3
		};
		
		cell.lblBadge.text = [self badgeTextWithCount: nonRecoveryIdentityCount];
		CGSize newSize = [cell.lblBadge sizeThatFits:CGSizeMake(cell.lblBadge.frame.size.width, 18)];
		newSize.width += 8;
		cell.cnstlblBadgeWidth.constant = MAX(18,newSize.width);
	}
	
	cell.imgAvatar.layer.cornerRadius = RemoteUserTableViewCell.avatarSize.height / 2;
	cell.imgAvatar.clipsToBounds = YES;
	cell.imgAvatar.layer.opacity = isMyUserID ? 0.4 : 1.0;

	cell.imgAvatar.hidden = NO;
        
	CGSize avatarSize = [RemoteUserTableViewCell avatarSize];
	
	UIImage* (^processingBlock)(UIImage*) = ^(UIImage *image) {
		
		return [image scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
	};
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns.
		
		cell.imgAvatar.image = image ?: self->defaultUserImage;
	};
	
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetchBlock is invoked LATER, possibly after downloading the image.
		
		if (image && [cell.userID isEqualToString:userID])
		{
			cell.imgAvatar.image = image;
		}
	};
	
	[zdc.imageManager fetchUserAvatar: user
	                      withOptions: nil
	                     processingID: NSStringFromClass([self class])
	                  processingBlock: processingBlock
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];
 
	cell.progress.hidden = YES;
	
	cell.showCheckMark = YES;
	cell.checkMark.checkMarkStyle = isMyUserID ? ZDCCheckMarkStyleGrayedOut : ZDCCheckMarkStyleOpenCircle;
	cell.checkMark.checked = !isMyUserID && isAlreadyShared;
	
	cell.accessoryView = [[UIView alloc] initWithFrame:(CGRect){
		.origin.x = 0,
		.origin.y = 0,
		.size.width = 4,
		.size.height = 0
	}];
	
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}


- (RemoteUserTableViewCell*)tableView:(UITableView *)tv
      remoteUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)
	  [tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];
	
	ZDCSearchResult *item = searchResults[indexPath.row];
	NSString *userID = item.userID;
	ZDCUserIdentity *displayIdentity = item.displayIdentity;

	// check if the user selected an alternate ID
	NSString* alternateID = [preferredIdentityIDs objectForKey:userID];
	if(alternateID)
	{
		ZDCUserIdentity *alternateIdentity = [item identityWithID:alternateID];
		displayIdentity = alternateIdentity;
 	}
	
	NSString *identityID = displayIdentity.identityID;
	
	cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;
	cell.userID  = userID;
	
	BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
	BOOL isMyUserID = [userID isEqualToString:localUserID];
	
	{ // Scoping
		
		NSString *displayName = displayIdentity.displayName;
		NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:displayName];
		ZDCSearchMatch *foundMatch = nil;

		if (item.matches.count)
		{
			UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
			/// Add the bold trait
			descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
			/// Pass 0 to keep the same font size
			UIFont *boldFont = [UIFont fontWithDescriptor:descriptor size:0];
			
			[attrString beginEditing];
			
			// find the matching string
			
			// check if the prefered on is correct
			for (ZDCSearchMatch *match in item.matches)
			{
				if([match.identityID isEqual:identityID]
					&& [match.matchingString isEqualToString:displayName])
				{
					foundMatch = match;
					break;
				}
			}
			
			// check if it's another identity
			for (ZDCSearchMatch *match in item.matches)
			{
				// we have to fix things up to use the matching identity
				displayName = match.matchingString;
				attrString = [[NSMutableAttributedString alloc] initWithString:displayName];
				identityID = match.identityID;
				displayIdentity = [item identityWithID:identityID];
				[self setPreferredIdentityID:identityID forUserID:userID];
				foundMatch = match;
				break;
			}
			
			if(foundMatch)
			{
				for (NSValue *matchRange in foundMatch.matchingRanges)
				{
					[attrString addAttribute: NSFontAttributeName
											 value: boldFont
											 range: matchRange.rangeValue];
				}
			}
			
			
			
			//				if (![match.identityID isEqual:identityID]) {
			//					continue;
			//				}
			//
			//				if(![match.matchingString isEqualToString:displayName]){
			//					continue;
			//				}
			//
			//				foundMatch = match;
			//			}
			//				for (NSValue *matchRange in match.matchingRanges)
			//				{
			//					[attrString addAttribute: NSFontAttributeName
			//					                   value: boldFont
			//					                   range: matchRange.rangeValue];
			//				}
			//		 	}
			
			
			[attrString endEditing];
		}
		
		if (isMyUserID)
		{
			// make the text appear in gray
			[attrString addAttribute: NSForegroundColorAttributeName
			                   value: [OSColor lightGrayColor]
			                   range: NSMakeRange(0, [attrString length])];
		}
		
		cell.lblUserName.attributedText = attrString;
	}
		
	cell.identityID = identityID;

	NSString *provider = displayIdentity.provider;
	OSImage *providerImage =
	  [[zdc.auth0ProviderManager iconForProvider: provider
														 type: Auth0ProviderIconType_Signin]
	                              scaledToHeight: [RemoteUserTableViewCell imgProviderHeight]];
	
	if (providerImage)
	{
		cell.imgProvider.image = providerImage;
		cell.imgProvider.layer.opacity = isMyUserID ? 0.4 : 1.0;
		cell.imgProvider.hidden = NO;
		cell.lblProvider.hidden = YES;
	}
	else
	{
		NSString *providerName =  [zdc.auth0ProviderManager displayNameForProvider:provider];
		
		cell.lblProvider.text = providerName;
		cell.imgProvider.hidden = YES;
		cell.lblProvider.hidden = NO;
	}
    
	if (item.identities.count  < 2)
	{
		cell.lblBadge.hidden = YES;
	}
	else
	{
		// a lot of work to make the badge look pretty
		cell.lblBadge.hidden = NO;
		cell.lblBadge.backgroundColor = isMyUserID?UIColor.lightGrayColor:self.view.tintColor;
		cell.lblBadge.clipsToBounds = YES;
		cell.lblBadge.font = [UIFont systemFontOfSize:14];
		cell.lblBadge.layer.cornerRadius = cell.lblBadge.frame.size.height/2;
		cell.lblBadge.textAlignment = NSTextAlignmentCenter;
		cell.lblBadge.edgeInsets = (UIEdgeInsets){
			.top = 0,
			.left = 4,
			.bottom = 0,
			.right = 3
		};
		
		cell.lblBadge.text = [self badgeTextWithCount: item.identities.count];
		
		CGSize newSize = [cell.lblBadge sizeThatFits:CGSizeMake(cell.lblBadge.frame.size.width, 18)];
		newSize.width += 8;
		
		cell.cnstlblBadgeWidth.constant = MAX(18, newSize.width);
	}
	
	cell.imgAvatar.layer.cornerRadius = RemoteUserTableViewCell.avatarSize.height / 2;
	cell.imgAvatar.clipsToBounds = YES;
	cell.imgAvatar.layer.opacity = isMyUserID ? 0.4 : 1.0;
	
	CGSize avatarSize = [RemoteUserTableViewCell avatarSize];
	
	UIImage* (^processingBlock)(UIImage*) = ^(UIImage *image){
		
		return [image scaledToSize:avatarSize scalingMode:ScalingMode_AspectFill];
	};
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns.
		
		cell.imgAvatar.image = image ?: self->defaultUserImage;
	};
	
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetchBlock is invoked LATER, possibly after downloading the image.
		
		if (image && [cell.identityID isEqualToString:identityID])
		{
			cell.imgAvatar.image = image;
		}
	};
	
	[zdc.imageManager fetchUserAvatar: item
	                       identityID: identityID
	                     processingID: NSStringFromClass([self class])
	                  processingBlock: processingBlock
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];
	
	cell.progress.hidden = YES;
	
	cell.showCheckMark = YES;
	cell.checkMark.checkMarkStyle = isMyUserID ? ZDCCheckMarkStyleGrayedOut : ZDCCheckMarkStyleOpenCircle;
	cell.checkMark.checked = !isMyUserID && isAlreadyImported;

	cell.accessoryView = [[UIView alloc] initWithFrame:(CGRect){
		.origin.x = 0,
		.origin.y = 0,
		.size.width = 4,
		.size.height = 0
	}];
	
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableView Swipe
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if __IPHONE_11_0
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0)
{
     UISwipeActionsConfiguration* config = nil;

    __weak typeof(self) weakSelf = self;
    if(self.shouldShowRecentRecipients)
    {
		 NSString *userID  = [recentRecipients objectAtIndex: indexPath.row ];
      
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
					
					[strongSelf->zdc.internalPreferences removeRecentRecipient:userID];
					strongSelf->recentRecipients  = strongSelf->zdc.internalPreferences.recentRecipients;
					
					//                 // select or deselect?
					//                 if([sharedUserIDs containsObject:userID])
					//                 {
					//                     [self removeUserFromSharedList:userID];
					//                 }
					
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableView Select/Deselect
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	// Don't allow selection of localUserID
	NSString *userID = nil;
	
	if (self.shouldShowRecentRecipients)
	{
		userID = [recentRecipients objectAtIndex: indexPath.row ];
	}
 	else
	{
		ZDCSearchResult *item = [searchResults objectAtIndex:indexPath.row];
		userID = item.userID;
	}
 
	
	if ([userID isEqualToString:localUserID]) {
		return nil;
	} else {
		return indexPath;
	}
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();
	
	if (self.shouldShowRecentRecipients)
		[self tableView:tv didSelectRecentUserCellForRowAtIndexPath:indexPath];
	else
		[self tableView:tv didSelectRemoteUserCellForRowAtIndexPath:indexPath];
}


- (void)tableView:(UITableView *)tv didSelectRemoteUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	ZDCLogAutoTrace();

	ZDCSearchResult *item = [searchResults objectAtIndex:indexPath.row];
	NSString *userID = item.userID;
	
	// Don't allow selection of localUser
	BOOL isMyUserID = [userID isEqualToString:localUserID];
	if (isMyUserID) {
		return;
	}
	
	// Select or deselect?
	if ([sharedUserIDs containsObject:userID])
	{
		[self removeUserFromSharedList:userID];
        
		[tv reloadRowsAtIndexPaths: @[indexPath]
		          withRowAnimation: UITableViewRowAnimationNone];
	}
	else  // select
	{
		__weak typeof(self) weakSelf = self;
		
		// check if the user selected an alternate ID
		NSString* useIdentity = [preferredIdentityIDs objectForKey:item.userID];
		if(useIdentity) {
			item.preferredIdentityID = useIdentity;
		}

		[self importUser:item
		 completionBlock:^(ZDCUser *user) {
			
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;
				
			SEL selector = @selector(userSearchViewController:addedRecipient:);
			if ([strongSelf->delegate respondsToSelector:selector])
			{
				[strongSelf->delegate userSearchViewController:self addedRecipient:user];
			}
			
			[strongSelf addUserToSharedList:user.uuid
										identityID:item.preferredIdentityID];
			
			[strongSelf->_tblUsers reloadRowsAtIndexPaths: @[indexPath]
												  withRowAnimation: UITableViewRowAnimationNone];
		}];
	}
}

- (void)tableView:(UITableView *)tv didSelectRecentUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString *userID = [recentRecipients objectAtIndex: indexPath.row ];

	// Select or deselect?
	if ([sharedUserIDs containsObject:userID])
	{
		[self removeUserFromSharedList:userID];
        
		[tv reloadRowsAtIndexPaths: @[indexPath]
		          withRowAnimation: UITableViewRowAnimationNone];
	}
	else  // select
	{
		__block ZDCUser *user = nil;
		[zdc.databaseManager.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		}];
		
		if(!user)
			return;
		
		SEL selector = @selector(userSearchViewController:addedRecipient:);
		if ([delegate respondsToSelector:selector])
		{
			[delegate userSearchViewController:self addedRecipient:user];
		}

		[self addUserToSharedList:user.uuid
								identityID:user.preferredIdentityID];
		
		[tv reloadRowsAtIndexPaths: @[indexPath]
		          withRowAnimation: UITableViewRowAnimationNone];
	}
}

- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Prevent deselection - in effect we have radio buttons
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark RemoteUserTableViewCellDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)tableView:(UITableView * _Nonnull)tv disclosureButtonTappedAtCell:(RemoteUserTableViewCell* _Nonnull)cell
{
	if(tv != _tblUsers)
		return;
	
	ZDCSearchResult* item = nil;
	NSString*  userID = cell.userID;
	
	if ([userID isEqualToString:localUserID]) {
		return;
	}
	
	if (self.shouldShowRecentRecipients)
	{
		__block ZDCUser*    user    = nil;
		
		[zdc.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		}];
		
		if(user)
		{
			item = [[ZDCSearchResult alloc] initWithUser:user];
		}
	}
	else
	{
		item  = [self searchResultsForUserID:userID];
	}
	
	if(!item) return;
	
	// check if the user selected an alternate ID
	NSString* alternateID = [preferredIdentityIDs objectForKey:userID];
	if(alternateID)
	{
		item.preferredIdentityID = alternateID;
 	}

	UserSearchSocialIDViewController_IOS*  remoteSRVC = nil;
	
	remoteSRVC = [[UserSearchSocialIDViewController_IOS alloc]
					  initWithDelegate:(id<UserSearchSocialIDViewControllerDelegate>)self
					  owner:zdc
					  localUserID:localUserID
					  searchResult:item];
	
	self.navigationController.navigationBarHidden = NO;
	[self.navigationController pushViewController:remoteSRVC animated:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UserSearchSocialIDViewControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
							didSelectIdentityID:(NSString *)identityID
										 forUserID:(NSString *)userID;

{
	__weak typeof(self) weakSelf = self;
	
	[self setPreferredIdentityID:identityID forUserID:userID];
	
	// if its already imported then we need to update the database
	[zdc.databaseManager.rwDatabaseConnection
	 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		ZDCLocalUser *updatedUser = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		
		if(updatedUser)
		{
			updatedUser                 		= updatedUser.copy;
			updatedUser.preferredIdentityID	= identityID;
			[transaction setObject:updatedUser
								 forKey:updatedUser.uuid
						 inCollection:kZDCCollection_Users];
		}
		
	}completionBlock:^{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;
	 		[strongSelf->_tblUsers reloadData];
	}];
	
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark IdentityProviderFilterViewControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)identityProviderFilter:(IdentityProviderFilterViewController *)sender
              selectedProvider:(NSString *)provider
{
	providerToSearch = provider;
	
	OSImage *image = nil;
	if (provider != nil)
	{
		image = [zdc.auth0ProviderManager iconForProvider:provider type:Auth0ProviderIconType_64x64];
	}
	
	if (!image)
	{
		image = threeDots;
	}
	
	[_btnFilter setImage:image  forState:UIControlStateNormal];
	[self startNewSearchQuery:nil];
}

@end
