
/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import "BackupSocialViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "LanguageListViewController_IOS.h"
#import "BackupSocialUITableViewCell.h"
#import "BackupShareUITableViewCell.h"
#import "ZDCDateFormatterCache.h"

#import "ZDCAccessCode.h"
#import "ZDCSplitKey.h"
#import "ZDCSplitKeyShare.h"

// Categories
#import "ZDCLogging.h"
#import "OSImage+QRCode.h"
#import "RKTagsView.h"
#import "OSImage+ZeroDark.h"
#import "NSString+ZeroDark.h"
#import "NSDate+ZeroDark.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int ddLogLevel = DDLogLevelVerbose;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

#define  USE_CUSTOM_ACTIVITY 1

#if USE_CUSTOM_ACTIVITY

@interface ZDCActivity : UIActivity
@property (nonatomic, strong) NSArray *activityItems;
@end

@implementation ZDCActivity

- (NSString *)activityType {
	
	// a unique identifier
	return @"com.4th-a.ZeroDark.share";
}

- (NSString *)activityTitle {
	
	// a title shown in the sharing menu
	return @"ZeroDarkCloud";
}

- (UIImage *)activityImage {
	
	UIImage* globeImage = [UIImage imageNamed:@"qrcode-default"
												inBundle:[ZeroDarkCloud frameworkBundle]
					compatibleWithTraitCollection:nil];
	
	// an image to go with our option
	return globeImage;
}

+ (UIActivityCategory)activityCategory {
	
	// which row our activity is shown in
	// top row is sharing, bottom row is action
	return UIActivityCategoryAction;
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
	
	// return YES for anything that our activity can deal with
	for (id item in activityItems) {
		
		// we can deal with strings and images
		if ([item isKindOfClass:[NSURL class]] || [item isKindOfClass:[UIImage class]]) {
			return YES;
		}
	}
	// for everything else, return NO
	return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems {
	
	// anything we need to prepare, now's the chance
	// custom UI, long running calculations, etc
	
	// also: grab a reference to the objects our user wants to share/action
	self.activityItems = activityItems;
}

# pragma mark - optional methods we can override

- (UIViewController *)activityViewController {
	
	// return a custom UI if we need it,
	// or the standard activity view controller if we don't
	return nil;
}

- (void)performActivity {
	
	// the main thing our activity does
	
	// act upon each item here
	for (id item in self.activityItems) {
		NSLog(@"YEY - someone wants to use our activity!");
		NSLog(@"They used this object: %@", [item description]);
	}
	
	// notify iOS that we're done here
	// return YES if we were successful, or NO if we were not
	[self activityDidFinish:YES];
}
@end

#endif


static inline UIViewAnimationOptions AnimationOptionsFromCurve(UIViewAnimationCurve curve)
{
	UIViewAnimationOptions opt = (UIViewAnimationOptions)curve;
	return opt << 16;
}


typedef NS_ENUM(NSInteger, BackupSocialViewController_Page) {
	kPage_Intro                = 0,
	kPage_Existing,
	kPage_CreateSplit,
	
	// manual pages
	kPage_Send,
	kPage_Print,
	kPage_SplitDetail,
	
};

@class BackupSocialViewController_Base;

@interface BackupSocialViewController_IOS ()

@property (readonly) BOOL isKeySplit;
@property (readonly, nullable	) NSString* splitKeyID;
@property (readonly, nonatomic) UILabel* bottomLabel;

-(void)failWithErrorMessage:(NSString*)message;

//-(void)doKeySplit;

-(void)doKeySplitWithCompletionBlock:(void (^)( NSError* error))completionBlock;

-(BOOL)hasExistingSplits;

-(ZDCSplitKey*) splitKey;
-(NSDictionary*)shares;
-(NSString*)splitNumWord;
-(NSString*)shareDataStringForShareID:(NSString*)shareID;
-(NSData*)shareKeyForShareID:(NSString*)shareID;
-(void)resetBackButton;

-(void)sendShareButtonHitForShareID:(NSString*)shareID
								 sourceView:(UIView*)sourceView
								 sourceRect:(CGRect)sourceRect
						  completionBlock:(void (^)(BOOL didSend, NSError* error))completionBlock;


-(void)refreshSentCount;

-(void) proceedToInitialView:(UIPageViewControllerNavigationDirection) direction;
-(void) proceedToSendView;
-(void) proceedToCreateSplitView;

-(void) proceedToNextViewFromView:(BackupSocialViewController_Base*)currentView;

-(void) pushSplitDetailViewForSplitID:(NSString*)splitID;


#if DEBUG
-(BOOL)testManagedSharesWithError:(NSError *_Nullable *_Nullable) outError;
#endif

@end

@interface BackupSocialViewController_Base : UIViewController
@property (readonly) NSInteger  pageIndex;
@property (nonatomic, readwrite, weak) BackupSocialViewController_IOS*   backupSocialVC;
@property (nonatomic, readwrite, weak) YapDatabaseConnection*     databaseConnection;
@end

@implementation BackupSocialViewController_Base
@synthesize backupSocialVC = backupSocialVC;
@synthesize databaseConnection = databaseConnection;
@end

// MARK:  Intro View

@interface BackupSocialViewController_Intro : BackupSocialViewController_Base
@end

@implementation BackupSocialViewController_Intro
{
	IBOutlet __weak UIButton	*_btnStart;
}

-(NSInteger)pageIndex
{
	return kPage_Intro;
}

- (IBAction)btnStartHit:(UISlider*)sender
{
	[self.backupSocialVC  proceedToCreateSplitView];
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[self.backupSocialVC resetBackButton];
}
@end


// MARK:  Existing
@interface BackupSocialViewController_Existing : BackupSocialViewController_Base
@end

@implementation BackupSocialViewController_Existing
{
	IBOutlet __weak UITableView             *_tblSplits;
	IBOutlet __weak NSLayoutConstraint      *_cnstTblSplitsHeight;
	IBOutlet __weak UIButton					 *_btnCreateShare;
	
	UIBarButtonItem*				bbnEdit;
	
	NSArray<NSString*>* 			splitIDs;
	
}
-(void)viewDidLoad
{
	[super viewDidLoad];

	_tblSplits.estimatedRowHeight = 0;
	_tblSplits.rowHeight = UITableViewAutomaticDimension;
	
	[BackupSocialUITableViewCell registerViewsforTable:_tblSplits bundle:[ZeroDarkCloud frameworkBundle]];}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(databaseConnectionDidUpdate:)
																name:UIDatabaseConnectionDidUpdateNotification
															 object:nil];
	
	
	[self.backupSocialVC	 resetBackButton];
	
	bbnEdit = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
																			  target:self
																			  action:@selector(btnEditHit:)];
	
	self.backupSocialVC.navigationItem.rightBarButtonItems = @[bbnEdit];
	_btnCreateShare.enabled = YES;
	
	
	[self refreshView];
}

-(void)viewWillDisappear:(BOOL)animated
{
	[self viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[_tblSplits setEditing:NO animated:YES];
	self.backupSocialVC.navigationItem.rightBarButtonItems = NULL;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_cnstTblSplitsHeight.constant = _tblSplits.contentSize.height;
}



- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
	BOOL hasChanges = NO;
	
	hasChanges = [self.databaseConnection hasChangeForCollection:kZDCCollection_SplitKeys
																inNotifications:notifications];
	
	if(hasChanges)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refreshView];
		});
}

-(NSInteger)pageIndex
{
	return kPage_Existing;
}


- (IBAction)btnEditHit:(id)sender
{
	DDLogAutoTrace();
	
	BOOL willEdit = !_tblSplits.editing;
	
	[self setEditing:willEdit];
}

-(void)setEditing:(BOOL)editing
{
	[_tblSplits setEditing:editing animated:YES];
	
	if(editing)
	{
		UIBarButtonItem* bbnCancel  = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
																											 target:self
																											 action:@selector(btnEditHit:)];
		
		self.backupSocialVC.navigationItem.rightBarButtonItems = @[bbnCancel];
		_btnCreateShare.enabled = NO;
	}
	else
	{
		self.backupSocialVC.navigationItem.rightBarButtonItems = @[bbnEdit];
		_btnCreateShare.enabled = YES;
	}
	
}


- (IBAction)btnCreateShare:(id)sender
{
	DDLogAutoTrace();
	
	[self.backupSocialVC proceedToCreateSplitView];
}



-(void)refreshView
{
	__block NSMutableArray<NSString*>* _splitIDs =  NSMutableArray.array;
	NSString* localUserID = self.backupSocialVC.keyBackupVC.user.uuid;
	
	[self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		YapDatabaseViewTransaction *viewTransaction = [transaction ext:Ext_View_SplitKeys_Date];
		if (viewTransaction)
		{
			[viewTransaction	enumerateKeysAndObjectsInGroup:localUserID
															 usingBlock:^(NSString * _Nonnull collection, NSString * _Nonnull key, id  _Nonnull object, NSUInteger index, BOOL * _Nonnull stop)
			 {
				 
				 if([collection isEqualToString:kZDCCollection_SplitKeys])
				 {
					 [_splitIDs addObject:key];
				 }
			 }];
		}
	}];
	
	splitIDs = _splitIDs;
	[_tblSplits reloadData];
	[self.view setNeedsLayout];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [BackupSocialUITableViewCell heightForCell];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return splitIDs.count;
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
	if(section == 0)
	{
		return @"Split Keys";
	}
	
	return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	BackupSocialUITableViewCell *cell = (BackupSocialUITableViewCell *)[tableView dequeueReusableCellWithIdentifier:kBackupSocialCellIdentifier];;
	
	NSString* splitID = [splitIDs objectAtIndex:indexPath.row];
	__block ZDCSplitKey* splitKey = NULL;
	
	[self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		splitKey  = [transaction objectForKey:splitID inCollection:kZDCCollection_SplitKeys];
	}];
	
	cell.uuid = splitID;
	cell.lblSplit.text  = [NSString stringWithFormat:@"(%ld/%ld)",
								  splitKey.threshold, splitKey.totalShares ];
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:splitKey.ownerID options:0];
	NSString* shareIDb58  = [NSString base58WithData:data];
	cell.lblTitle.text = shareIDb58;
	
	NSString* dateString = splitKey.creationDate? splitKey.creationDate.whenString:nil;
	cell.lblDate.text = dateString;
	
	NSString* comment = splitKey.comment;
	if(comment)
	{
		cell.lblDetails.text = comment;
		cell.lblTitleCenterOffset.constant = cell.lblDetails.frame.size.height /2 + 4;
	}
	else
	{
		cell.lblDetails.text = @"";
		cell.lblTitleCenterOffset.constant = 0;
	}
	return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString* splitID = [splitIDs objectAtIndex:indexPath.row];
	
	[self.backupSocialVC	pushSplitDetailViewForSplitID:splitID];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}


