/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "UserSearchViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCImageManagerPrivate.h"
#import "Auth0Utilities.h"

#import "ZDCBadgedBarButtonItem.h"
#import "UITableViewTouch.h"
#import "ZDCPopoverTransition.h"

#import "RemoteUserTableViewCell.h"
#import "UserSearchTableViewHeaderCell.h"
#import "UserSearchSocialIDViewController_IOS.h"
#import "IdentityProviderFilterViewController.h"

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


@interface SearchBarWithloading : UISearchBar
@property(nonatomic) BOOL isLoading;
@end

@implementation SearchBarWithloading
{
    UIActivityIndicatorView *_activityIndicatorView;
    UIImage* _searchIcon;
}

@synthesize isLoading;

- (NSMutableArray*)allSubViewsForView:(UIView*)viewIn
{
    NSMutableArray *array = NSMutableArray.array;
    [array addObject:viewIn];
    for (UIView *subview in viewIn.subviews)
    {
        [array addObjectsFromArray:[self allSubViewsForView:subview]];
    }
    return array;
}

-(UIActivityIndicatorView*) activityIndicatorView
{
    if (!_activityIndicatorView)
    {
        UITextField *searchField = nil;
        
        for(UIView* view in [self allSubViewsForView:self])
        {
            if([view isKindOfClass:[UITextField class]]){
                searchField= (UITextField *)view;
                break;
            }
        }
  
        if(searchField)
        {
            // save old search icon
            _searchIcon =  [((UIImageView*) searchField.leftView) image];
            
            // create an activity view
            UIActivityIndicatorView *taiv = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            taiv.backgroundColor = UIColor.clearColor;
            
            taiv.center = CGPointMake(searchField.leftView.bounds.origin.x + searchField.leftView.bounds.size.width/2,
                                      searchField.leftView.bounds.origin.y + searchField.leftView.bounds.size.height/2);
            taiv.hidesWhenStopped = YES;
            _activityIndicatorView = taiv;
            [searchField.leftView addSubview:_activityIndicatorView];
        }
        
    }
    return _activityIndicatorView;
}

