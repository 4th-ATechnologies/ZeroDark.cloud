
/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "VerifyTextViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

#import "LanguageListViewController_IOS.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "RKTagsView.h"
#import "NSError+S4.h"

#import "ZDCLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)



@implementation VerifyTextViewController_IOS
{
    UIBarButtonItem*                 globeBbn;

    IBOutlet __weak UILabel*            _lblLang;
    IBOutlet __weak RKTagsView  *       _tagView;
  
    IBOutlet  __weak UIButton   *       _btnVerify;
 
    IBOutlet __weak NSLayoutConstraint *_viewBottomConstraint;
    CGFloat                             originalViewBottomConstraint;

    YapDatabaseConnection *         databaseConnection;

    NSUInteger                      requiredbip39WordCount;
    BOOL                            autoPickLanguage;
    
    NSSet*                          bip39Words;

	UISwipeGestureRecognizer*       swipeRight;
    NSLocale*                       currentLocale;
}


@synthesize keyBackupVC = keyBackupVC;

- (void)viewDidLoad {
	[super viewDidLoad];

    originalViewBottomConstraint = CGFLOAT_MAX;
    
    _tagView.lineSpacing = 4;
    _tagView.interitemSpacing = 4;
    _tagView.allowCopy = NO;
    
    _tagView.layer.cornerRadius   = 8;
    _tagView.layer.masksToBounds  = YES;
    _tagView.layer.borderColor    = [UIColor lightGrayColor].CGColor;
    _tagView.layer.borderWidth    = 1.0f;
    _tagView.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];//
    
    
    _tagView.tagsEdgeInsets  = UIEdgeInsetsMake(8, 8, 8, 8);
    //    _tagView.userInteractionEnabled = NO;
    _tagView.allowCopy = YES;
    _tagView.editable = YES;
    _tagView.selectable = YES;
    _tagView.tintAdjustmentMode =  UIViewTintAdjustmentModeNormal;
    _tagView.tintColor = self.view.tintColor;
    
   _tagView.textField.placeholder = @"Enter recovery phrase…";
   _tagView.delegate = (id <RKTagsViewDelegate>) self;
   _tagView.textField.autocorrectionType = UITextAutocorrectionTypeNo;

    _btnVerify.layer.cornerRadius    = 8.0f;
    _btnVerify.layer.masksToBounds    = YES;
    _btnVerify.layer.borderWidth      = 1.0f;
    _btnVerify.layer.borderColor      = self.view.tintColor.CGColor;

}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
    
    if(originalViewBottomConstraint == CGFLOAT_MAX)
        originalViewBottomConstraint = _viewBottomConstraint.constant;

    currentLocale     = [NSLocale autoupdatingCurrentLocale] ;

	databaseConnection = keyBackupVC.owner.databaseManager.uiDatabaseConnection;

	self.navigationItem.title = @"Verify Text Backup";

	UIImage* image = [[UIImage imageNamed:@"backarrow"
								 inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																 style:UIBarButtonItemStylePlain
																target:self
																action:@selector(handleNavigationBack:)];

	self.navigationItem.leftBarButtonItem = backItem;

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
    self.navigationItem.rightBarButtonItem = globeBbn;

	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];
 
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
 
    [BIP39Mnemonic mnemonicCountForBits:256 mnemonicCount:&requiredbip39WordCount];
    [_tagView removeAllTags];
    [self refreshCloneWordForCount:0 validWords:0];
    
    [self refreshView];

}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;

	[[NSNotificationCenter defaultCenter]  removeObserver:self];
}
 
-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[self handleNavigationBack:NULL];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}

- (void)handleGlobeButton:(id)sender
{
    LanguageListViewController_IOS* langVC =
    [[LanguageListViewController_IOS alloc]initWithDelegate:(id<LanguageListViewController_Delegate>) self
                                              languageCodes:BIP39Mnemonic.availableLanguages
                                                currentCode:keyBackupVC.currentLanguageId
                                         shouldShowAutoPick:NO];
    
    langVC.modalPresentationStyle = UIModalPresentationPopover;
    
    UIPopoverPresentationController *popover =  langVC.popoverPresentationController;
    popover.delegate = langVC;
    popover.sourceView = self.view;
    
    popover.barButtonItem = globeBbn;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    
    [self presentViewController:langVC animated:YES completion:^{
        //        currentVC = langVC;
        //        [self refreshTitleBar];
    }];
}



- (BOOL)canPopViewControllerViaPanGesture:(KeyBackupViewController_IOS *)sender
{
	return NO;

}