- (nullable NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return NSLocalizedString(@"Revoke Split", @"Revoke Split");
	
};

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	CGRect aFrame = [tv rectForRowAtIndexPath:indexPath];
	aFrame.origin.y -= aFrame.size.height/2;
	
	NSString* splitID = [splitIDs objectAtIndex:indexPath.row];
	
	__weak typeof(self) weakSelf = self;
	
	NSString* warningText =  NSLocalizedString( @"Removing this key split will invalidate this key backup",
															 @"Removing this key split will invalidate this key backup");
	
	
	UIAlertController *alertController =
	[UIAlertController alertControllerWithTitle:
	 NSLocalizedString(@"Are you sure you want to revoke this split?", @"Are you sure you want to revoke this split?")
													message:warningText
										  preferredStyle:UIAlertControllerStyleActionSheet];
	
	UIAlertAction *yesAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Revoke the Split", @"Revoke the Split")
									 style:UIAlertActionStyleDestructive
								  handler:^(UIAlertAction *action)
	 {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 
		 [strongSelf.backupSocialVC.keyBackupVC removeSplitKeyID:splitID
															  completionBlock:^
		  {
			  __strong typeof(self) strongSelf = weakSelf;
			  
			  if(strongSelf.backupSocialVC.hasExistingSplits)
			  {
				  [strongSelf refreshView];
			  }
			  else
			  {
				  [strongSelf.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
			  }
			  
		  }];
	 }];
	
	UIAlertAction *cancelAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
									 style:UIAlertActionStyleCancel
								  handler:^(UIAlertAction * _Nonnull action) {
									  [self refreshView];
									  
								  }];
	
	[alertController addAction:yesAction];
	[alertController addAction:cancelAction];
	
	if([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.sourceView = tv;
		alertController.popoverPresentationController.sourceRect = aFrame;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController:alertController animated:YES
						  completion:^{
						  }];
}

@end



// MARK:  Intro View

@interface BackupSocialViewController_SplitDetail : BackupSocialViewController_Base
@property (nonatomic, readwrite) NSString*   splitID;
@end


@implementation BackupSocialViewController_SplitDetail
{
	IBOutlet __weak UILabel 	*_lblSplitID;
	IBOutlet __weak UILabel 	*_lblDate;
	IBOutlet __weak UITextField 	*_txtDescription;
	IBOutlet __weak UITableView *_tblShares;
	IBOutlet __weak NSLayoutConstraint  *_cnstTblSplitsHeight;
	
	IBOutlet __weak UIButton 		*btnRevoke;
	IBOutlet  NSLayoutConstraint *_btnRevokeBottomConstraint;
	
	
	ZDCSplitKey* 								splitKey;
	NSArray <NSString*> * 					shareIDs;
	NSDateFormatter*                   formatter;
	
	BOOL hasChanges;
}

@synthesize splitID = _splitID;


-(NSInteger)pageIndex
{
	return kPage_SplitDetail;
}

-(void)viewDidLoad
{
	[self viewDidLoad];
	
	[BackupShareUITableViewCell registerViewsforTable:_tblShares bundle:[ZeroDarkCloud frameworkBundle]];
	
	_tblShares.estimatedRowHeight = 0;
	_tblShares.rowHeight = UITableViewAutomaticDimension;
	
	_tblShares.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblShares.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblShares.frame.size.width, 1)];
	_tblShares.separatorInset = UIEdgeInsetsMake(0, 8, 0, 0); // top, left, bottom, right
	
	formatter = [ZDCDateFormatterCache dateFormatterWithDateStyle:NSDateFormatterMediumStyle
																		 timeStyle:NSDateFormatterShortStyle];
	
	_txtDescription.delegate = (id <UITextFieldDelegate >)self;
}

-(void)viewWillAppear:(BOOL)animated
{
	[self viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillShow:)
																name:UIKeyboardWillShowNotification
															 object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillHide:)
																name:UIKeyboardWillHideNotification
															 object:nil];
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																					 style:UIBarButtonItemStylePlain
																					target:self
																					action:@selector(handleNavigationBack:)];
	
	self.backupSocialVC.navigationItem.leftBarButtonItems = @[backItem];
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	[self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		splitKey  = [transaction objectForKey:_splitID inCollection:kZDCCollection_SplitKeys];
	}];
#pragma clang diagnostic pop
	
	NSString* ownerID = splitKey.ownerID;
	NSString* comment = splitKey.comment;
	NSDate* date = splitKey.creationDate;
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:ownerID options:0];
	NSString* splitIDb58  = [NSString base58WithData:data];
	
	_lblSplitID.text = [NSString stringWithFormat:
							  NSLocalizedString(@"Split ID: %@", @"Split ID: %@"),
							  splitIDb58];
	
	_lblDate.text = [formatter stringFromDate:date];
	_txtDescription.text = comment;
	
	shareIDs = splitKey.shareIDs;
	
	[_tblShares reloadData];
	
	hasChanges = NO;
}


-(void)viewWillDisappear:(BOOL)animated
{
	[self viewWillDisappear:animated];
	__weak typeof(self) weakSelf = self;
	
	[[NSNotificationCenter defaultCenter]  removeObserver:self];
	
	if(hasChanges)
	{
		
		NSString* splitID = _splitID;
		NSString* updatedComment = _txtDescription.text;
		
		YapDatabaseConnection *rwConnection = self.backupSocialVC.keyBackupVC.owner.databaseManager.rwDatabaseConnection;
		
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			__strong typeof(self) strongSelf = weakSelf;
			if(!strongSelf) return;
			
			ZDCSplitKey* splitKey = [transaction objectForKey:splitID inCollection:kZDCCollection_SplitKeys];
			if(splitKey)
			{
				splitKey = splitKey.copy;
				splitKey.comment = updatedComment.length?updatedComment:NULL;
				
				[transaction setObject:splitKey
									 forKey:splitKey.uuid
							 inCollection:kZDCCollection_SplitKeys];
				
			}
		}completionBlock:^{
			
		}];
		
	}
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[self.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
}



- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_cnstTblSplitsHeight.constant = _tblShares.contentSize.height;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
								reason:(UITextFieldDidEndEditingReason)reason
API_AVAILABLE(ios(10.0)){
	
	if(textField == _txtDescription )
	{
		hasChanges = YES;
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)aTextField
{
	[aTextField resignFirstResponder];
	return YES;
}

- (IBAction)btnRevokeSplitHit:(UIButton*)sender
{
	__weak typeof(self) weakSelf = self;
	
	NSString* warningText =  NSLocalizedString( @"Removing this key split will invalidate this key backup",
															 @"Removing this key split will invalidate this key backup");
	
	UIAlertController *alertController =
	[UIAlertController alertControllerWithTitle:
	 NSLocalizedString(@"Are you sure you want to revoke this split?", @"Are you sure you want to revoke this split?")
													message:warningText
										  preferredStyle:UIAlertControllerStyleActionSheet];
	
	UIAlertAction *yesAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Revoke the Split", @"Revoke the Split")
									 style:UIAlertActionStyleDestructive
								  handler:^(UIAlertAction *action)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 
		 [strongSelf.backupSocialVC.keyBackupVC removeSplitKeyID:strongSelf->_splitID
															  completionBlock:^{
																  
																  __strong typeof(self) strongSelf = weakSelf;
																  
																  [strongSelf.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
															  }];
	 }];
	
	UIAlertAction *cancelAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
									 style:UIAlertActionStyleCancel
								  handler:^(UIAlertAction * _Nonnull action) {
									  
								  }];
	
	[alertController addAction:yesAction];
	[alertController addAction:cancelAction];
	
	if([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.sourceView = sender;
		alertController.popoverPresentationController.sourceRect = sender.frame;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	// FIXME: alert controller complains about NSLayoutConstraint:0x6000010f0cd0 UIView:0x7fa075640e70.width == - 16   -- looks like apple bug
	
	[self presentViewController:alertController animated:YES
						  completion:^{
						  }];
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
	//	CGPoint containerPoint = [_vwCloneContainer convertPoint:locationPoint fromView:self.view];
	
	if(!CGRectContainsPoint(_txtDescription.frame, locationPoint))
	{
		if([_txtDescription isFirstResponder])
			[_txtDescription resignFirstResponder];
	}
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	DDLogAutoTrace();
	
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
								 delay:0.0
							  options:AnimationOptionsFromCurve(animationCurve)
						  animations:
	 ^{
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_btnRevokeBottomConstraint.constant = keyboardHeight;
			 [self.view layoutIfNeeded]; // animate constraint change
		 }
		 
	 } completion:^(BOOL finished) {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 // refresh the cloneview to get a better resultion image
			 //			 [strongSelf refreshView];
		 }
	 }];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	DDLogAutoTrace();
	
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
								 delay:0.0
	 //	  	 		 usingSpringWithDamping:1
	 //	  	 		  initialSpringVelocity:0
							  options:AnimationOptionsFromCurve(animationCurve)
						  animations:
	 ^{
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_btnRevokeBottomConstraint.constant =  8;
			 
			 [self.view layoutIfNeeded]; // animate constraint change
		 }
		 
	 } completion:^(BOOL finished) {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
		 }
	 }];
}



- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return shareIDs.count;
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [BackupShareUITableViewCell heightForCell];
}


- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
	if(section == 0)
	{
		NSString* title  = [NSString stringWithFormat:
								  NSLocalizedString(@"%ld Shares, %ld Required", @"%ld Shares,  %ld Required"),
								  splitKey.totalShares , splitKey.threshold ];
		
		return title;
	}
	
	return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	BackupShareUITableViewCell *cell = (BackupShareUITableViewCell *)[tableView dequeueReusableCellWithIdentifier:kBackupShareCellIdentifier];;
	
	NSString* shareID = [shareIDs objectAtIndex: indexPath.row];
	
	NSDictionary <NSString*, NSNumber*>* shareNums = splitKey.shareNums;
	NSNumber* shareNum = [shareNums objectForKey:shareID];
	//	NSString* shareNumString = [ZDCAccessCode stringFromShareNum:shareNum];
	
	NSAttributedString* attrStr = NULL;
	OSColor* bgColor = NULL;
	[ZDCAccessCode  attributedStringFromShareNum:shareNum
													  string:&attrStr
													 bgColor:&bgColor];
	cell.lblTitle.attributedText = attrStr;
	cell.lblTitle.backgroundColor = bgColor;
	cell.lblTitle.layer.cornerRadius   = 8;
	cell.lblTitle.layer.masksToBounds  = YES;
	cell.lblTitle.layer.borderColor    = [UIColor blackColor].CGColor;
	cell.lblTitle.layer.borderWidth    = .50f;
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:shareID options:0];
	cell.lblDetails.text = [NSString base58WithData:data];
	
	return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end