-(void)setIsLoading:(BOOL)isLoading
{
    if (isLoading)
    {
        [self.activityIndicatorView startAnimating];
        [self setImage:[[UIImage alloc] init]
                forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    }
    else
    {
        [self.activityIndicatorView stopAnimating];
        [self setImage:_searchIcon  forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    }
    [self layoutSubviews];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation UserSearchViewController_IOS
{
    ZeroDarkCloud*    owner;
    
    IBOutlet __weak SearchBarWithloading*   _searchBar;
    IBOutlet __weak UILabel*                _lblSearchPrompt;
    
    NSTimer *                               showSearchingTimer;    // so we dont fire a seacrh right away while user is typing
    NSTimer *                               importingTimer;        // used to remove the keyboard durring a long import
    
    IBOutlet __weak UIButton*               _btnFilter;
    
    IBOutlet __weak UITableViewTouch*       _tblUsers;
    IBOutlet __weak NSLayoutConstraint*     _cnstTbleUserBottomOffset;
    
    IBOutlet __weak UIView*                 _vwInfo;
    IBOutlet __weak UILabel*                _lblInfo;
    
    ZDCBadgedBarButtonItem*                 _bbtnBack;
    UISwipeGestureRecognizer*               swipeGesture;
    
    UIViewController*                       remoteSRVC;
    
    YapDatabaseConnection*                  databaseConnection;
    Auth0ProviderManager*                   providerManager;
    ZDCImageManager*                        imageManager;
 
    NSTimer*                                queryStartTimer;
    NSInteger                               searchId;  // track searches
    NSInteger                               displayedSearchId  ;
    
    dispatch_queue_t                        searchResultsQueue;
    void *                                  IsOnSearchResultsQueue;
    
    dispatch_queue_t                        dataQueue;
    void *                                  IsOnDataQueue;

    NSArray <ZDCSearchUserResult*> *        searchResults;
    NSDictionary<NSString *,NSString *> *   preferedAuth0IDs;      // map of selected Auth0ID for userID;
    
    NSArray*                                recentRecipients;
    UIImage*                                defaultUserImage;
    
    NSArray*                                remoteUserIDs;
    NSString*                               localUserID;
    NSString *                              filterProvider;
    NSArray*                                importingUserIDs;        // used when animating the import of users
 
    NSSet*                                  sharedUserIDs;
    
    ZDCPopoverTransition *                  popoverTransition;
    
    BOOL                                    isImportingUsers;
    UIImage*                                threeDots;
    BOOL                                    awake;

}

@synthesize delegate = delegate;

- (instancetype)initWithDelegate:(nullable id <UserSearchViewControllerDelegate>)inDelegate
                           owner:(ZeroDarkCloud*)inOwner
                     localUserID:(NSString* __nonnull)inLocalUserID
                   sharedUserIDs:(NSArray <NSString* /* [userID */> *)inSharedUserIDs

{
    NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UserSearchViewController_IOS" bundle:bundle];
    self = [storyboard instantiateViewControllerWithIdentifier:@"UserSearchViewController"];
    if (self)
    {
        owner = inOwner;
        delegate = inDelegate;
        localUserID = inLocalUserID;
        sharedUserIDs = [NSSet setWithArray:inSharedUserIDs];
        [self commonInit];
    }
    return self;
}

-(void)commonInit
{
    awake = NO;
    importingUserIDs = nil;
    
    searchResultsQueue     = dispatch_queue_create("UserSearchViewController.searchResultsQueue", DISPATCH_QUEUE_SERIAL);
    IsOnSearchResultsQueue = &IsOnSearchResultsQueue;
    dispatch_queue_set_specific(searchResultsQueue, IsOnSearchResultsQueue, IsOnSearchResultsQueue, NULL);
    
    dataQueue     = dispatch_queue_create("UserSearchViewController.dataQueue", DISPATCH_QUEUE_SERIAL);
    IsOnDataQueue = &IsOnDataQueue;
    dispatch_queue_set_specific(dataQueue, IsOnDataQueue, IsOnDataQueue, NULL);
    
    databaseConnection = owner.databaseManager.uiDatabaseConnection;
    providerManager = owner.auth0ProviderManager;
    imageManager =  owner.imageManager;

    threeDots = [[UIImage imageNamed:@"3dots"
                            inBundle:[ZeroDarkCloud frameworkBundle]
       compatibleWithTraitCollection:nil]
                 maskWithColor: self.view.tintColor];
    
    [_btnFilter setImage:threeDots  forState:UIControlStateNormal];

}


- (void)viewDidLoad {
	[super viewDidLoad];
	
	self.navigationItem.title = @"Add Recipients";
	
	[RemoteUserTableViewCell registerViewsforTable:_tblUsers
														 bundle:[ZeroDarkCloud frameworkBundle]];
	
	
	[UserSearchTableViewHeaderCell registerViewsforTable:_tblUsers
																 bundle:[ZeroDarkCloud frameworkBundle]];
	
	_tblUsers.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0); // top, left, bottom, right
	//    _tblUsers.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblUsers.frame.size.width, 1)];
	
	_tblUsers.allowsSelection = YES;
	_tblUsers.estimatedRowHeight = 0;
	_tblUsers.estimatedSectionHeaderHeight = 0;
	_tblUsers.estimatedSectionFooterHeight = 0;
	_tblUsers.touchDelegate    =  (id <UITableViewTouchDelegate>) self;
	
	_lblSearchPrompt.hidden = YES;
	_lblSearchPrompt.text =  NSLocalizedString(@"Type at least 2 characters",
															 @"Type at least 2 characters");
	
	remoteSRVC = nil;
	
	defaultUserImage = [imageManager.defaultUserAvatar imageWithMaxSize:[RemoteUserTableViewCell avatarSize]];
	
	_searchBar.text = @"";
	searchResults = nil;
	preferedAuth0IDs =  nil;
	//    preferedAuth0IDs =  owner.internalPreferences.preferedAuth0IDs;
	searchId = 0;
	displayedSearchId = -1;
	
	_vwInfo.layer.cornerRadius = 5;
	_vwInfo.layer.masksToBounds = YES;
	_vwInfo.hidden = YES;
	
	//    [self.view addKeyboardPanningWithFrameBasedActionHandler:^(CGRect keyboardFrameInView, BOOL opening, BOOL closing) {
	//
	//    } constraintBasedActionHandler:nil];
	//
	[self cancelSearching];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    
    // the swipe gesture fights with table editing
    
    //    swipeGesture = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(gestureFired:)];
    //    [self.view addGestureRecognizer:swipeGesture];
    
//    [[NSNotificationCenter defaultCenter] addObserver: self
//                                             selector: @selector(prefsChanged:)
//                                                 name: ZDCLocalPreferencesChangedNotification
//                                               object: nil];
//
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(databaseConnectionDidUpdate:)
//                                                 name:UIDatabaseConnectionDidUpdateNotification
//                                               object:S4DatabaseManager];
//
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    recentRecipients =   owner.internalPreferences.recentRecipients;
  
    if (!awake)
    {
        awake = YES;
        
    }
    
    
    [self.tabBarController.tabBar setHidden:YES];
    [self.navigationController setNavigationBarHidden:NO];
    
    self.navigationItem.title = NSLocalizedString(@"Select Recipients", @"Select Recipients");
    
    [self reloadResults];
    
    [_searchBar becomeFirstResponder];
    [self cancelSearching];
    
}


-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self.view removeGestureRecognizer:swipeGesture];
    swipeGesture = nil;
    
    [[NSNotificationCenter defaultCenter]  removeObserver:self];
    
}

