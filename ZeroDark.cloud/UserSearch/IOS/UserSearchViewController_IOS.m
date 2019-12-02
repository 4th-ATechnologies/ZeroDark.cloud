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
	
	NSTimer * showSearchingTimer;    // So we don't fire a search right away while user is typing.
	NSTimer * importingTimer;        // Used to remove the keyboard during a long import.
	
	UISwipeGestureRecognizer * swipeGesture;
	
	UIViewController * remoteSRVC;
 
	NSTimer   * queryStartTimer;
	NSInteger   searchId;  // track searches
	NSInteger   activeSearchId;
	NSInteger   displayedSearchId;
	
	dispatch_queue_t dataQueue;
	void *           IsOnDataQueue;

	NSArray<ZDCSearchResult *> *searchResults;
	NSMutableDictionary<NSString *,NSString *> *preferredIdentityIDs; // Map: userID => selected identityID
    
	UIImage * defaultUserImage;
	UIImage * threeDots;
	
	NSString *filterProvider;
	
	NSArray *recentRecipients;
	
	NSArray<NSString *> *remoteUserIDs;
	NSArray<NSString *> *importingUserIDs;        // used when animating the import of users
	
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
		
		dataQueue = dispatch_queue_create("UserSearchViewController.dataQueue", DISPATCH_QUEUE_SERIAL);
		IsOnDataQueue = &IsOnDataQueue;
		dispatch_queue_set_specific(dataQueue, IsOnDataQueue, IsOnDataQueue, NULL);
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
	
	[_btnFilter setImage:threeDots  forState:UIControlStateNormal];
	
	_searchBar.text = @"";
	
	searchId = 0;
	activeSearchId = -1;
	displayedSearchId = -1;
	
	_vwInfo.layer.cornerRadius = 5;
	_vwInfo.layer.masksToBounds = YES;
	_vwInfo.hidden = YES;
	
//	[self.view addKeyboardPanningWithFrameBasedActionHandler:^(CGRect keyboardFrameInView, BOOL opening, BOOL closing) {
//
//	} constraintBasedActionHandler:nil];
	
	[self cancelSearching]; // why ?
}

- (void)viewWillAppear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillAppear:animated];
	
	// The swipe gesture fights with table editing.
//	swipeGesture = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(gestureFired:)];
//	[self.view addGestureRecognizer:swipeGesture];
	
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
	
	[self reloadResults];
	
	[_searchBar becomeFirstResponder];
	[self cancelSearching];
}

- (void)viewWillDisappear:(BOOL)animated
{
	ZDCLogAutoTrace();
	[super viewWillDisappear:animated];
	
	[self.view removeGestureRecognizer:swipeGesture];
	swipeGesture = nil;
	
	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}