// MARK:  Get Share Count View

@interface BackupSocialViewController_CreateSplit : BackupSocialViewController_Base

@property (readonly) NSInteger  totalShares;
@property (readonly) NSInteger  requiredShares;
@property (nonatomic, readonly) NSString* comment;

-(void)reset;

@end

@implementation BackupSocialViewController_CreateSplit
{
	IBOutlet __weak UIView 		*_vwSliders;
	IBOutlet __weak UISlider 	*_sldTotal;
	IBOutlet __weak UILabel		*_lblTotal;
	IBOutlet __weak UISlider	*_sldRequired;
	IBOutlet __weak UILabel 	*_lblRequired;
	
	IBOutlet __weak UITextField *_txtDescription;
	
	IBOutlet __weak UITextView *_txtExplain;
	IBOutlet  NSLayoutConstraint *_txtExplainHeightConstraint;
	
	IBOutlet __weak UIButton	*_btnSplit;
	IBOutlet  NSLayoutConstraint *_btnSplitBottomConstraint;
	
	float lastSliderRatio;
}


-(NSInteger)pageIndex
{
	return kPage_CreateSplit;
}

-(NSInteger)totalShares
{
	return roundf(_sldTotal.value) ;
}

-(NSInteger)requiredShares
{
	return roundf(_sldRequired.value) ;
}

-(NSString*)comment
{
	if( _txtDescription.text.length)
		return _txtDescription.text;
	else
		return NULL;
}

-(void)viewDidLoad
{
	[self viewDidLoad];
	_vwSliders.layer.cornerRadius   = 16;
	_vwSliders.layer.masksToBounds  = YES;
	_vwSliders.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];
	
	[_sldTotal addTarget:self
					  action:@selector(userIsScrubbing:)
		 forControlEvents:UIControlEventTouchDragInside];
	
	[_sldTotal addTarget:self
					  action:@selector(doneScrubbing:)
		 forControlEvents:UIControlEventTouchUpInside];
	
	[_sldTotal addTarget:self
					  action:@selector(doneScrubbing:)
		 forControlEvents:UIControlEventTouchUpOutside];
	
	[_sldRequired addTarget:self
						  action:@selector(userIsScrubbing:)
			 forControlEvents:UIControlEventTouchDragInside];
	
	[_sldRequired addTarget:self
						  action:@selector(doneScrubbing:)
			 forControlEvents:UIControlEventTouchUpInside];
	
	[_sldRequired addTarget:self
						  action:@selector(doneScrubbing:)
			 forControlEvents:UIControlEventTouchUpOutside];
	
	
	// setup for clickable URL
	_txtExplain.scrollEnabled = NO;
	_txtExplain.editable = NO;
	_txtExplain.textContainer.lineFragmentPadding = 0;
	_txtExplain.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
	_txtExplain.delegate =  (id <UITextViewDelegate>)self;
	
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillShow:)
																name:UIKeyboardWillShowNotification
															 object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
														  selector:@selector(keyboardWillHide:)
																name:UIKeyboardWillHideNotification
															 object:nil];
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																					 style:UIBarButtonItemStylePlain
																					target:self
																					action:@selector(handleNavigationBack:)];
	
	self.backupSocialVC.navigationItem.leftBarButtonItems = @[backItem];
	
	[self reset];
	
}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}


- (void)handleNavigationBack:(UIButton *)backButton
{
	[self.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
}


-(void)reset
{
	_sldTotal.minimumValue = 2;
	_sldTotal.maximumValue = 10;
	_sldTotal.value = 5;
	_sldTotal.continuous = NO;
	
	_sldRequired.minimumValue = 2;
	_sldRequired.maximumValue = _sldTotal.maximumValue -1 ;
	_sldRequired.value = 3;
	_sldRequired.continuous = NO;
	
	lastSliderRatio = _sldRequired.value / _sldTotal.value;
	
	_txtDescription.text = NULL;
	
	[self doneScrubbing:_sldTotal];
	[self doneScrubbing:_sldRequired];
	
}


- (IBAction)userIsScrubbing:(UISlider*)sender {
	
	[sender setValue: roundf(sender.value) animated:YES];
	if(sender == _sldTotal)
	{
		_sldRequired.maximumValue = _sldTotal.value ;
		
		_sldRequired.value = roundf(lastSliderRatio * _sldTotal.value);
		_lblRequired.text = [NSString stringWithFormat:@"%@", @(_sldRequired.value)];
		
		_lblTotal.text = [NSString stringWithFormat:@"%@", @(sender.value)];
	}
	else if(sender == _sldRequired)
	{
		lastSliderRatio = _sldRequired.value / _sldTotal.value;
		
		_lblRequired.text = [NSString stringWithFormat:@"%@", @(sender.value)];
	}
	[self updateText];
	
}

- (IBAction)doneScrubbing:(UISlider*)sender
{
	[sender setValue: roundf(sender.value) animated:YES];
	
	if(sender == _sldTotal)
	{
		_sldRequired.maximumValue = _sldTotal.value ;
		
		_sldRequired.value = roundf(lastSliderRatio * _sldTotal.value);
		_lblRequired.text = [NSString stringWithFormat:@"%@", @(_sldRequired.value)];
		
		_lblTotal.text = [NSString stringWithFormat:@"%@", @(sender.value)];
		
	}
	else if(sender == _sldRequired)
	{
		lastSliderRatio = _sldRequired.value / _sldTotal.value;
		
		_lblRequired.text = [NSString stringWithFormat:@"%@", @(sender.value)];
	}
	[self updateText];
	
}

-(void)updateText
{
	
	NSURL* blogURL = [ZDCConstants ZDCsplitKeyBlogPostURL];
	
	NSString* explainationText =
	NSLocalizedString(
							@"The original key will be split into %@ parts. "
							"You can restore the key using any %@ of the %@ parts.\n\n"
							"Each part is encrypted. That is, the recipients who you send the parts to will "
							"not be able to a read a portion of your key.\n"
							"In addition each piece is assigned a random color value to make it easier for you to keep track of them\n\n",
							@"Split key text");
	
	NSString* formatedExplainText = [ NSString stringWithFormat:explainationText,
												@(_sldTotal.value),
												@( _sldRequired.value),  @(_sldTotal.value)];
	
	
	UIFont* textFont =  [ UIFont  preferredFontForTextStyle: UIFontTextStyleFootnote];
	NSMutableAttributedString *atrStr1 	= [[NSMutableAttributedString alloc] initWithString:formatedExplainText
																										  attributes:@{ NSFontAttributeName: textFont  }];
	
	NSString* blogText = NSLocalizedString(
														@"To learn more about how this process works, check out our <blog post>",
														@"Split key blog post text");
	
	NSRange openingRange = [blogText rangeOfString:@"<"];
	blogText = [blogText stringByReplacingOccurrencesOfString:@"<" withString:@""];
	NSRange closingRange = [blogText rangeOfString:@">"];
	blogText = [blogText stringByReplacingOccurrencesOfString:@">" withString:@""];
	NSRange textRange = NSMakeRange(openingRange.location, closingRange.location  - openingRange.location);
	
	NSMutableAttributedString *atrStr2 	= [[NSMutableAttributedString alloc] initWithString:blogText
																										  attributes:@{ NSFontAttributeName: textFont  }];
	
	[atrStr2 beginEditing];
	[atrStr2 addAttribute:NSLinkAttributeName value:[blogURL absoluteString] range:textRange];
	
	// make the text appear in blue
	[atrStr2 addAttribute:NSForegroundColorAttributeName
						 value:self.view.tintColor
						 range:textRange];
	[atrStr2 addAttribute:
	 NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:textRange];
	
	[atrStr2 endEditing];
	
	[atrStr1 appendAttributedString:atrStr2];
	
	_txtExplain.attributedText = atrStr1;
	[_txtExplain sizeToFit];
	
	if(!_txtDescription.isFirstResponder)
	{
		_txtExplainHeightConstraint.constant = _txtExplain.contentSize.height;
	}
	
}



- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction
API_AVAILABLE(ios(10.0)){
	return YES;
}

- (IBAction)btnSplitHit:(UISlider*)sender
{
	[self.backupSocialVC doKeySplitWithCompletionBlock:^(NSError *error) {
		
#if DEBUG
		if(!error)
		{
			[self.backupSocialVC testManagedSharesWithError:&error];
		}
#endif
		if(error)
		{
			[self.backupSocialVC failWithErrorMessage:error.localizedDescription];
		}
		else
		{
			[self.backupSocialVC  proceedToSendView];
		}
	}];
}



- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
	//	CGPoint containerPoint = [_vwCloneContainer convertPoint:locationPoint fromView:self.view];
	
	if(!CGRectContainsPoint(_txtDescription.frame, locationPoint))
	{
		if([_txtDescription isFirstResponder])
			[_txtDescription resignFirstResponder];
	}
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	DDLogAutoTrace();
	
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
								 delay:0.0
							  options:AnimationOptionsFromCurve(animationCurve)
						  animations:
	 ^{
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_txtExplain.hidden = YES;
			 strongSelf->_txtExplainHeightConstraint.constant = 0;
			 strongSelf->_btnSplitBottomConstraint.constant = keyboardHeight;
			 [self.view layoutIfNeeded]; // animate constraint change
		 }
		 
	 } completion:^(BOOL finished) {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 // refresh the cloneview to get a better resultion image
			 //			 [strongSelf refreshView];
		 }
	 }];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	DDLogAutoTrace();
	
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
								 delay:0.0
	 //	  	 		 usingSpringWithDamping:1
	 //	  	 		  initialSpringVelocity:0
							  options:AnimationOptionsFromCurve(animationCurve)
						  animations:
	 ^{
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_txtExplain.hidden = NO;
			 [strongSelf->_txtExplain sizeToFit];
			 strongSelf->_txtExplainHeightConstraint.constant = strongSelf->_txtExplain.contentSize.height;
			 strongSelf->_btnSplitBottomConstraint.constant =  0;
			 
			 [self.view layoutIfNeeded]; // animate constraint change
		 }
		 
	 } completion:^(BOOL finished) {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
		 }
	 }];
}


@end


// MARK:  create Share document PDF/Image

@interface BackupSocialViewController_Print: BackupSocialViewController_Base

-(void)setShareID:(NSString*)shareIDIn;
-(void)createShareDocumentWithCompletionBlock:(void (^)(NSURL *_Nullable url,
																		  UIImage* _Nullable image,
																		  NSError *_Nullable error ))completionBlock;


@end