//
//-(void)gestureFired:(UISwipeGestureRecognizer *)gesture {
//    if (gesture.direction == UISwipeGestureRecognizerDirectionRight)
//    {
//        [self.navigationController popViewControllerAnimated:YES];
//    }
//}
//


-(void) updateViewConstraints
{
    [super updateViewConstraints];
    
}



-(void)fadeView:(UIView*)theView
     shouldHide:(BOOL)shouldHide
{
    if(theView.isHidden != shouldHide)
    {
        
        if(shouldHide)
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
    
    __weak typeof(self) weakSelf = self;
    
    // With multitasking on iPad, all visible apps are notified when the keyboard appears and disappears.
    // The value of [UIKeyboardIsLocalUserInfoKey] is YES for the app that caused the keyboard to appear
    // and NO for any other apps.
    
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
    
    [UIView animateWithDuration:animationDuration
                          delay:0.2
                        options:AnimationOptionsFromCurve(animationCurve)
                     animations:
     ^{
         __strong typeof(self) strongSelf = weakSelf;
         if (strongSelf == nil) return;
         
         strongSelf->_cnstTbleUserBottomOffset.constant =   - keyboardHeight;
         
         [strongSelf.view layoutIfNeeded]; // animate constraint change
         
     } completion:^(BOOL finished) {
     }];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    ZDCLogAutoTrace();
    
    // With multitasking on iPad, all visible apps are notified when the keyboard appears and disappears.
    // The value of [UIKeyboardIsLocalUserInfoKey] is YES for the app that caused the keyboard to appear
    // and NO for any other apps.
    
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
#pragma mark UIViewControllerTransitioningDelegate

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

    IdentityProviderFilterViewController *iPvc = [[IdentityProviderFilterViewController alloc] initWithDelegate:(id <IdentityProviderFilterViewControllerDelegate>) self
                                                                                                          owner:owner];

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


// Handles the dismissal of a self presented detailVC with custom Back button
- (void)handleNavigationBack:(UIButton *)backButton
{
    //    if ([self isEditing])
    //    {
    //        [self endEditing:NULL];
    //    }
    
    [[self navigationController] popViewControllerAnimated:YES];
}


-(void)resetSearch
{
    _searchBar.text = @"";
    
    searchResults = nil;
    preferedAuth0IDs =  nil;
//    preferedAuth0IDs =  owner.internalPreferences.preferedAuth0IDs;
    searchId = 0;
    displayedSearchId = -1;
    
    [self reloadResults];
}

-(void)reloadResults
{
    [_tblUsers reloadData];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Recipient Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void) setPreferedAuth0ID:(NSString*)auth0ID forUserID:(NSString*)userID
{
    NSMutableDictionary* ppTable = [NSMutableDictionary dictionaryWithDictionary:preferedAuth0IDs];
    [ppTable setObject:auth0ID forKey:userID];
    preferedAuth0IDs = ppTable;
}

-(void)removeUserFromSharedList:(NSString * _Nonnull)userID
{
    NSMutableSet* _sharedUserIDs = [NSMutableSet setWithSet:sharedUserIDs];
    [_sharedUserIDs removeObject:userID];
    sharedUserIDs = _sharedUserIDs;

    // deselect
    if([delegate respondsToSelector:@selector(userSearchUserViewController:removedRecipients:)])
    {
        [delegate userSearchUserViewController:self
                             removedRecipients:@[userID]];
    }

}


-(void)addUserToSharedList:(NSString * _Nonnull)userID
                   auth0ID:( NSString * _Nonnull) auth0ID
{
    NSMutableSet* _sharedUserIDs = [NSMutableSet setWithSet:sharedUserIDs];
    [_sharedUserIDs addObject:userID];
    sharedUserIDs = _sharedUserIDs;
 
    // never select yourself
    if([localUserID isEqualToString:userID])
        return;
    
    __block ZDCUser*    user    = nil;
 
    [owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
    }];

    [owner.internalPreferences setRecentRecipient:userID auth0ID:auth0ID];
    [self setPreferedAuth0ID:auth0ID forUserID:userID];
  
    // if the new prefered ID doesnt match the user.auth0_preferredID then update the pref
    if([user.auth0_preferredID isEqualToString:auth0ID])
    {
        [owner.internalPreferences setPreferedAuth0ID:NULL userID:userID];
    }
    else
    {
        [owner.internalPreferences setPreferedAuth0ID:auth0ID userID:userID];
    }

    if([delegate respondsToSelector:@selector(userSearchUserViewController:selectedRecipients:)])
    {
        [delegate userSearchUserViewController:self
                            selectedRecipients:@[@[userID, auth0ID]]];
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


-(NSString*) firstMatchedProfileFromMatches:(NSArray<ZDCSearchUserMatching*>*)matches
{
    __block NSString* filteredKey = NULL;
    
    if(matches.count && filterProvider)
    {
        [matches enumerateObjectsUsingBlock:^(ZDCSearchUserMatching * match, NSUInteger idx, BOOL * _Nonnull stop) {
            
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
            
            NSArray* comps = [match.auth0_profileID componentsSeparatedByString:@"|"];
            NSString* provider = comps.firstObject;
            if([provider isEqualToString:filterProvider])
            {
                filteredKey = match.auth0_profileID;
                *stop = YES;
            }
#pragma clang diagnostic pop
        }];
    }
    return filteredKey;
}


-(void) createRemoteUserIfNeeded:(NSString*)remoteUserID
                 completionBlock:(void (^)(ZDCUser *remoteUser, NSError *error))completionBlock
{
    
    __block ZDCUser*    user    = nil;
 	
    // SELECT A USERID for doing searches
    [owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        user = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
    }];
    
    if(!user)
    {
        dispatch_queue_t concurrentQueue
        = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
        [owner.remoteUserManager fetchRemoteUserWithID: remoteUserID
                                           requesterID: localUserID
                                       completionQueue: concurrentQueue
                                       completionBlock:^(ZDCUser *remoteUser, NSError *error)
         {
             
             dispatch_async(dispatch_get_main_queue(), ^{ @autoreleasepool {
                 
                 if(completionBlock)
                     completionBlock(remoteUser,error);
             }});
             
         }];
    }
    else
    {
        if(completionBlock)
            completionBlock(user,nil);
    }
}


//MARK: UISearchBar activity

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

-(void)startSearching
{
    [self cancelSearching];
    showSearchingTimer =  [NSTimer scheduledTimerWithTimeInterval:.3
                                                           target:self
                                                         selector:@selector(showSearching:)
                                                         userInfo:nil
                                                          repeats:NO];
}

-(void)cancelSearching
{
    if(showSearchingTimer) {
        [showSearchingTimer invalidate];
    }
   
    //    UISearchBar+Ext.swift
    _searchBar.isLoading = NO;
}

- (void)showSearching:(NSTimer*)sender
{
    //    UISearchBar+Ext.swift
    _searchBar.isLoading = YES;
    
}

//MARK: UISearchBarDelegate

-(void) updateSearchPrompt
{
    __weak typeof(self) weakSelf = self;
    
    if(_searchBar.text.length ==1)
    {
        _lblSearchPrompt.hidden = NO;
        _lblSearchPrompt.alpha = 0;
        
        [UIView animateWithDuration:0.5 animations:^{
            
            __strong typeof(self) strongSelf = weakSelf;
            if(strongSelf == nil) return;
            strongSelf->_lblSearchPrompt.alpha = 1;
            
        } completion:^(BOOL finished) {
            
        }];
    }
    else
        _lblSearchPrompt.hidden = YES;
    
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)sender
{
    _lblSearchPrompt.hidden = YES;
    
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)sender
{
    _lblSearchPrompt.hidden = YES;
    
    // only fire a search when the bar is enabled.
    if(sender.userInteractionEnabled)
        [self startNewSearchQuery:nil];
}

- (void)searchBar:(UISearchBar *)sender textDidChange:(NSString *)searchText
{
    const NSTimeInterval kQueryDelay = 0.25;
    [self updateSearchPrompt];
    
    if (queryStartTimer)
    {
        [queryStartTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kQueryDelay]];
    }
    else
    {
        queryStartTimer = [NSTimer scheduledTimerWithTimeInterval:kQueryDelay target:self selector:@selector(startNewSearchQuery:) userInfo:nil repeats:NO];
    }
    
}



#pragma mark search queries

- (void)startNewSearchQuery:(NSTimer*)theTimer
{
    [self queryForUsersByName:_searchBar.text];
    [queryStartTimer invalidate];
    queryStartTimer = NULL;
    _vwInfo.hidden = YES;
}


- (void)queryForUsersByName:(NSString *)name
{
    __weak typeof(self) weakSelf = self;
    
    NSInteger curSearchId = searchId;
    
    //    if ([name length] == 0)
    //    {
    //        searchResults = nil;
    //        preferedAuth0IDs = nil;
    //        [self reloadResults];
    //        return;
    //    }
    
    if (name.length < 2)
    {
        searchResults = nil;
        preferedAuth0IDs =  nil;
//        preferedAuth0IDs =  owner.internalPreferences.preferedAuth0IDs;
        [self cancelSearching];
        [self reloadResults];
        return;
    }
    
    NSString* searchString = name;
    
    searchResults = nil;
    // start search indicator;
    
    [self startSearching];
    
     [owner.searchManager queryForUsersWithString:searchString
                                       forUserID:localUserID
                                 providerFilters:filterProvider?@[filterProvider]:nil
                                 localSearchOnly:NO
                                 completionQueue:nil
                                    resultsBlock:^(ZDCSearchUserManagerResultStage stage,
                                                   NSArray<ZDCSearchUserResult*>* results,
                                                   NSError * _Nonnull error)
      {
          
          __strong typeof(self) strongSelf = weakSelf;
          if(strongSelf == nil) return;
          
          if (curSearchId <= strongSelf->displayedSearchId)
              return; // Newest query already displayed
          
          if(error)
          {
              
              [strongSelf cancelSearching];
              
              //                                            [strongSelf.container showError:@"User Search Failed"
              //                                                                    message:error.localizedDescription
              //                                                            completionBlock:^{
              //
              //                                                                [strongSelf.container popFromCurrentView];
              //
              //                                                            }];
              
              return;
          }
          
          [strongSelf updateSearchResults:results];
          [strongSelf reloadResults];
          
          if(stage == ZDCSearchUserManagerResultStage_Done)
          {
              // end search indicator;
              
              [strongSelf cancelSearching];
              strongSelf->displayedSearchId = curSearchId;
              
              if(strongSelf->searchResults.count == 0)
              {
					  [strongSelf fadeView:strongSelf->_vwInfo shouldHide:NO];
              }
          }
      }];
    
    ++searchId;
}

-(void) updateSearchResults:(NSArray<ZDCSearchUserResult*>*) newResults
{
    dispatch_sync(searchResultsQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        
        __block NSMutableDictionary<NSString*, ZDCSearchUserResult*>* searchDict = NSMutableDictionary.dictionary;
        
        // create a dictionary with existing search results
        [searchResults enumerateObjectsUsingBlock:^(ZDCSearchUserResult* entry, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString*  userID = entry.uuid;
            [searchDict setObject:entry forKey:userID];
        }];
        
        // update the dictionary with new results
        [newResults enumerateObjectsUsingBlock:^(ZDCSearchUserResult* entry, NSUInteger idx, BOOL * _Nonnull stop) {
            
            NSString*  userID = entry.uuid;
            NSDate*   auth0_lastUpdated = entry.auth0_lastUpdated;
            
            ZDCSearchUserResult* existingEntry = [searchDict objectForKey:userID];
            NSDate*   existingDate = existingEntry.auth0_lastUpdated;
    
            // dont update if there is  newer entry
            if(!existingDate || [existingDate isBefore:auth0_lastUpdated])
            {
                [searchDict setObject:entry forKey:userID];
            }
        }];
        
        // update the searchResults
        __block NSMutableArray<ZDCSearchUserResult*>* _searchResults = NSMutableArray.array;
        [searchDict enumerateKeysAndObjectsUsingBlock:^(NSString *userID ,ZDCSearchUserResult* entry, BOOL * _Nonnull stop) {
            [_searchResults addObject:entry];
        }];
        searchResults =  _searchResults;
#pragma clang diagnostic pop
    });
    
}