- (void)fadeView:(UIView *)theView
      shouldHide:(BOOL)shouldHide
{
	if (theView.isHidden == shouldHide) {
		// Nothing to do
		return;
	}
	
	if (shouldHide)
	{
		[UIView animateWithDuration:0.3 animations:^{
			theView.alpha = 0;
		} completion: ^(BOOL finished) {
			theView.hidden = finished;
		}];
	}
	else
	{
		theView.alpha = 0;
		theView.hidden = NO;
		[UIView animateWithDuration:0.7 animations:^{
			theView.alpha = 1;
		}];
	}
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)btnFilterTapped:(id)sender
{
	ZDCLogAutoTrace();
	
	UIButton* btn = sender;

	IdentityProviderFilterViewController *iPvc =
	  [[IdentityProviderFilterViewController alloc] initWithDelegate:self owner:zdc];

    iPvc.provider = filterProvider;
    // this is best presented as a popover on both Iphone and iPad
    iPvc.modalPresentationStyle = UIModalPresentationPopover;
    CGFloat height =  self.view.frame.size.height - btn.frame.origin.y - btn.frame.size.height;

    iPvc.preferredContentSize = (CGSize){ .width = iPvc.preferredWidth, .height = height };

    UIPopoverPresentationController *popover =  iPvc.popoverPresentationController;
    popover.delegate = iPvc;
    popover.sourceView = self.view;
    popover.sourceRect = btn.frame;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;

    [self presentViewController:iPvc animated:YES completion:nil];
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

-(void)reloadResults
{
    [_tblUsers reloadData];
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
	
	preferredIdentityIDs[userID] = identityID;
}

- (void)removeUserFromSharedList:(NSString *)userID
{
	ZDCLogAutoTrace();
	
	NSMutableSet *_sharedUserIDs = [NSMutableSet setWithSet:sharedUserIDs];
	[_sharedUserIDs removeObject:userID];
	sharedUserIDs = [_sharedUserIDs copy];
	
	SEL selector = @selector(userSearchViewController:removedRecipients:);
	if ([delegate respondsToSelector:selector])
	{
		[delegate userSearchViewController: self
		                 removedRecipients: @[userID]];
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
 
	__block ZDCUser *user = nil;
 
	YapDatabaseConnection *uiConnection = zdc.databaseManager.uiDatabaseConnection;
	[uiConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
	}];

	[zdc.internalPreferences addRecentRecipient:userID];
	[self setPreferredIdentityID:identityID forUserID:userID];
  
	// if the new prefered ID doesnt match the user.auth0_preferredID then update the pref
//	if ([user.preferredIdentityID isEqualToString:auth0ID])
//	{
//		[zdc.internalPreferences setPreferedAuth0ID:NULL userID:userID];
//	}
//	else
//	{
//		[zdc.internalPreferences setPreferedAuth0ID:auth0ID userID:userID];
//	}
	
	SEL selector = @selector(userSearchViewController:selectedRecipients:);
	if ([delegate respondsToSelector:selector])
	{
		[delegate userSearchViewController:self selectedRecipients:@[@[userID, identityID]]];
	}
}

-(BOOL)shouldShowRecentRecipients
{
    BOOL result = NO;
    
    result = (_searchBar.text.length == 0) && recentRecipients.count > 0;
    
    return result;
}

-(void)removeRecipientAtIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray* newUsers = [NSMutableArray arrayWithArray:remoteUserIDs];
    
    NSUInteger index = indexPath.row;
    [newUsers removeObjectAtIndex:index];
    remoteUserIDs = newUsers;
    
    [_tblUsers beginUpdates];
    [_tblUsers deleteRowsAtIndexPaths:@[indexPath]  withRowAnimation:YES];
    [_tblUsers endUpdates];
    [self.view setNeedsUpdateConstraints];
    
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UISearchBar Activity
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// this timer prevents the ketboard from hiding/appearing durring an import unless we are taking to long

-(void)startImporting
{
    [self completedImport];
    importingTimer =  [NSTimer scheduledTimerWithTimeInterval:.3
                                                       target:self
                                                     selector:@selector(importIsTakingToLong:)
                                                     userInfo:nil
                                                      repeats:NO];
    
}

-(void)completedImport
{
    if(importingTimer) {
        [importingTimer invalidate];
    }
    
    if(!_searchBar.userInteractionEnabled)
    {
        [_searchBar setUserInteractionEnabled:YES];
        
        [UIView animateWithDuration:0.3 animations:^{
			  self->_searchBar.alpha= 1;
        } completion:nil];
    }
}

- (void)importIsTakingToLong:(NSTimer*)sender
{
    [_searchBar setUserInteractionEnabled:NO];
    
    [UIView animateWithDuration:0.3 animations:^{
		 self->_searchBar.alpha= .5;
    } completion:nil];
}


// this timer prevents the user typing from firing off a search for each char, we delay just a bit

- (void)startSearching
{
	ZDCLogAutoTrace();
	
	[self cancelSearching];
	showSearchingTimer =
	  [NSTimer scheduledTimerWithTimeInterval: 0.3
	                                   target: self
	                                 selector: @selector(showSearching:)
	                                 userInfo: nil
	                                  repeats: NO];
}

- (void)cancelSearching
{
	ZDCLogAutoTrace();
	
	if (showSearchingTimer) {
		[showSearchingTimer invalidate];
	}
   
	_searchBar.isLoading = NO;
}

- (void)showSearching:(NSTimer*)sender
{
	ZDCLogAutoTrace();
	
	_searchBar.isLoading = YES;
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
		searchResults = nil;
	//	preferredIdentityIDs = nil;
		[self cancelSearching];
		[self reloadResults];
		return;
	}
	
	NSInteger currentSearchId = searchId;
	[self startSearching];
	
	ZDCSearchOptions *options = [[ZDCSearchOptions alloc] init];
	options.providerToSearch = filterProvider;
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
		[self cancelSearching];
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
	searchResults =  [searchDict.allValues copy];
	[self reloadResults];
	
	if (stage == ZDCSearchResultStage_Done)
	{
		// end search indicator;
		
		[self cancelSearching];
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
	
	if (tv == _tblUsers)
	{
		if (self.shouldShowRecentRecipients)
			result = recentRecipients.count;
		else
			result = searchResults.count;
	}
	
	return result;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat result = 0;
    
    if(tv == _tblUsers)
    {
        result =  [RemoteUserTableViewCell heightForCell];
    }
    
    return result;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = nil;
	if (tv == _tblUsers)
	{
		if (self.shouldShowRecentRecipients)
			cell = [self tableView:tv  recentUserCellForRowAtIndexPath:indexPath];
		else
			cell = [self tableView:tv  remoteUserCellForRowAtIndexPath:indexPath];
	}
	
	return cell;
}

- (RemoteUserTableViewCell *)tableView:(UITableView *)tv
       recentUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)
	  [tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];
	
	NSString *userID = [recentRecipients objectAtIndex:indexPath.row];
	
	BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
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