@implementation BackupSocialViewController_Print
{
	IBOutlet __weak UIView 			*_vwContainer;
	
	IBOutlet __weak UILabel 		*_lblTitle;
	IBOutlet __weak UILabel 	 	*_lblInfo;
	
	IBOutlet __weak UIImageView  *_imgAvatar;
	IBOutlet __weak UILabel    	*_lblDisplayName;
	IBOutlet __weak UIImageView	*_imgProvider;
	IBOutlet __weak UILabel     	*_lblProvider;
	
	IBOutlet __weak UIImageView 	*_imgQRCode;
	
	IBOutlet __weak UILabel 		*_lblColor;
	IBOutlet __weak RKTagsView  	*_tagView;
	IBOutlet __weak NSLayoutConstraint *_tagViewHeightConstraint;
	
	
	NSString* _shareID;
	
}


- (void)viewDidLoad {
	[super viewDidLoad];
	
	_imgAvatar.layer.cornerRadius = 50 / 2;
	_imgAvatar.clipsToBounds = YES;
	
	_tagView.lineSpacing = 4;
	_tagView.interitemSpacing = 4;
	_tagView.allowCopy = NO;
	
	_tagView.layer.cornerRadius   = 8;
	_tagView.layer.masksToBounds  = YES;
	_tagView.layer.borderColor    = [UIColor lightGrayColor].CGColor;
	_tagView.layer.borderWidth    = 1.0f;
	//	_tagView.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//
	
	_tagView.tagsEdgeInsets  = UIEdgeInsetsMake(8, 8, 8, 8);
	//	_tagView.userInteractionEnabled = NO;
	_tagView.allowCopy = YES;
	_tagView.editable = NO;
	_tagView.selectable = NO;
	_tagView.tintAdjustmentMode =  UIViewTintAdjustmentModeNormal;
	_tagView.tintColor = UIColor.darkGrayColor;
	
}

-(void)setShareID:(NSString*)shareIDIn
{
	_shareID = shareIDIn;
	
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_tagViewHeightConstraint.constant = _tagView.contentSize.height;
}

-(void) refreshViewWithCompletion:(dispatch_block_t __nullable)completionBlock;

{
	__weak typeof(self) weakSelf = self;
	
	ZDCLocalUser* localUser = self.backupSocialVC.keyBackupVC.user;
	NSDictionary <NSString*, NSNumber*>* shareNums =  self.backupSocialVC.splitKey.shareNums;
	NSNumber* shareNum = [shareNums objectForKey:_shareID];
	
	NSError* error = nil;
	NSString* languageId  = self.backupSocialVC.keyBackupVC.currentLanguageId;
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:_shareID options:0];
	NSString* shareIDb58  = [NSString base58WithData:data];
	
	_lblTitle.text = [NSString stringWithFormat:
							NSLocalizedString(@"ShareID: %@", @"ShareID: %@"),
							shareIDb58];
	
	NSData* shareKey = [self.backupSocialVC shareKeyForShareID:_shareID];
	NSArray<NSString*> * wordList  = [BIP39Mnemonic mnemonicFromData:shareKey
																			languageID:languageId
																				  error:&error];
	[_tagView removeAllTags];
	
	NSString* splitWord = [self.backupSocialVC splitNumWord];
	[_tagView	addTag:splitWord];
	
	for(NSString* tag in wordList)
		[_tagView addTag:tag];
	
	NSAttributedString* attrStr = NULL;
	OSColor* bgColor = NULL;
	[ZDCAccessCode  attributedStringFromShareNum:shareNum
													  string:&attrStr
													 bgColor:&bgColor];
	
	_lblColor.attributedText = attrStr;
	_lblColor.backgroundColor = bgColor;
	_lblColor.layer.cornerRadius   = 8;
	_lblColor.layer.masksToBounds  = YES;
	
	NSString* qrCodeString = [self.backupSocialVC shareDataStringForShareID:_shareID];
	_imgQRCode.image = [OSImage QRImageWithString:qrCodeString
													 withSize:CGSizeMake(400, 400)];
	
	NSString* displayName = localUser.displayName;
	_lblDisplayName.text = displayName;
	
	NSArray* comps = [localUser.auth0_preferredID componentsSeparatedByString:@"|"];
	NSString* provider = comps.firstObject;
	
	Auth0ProviderManager	 * providerManager= self.backupSocialVC.keyBackupVC.owner.auth0ProviderManager;
	OSImage* providerImage = [[providerManager providerIcon:Auth0ProviderIconType_Signin
															  forProvider:provider] scaledToHeight:_imgProvider.frame.size.height];
	if(providerImage)
	{
		_imgProvider.hidden = NO;
		_imgProvider.image = providerImage;
		_lblProvider.hidden = YES;
	}
	else
	{
		_imgProvider.hidden = YES;
		_lblProvider.text = provider;
		_lblProvider.hidden = NO;
	}
	
	ZDCImageManager *imageManager= self.backupSocialVC.keyBackupVC.owner.imageManager;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: imageManager.defaultUserAvatar;
		
		if (!willFetch)
		{
			if (completionBlock) {
				completionBlock();
			}
		}
	};
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: imageManager.defaultUserAvatar;
		
		if (completionBlock) {
			completionBlock();
		}
	};
	
	[imageManager fetchUserAvatar: localUser
						 preFetchBlock: preFetchBlock
						postFetchBlock: postFetchBlock];
}

-(void)createShareDocumentWithCompletionBlock:(void (^)(NSURL *_Nullable url,
																		  UIImage* _Nullable image,
																		  NSError *_Nullable error ))completionBlock
{
	
	__weak typeof(self) weakSelf = self;
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:_shareID options:0];
	NSString* shareIDb58  = [NSString base58WithData:data];
	
	NSURL *tempDir = [ZDCDirectoryManager tempDirectoryURL];
	NSURL *fileURL = [[tempDir URLByAppendingPathComponent:shareIDb58 isDirectory:NO]
							URLByAppendingPathExtension:@"pdf" ];
	
	self.view.frame = CGRectMake(0, 0, 792, 1102);
	
	NSMutableData* pdfData = NSMutableData.data;
	__block UIImage *shareImage = nil;
	
	[self refreshViewWithCompletion:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		NSError* error = NULL;
		
		[strongSelf.view setNeedsLayout];
		[strongSelf.view layoutIfNeeded];
		
		UIGraphicsBeginImageContextWithOptions(strongSelf->_vwContainer.frame.size, NO, 1.0);
		[strongSelf->_vwContainer.layer renderInContext:UIGraphicsGetCurrentContext()];
		shareImage = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		
		UIGraphicsBeginPDFContextToData(pdfData, strongSelf.view.bounds, nil);
		UIGraphicsBeginPDFPage();
		CGContextRef pdfContext = UIGraphicsGetCurrentContext();
		[strongSelf.view.layer renderInContext:pdfContext];
		UIGraphicsEndPDFContext();
		
		[pdfData writeToURL:fileURL
						options:NSDataWritingAtomic error:&error];
		
		if(completionBlock)
		{
			if(error)
				completionBlock(nil,nil,error);
			else
				completionBlock(fileURL,shareImage,error);
		}
		
	}];
}


@end

// MARK:  Send Key View - share view

@interface BackupSocialViewController_Send_ShareView : BackupSocialViewController_Base
@property (nonatomic, readwrite, getter=didSend) BOOL sent;
@property (nonatomic, readonly) NSString* shareID;


-(void)refreshView;
@end

@implementation BackupSocialViewController_Send_ShareView
{
	IBOutlet __weak RKTagsView  *       _tagView;
	IBOutlet __weak NSLayoutConstraint *_tagViewHeightConstraint;
	IBOutlet __weak UIImageView 	*_imgQRCode;
	
	IBOutlet __weak UILabel 		*_lblTitle;
	
	IBOutlet __weak UILabel 		*_lblColor;
	
	IBOutlet __weak UIButton	 	 *_btnSend;
	IBOutlet __weak UIImageView 	 *_imgStatus;
	
	NSString* _shareID;
	NSUInteger pageIndex;
	NSUInteger totalPages;
	
}

-(NSInteger)pageIndex
{
	return pageIndex;
}


- (instancetype)initWithShareID:(NSString*)shareIDIn
							 pageIndex:(NSUInteger)pageIndexIn
							totalPages:(NSUInteger)totalPagesIn
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"BackupSocial_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_Send_ShareView"];
	if (self)
	{
		_shareID = shareIDIn;
		pageIndex = pageIndexIn;
		totalPages = totalPagesIn;
		_sent = NO;
	}
	
	return self;
}



- (void)viewDidLoad {
	[super viewDidLoad];
	
	_tagView.lineSpacing = 4;
	_tagView.interitemSpacing = 4;
	_tagView.allowCopy = NO;
	
	_tagView.layer.cornerRadius   = 8;
	_tagView.layer.masksToBounds  = YES;
	_tagView.layer.borderColor    = [UIColor lightGrayColor].CGColor;
	_tagView.layer.borderWidth    = 1.0f;
	//	_tagView.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//
	
	
	_tagView.tagsEdgeInsets  = UIEdgeInsetsMake(8, 8, 8, 8);
	//	_tagView.userInteractionEnabled = NO;
	_tagView.allowCopy = YES;
	_tagView.editable = NO;
	_tagView.selectable = NO;
	_tagView.tintAdjustmentMode =  UIViewTintAdjustmentModeNormal;
	_tagView.tintColor = UIColor.darkGrayColor;
	
	NSDictionary <NSString*, NSNumber*>* shareNums =  self.backupSocialVC.splitKey.shareNums;
	NSNumber* shareNum = [shareNums objectForKey:_shareID];
	NSAttributedString* attrStr = NULL;
	OSColor* bgColor = NULL;
	[ZDCAccessCode  attributedStringFromShareNum:shareNum
													  string:&attrStr
													 bgColor:&bgColor];
	
	_lblColor.attributedText = attrStr;
	_lblColor.backgroundColor = bgColor;
	_lblColor.layer.cornerRadius   = 8;
	_lblColor.layer.masksToBounds  = YES;
	
	_lblTitle.text = [NSString stringWithFormat:
							NSLocalizedString(@"Share %ld of %ld", @"Share %ld of %ld"),
							pageIndex+1, totalPages];
}

-(void)viewWillAppear:(BOOL)animated
{
	[self viewWillDisappear:animated];
	_imgStatus.hidden = !self.didSend;
	[self refreshView];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_tagViewHeightConstraint.constant = _tagView.contentSize.height;
}

-(void)refreshStatus
{
	if(self.didSend)
	{
		[_btnSend setTitle:NSLocalizedString(@"Sent", @"Sent") forState:UIControlStateNormal];
		_btnSend.tintColor = UIColor.darkGrayColor;
		_imgStatus.hidden = NO;
	}
	else
	{
		[_btnSend setTitle:NSLocalizedString(@"Send", @"Send") forState:UIControlStateNormal];
		_btnSend.tintColor = self.view.tintColor;
		_imgStatus.hidden = YES;
	}
	[_btnSend sizeToFit];
}