-(ZDCSearchUserResult*)searchResultsForUserID:(NSString*) userIDIn
{
    __block ZDCSearchUserResult* result = nil;
    
    dispatch_sync(searchResultsQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        
        [searchResults enumerateObjectsUsingBlock:^(ZDCSearchUserResult* entry, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString*  userID = entry.uuid;
             if([userID isEqualToString:userIDIn])
            {
                result = entry;
                *stop = YES;
            }
        }];
        
#pragma clang diagnostic pop
        
    });
    return result;
}


-(NSDictionary*)profileInfoFromSearchResults:(ZDCSearchUserResult*)item
{
    
    NSDictionary* auth0_profiles                = item.auth0_profiles;
    NSString* preferedAuth0ID                   = item.auth0_preferredID;
    NSArray<ZDCSearchUserMatching*>* matches    = item.matches;
    NSString*  userID                           = item.uuid;
 
    NSDictionary* auth0_profile    = nil;
     // result values in dict
    NSString* auth0ID               = nil;
    NSString* provider              = nil;
    NSURL* pictureURL               = nil;
    NSAttributedString* displayAttr = nil;
    
    if(matches.count)
    {
        NSString* matchedProfileID          = nil;
        __block ZDCSearchUserMatching*      matchedProfile = nil;
        NSString* displayName               = nil;
        NSArray*  matchRanges               = nil;
        
        // find the uuid of the matched profile
        matchedProfileID = [self firstMatchedProfileFromMatches:matches];
        if(!matchedProfileID)
        {
            matchedProfileID = [preferedAuth0IDs objectForKey:userID];
            if(!matchedProfileID)
                matchedProfileID = matches.firstObject.auth0_profileID;
        }
        
        
        // get actual result.
        [matches enumerateObjectsUsingBlock:^(ZDCSearchUserMatching * entry,
                                              NSUInteger idx, BOOL * _Nonnull stop)
         {
             if([entry.auth0_profileID isEqualToString:matchedProfileID])
             {
                 matchedProfile = entry;
                 *stop = YES;
             }
         }];
        
        NSArray* comps = [matchedProfileID componentsSeparatedByString:@"|"];
        provider = comps.firstObject;
        
        displayName = matchedProfile.matchingString;
        matchRanges = matchedProfile.matchingRanges;
        
        auth0_profile = auth0_profiles[matchedProfileID];
        if(auth0_profile)
            auth0ID = matchedProfileID;
        
        if(!auth0_profile)
        {
            if(preferedAuth0ID)
            {
                NSArray* comps = [preferedAuth0ID componentsSeparatedByString:@"|"];
                provider = comps.firstObject;
                auth0_profile = [auth0_profiles objectForKey:preferedAuth0ID];
                if(auth0_profile)
                    auth0ID = preferedAuth0ID;
            }
        }
        
        if(!auth0_profile)
        {
            NSString* thisAuth0ID = auth0_profiles.allKeys.firstObject;
            NSArray* comps = [thisAuth0ID componentsSeparatedByString:@"|"];
            provider = comps.firstObject;
            auth0_profile = [auth0_profiles objectForKey:thisAuth0ID];
            if(auth0_profile)
                auth0ID = thisAuth0ID;
        }
        
        if(!displayName)
        {
            NSString* email          = [auth0_profile objectForKey:@"email"];
            NSString* name           = [auth0_profile objectForKey:@"name"];
            NSString* username       = [auth0_profile objectForKey:@"username"];
            NSString* nickname       = [auth0_profile objectForKey:@"nickname"];
            
            // process nsdictionary issues
            if([username isKindOfClass:[NSNull class]])
                username = nil;
            if([email isKindOfClass:[NSNull class]])
                email = nil;
            if([name isKindOfClass:[NSNull class]])
                name = nil;
            if([nickname isKindOfClass:[NSNull class]])
                nickname = nil;
            
            if(!displayName && name.length)
                displayName =  name;
            
            if(!displayName && username.length)
                displayName =  username;
            
            if(!displayName && email.length)
                displayName =  email;
            
            if(!displayName && nickname.length)
                displayName =  nickname;
            
        }
        
        if(displayName)
        {
            NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:displayName];
            
            UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
            /// Add the bold trait
            descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
            /// Pass 0 to keep the same font size
            UIFont *boldFont = [UIFont fontWithDescriptor:descriptor size:0];
            
            if(matchRanges.count)
            {
                [attrString beginEditing];
                
                for(NSValue* matchRange in matchRanges)
                {
                    [attrString addAttribute:NSFontAttributeName
                                       value:boldFont
                                       range:matchRange.rangeValue];
                }
                [attrString endEditing];
            }
            
            displayAttr = attrString;
        }
        
        if([auth0_profile objectForKey:@"picture"])
            pictureURL = [NSURL URLWithString:[auth0_profile objectForKey:@"picture"]];
    }

    NSMutableDictionary* info = NSMutableDictionary.dictionary;

    if(auth0ID)
        info[@"auth0ID"] = auth0ID;

    if(provider)
        info[@"provider"] = provider;

    if(pictureURL)
        info[@"pictureURL"] = pictureURL;

    if(displayAttr)
        info[@"displayAttr"] = displayAttr;

    return info;
}