- (RemoteUserTableViewCell*)tableView:(UITableView *)tv
      remoteUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)
	  [tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];
	
	ZDCSearchResult *item = searchResults[indexPath.row];
	ZDCUserIdentity *displayIdentity = item.displayIdentity;
	
	NSString *userID = item.userID;
	NSString *identityID = displayIdentity.identityID;
	
	cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;
	cell.userID  = userID;
	cell.identityID = identityID;
	
	BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
	BOOL isMyUserID = [userID isEqualToString:localUserID];
	
	{ // Scoping
		
		NSString *displayName = displayIdentity.displayName;
		NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:displayName];
		
		if (item.matches.count)
		{
			UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
			/// Add the bold trait
			descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
			/// Pass 0 to keep the same font size
			UIFont *boldFont = [UIFont fontWithDescriptor:descriptor size:0];
			
			[attrString beginEditing];
		 	for (ZDCSearchMatch *match in item.matches)
			{
				if (![match.identityID isEqual:identityID]) {
					continue;
				}
				
				for (NSValue *matchRange in match.matchingRanges)
				{
					[attrString addAttribute: NSFontAttributeName
					                   value: boldFont
					                   range: matchRange.rangeValue];
				}
		 	}
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
	                     processingID: NSStringFromClass([self class])
	                  processingBlock: processingBlock
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];
	
	if ([importingUserIDs containsObject:userID])
	{
		cell.progress.indeterminate = YES;
		cell.progress.hidden = NO;
	}
	else
	{
		cell.progress.hidden = YES;
	}
	
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
#pragma mark TableView Swipe
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if __IPHONE_11_0
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0)
{
	NSAssert(NO, @"Not implemented"); // finish refactoring
	return nil;
	
/*
    UISwipeActionsConfiguration* config = nil;

    __weak typeof(self) weakSelf = self;
    if(self.shouldShowRecentRecipients)
    {
  
        NSArray* item = [recentRecipients objectAtIndex: indexPath.row ];
        NSString* userID = item[0];
        
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
          
                 [strongSelf->owner.internalPreferences removeRecentRecipient:userID];
					 strongSelf->recentRecipients  = strongSelf->owner.internalPreferences.recentRecipients;

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
*/
}

#endif


//MARK: tableview select/deselect

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    if(tv == _tblUsers)
    {
        if(self.shouldShowRecentRecipients)
            [self tableView:tv  didSelectRecentUserCellForRowAtIndexPath:indexPath];
        else
            [self tableView:tv  didSelectRemoteUserCellForRowAtIndexPath:indexPath];
    }
}


- (void)tableView:(UITableView *)tv didSelectRemoteUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSAssert(NO, @"Not implemented"); // finish refactoring
	