-(void)refreshView
{
	__weak typeof(self) weakSelf = self;
	
	NSError* error = nil;
	NSString* languageId  = self.backupSocialVC.keyBackupVC.currentLanguageId;
	
	NSString* shareString = [self.backupSocialVC shareDataStringForShareID:_shareID];
	
	NSString* qrCodeString = [ZDCAccessCode shareDataStringFromShare:shareString
																		  localUserID:self.backupSocialVC.keyBackupVC.user.uuid
																				  error:&error];
	if(error)
	{
		[self.backupSocialVC failWithErrorMessage:error.localizedDescription];
		return;
	}
	
	/* debug */
#if DEBUG
	[ZDCAccessCode compareEncodedShareString:qrCodeString
									 shareDictString:shareString
										  localUserID:self.backupSocialVC.keyBackupVC.user.uuid
												  error:&error];
	if(error)
	{
		[self.backupSocialVC failWithErrorMessage:error.localizedDescription];
		return;
	}
	
#endif
	
	NSData* shareKey = [self.backupSocialVC shareKeyForShareID:_shareID];
	NSArray<NSString*> * wordList  = [BIP39Mnemonic mnemonicFromData:shareKey
																			languageID:languageId
																				  error:&error];
	if(error)
	{
		[self.backupSocialVC failWithErrorMessage:error.localizedDescription];
		return;
	}
	
	[_tagView removeAllTags];
	
	NSString* splitWord = [self.backupSocialVC splitNumWord];
	[_tagView	addTag:splitWord];
	
	for(NSString* tag in wordList)
		[_tagView addTag:tag];
	
	[OSImage QRImageWithString:qrCodeString
						 scaledSize:CGSizeMake(400, 400)
				  completionQueue:nil
				  completionBlock:^(OSImage * _Nullable image)
	 {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 if(strongSelf)
		 {
			 strongSelf->_imgQRCode.image = image;
		 }
	 }];
	
	[self refreshStatus];
}


- (IBAction)btnSendHit:(UIButton*)sender
{
	
	// Dont weakSelf this - we nd to retain beacuse of aync view controler behavior
	// that occurs when we create the PDF view
	
	//	__weak typeof(self) weakSelf = self;
	
	[self.backupSocialVC sendShareButtonHitForShareID:_shareID
														sourceView:sender
														sourceRect:sender.bounds
												 completionBlock:^(BOOL success, NSError* error)
	 {
		 
		 //		 __strong typeof(self) strongSelf = weakSelf;
		 //		 if(!strongSelf) return;
		 //
		 if(error)
		 {
			 if([error.domain isEqualToString:NSCocoaErrorDomain]
				 && error.code == NSUserCancelledError) {
				 
			 }
			 else {
				 
				 [self.backupSocialVC.keyBackupVC showError: NSLocalizedString(@"Sending Key Failed", @"Sending Key Failed")
																message:error.localizedDescription
													 completionBlock:nil];
			 }
		 }
		 else if(success)
		 {
			 // dont mark it if wer already succeeded.
			 if(!self.didSend)
			 {
				 [self.backupSocialVC.keyBackupVC didSendShareID:self->_shareID
															  forSplitKeyID:self.backupSocialVC.splitKeyID
															completionBlock:^{
																
																self->_sent = success;
																
																[self refreshStatus];
																[self.backupSocialVC refreshSentCount];
															}];
			 }
		 }
		 
	 }];
}

@end



// MARK:  Send Key View


@interface BackupSocialViewController_Send : BackupSocialViewController_Base
-(void)refreshSentCount;
@end

@implementation BackupSocialViewController_Send
{
	IBOutlet __weak UIView 	 	*containerView;
	IBOutlet __weak UIStackView*	_stkPages;
	IBOutlet __weak UILabel*	_lblSplitID;
	IBOutlet __weak UILabel*	_lblDescription;
	
	UIBarButtonItem* 			doneBbn;
	UIBarButtonItem* 			cancelBbn;
	UIBarButtonItem* 			globeBbn;
	
	UIPageViewController*	pageController;
	
	UIImage*						imgGreenBall;
	UIImage*						imgDarkGreenBall;
	UIImage*						imgGrayBall;
	UIImage*						imgBlackBall;
	
	BackupSocialViewController_Send_ShareView *shareView;
	
	NSArray* sharePartVCs;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	containerView.layer.cornerRadius   = 16;
	containerView.layer.masksToBounds  = YES;
	containerView.layer.borderColor    = [UIColor whiteColor].CGColor;
	containerView.layer.borderWidth    = 1.0f;
	containerView.backgroundColor      =  [UIColor colorWithWhite:.8 alpha:.4];
	
	imgGreenBall = [UIImage imageNamed:@"ball-green"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil]  ;
	
	imgDarkGreenBall = [UIImage imageNamed:@"ball-darkgreen"
											inBundle:[ZeroDarkCloud frameworkBundle]
				compatibleWithTraitCollection:nil]  ;
	
	
	imgGrayBall = [UIImage imageNamed:@"ball-gray"
									 inBundle:[ZeroDarkCloud frameworkBundle]
		 compatibleWithTraitCollection:nil]  ;
	
	imgBlackBall = [UIImage imageNamed:@"ball-black"
									  inBundle:[ZeroDarkCloud frameworkBundle]
		  compatibleWithTraitCollection:nil]  ;
}

-(NSInteger)pageIndex
{
	return kPage_Send;
}