//MARK: tableview header


- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section
{
    CGFloat height = [UserSearchTableViewHeaderCell heightForCell];
    
    if(!self.shouldShowRecentRecipients &&  searchResults == 0)
        height = 0;
    
    return height;
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section
{
    CGFloat height = 0;
    return height;
}



- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section
{
    
    UserSearchTableViewHeaderCell *cell = (UserSearchTableViewHeaderCell *)
    [tv dequeueReusableCellWithIdentifier:kUserSearchTableViewHeaderCellIdentifier];
    
    if(self.shouldShowRecentRecipients)
    {
        // show recents
        cell.lblText.text = @"Recent Recipients";
    }
    else if(searchResults)
    {
        // show results
        cell.lblText.text = @"Search Results";
    }
    
    return cell;
}


//MARK: tableview

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
    NSInteger result = 0;
    
    if(tv == _tblUsers)
    {
        if(self.shouldShowRecentRecipients)
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
    UITableViewCell* cell = nil;
    
    if(tv == _tblUsers)
    {
        if(self.shouldShowRecentRecipients)
            cell = [self tableView:tv  recentUserCellForRowAtIndexPath:indexPath];
        else
            cell = [self tableView:tv  remoteUserCellForRowAtIndexPath:indexPath];
    }
    
    return cell;
}


-(RemoteUserTableViewCell*)tableView:(UITableView *)tv
     recentUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)[tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];

    __weak typeof(self) weakSelf = self;
    
    NSArray* item = [recentRecipients objectAtIndex: indexPath.row ];
    NSString* userID = item[0];
    NSString* auth0ID = item.count>1?item[1]:@"";
    NSString* provider = nil;
    
    BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
    BOOL isMyUserID = [userID isEqualToString:localUserID];
                   
    if(auth0ID.length == 0)
        auth0ID = nil;
    
    if(auth0ID)
    {
        NSArray* comps = [auth0ID componentsSeparatedByString:@"|"];
        provider = comps.firstObject;
    }
    
    __block ZDCUser *user = nil;
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
    }];
    
    cell.userID = userID;
    cell.auth0ID = auth0ID;
    cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;
    
    NSString* displayName  = [user displayNameForAuth0ID:auth0ID];
    cell.lblUserName.text = displayName;
    
    NSURL *pictureURL = nil;
    NSString* picture  = [Auth0ProviderManager correctPictureForAuth0ID:auth0ID
                                                            profileData:user.auth0_profiles[auth0ID]
                                                                 region:user.aws_region
                                                                 bucket:user.aws_bucket];
    if(picture)
        pictureURL = [NSURL URLWithString:picture];

    if(isMyUserID)
    {
        cell.lblUserName.textColor = UIColor.darkGrayColor;
    }
    else
    {
        cell.lblUserName.textColor = UIColor.blackColor;
    }
    
    OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:provider] scaledToHeight:[RemoteUserTableViewCell imgProviderHeight]];
    
    if(providerImage)
    {
        cell.imgProvider.image =  providerImage;
        cell.imgProvider.layer.opacity   = isMyUserID?.4:1.0;
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

    NSDictionary * auth0_profiles = [Auth0Utilities excludeRecoveryProfile:user.auth0_profiles];
    
    if(auth0_profiles.count  < 2)
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
        cell.lblBadge.edgeInsets = (UIEdgeInsets) {    .top = 0,
            .left = 4,
            .bottom = 0,
            .right = 3};
        
        cell.lblBadge.text =  [self badgeTextWithCount: auth0_profiles.count];
        CGSize newSize = [cell.lblBadge sizeThatFits:CGSizeMake(cell.lblBadge.frame.size.width, 18)];
        newSize.width += 8;
        cell.cnstlblBadgeWidth.constant  = MAX(18,newSize.width);
        
    }
    
    cell.imgAvatar.layer.cornerRadius =  RemoteUserTableViewCell.avatarSize.height / 2;
    cell.imgAvatar.clipsToBounds = YES;
    cell.imgAvatar.layer.opacity   = isMyUserID?.4:1.0;
