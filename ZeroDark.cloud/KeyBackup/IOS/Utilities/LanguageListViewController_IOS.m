//
//  LanguageListViewController_IOS.m
//  ZeroDarkCloud
//
//  Created by vinnie on 3/20/19.
//

#import "LanguageListViewController_IOS.h"
#import <ZeroDarkCloud/ZeroDarkCloud.h>
#import "ZDCConstantsPrivate.h"

// Libraries
#import <QuartzCore/QuartzCore.h>


@interface LangTableCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel        *lblTitle;
@property (nonatomic, weak) IBOutlet UILabel        *lblDetail;
@property (nonatomic, copy) NSString *langIdent;
@end

@implementation LangTableCell
//@synthesize lblTitle;
//@synthesize lblDetail;
//@synthesize langIdent;

- (void)awakeFromNib {
	[super awakeFromNib];
	// Initialization code
}

@end

NSString *const kLanguageListAutoDetect = @"LanguageListViewController.auto.detect";

@implementation LanguageListViewController_IOS
{
	IBOutlet __weak UITableView             *_tblButtons;
	IBOutlet __weak NSLayoutConstraint      *_cnstTblButtonsHeight;

	NSArray <NSString *>		* languageCodes;
	NSString					* currentCode;
	NSLocale				  * currentLocale;

 }

@synthesize delegate = delegate;

- (instancetype)initWithDelegate:(nullable id <LanguageListViewController_Delegate>)inDelegate
				   languageCodes:(NSArray <NSString *>*)languageCodesIn
					 currentCode:(NSString*)currentCodeIn
			  shouldShowAutoPick:(BOOL)shouldShowAutoPick
{

	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LanguageListView_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"LanguageListView_IOS"];
	if (self)
	{
		delegate = inDelegate;
		languageCodes = [self sortLanguageCodes:languageCodesIn
						 shouldShowAutoPick:shouldShowAutoPick];
		currentCode = currentCodeIn;
 	}
	return self;
}


-(NSArray <NSString *>*)sortLanguageCodes:(NSArray <NSString *>*)codesIn
					   shouldShowAutoPick:(BOOL)shouldShowAutoPick
{
	currentLocale	 = [NSLocale autoupdatingCurrentLocale] ;
	
	NSMutableArray* codesOut =  [NSMutableArray arrayWithArray:
										  [codesIn sortedArrayUsingComparator:^NSComparisonResult(NSString * lang1, NSString * lang2)
			{
				if (@available(iOS 10.0, *)) {
					NSString* localName1 = [self->currentLocale localizedStringForLocaleIdentifier: lang1];
					NSString* localName2 = [self->currentLocale localizedStringForLocaleIdentifier: lang2];
					return [localName1 localizedCaseInsensitiveCompare: localName2];
				}
				else
				{
					NSString* localName1 = lang1;
					NSString* localName2 = lang2 ;
					return [localName1 localizedCaseInsensitiveCompare: localName2];
			}
			}]];
	
	[codesOut removeObject: [currentLocale localeIdentifier]];
	[codesOut insertObject: [currentLocale localeIdentifier] atIndex:0];
	
	if(shouldShowAutoPick)
		[codesOut insertObject:kLanguageListAutoDetect atIndex:0];
	
	return codesOut;
}

- (void)viewDidLoad {
    [super viewDidLoad];

	currentLocale	 = [NSLocale autoupdatingCurrentLocale] ;

	_tblButtons.estimatedSectionHeaderHeight = 0;
	_tblButtons.estimatedSectionFooterHeight = 0;
	_tblButtons.estimatedRowHeight = 0;
	_tblButtons.rowHeight = UITableViewAutomaticDimension;

	_tblButtons.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	_tblButtons.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblButtons.frame.size.width, 1)];
//
	_tblButtons.separatorInset = UIEdgeInsetsMake(0, 44, 0, 0); // top, left, bottom, right

}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
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


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{

	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return languageCodes.count;
}



- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	LangTableCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LangTableCell"];
	NSString* langCode = languageCodes[indexPath.row];

	if([langCode isEqualToString:kLanguageListAutoDetect])
	{
		cell.lblTitle.text = NSLocalizedString(@"Automatic", @"Automatic");
		cell.lblDetail.text = NSLocalizedString(@"Detect language from text", @"Detect language from text");
 	}
	else
	{
		NSLocale* there = [[NSLocale alloc]initWithLocaleIdentifier:langCode];

		if (@available(iOS 10.0, *)) {
			NSString* localName = [currentLocale localizedStringForLocaleIdentifier: langCode];
			NSString* translation = [there localizedStringForLocaleIdentifier: langCode];

			cell.lblTitle.text = translation;
			cell.lblDetail.text = localName;
		} else {
			// Fallback on earlier versions
		}
 	}

	cell.langIdent = langCode;

	if([currentCode isEqualToString: langCode])
	{
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}
	else
	{
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

	return cell;
}



- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSString* langCode = languageCodes[indexPath.row];
	currentCode = langCode;
	[_tblButtons reloadData];

	if ([self.delegate  respondsToSelector:@selector(languageListViewController:didSelectLanguage:)])
	{
		[self.delegate languageListViewController:self didSelectLanguage:langCode ];
	}
}

@end