-(void)viewWillAppear:(BOOL)animated
{
	[self viewWillDisappear:animated];
	// we do this to force the pageController to free its contents
	
	for( UIView* vw in _stkPages.arrangedSubviews)
		[_stkPages removeArrangedSubview:vw];
	
	pageController =  [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
																						 options:nil];
	
	pageController.dataSource =  (id <UIPageViewControllerDataSource>)self;
	pageController.delegate =  (id <UIPageViewControllerDelegate>)self;
	[pageController.view  setFrame:containerView.bounds];
	[containerView addSubview:pageController.view];
	
	NSDictionary* shares = [self.backupSocialVC shares];
	__block NSMutableArray* _sharePartVCs = [NSMutableArray arrayWithCapacity:shares.count];
	
	__block NSUInteger pIndex = 0;
	[shares enumerateKeysAndObjectsUsingBlock:^(NSString*  shareID, NSString*  obj, BOOL * _Nonnull stop) {
		
		BackupSocialViewController_Send_ShareView* vc
		= [[BackupSocialViewController_Send_ShareView alloc] initWithShareID:shareID
																					  pageIndex:pIndex++
																					 totalPages:shares.count];
		
		
		vc.backupSocialVC = self.backupSocialVC;
		
		[vc setSent:NO];
		[_sharePartVCs addObject:vc];
		
		UIImageView* imv = [[UIImageView alloc]initWithImage:self->imgGrayBall];
		[imv.heightAnchor constraintEqualToConstant:8].active = true;
		[imv.widthAnchor constraintEqualToConstant:8].active = true;
		[self->_stkPages addArrangedSubview:imv];
	}];
	
	sharePartVCs = _sharePartVCs;
	
	NSArray<UIViewController *> *viewControllers = @[ sharePartVCs.firstObject ];
	
	[pageController setViewControllers:viewControllers
									 direction:UIPageViewControllerNavigationDirectionForward
									  animated:YES
									completion:nil];
	
	cancelBbn = [[UIBarButtonItem alloc]
					 initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
					 target:self action:@selector(cancelButtonTapped:)];
	
	self.backupSocialVC.navigationItem.leftBarButtonItems = @[cancelBbn];
	
	doneBbn = [[UIBarButtonItem alloc]
				  initWithBarButtonSystemItem:UIBarButtonSystemItemDone
				  target:self action:@selector(doneButtonTapped:)];
	
	UIImage* globeImage = [[UIImage imageNamed:@"globe"
												 inBundle:[ZeroDarkCloud frameworkBundle]
					 compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIButton *globeButton = [[UIButton alloc]init];
	[globeButton setImage:globeImage forState:UIControlStateNormal];
	[globeButton addTarget:self
						 action:@selector(handleGlobeButton:)
			forControlEvents:UIControlEventTouchUpInside];
	UIBarButtonItem* globeButtonItem = [[UIBarButtonItem alloc] initWithCustomView:globeButton];
	[globeButtonItem.customView.widthAnchor constraintEqualToConstant:22].active = YES;
	[globeButtonItem.customView.heightAnchor constraintEqualToConstant:22].active = YES;
	globeBbn = globeButtonItem;
	
	self.backupSocialVC.navigationItem.rightBarButtonItems = @[doneBbn,globeBbn];
	doneBbn.enabled = NO;
	
	NSString* ownerID = self.backupSocialVC.splitKey.ownerID;
	NSString* comment = self.backupSocialVC.splitKey.comment;
	NSData* data = [[NSData alloc] initWithBase64EncodedString:ownerID options:0];
	NSString* splitIDb58  = [NSString base58WithData:data];
	
	_lblSplitID.text = [NSString stringWithFormat:
							  NSLocalizedString(@"Split Key ID: %@", @"Split Key ID: %@"),
							  splitIDb58];
	
	if(comment.length)
		_lblDescription.text = comment;
	else
		_lblDescription.text = @"";
	
	
	[self refreshSentCount];
}


-(void)refreshPageControl
{
	UIViewController *viewController = pageController.viewControllers.firstObject;
	NSUInteger currentIndex = ((BackupSocialViewController_Base*) viewController).pageIndex;
	
	[sharePartVCs enumerateObjectsUsingBlock:^(BackupSocialViewController_Send_ShareView* ssVc, NSUInteger idx, BOOL * _Nonnull stop) {
		
		UIImageView* imv =  [self->_stkPages.arrangedSubviews objectAtIndex:idx];
		if(idx == currentIndex)
		{
			imv.image = ssVc.sent? self->imgDarkGreenBall :self->imgBlackBall;
		}
		else if(ssVc.sent)
		{
			imv.image = self->imgGreenBall;
		}
		else
		{
			imv.image = self->imgGrayBall;
		}
	}];
	
}


- (void)handleGlobeButton:(id)sender
{
	LanguageListViewController_IOS* langVC =
	[[LanguageListViewController_IOS alloc]initWithDelegate:(id<LanguageListViewController_Delegate>) self
															languageCodes:BIP39Mnemonic.availableLanguages
															  currentCode: self.backupSocialVC.keyBackupVC.currentLanguageId
													 shouldShowAutoPick:NO];
	
	langVC.modalPresentationStyle = UIModalPresentationPopover;
	
	UIPopoverPresentationController *popover =  langVC.popoverPresentationController;
	popover.delegate = langVC;
	popover.sourceView = self.view;
	
	popover.barButtonItem = globeBbn;
	popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
	
	// we present this from the parent view, beacuse this is actually a detached view controller.
	[self.backupSocialVC presentViewController:langVC
												 animated:YES
											  completion:^{
												  //		currentVC = langVC;
												  //		[self refreshTitleBar];
											  }];
}

- (IBAction)doneButtonTapped:(id)sender
{
	
	
	[self.backupSocialVC.keyBackupVC  setBackupVerifiedForUserID:self.backupSocialVC.keyBackupVC.user.uuid
									 completionBlock:^
	 {
		 //TODO: maybe push a backup sucesss view..
		 [self.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];

	 }];
	
}

- (IBAction)cancelButtonTapped:(id)sender
{
	NSRange range = self.shareSendRange;
	if(range.location > 0)
	{
		[self warnBeforeCancel];
	}
	else
	{
		__weak typeof(self) weakSelf = self;
		
		UILabel* bottomLabel = self.backupSocialVC.bottomLabel;
		bottomLabel.hidden = YES;
		
		if(self.backupSocialVC.splitKeyID)
		{
			[self.backupSocialVC.keyBackupVC removeSplitKeyID:self.backupSocialVC.splitKeyID completionBlock:^{
				__strong typeof(self) strongSelf = weakSelf;
				
				[strongSelf.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
			}];
		}
		else
		{
			[self.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
		}
	}
}

-(void)warnBeforeCancel
{
	__weak typeof(self) weakSelf = self;
	NSRange range = self.shareSendRange;
	NSUInteger leftToSend = range.length - range.location;
	
	NSString* warningText =  [NSString stringWithFormat:
									  NSLocalizedString( @"You have %ld shares left to send, canceling will invalidate this key backup",
															  @"You have %ld shares left to send, canceling will invalidate this key backup"),
									  leftToSend];
	
	if(range.location	== range.length)
	{
		warningText =   NSLocalizedString( @"Canceling will revoke the split and invalidate any shares you sent.",
													 @"Canceling will revoke the split and invalidate any shares you sent");
		
	}
	
	UIAlertController *alertController =
	[UIAlertController alertControllerWithTitle:
	 NSLocalizedString(@"Are you sure you want to cancel?", @"Are you sure you want to cancel?")
													message:warningText
										  preferredStyle:UIAlertControllerStyleActionSheet];
	
	UIAlertAction *yesAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Invalidate the Shares", @"Invalidate the Shares")
									 style:UIAlertActionStyleDestructive
								  handler:^(UIAlertAction *action)
	 {
		 
		 __strong typeof(self) strongSelf = weakSelf;
		 
		 if(strongSelf.backupSocialVC.splitKeyID)
		 {
			 [strongSelf.backupSocialVC.keyBackupVC removeSplitKeyID:strongSelf.backupSocialVC.splitKeyID completionBlock:^{
				 __strong typeof(self) strongSelf = weakSelf;
				 
				 [strongSelf.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
			 }];
		 }
		 else
		 {
			 [strongSelf.backupSocialVC proceedToInitialView:UIPageViewControllerNavigationDirectionReverse];
		 }
	 }];
	
	UIAlertAction *continueAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Continue Sending", @"Continue Sending")
									 style:UIAlertActionStyleCancel
								  handler:^(UIAlertAction * _Nonnull action) {
									  
								  }];
	
	[alertController addAction:yesAction];
	[alertController addAction:continueAction];
	
	if([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.barButtonItem = cancelBbn;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController:alertController animated:YES
						  completion:^{
						  }];
	
}


-(void)viewDidDisappear:(BOOL)animated
{
	[self viewDidDisappear:animated];
	
	// we do this to force the pageController to free its contents
	[pageController.view removeFromSuperview];
	pageController = NULL;
	
	self.backupSocialVC.navigationItem.rightBarButtonItems = @[];
	self.backupSocialVC.navigationItem.leftBarButtonItems = @[];
	
}

-(NSRange)shareSendRange
{
	
	__block NSUInteger total = 0;
	__block NSUInteger sent = 0;
	
	[sharePartVCs enumerateObjectsUsingBlock:^(BackupSocialViewController_Send_ShareView* obj, NSUInteger idx, BOOL * _Nonnull stop) {
		
		total++;
		if(obj.sent) sent++;
	}];
	
	NSRange range = NSMakeRange(sent, total);
	return range;
}

-(void)refreshSentCount
{
	NSRange range = self.shareSendRange;
	NSUInteger leftToSend = range.length - range.location;
	UILabel* bottomLabel = self.backupSocialVC.bottomLabel;
	
	if(leftToSend > 0)
	{
		bottomLabel.text = [NSString stringWithFormat:
								  NSLocalizedString(@"%ld more parts left to send.", @"%ld more parts left to send."),
								  leftToSend];
		
		doneBbn.enabled = NO;
	}
	else
	{
		bottomLabel.text =   NSLocalizedString(@"All parts sent.", @"All parts sent");
		doneBbn.enabled = YES;
	}
	
	bottomLabel.hidden = NO;
	[self refreshPageControl];
}


// MARK:  Page View Controller Data Source - key


- (UIViewController *)viewControllerAtIndex:(NSUInteger)index
{
	__block BackupSocialViewController_Base* vc = nil;
	
	[sharePartVCs enumerateObjectsUsingBlock:^(BackupSocialViewController_Base* obj, NSUInteger idx, BOOL * _Nonnull stop) {
		
		if(obj.pageIndex == index)
		{
			vc = obj;
			*stop = YES;
		}
	}];
	
	return vc;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController
{
	NSUInteger index = ((BackupSocialViewController_Base*) viewController).pageIndex;
	
	index--;
	
	return [self viewControllerAtIndex:index];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController
{
	NSUInteger index = ((BackupSocialViewController_Base*) viewController).pageIndex;
	
	index++;
	if(index >= sharePartVCs.count) return nil;
	
	return [self viewControllerAtIndex:index];
}

- (void)pageViewController:(UIPageViewController *)pageViewController
		  didFinishAnimating:(BOOL)finished
	previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers
		 transitionCompleted:(BOOL)completed
{
	
	if(completed)
	{
		[self refreshPageControl];
	}
}


/**
 * Returns the number of pages in the UIPageViewController.
 **/

//- (NSInteger)presentationCountForPageViewController:(UIPageViewController *)pageViewController
//{
//	return sharePartVCs.count;
//}
//
///**
// * Returns the index that should be selected when the UIPageViewController first loads.
// **/
//- (NSInteger)presentationIndexForPageViewController:(UIPageViewController *)pageViewController
//{
//	return 0;
//}
//

// MARK: LanguageListViewController_Delegate

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
					  didSelectLanguage:(NSString* __nullable) languageID
{
	self.backupSocialVC.keyBackupVC.currentLanguageId = languageID;
	BackupSocialViewController_Send_ShareView* vc =  pageController.viewControllers.firstObject;
	if(vc)
		[vc refreshView];
}

@end


// MARK:  Main View


@implementation BackupSocialViewController_IOS
{
	
	IBOutlet __weak UIView        *containerView;
	IBOutlet __weak UILabel       *_lblBottom;
	
	UIPageViewController           *_pageController;
	BackupSocialViewController_Intro        *vc_Intro;
	BackupSocialViewController_Existing		 *vc_Existing;
	BackupSocialViewController_CreateSplit  *vc_CreateSplit;
	BackupSocialViewController_Send         *vc_Send;
	BackupSocialViewController_Print			 *vc_Print;
	
	BackupSocialViewController_SplitDetail	 *vc_SplitDetail;
	
	ZDCSplitKey 									* splitKey;
	NSDictionary<NSString *, NSString *> * sharesDict;				// NString version of shares
	NSDictionary<NSString *, NSData *> * 	sharesKeys;				// keys for each share/
	
	YapDatabaseConnection*						databaseConnection;	// shared UI Database connection
	
	
	BOOL isSetup;
	
	// the UIActivityViewController  <UIActivityItemSource> protocol isnt very modern.
	// we need to keep some data lying around to tell the UIActivityViewController what to share.
	NSArray* itemsToSend;
	NSString* shareIDToSend;
	
}

@synthesize keyBackupVC = keyBackupVC;

- (instancetype)initViewController
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"BackupSocial_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_IOS"];
	if (self)
	{
		isSetup = NO;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;
	
	_pageController =  [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
																						  options:nil];
	
	_pageController.dataSource =  (id <UIPageViewControllerDataSource>)self;
	_pageController.delegate =  (id <UIPageViewControllerDelegate>)self;
	
	[_pageController.view  setFrame:containerView.bounds];
	[containerView addSubview:_pageController.view];
	
	[[UIPageControl appearanceWhenContainedInInstancesOfClasses:@[self.class]]
	 setPageIndicatorTintColor: [UIColor lightGrayColor]];
	[[UIPageControl appearanceWhenContainedInInstancesOfClasses:@[self.class]]
	 setCurrentPageIndicatorTintColor: [UIColor blackColor]];
	[[UIPageControl appearanceWhenContainedInInstancesOfClasses:@[self.class]]
	 setTintColor: [UIColor blackColor]];
	
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	if(!isSetup)
	{
		self.navigationItem.title = NSLocalizedString(@"Social Key Backup", @"Social Key Backup");
		
		[self resetBackButton];
		
		UIViewController* initialVC =  [self viewControllerAtIndex:
												  self.hasExistingSplits?kPage_Existing: kPage_Intro];
		
		NSArray<UIViewController *> *viewControllers = @[ initialVC ];
		
		[_pageController setViewControllers:viewControllers
										  direction:UIPageViewControllerNavigationDirectionForward
											animated:YES
										 completion:nil];
		[self hideDots:NO];
		splitKey = NULL;
		sharesDict = NULL;
		sharesKeys = NULL;
		
		itemsToSend = nil;
		shareIDToSend = nil;
		
		_lblBottom.hidden = YES;
		
		if(vc_CreateSplit)
			[vc_CreateSplit reset];
		
		isSetup = YES;
	}
	
}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter]  removeObserver:self];
	vc_Send = NULL;
	
}


- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;
	
}

-(void)resetOnWillAppear
{
	isSetup = NO;
}

-(void)failWithErrorMessage:(NSString*)message
{
	
	__weak typeof(self) weakSelf = self;
	
	[keyBackupVC showError: NSLocalizedString(@"Key Split Failed", @"Key Split Failed")
						message:message
			 completionBlock:^{
				 
				 __strong typeof(self) strongSelf = weakSelf;
				 if(!strongSelf) return;
				 
				 [strongSelf->keyBackupVC handleFail];
			 }];
	
}


#if DEBUG
// test if the managed shares can be decrypted with the sharesKey
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

-(NSArray*) randomItemsFromArray:(NSArray*)arrayIn count:(NSUInteger)count
{
	NSMutableSet* set = NSMutableSet.set;
	
	while(set.count < count)
	{
		NSString* entry = [arrayIn objectAtIndex: (arc4random() % arrayIn.count) ];
		[set addObject:entry];
	}
	
	return set.allObjects;
}

-(BOOL)testManagedSharesWithError:(NSError *_Nullable *_Nullable) outError
{
	NSError* 			error = NULL;
	
	if(splitKey)
	{
		ZDCSharesManager * sharesManager =  self.keyBackupVC.owner.sharesManager;
		ZDCLocalUser* localUser = self.keyBackupVC.user;
		NSUInteger splitNum = splitKey.splitNum;
		
		__block NSMutableDictionary <NSString *, NSString *> * shareStringDict;				// NString version of recovered shres
		shareStringDict = NSMutableDictionary.dictionary;
		
		// test that split can be found
		ZDCSplitKey  * spKey =  [sharesManager splitKeyForLocalUserID:localUser.uuid
																		 withSplitNum:splitNum];
		if(spKey)
		{
			NSDictionary* keyDict = spKey.keyDict;
			NSDictionary *managedShares = [keyDict objectForKey:@"managedShares"];
			
			if(managedShares)
			{
				// walk through all the keys.
				
				[sharesKeys enumerateKeysAndObjectsUsingBlock:^(NSString * keyID,
																				NSData *decryptionKey,
																				BOOL * _Nonnull stop1)
				 {
					 
					 // find a managed share that it unlocks
					 [managedShares enumerateKeysAndObjectsUsingBlock:^(NSString* shareID,
																						 NSString* entry,
																						 BOOL * _Nonnull stop)
					  {
						  NSError*  decryptionError = NULL;
						  
						  NSString* shareString = [ZDCAccessCode decryptShareWithShareCodeEntry:entry
																									 decryptionKey:decryptionKey
																												error:&decryptionError];
						  if(!error && shareString)
						  {
							  [shareStringDict setObject:shareString forKey:shareID];
							  *stop = YES;
						  }
					  }];
					 
					 
				 }];
				
				if(shareStringDict.count >= splitKey.threshold)
				{
					
					//  take threshold amount of shasres randomly
					NSArray* shareIDs = [self randomItemsFromArray:shareStringDict.allKeys
																		  count:splitKey.threshold];
					
					NSMutableArray* shraresToUse = NSMutableArray.array;
					for(NSString* shareID  in shareIDs)
					{
						[shraresToUse addObject:[shareStringDict objectForKey:shareID]];
					}
					
					NSData* splitData = [NSJSONSerialization dataWithJSONObject:keyDict
																						 options:0
																							error:nil];
					
					NSString* splitString = [[NSString alloc] initWithData:splitData
																				 encoding:NSUTF8StringEncoding];
					
					NSData* accessKey = [ZDCAccessCode accessKeyDataFromSplit:splitString
																				  withShares:shraresToUse
																						 error:&error];
					if(!error && accessKey)
					{
						if(  [self.keyBackupVC.accessKeyData isEqual:accessKey])
						{
							error = NULL;
							//  success - recovered accessKey matches
						}
						else
						{
							error = [keyBackupVC errorWithDescription:@"test failed: accessKey compare fsiled." statusCode:500];
						}
					}
				}
				else
				{
					error = [keyBackupVC errorWithDescription:@"test failed: managedShares failed to decode" statusCode:500];
				}
			}
			else
			{
				error = [keyBackupVC errorWithDescription:@"test failed: managedShares not found" statusCode:500];
			}
		}
		else
		{
			error = [keyBackupVC errorWithDescription:@"test failed: split not found" statusCode:500];
		}
		
	}
	
	
	if(outError)
		*outError = error;
	
	return (error == NULL);
}

#pragma clang diagnostic pop

#endif

-(UILabel*) bottomLabel
{
	return _lblBottom;
}


-(BOOL)isKeySplit
{
	return (splitKey != NULL)  && (sharesDict != NULL);
}

-(NSString*)splitKeyID
{
	return splitKey.uuid;
}

-(NSDictionary*)shares
{
	return sharesDict;
}

-(BOOL)hasExistingSplits
{
	__block NSUInteger count = 0;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		count = [self.keyBackupVC numberOfSplitsWithTransAction:transaction];
	}];