//    cell.imgAvatar.image = defaultUserImage;


    if(pictureURL)
    {
        cell.imgAvatar.hidden = YES;
        [cell.actAvatar startAnimating];
        cell.actAvatar.hidden = NO;
        
        CGSize avatarSize = [RemoteUserTableViewCell avatarSize];
        
        [ imageManager fetchUserAvatar:userID
                               auth0ID:auth0ID
                               fromURL:pictureURL
			                      options: nil
                      processingID:pictureURL.absoluteString
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
 
    cell.progress.hidden = YES;
    [cell.actAvatar stopAnimating];
    cell.actAvatar.hidden = YES;
    
    cell.showCheckMark     = !isMyUserID;
    cell.enableCheck     = !isMyUserID;
    cell.checked         = isAlreadyImported;
    
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


-(RemoteUserTableViewCell*)tableView:(UITableView *)tv
     remoteUserCellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RemoteUserTableViewCell *cell = (RemoteUserTableViewCell *)[tv dequeueReusableCellWithIdentifier:kRemoteUserTableViewCellIdentifier];
    
    __weak typeof(self) weakSelf = self;
    
    ZDCSearchUserResult* item   = [searchResults objectAtIndex: indexPath.row ];
    NSString*      userID       = item.uuid;
    NSDictionary* auth0_profiles     = item.auth0_profiles;
    
    BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
    BOOL isMyUserID = [userID isEqualToString:localUserID];

    NSDictionary* info = [self profileInfoFromSearchResults:item];
    NSAttributedString* attrString      = info[@"displayAttr"];
    NSURL* pictureURL                   = info[@"pictureURL"];
    NSString* provider                  = info[@"provider"];
    
    cell.userID                         = userID;
    cell.auth0ID                        = info[@"auth0ID"];
    if(isMyUserID)
    {
        // make the text appear in gray
         NSMutableAttributedString *attrStr1 = attrString.mutableCopy;
        [attrStr1 beginEditing];
        [attrStr1 addAttribute:NSForegroundColorAttributeName
                         value:[OSColor lightGrayColor]
                         range:NSMakeRange(0, [attrStr1 length])];
        [attrStr1 endEditing];
        attrString = attrStr1;
    }
  
    cell.lblUserName.attributedText     = attrString;
    cell.delegate = (id <RemoteUserTableViewCellDelegate>)self;
    
    OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:provider] scaledToHeight:[RemoteUserTableViewCell imgProviderHeight]];
    if(providerImage)
    {
        cell.imgProvider.image =  providerImage;
        cell.imgProvider.layer.opacity   = isMyUserID?.4:1.0;
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
    
    if(auth0_profiles.count  < 2)
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
        cell.lblBadge.edgeInsets = (UIEdgeInsets) {    .top = 0,
            .left = 4,
            .bottom = 0,
            .right = 3};
        
        cell.lblBadge.text =  [self badgeTextWithCount: auth0_profiles.count];
        CGSize newSize = [cell.lblBadge sizeThatFits:CGSizeMake(cell.lblBadge.frame.size.width, 18)];
        newSize.width += 8;
        cell.cnstlblBadgeWidth.constant  = MAX(18,newSize.width);
        
    }
    
    cell.imgAvatar.layer.cornerRadius =  RemoteUserTableViewCell.avatarSize.height / 2;
    cell.imgAvatar.clipsToBounds = YES;
    cell.imgAvatar.layer.opacity   = isMyUserID?.4:1.0;
    cell.imgAvatar.image = defaultUserImage;

    if(pictureURL)
    {
        cell.imgAvatar.hidden = YES;
        [cell.actAvatar startAnimating];
        cell.actAvatar.hidden = NO;
        
        CGSize avatarSize = [RemoteUserTableViewCell avatarSize];
        
        [ imageManager fetchUserAvatar:userID
                               auth0ID:info[@"auth0ID"]
                               fromURL:pictureURL
			                      options: nil
                      processingID:pictureURL.absoluteString
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
    
    if([importingUserIDs containsObject:userID])
    {
        cell.progress.indeterminate = YES;
        cell.progress.hidden = NO;
    }
    else
    {
        cell.progress.hidden = YES;
    }
    
    cell.showCheckMark     = !isMyUserID;
    cell.enableCheck     = !isMyUserID;
    cell.checked         = isAlreadyImported;
   
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

// MARK: tableview Swipe


#if __IPHONE_11_0
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0)
{
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
	__weak typeof(self) weakSelf = self;

    ZDCSearchUserResult* item   = [searchResults objectAtIndex: indexPath.row ];
    NSString*      userID       = item.uuid;
    
    NSDictionary* info = [self profileInfoFromSearchResults:item];
    NSString* auth0ID = info[@"auth0ID"];
    
    BOOL isMyUserID = [userID isEqualToString:localUserID];

    // dont allow selection of myself.
    if(isMyUserID)
        return;
    
    // select or deselect?
    if([sharedUserIDs containsObject:userID])
    {
        [self removeUserFromSharedList:userID];
        
        [tv reloadRowsAtIndexPaths:@[indexPath]
                  withRowAnimation:UITableViewRowAnimationNone];
    }
    else  // select
    {
        // signal that we are importing this user.
        dispatch_sync(dataQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
            NSMutableArray* temp = [NSMutableArray arrayWithArray:importingUserIDs];
            [temp addObject:userID];
            importingUserIDs = temp;
#pragma clang diagnostic pop
        });
        [_tblUsers reloadRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationNone];
        
        // disable the searchbar
        [self startImporting];
        
        [self createRemoteUserIfNeeded:userID
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
        [self addUserToSharedList:userID auth0ID:auth0ID];
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
            ZDCSearchUserResult* item   = [searchResults objectAtIndex: indexPath.row ];
            userID = item.uuid;
        }
        
        if(![localUserID isEqualToString:userID])
            newIndexPath = indexPath;
     }
    
    return newIndexPath;
}