#pragma mark - Actions
- (IBAction)VerifyButtonTapped:(id)sender
{
    __weak typeof(self) weakSelf = self;
    NSMutableArray* normalizedTagArray = [NSMutableArray array];
    
    for(NSString* tag in _tagView.tags)
    {
        NSArray* comps = [tag componentsSeparatedByString:@"\n"];
        NSString* normalizedTag = [[comps[0] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [normalizedTagArray addObject:normalizedTag];
    }
    
    if( [normalizedTagArray count] ==  requiredbip39WordCount)
    {
        ZDCLocalUser* localUser = keyBackupVC.user;
        
        NSError* error = NULL;
        
        NSData* accessKey = [BIP39Mnemonic keyFromMnemonic:normalizedTagArray
                                                passphrase:localUser.syncedSalt
                                                languageID:keyBackupVC.currentLanguageId
                                                     error:&error];
        if(!error
           && accessKey
           && [accessKey isEqual:keyBackupVC.accessKeyData])
        {
             // good key
            [keyBackupVC  setBackupVerifiedForUserID:keyBackupVC.user.uuid
                                     completionBlock:^
             {
                 __strong typeof(self) ss = weakSelf;
                 if (!ss) return;
                 [ss->keyBackupVC pushBackupSuccess];
             }];
        }
        else
        {
            // BAD KEY
        }
    }
}

#pragma mark - refresh

-(void) refreshView
{
	if (@available(iOS 10.0, *)) {
		NSString* localName = [currentLocale localizedStringForLocaleIdentifier: keyBackupVC.currentLanguageId];
		
		_lblLang.text = localName;
	} else {
		// Fallback on earlier versions
	}
}


-(void)refreshCloneWordForCount:(NSUInteger)totalWords
                     validWords:(NSUInteger)validWords
{
    _btnVerify.enabled = NO;
    
    if(totalWords == 0)
    {
        _tagView.textField.placeholder = [NSString stringWithFormat:
                                          NSLocalizedString(@"Enter %ld words", @"Enter %ld words"),  requiredbip39WordCount];
    }
    else if(totalWords < requiredbip39WordCount) {
        
        _tagView.textField.placeholder = [NSString stringWithFormat:
                                          NSLocalizedString(@"%ld more  words needed",@"%ld more  words needed"),
                                          requiredbip39WordCount - totalWords];
    }
    else if(totalWords > requiredbip39WordCount) {
        _tagView.textField.placeholder =NSLocalizedString(@"Too many words…",@"Too many words…");
    }
    else if( validWords == requiredbip39WordCount){
        // correct number of valid  words
        _tagView.textField.placeholder  = @"";
		 _btnVerify.enabled = YES;
    }
    
}

#pragma mark - RKTagsViewDelegate

- (NSString *)languageForString:(NSString *) text{
    
    NSString* langString = (NSString *) CFBridgingRelease(CFStringTokenizerCopyBestStringLanguage((CFStringRef)text, CFRangeMake(0, text.length)));
    
    return langString;
}

-(void)updateTagsToLanguageID:(NSString*)newLangID
{
    
    keyBackupVC.currentLanguageId = newLangID;
    bip39Words = [NSSet setWithArray:[BIP39Mnemonic wordListForLanguageID:keyBackupVC.currentLanguageId
                                                                    error:nil]];
    NSMutableArray* newTagArray = [NSMutableArray array];
    
    for(NSString* tag in _tagView.tags)
    {
        NSString* newTag = nil;
        
        NSArray* comps = [tag componentsSeparatedByString:@"\n"];
        NSString* normalizedTag = [[comps[0] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if(normalizedTag.length == 0) continue;
        
        if([bip39Words containsObject: normalizedTag ])
        {
            newTag = normalizedTag;
        }
        else if( normalizedTag.length >4)
        {
            normalizedTag = [normalizedTag substringWithRange:NSMakeRange(0, 4)];
        }
        
        NSString* mnemonic = [BIP39Mnemonic matchingMnemonicForString:normalizedTag
                                                           languageID:keyBackupVC.currentLanguageId
                                                                error:nil];
        if(mnemonic.length > 0)
        {
            newTag = mnemonic;
        }
        
        if(newTag == nil)
        {
            newTag = [NSString stringWithFormat:@"%@%@",normalizedTag, kRKTagsColorSuffix_Red];
        }
        
        [newTagArray addObject:newTag];
        
    }
    
    [_tagView removeAllTags];
    
    for(NSString* tag in newTagArray)
        [_tagView addTag:tag];
    
}

- (void)tagsViewDidChange:(RKTagsView *)tagsView
{
    NSMutableArray* newTagArray = [NSMutableArray array];
    NSUInteger bip39WordCount = 0;
    
    if(autoPickLanguage)
    {
        // Attempt to auto pick language
        
        NSString* str = [_tagView.tags componentsJoinedByString:@" "];
        NSString* lang = [self languageForString:str];
        if(lang)
        {
            NSLocale *newLocale = [NSLocale localeWithLocaleIdentifier:lang];
            if(newLocale)
            {
                NSString* newLangID = [BIP39Mnemonic languageIDForLocaleIdentifier: newLocale.localeIdentifier];
                if(newLangID && ![newLangID isEqualToString:keyBackupVC.currentLanguageId])
                {
                    [self updateTagsToLanguageID:newLangID];
                }
            }
        }
    }
    
    for(NSString* tag in _tagView.tags)
    {
        NSString* newTag = nil;
        
        NSArray* comps = [tag componentsSeparatedByString:@"\n"];
        NSString* normalizedTag = [[comps[0] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if(normalizedTag.length == 0) continue;
        
        if([bip39Words containsObject: normalizedTag ])
        {
            newTag = normalizedTag;
        }
        
        NSString* mnemonic = [BIP39Mnemonic matchingMnemonicForString:normalizedTag
                                                           languageID:keyBackupVC.currentLanguageId
                                                                error:nil];
        if(mnemonic.length > 0)
        {
            newTag = mnemonic;
        }
        
        if(newTag == nil)
        {
            newTag = [NSString stringWithFormat:@"%@%@",normalizedTag, kRKTagsColorSuffix_Red];
        }
        else
        {
            bip39WordCount = bip39WordCount+1;
        }
        [newTagArray addObject:newTag];
        
    }
    [_tagView removeAllTags];
    
    for(NSString* tag in newTagArray)
        [_tagView addTag:tag];
    
    [self refreshCloneWordForCount:newTagArray.count
                        validWords:bip39WordCount];
}

- (BOOL)tagsView:(RKTagsView *)tagsView shouldAddTagWithText:(NSString *)text
{
    BOOL shouldAddTag = YES;
    return shouldAddTag;
}

- (void)tagsViewDidGetNewline:(RKTagsView *)tagsView
{
    if(_btnVerify.enabled)
    {
 //       [self cloneWordsVerifyButtonTapped:self];
    }
}


#pragma mark - Keyboard show/Hide Notifications


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
//    CGPoint containerPoint = [_vwCloneContainer convertPoint:locationPoint fromView:self.view];
//
//    if (![_vwCloneContainer pointInside:containerPoint withEvent:event])
//    {
//        [super touchesBegan:touches withEvent:event];
//    }
//    else
//    {
        if(!CGRectContainsPoint(_tagView.frame, locationPoint))
        {
            [_tagView  endEditing:YES];
            
        }
//    }
    
    
}

static inline UIViewAnimationOptions AnimationOptionsFromCurve(UIViewAnimationCurve curve)
{
    UIViewAnimationOptions opt = (UIViewAnimationOptions)curve;
    return opt << 16;
}

- (void)keyboardWillShow:(NSNotification *)notification
{
	__weak typeof(self) weakSelf = self;
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
		  if (!strongSelf) return;

         strongSelf->_viewBottomConstraint.constant =  (keyboardHeight + 8);
         [strongSelf.view layoutIfNeeded]; // animate constraint change
//         currentCloneView.frame = _vwCloneContainer.bounds;
         
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
    
    _viewBottomConstraint.constant = originalViewBottomConstraint;
    [self.view layoutIfNeeded]; // animate constraint change
    
//    [UIView animateWithDuration:animationDuration
//                          delay:0.1
//                        options:AnimationOptionsFromCurve(animationCurve)
//                     animations:
//     ^{
//         currentCloneView.frame = _vwCloneContainer.bounds;
//
//     } completion:^(BOOL finished) {
//
//         // Nothing to do
//     }];
}


#pragma mark - LanguageListViewController_Delegate

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
                 didSelectLanguage:(NSString* __nullable) languageID
{
    
    if([languageID isEqualToString:kLanguageListAutoDetect])
    {
        autoPickLanguage = YES;
      }
    else
    {
        autoPickLanguage = NO;
           keyBackupVC.currentLanguageId = languageID;
    }
    [self refreshView];

    
}

@end