#pragma clang diagnostic pop
	
	return count > 0;
}

-(NSString*)shareDataStringForShareID:(NSString*)shareID
{
	return [sharesDict objectForKey:shareID];
}

-(ZDCSplitKey*) splitKey
{
	return splitKey;
}

-(NSString*)splitNumWord
{
	NSString* word = NULL;
	
	NSArray<NSString*> *wordList = keyBackupVC.currentBIP39WordList;
	NSUInteger splitNum = splitKey.splitNum;
	
	if(splitNum <= wordList.count)
		word =  [wordList objectAtIndex:splitNum];
	
	return word;
}

-(NSData*)shareKeyForShareID:(NSString*)shareID
{
	return [sharesKeys objectForKey:shareID];
}

-(void)doKeySplitWithCompletionBlock:(void (^)( NSError* error))completionBlock
{
	__weak typeof(self) weakSelf = self;
	
	[keyBackupVC createSplitKeyWithTotalShares:vc_CreateSplit.totalShares
												threshold:vc_CreateSplit.requiredShares
									 shareKeyAlgorithm:kCipher_Algorithm_AES128
												  comment:vc_CreateSplit.comment
										completionQueue:nil
										completionBlock:^(ZDCSplitKey * _Nullable _splitKey,
																NSDictionary<NSString *,NSString *> * _Nullable _shareDict,
																NSDictionary<NSString *,NSData *> * _Nullable _shareKeys,
																NSError * _Nullable error) {
											
											__strong typeof(self) strongSelf = weakSelf;
											if(!strongSelf) return;
											
											strongSelf->splitKey	  = _splitKey;
											strongSelf->sharesDict = _shareDict;
											strongSelf->sharesKeys = _shareKeys;
											
											if(completionBlock)
												completionBlock(error);
										}];
}


-(void) hideDots:(BOOL)hidden
{
	for (UIScrollView *view in  _pageController.view.subviews) {
		
		if ([view isKindOfClass:[UIPageControl class]]) {
			
			view.hidden = hidden;
		}
	}
}



-(void)resetBackButton
{
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																					 style:UIBarButtonItemStylePlain
																					target:self
																					action:@selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItems = @[backItem];
	
}

-(void) proceedToInitialView:(UIPageViewControllerNavigationDirection) direction
{
	BOOL hasSplits = self.hasExistingSplits;
	
	__weak typeof(self) weakSelf = self;
	
	UIViewController* vc =  [self viewControllerAtIndex:
									 hasSplits?kPage_Existing: kPage_Intro];
	if(vc)
	{
		_lblBottom.hidden = YES;
		
		
		[_pageController setViewControllers:@[vc]
										  direction:direction
											animated:YES
										 completion:^(BOOL finished)
		 {
			 
			 __strong typeof(self) strongSelf = weakSelf;
			 if(!strongSelf) return;
			 
			 [strongSelf resetBackButton];
			 [strongSelf hideDots:hasSplits];
			 
		 }];
		
	}
}


-(void) proceedToCreateSplitView
{
	UIViewController* vc =  [self viewControllerAtIndex:kPage_CreateSplit];
	if(vc)
	{
		
		[_pageController setViewControllers:@[vc]
										  direction:UIPageViewControllerNavigationDirectionForward
											animated:YES
										 completion:nil];
	}
}


-(void) proceedToSendView
{
	UIViewController* vc =  [self viewControllerAtIndex:kPage_Send];
	if(vc)
	{
		
		[_pageController setViewControllers:@[vc]
										  direction:UIPageViewControllerNavigationDirectionForward
											animated:YES
										 completion:nil];
		
		[self hideDots:YES];
	}
}

-(void) pushSplitDetailViewForSplitID:(NSString*)splitID
{
	BackupSocialViewController_SplitDetail* vc =  (BackupSocialViewController_SplitDetail*)[self viewControllerAtIndex:kPage_SplitDetail];
	if(vc)
	{
		vc.splitID = splitID;
		[_pageController setViewControllers:@[vc]
										  direction:UIPageViewControllerNavigationDirectionForward
											animated:YES
										 completion:nil];
		
		[self hideDots:YES];
	}
}



-(void) proceedToNextViewFromView:(BackupSocialViewController_Base*)currentView
{
	NSUInteger index = currentView.pageIndex;
	index++;
	UIViewController* vc =  [self viewControllerAtIndex:index];
	
	if(vc)
	{
		[_pageController setViewControllers:@[vc]
										  direction:UIPageViewControllerNavigationDirectionForward
											animated:YES
										 completion:nil];
		
	}
}

-(void)refreshSentCount
{
	[self viewControllerAtIndex:kPage_Send];
	[vc_Send refreshSentCount];
}

-(void)sendShareButtonHitForShareID:(NSString*)shareID
								 sourceView:(UIView*)sourceView
								 sourceRect:(CGRect)sourceRect
						  completionBlock:(void (^)(BOOL didSend, NSError* error))completionBlock;

{
	NSError* error = nil;
	
	__weak typeof(self) weakSelf = self;
	
	// creata anm exportable string for
	NSData* shareData =  [ZDCAccessCode exportableShareDataFromShare:[self shareDataStringForShareID:shareID]
																		  localUserID:self.keyBackupVC.user.uuid
																				  error:&error];
	if(error)
	{
		if(completionBlock)
			completionBlock(NO, error);
		return;
	}
	
	BackupSocialViewController_Print* pVC =  (BackupSocialViewController_Print*) [self viewControllerAtIndex:kPage_Print];
	
	[pVC setShareID:shareID];
	
	[pVC createShareDocumentWithCompletionBlock:^(NSURL * pdfFileURL,
																 UIImage* image,
																 NSError * error) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		if(error)
		{
			if(completionBlock)
				completionBlock(NO, error);
		}
		else
		{
			
			[strongSelf selectSendingShareDocumentWithFile:pdfFileURL
																  image:image
															 shareData:shareData
																shareID:shareID
															sourceView:sourceView
															sourceRect:sourceRect
													 completionBlock:completionBlock];
		}
	}];
}