// MARK: RemoteUserTableViewCellDelegate

- (void)tableView:(UITableView * _Nonnull)tv disclosureButtonTappedAtCell:(RemoteUserTableViewCell* _Nonnull)cell
{
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
    
}

//MARK:  UserSearchSocialIDViewControllerDelegate

- (void) userSearchSocialIDViewController:(UserSearchSocialIDViewController_IOS *)sender
                         didSelectAuth0ID:(NSString*)auth0ID
                                forUserID:(NSString*)userID
{
    
 
    BOOL isAlreadyImported = [sharedUserIDs containsObject:userID];
    
    [self setPreferedAuth0ID:auth0ID forUserID:userID];
    
    // if the user is already selected
    if(isAlreadyImported)
    {
        // update our copy and recents if needed
        [self addUserToSharedList:userID auth0ID:auth0ID];
    }
    
  }

//MARK:  IdentityProviderFilterViewControllerDelegate

- (void)identityProviderFilter:(IdentityProviderFilterViewController * _Nonnull)sender
              selectedProvider:(NSString* _Nullable )provider
{
    filterProvider = provider;
    
    OSImage* image = nil;
    
    if(provider  != nil)
    {
        image = [providerManager providerIcon:Auth0ProviderIconType_64x64
                                  forProvider:provider];
    }
    
    if(!image)
    {
        image = threeDots;
    }
    
    [_btnFilter setImage:image  forState:UIControlStateNormal];
    [self startNewSearchQuery:nil];
}

@end