/*
	__weak typeof(self) weakSelf = self;

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
		// Signal that we are importing this user.
		dispatch_sync(dataQueue, ^{
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			NSMutableArray *temp = [importingUserIDs mutableCopy];
			[temp addObject:userID];
			importingUserIDs = [temp copy];
			
		#pragma clang diagnostic pop
		});
		
		[_tblUsers reloadRowsAtIndexPaths: @[indexPath]
		                 withRowAnimation: UITableViewRowAnimationNone];
		
		// Disable the searchbar
		[self startImporting];
		
		
        [self createRemoteUserIfNeeded:userID // replace with zdc.userManager fetchUserWith
                       completionBlock:^(ZDCUser *remoteUser, NSError *error)
         {
				__strong typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;

            [strongSelf addUserToSharedList:userID auth0ID:auth0ID];
             
             // we should reload the recents list in this view
             strongSelf->recentRecipients  = strongSelf->owner.internalPreferences.recentRecipients;

             [strongSelf completedImport];
             // signal that we completed the import
             dispatch_sync(strongSelf->dataQueue, ^{
					 NSMutableArray* temp = [NSMutableArray arrayWithArray:strongSelf->importingUserIDs];
                 [temp removeObject:userID];
                 strongSelf->importingUserIDs = temp;
             });
             
             [tv reloadRowsAtIndexPaths:@[indexPath]
                       withRowAnimation:UITableViewRowAnimationNone];
             
             
         }];
        
    }
*/
}

- (void)tableView:(UITableView *)tv didSelectRecentUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray* item = [recentRecipients objectAtIndex: indexPath.row ];
    NSString* userID = item[0];
    NSString* auth0ID = item.count>1?item[1]:@"";
    
    // select or deselect?
    if([sharedUserIDs containsObject:userID])
    {
        [self removeUserFromSharedList:userID];
        [tv reloadRowsAtIndexPaths:@[indexPath]
                  withRowAnimation:UITableViewRowAnimationNone];
    }
    else  // select
    {
        [self addUserToSharedList:userID identityID:auth0ID];
        [tv reloadRowsAtIndexPaths:@[indexPath]
                  withRowAnimation:UITableViewRowAnimationNone];
    }
}

// prevent deselection - in effect we have radio buttons
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

- (nullable NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath* newIndexPath = nil;
    if(tv == _tblUsers)
    {
        NSString* userID = nil;
        if(self.shouldShowRecentRecipients)
        {
            NSArray* item = [recentRecipients objectAtIndex: indexPath.row ];
            userID = item[0];
        }
        else
        {
            ZDCSearchResult *item = [searchResults objectAtIndex:indexPath.row];
            userID = item.userID;
        }
        
        if(![localUserID isEqualToString:userID])
            newIndexPath = indexPath;
     }
    
    return newIndexPath;
}


// MARK: RemoteUserTableViewCellDelegate

- (void)tableView:(UITableView * _Nonnull)tv disclosureButtonTappedAtCell:(RemoteUserTableViewCell* _Nonnull)cell
{
	NSAssert(NO, @"Not implemented"); // finish refactoring
	
/*
    if(tv != _tblUsers)
        return;
    
    NSString*  userID = cell.userID;
    NSString*  auth0ID = cell.auth0ID;
    ZDCSearchUserResult* info = nil;
    
    if(self.shouldShowRecentRecipients)
    {
        __block ZDCUser*    user    = nil;
        [owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
        }];
        
        if(user)
        {
            info = [[ZDCSearchUserResult alloc] initWithUser:user];
            info.auth0_preferredID = auth0ID;
        }
    }
    else
    {
        info = [self searchResultsForUserID:userID];
        info.auth0_preferredID = auth0ID;
        
    }
    
    
    if(info)
    {
        UserSearchSocialIDViewController_IOS*  remoteSRVC = nil;
        
        remoteSRVC = [[UserSearchSocialIDViewController_IOS alloc]
                      initWithDelegate:(id<UserSearchSocialIDViewControllerDelegate>)self
                      owner:owner
                      localUserID:localUserID
                      searchResultInfo:info];
        
        self.navigationController.navigationBarHidden = NO;
        [self.navigationController pushViewController:remoteSRVC animated:YES];
        
    }
*/
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UserSearchSocialIDViewControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
                        didSelectAuth0ID:(NSString *)auth0ID
                               forUserID:(NSString *)userID
{
	BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
	
	[self setPreferredIdentityID:auth0ID forUserID:userID];
	
	// if the user is already selected
	if (isAlreadyImported)
	{
		// update our copy and recents if needed
		[self addUserToSharedList:userID identityID:auth0ID];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark IdentityProviderFilterViewControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)identityProviderFilter:(IdentityProviderFilterViewController *)sender
              selectedProvider:(NSString *)provider
{
	filterProvider = provider;
	
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