-(void)selectSendingShareDocumentWithFile:(NSURL*)pdfFileURL
												image:(UIImage*)image
										  shareData:(NSData*)shareData
											 shareID:(NSString*)shareID
										 sourceView:(UIView*)sourceView
										 sourceRect:(CGRect)sourceRect
								  completionBlock:(void (^)(BOOL didSend,  NSError * error))completionBlock
{
	
	UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Send Share"
																									 message:NULL
																							preferredStyle:UIAlertControllerStyleActionSheet];
	
	UIAlertAction *sendAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Send", @"Send")
									 style:UIAlertActionStyleDefault
								  handler:^(UIAlertAction * _Nonnull action) {
									  
									  [self sendShareDocumentWithActivityView:pdfFileURL
																					image:image
																			  shareData:shareData
																				 shareID:shareID
																			 sourceView:sourceView
																			 sourceRect:sourceRect
																	  completionBlock:completionBlock];
									  
								  }];
	
	UIAlertAction *sendSecureAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Send Securely", @"Send Securely")
									 style:UIAlertActionStyleDefault
								  handler:^(UIAlertAction * _Nonnull action) {
									  
									  [self sendShareDocumentWithZDC:pdfFileURL
																		image:image
																  shareData:shareData
																	 shareID:shareID
																 sourceView:sourceView
																 sourceRect:sourceRect
														  completionBlock:completionBlock];
								  }];
	
	
	UIAlertAction *cancelAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
									 style:UIAlertActionStyleCancel
								  handler:^(UIAlertAction * _Nonnull action) {
									  
									  completionBlock(NO,
															[NSError errorWithDomain:NSCocoaErrorDomain
																					  code:NSUserCancelledError
																				 userInfo:nil]);
									  
								  }];
	
#if DEBUG
	
	UIAlertAction *saveAction =
	[UIAlertAction actionWithTitle:NSLocalizedString(@"Save Split", @"Save Split")
									 style:UIAlertActionStyleDefault
								  handler:^(UIAlertAction * _Nonnull action)
	 {
		 
		 // save this split?
		 ZDCSplitKeyShare* split = [[ZDCSplitKeyShare alloc] initWithLocalUserID:self.keyBackupVC.user.uuid
																							shareData:shareData];
		 if(split)
		 {
			 
			 YapDatabaseConnection *rwConnection = self.keyBackupVC.owner.databaseManager.rwDatabaseConnection;
			 [rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				 
				 [transaction setObject:split
									  forKey:split.uuid
							  inCollection:kZDCCollection_SplitKeyShares];
				 
			 } completionBlock:^
			  {
				  completionBlock(YES, NULL);
			  }];
			 
			}
	 }];
	
	[alertController addAction:saveAction];
#endif
	
	[alertController addAction:sendSecureAction];
	[alertController addAction:sendAction];
	[alertController addAction:cancelAction];
	
	if([ZDCConstants isIPad])
	{
		alertController.popoverPresentationController.sourceView = sourceView;
		alertController.popoverPresentationController.sourceRect = sourceRect;
		alertController.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController:alertController animated:YES
						  completion:^{
						  }];
	
}



-(void)sendShareDocumentWithZDC:(NSURL*)url
								  image:(UIImage*)image
							 shareData:(NSData*)shareData
								shareID:(NSString*)shareID
							sourceView:(UIView*)sourceView
							sourceRect:(CGRect)sourceRect
					 completionBlock:(void (^)(BOOL didSend,  NSError * error))completionBlock;
{
	
	//TODO: write code to Send securely
	
 	[self.keyBackupVC showError: NSLocalizedString(@"Not Available Yet ", @"Not Available Yet")
							  message:@"Future versions of ZDC will allow you to send securely"
					completionBlock:^{
						
						
						completionBlock(NO,
											 [NSError errorWithDomain:NSCocoaErrorDomain
																		code:NSUserCancelledError
																  userInfo:nil]);
					}];
	

	
}

-(void)sendShareDocumentWithActivityView:(NSURL*)url
											  image:(UIImage*)image
										 shareData:(NSData*)shareData
											shareID:(NSString*)shareID
										sourceView:(UIView*)sourceView
										sourceRect:(CGRect)sourceRect
								 completionBlock:(void (^)(BOOL didSend,  NSError * error))completionBlock;
{
	
	__weak typeof(self) weakSelf = self;
	
	
	NSData* data = [[NSData alloc] initWithBase64EncodedString:shareID options:0];
	NSString* shareIDb58  = [NSString base58WithData:data];
	
	// the UIActivityViewController  <UIActivityItemSource> protocol isnt very modern.
	// we need to keep some data lying around to tell the UIActivityViewController what to share.
	NSArray *objectsToShare = @[self ];
	
	itemsToSend = @[image,url, shareData];
	shareIDToSend = shareIDb58;
	
#if USE_CUSTOM_ACTIVITY
	ZDCActivity*  zdcActivity = [[ZDCActivity alloc]init];
	
	UIActivityViewController *avc = [[UIActivityViewController alloc]
												initWithActivityItems:objectsToShare
												applicationActivities:  @[zdcActivity]  ];
	
#else
	UIActivityViewController *avc = [[UIActivityViewController alloc]
												initWithActivityItems:objectsToShare
												applicationActivities: nil ];
	
#endif
	
	NSMutableArray* excludeTypes = [NSMutableArray arrayWithArray:
											  @[UIActivityTypeAssignToContact,
												 UIActivityTypePostToFacebook,
												 UIActivityTypePostToTwitter,
												 UIActivityTypePostToWeibo,
												 UIActivityTypeAddToReadingList,
												 UIActivityTypePostToVimeo,
												 UIActivityTypePostToTencentWeibo,
												 ]];
	
	// prevent crashing , if the photo lib is not available dont show it
	if(!ZDCConstants.appHasPhotosPermission)
		[excludeTypes addObject: UIActivityTypeSaveToCameraRoll];
	
	avc.excludedActivityTypes = excludeTypes;
	avc.completionWithItemsHandler = ^(NSString *activityType,
												  BOOL completed,
												  NSArray *returnedItems,
												  NSError *activityError)
	{
		
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		
		strongSelf->itemsToSend = nil;
		strongSelf->shareIDToSend = nil;
		
		// delete the share file item
		[NSFileManager.defaultManager removeItemAtURL:url
															 error:nil];
		
		if(completionBlock)
		{
			
			if([activityError.domain isEqualToString:NSCocoaErrorDomain]
				&& activityError.code == NSUserCancelledError)
			{
				completed = NO;
				activityError = nil;
			}
			
			completionBlock(completed, activityError);
		}
		
	};
	
	if([ZDCConstants isIPad])
	{
		avc.popoverPresentationController.sourceView = sourceView;
		avc.popoverPresentationController.sourceRect = sourceRect;
		avc.popoverPresentationController.permittedArrowDirections  = UIPopoverArrowDirectionAny;
	}
	
	[self presentViewController:avc
							 animated:YES
						  completion:nil];
}


- (id)activityViewController:(UIActivityViewController *)activityViewController
			itemForActivityType:(NSString *)activityType
{
	__block NSURL* pdfURL = nil;
	__block UIImage *image = nil;
	__block NSData *data = nil;
	
	id returnObj = nil;
	
	[itemsToSend	enumerateObjectsUsingBlock:^(id  obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if([obj isKindOfClass:[NSURL class]])
		{
			pdfURL = (NSURL*) obj;
		}
		else if([obj isKindOfClass:[UIImage class]])
		{
			image = (UIImage*) obj;
		}
		else if([obj isKindOfClass:[NSData class]])
		{
			data = (NSData*) obj;
		}
	}];
	
	if( [activityType isEqualToString:UIActivityTypeCopyToPasteboard]
		||  [activityType isEqualToString:UIActivityTypeSaveToCameraRoll])
	{
		returnObj = image;
	}
#if USE_CUSTOM_ACTIVITY
	else if( [activityType isEqualToString:@"com.4th-a.ZeroDark.share"])
	{
		returnObj = data;
	}
#endif
	else
	{
		returnObj = pdfURL;
	}
	
	return returnObj;
}

// UIActivityViewController protocol..
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
	__block UIImage *image = nil;
	
	[itemsToSend	enumerateObjectsUsingBlock:^(id  obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if([obj isKindOfClass:[UIImage class]])
		{
			image = (UIImage*) obj;
			*stop = YES;
		}
	}];
	
	return image;
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController subjectForActivityType:(NSString *)activityType
{
	NSString* title = [NSString stringWithFormat:@"ShareID: %@" , shareIDToSend];
	return title;
	
}

// MARK:  Page View Controller Data Source


- (UIViewController *)viewControllerAtIndex:(NSUInteger)index
{
	BackupSocialViewController_Base* vc = nil;
	
	switch(index)
	{
		case kPage_Intro:
			if(!vc_Intro)
			{
				vc_Intro = [self.storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_Intro"];
			}
			vc = vc_Intro;
			break;
			
			
		case kPage_Existing:
			if(!vc_Existing)
			{
				vc_Existing = [self.storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_Existing"];
			}
			vc = vc_Existing;
			break;
			
			
		case kPage_CreateSplit:
			if(!vc_CreateSplit)
			{
				vc_CreateSplit = [self.storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_CreateSplit"];
			}
			vc = vc_CreateSplit;
			break;
			
		case kPage_Send:
			if(!vc_Send)
			{
				vc_Send = [self.storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_Send"];
			}
			vc = vc_Send;
			break;
			
		case kPage_Print:
			if(!vc_Print)
			{
				vc_Print = [self.storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_Print"];
			}
			vc = vc_Print;
			break;
			
		case kPage_SplitDetail:
			if(!vc_SplitDetail)
			{
				vc_SplitDetail = [self.storyboard instantiateViewControllerWithIdentifier:@"BackupSocialViewController_SplitDetail"];
			}
			vc = vc_SplitDetail;
			break;
			
		default:;
	}
	
	if(vc)
	{
		vc.backupSocialVC  = self;
		vc.databaseConnection = databaseConnection;
	}
	
	return vc;
}


- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController
{
	NSUInteger index = ((BackupSocialViewController_Base*) viewController).pageIndex;
	UIViewController* nextVC = NULL;
	
	switch (index) {
		case kPage_CreateSplit:
			nextVC =  [self viewControllerAtIndex:
						  self.hasExistingSplits?kPage_Existing: kPage_Intro];
			
			break;
			
		case kPage_SplitDetail:
			nextVC =  [self viewControllerAtIndex: kPage_Existing];
			
			
		default:
			break;
	}
	
	return nextVC;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController
{
	NSUInteger index = ((BackupSocialViewController_Base*) viewController).pageIndex;
	
	UIViewController* nextVC = NULL;
	
	switch (index) {
		case kPage_Intro:
		case kPage_Existing:
			nextVC = [self viewControllerAtIndex:kPage_CreateSplit];
			break;
			
		default:
			break;
	}
	
	return nextVC;
}

/**
 * Returns the number of pages in the UIPageViewController.
 **/

- (NSInteger)presentationCountForPageViewController:(UIPageViewController *)pageViewController
{
	return 2;		// we only ever have two views
}

/**
 * Returns the index that should be selected when the UIPageViewController first loads.
 **/
- (NSInteger)presentationIndexForPageViewController:(UIPageViewController *)pageViewController
{
	return 0;
}

@end

