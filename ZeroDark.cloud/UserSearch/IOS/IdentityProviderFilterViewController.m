/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "IdentityProviderFilterViewController.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "IdentityProviderTableViewCell.h"

#import "ZDCLogging.h"

// Categories
#import "OSImage+ZeroDark.h"

// Libraries
#import <stdatomic.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation IdentityProviderFilterViewController
{
	IBOutlet UILabel             			*_lblTitle;
	IBOutlet __weak UITableView             *_tblProviders;

    ZeroDarkCloud*                           owner;
     Auth0ProviderManager*                   providerManager;
    
	NSArray*    identityProviderKeys;
	NSString* selectedProviderKey;
	
}

@synthesize delegate = delegate;

- (id)initWithDelegate:(nullable id <IdentityProviderFilterViewControllerDelegate>)inDelegate
                 owner:(ZeroDarkCloud*)inOwner;
{
    NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
    
	if ((self = [super initWithNibName:@"IdentityProviderFilterViewController" bundle:bundle]))
	{
		delegate = inDelegate;
        owner = inOwner;
        
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
    NSBundle *bundle = [ZeroDarkCloud frameworkBundle];

	[IdentityProviderTableViewCell registerViewsforTable:_tblProviders
                                                  bundle:bundle];

 	self.navigationItem.title = NSLocalizedString(@"Search by provider", @"Search by provider");

	_tblProviders.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblProviders.frame.size.width, 1)];
    
    providerManager = owner.auth0ProviderManager;

}

-(void)setProvider:(NSString *)providerIn
{
	if(providerIn)
 		selectedProviderKey = providerIn;
	else
		selectedProviderKey = @"";

	__weak typeof(self) weakSelf = self;

	NSUInteger foundIdx = [identityProviderKeys indexOfObject:selectedProviderKey];
	if(foundIdx != NSNotFound)
	{
		// deselect all others
		NSArray<NSIndexPath *>* indexPaths = _tblProviders.indexPathsForSelectedRows;
		[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * iPath, NSUInteger idx, BOOL * _Nonnull stop) {

			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) return;

			if(idx != foundIdx)
				[strongSelf->_tblProviders deselectRowAtIndexPath:iPath animated:NO];
		}];

		NSIndexPath* indexPath = [NSIndexPath indexPathForRow:foundIdx inSection:0];

		[_tblProviders selectRowAtIndexPath:indexPath
								   animated:YES
							 scrollPosition:UITableViewScrollPositionMiddle];
	}

}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	__weak typeof(self) weakSelf = self;

	[self fillIdentityProvidersWithCompletion:^{

		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;

		[CATransaction begin];
		[strongSelf->_tblProviders reloadData];

		[strongSelf->_tblProviders setEditing:YES];
		strongSelf->_tblProviders.allowsMultipleSelection = NO;
		strongSelf->_tblProviders.allowsMultipleSelectionDuringEditing = NO;

		[CATransaction setCompletionBlock:^{

			NSUInteger foundIdx = [strongSelf->identityProviderKeys indexOfObject:strongSelf->selectedProviderKey];

			if(foundIdx != NSNotFound)
			{
				NSIndexPath* indexPath = [NSIndexPath indexPathForRow:foundIdx inSection:0];
				[strongSelf->_tblProviders selectRowAtIndexPath:indexPath
													   animated:NO
												 scrollPosition:UITableViewScrollPositionMiddle];
			}

		}];
		[CATransaction commit];

 	}];
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


- (CGFloat)preferredWidth
{
  	return 220;
}

#pragma mark - Utilities

- (void)fillIdentityProvidersWithCompletion:(dispatch_block_t)completionBlock
{
	__weak typeof(self) weakSelf = self;

	[providerManager fetchSupportedProviders: dispatch_get_main_queue()
	                         completionBlock:^(NSArray<NSString *> * _Nullable providerKeys, NSError * _Nullable error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) return;

		if (error)
		{
		//	[strongSelf.accountSetupVC showError: @"Could not get list of identity providers "
		//	                             message: error.localizedDescription
		//	                      viewController: self
		//	                     completionBlock:
		//	^{
		//		[strongSelf.accountSetupVC popFromCurrentView   ];
		//	}];
		}
		
		NSMutableArray<NSString *> *supportedKeys = nil;
		
		if (providerKeys)
		{
			supportedKeys = [providerKeys mutableCopy];
			[supportedKeys insertObject:@"" atIndex:0];
		}
		
		strongSelf->identityProviderKeys = supportedKeys;

		if (completionBlock) {
			completionBlock();
		}
	}];
}

#pragma mark - Tableview

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [IdentityProviderTableViewCell heightForCell];

}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	return  identityProviderKeys.count ;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{

	IdentityProviderTableViewCell *cell = (IdentityProviderTableViewCell *)  [tv dequeueReusableCellWithIdentifier:kIdentityProviderTableCellIdentifier];

	NSString* key  = identityProviderKeys[indexPath.row];

	if([key isEqualToString:@""])
	{
		cell._imgProvider.hidden = YES;
		cell.textLabel.text = @"All Providers";
		cell.textLabel.textColor = self.view.tintColor;
		cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
		cell.textLabel.hidden = NO;
	}
	else
	{
		OSImage *image = [providerManager iconForProvider:key type:Auth0ProviderIconType_Signin];
		if(!image) image = [OSImage imageNamed:@"provider_auth0"];
		cell._imgProvider.image = [image scaledToHeight:24];
		cell._imgProvider.hidden = NO;
		cell.textLabel.hidden = YES;
	}

	cell._imgProvider.contentMode = UIViewContentModeLeft;

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

	NSArray<NSIndexPath *>* indexPaths = tableView.indexPathsForSelectedRows;
	[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * iPath, NSUInteger idx, BOOL * _Nonnull stop) {

		if(![iPath isEqual:indexPathIn])
			[tableView deselectRowAtIndexPath:iPath animated:NO];
	}];

	NSString* key  = identityProviderKeys[indexPathIn.row];
	selectedProviderKey = key;

	if([self.delegate respondsToSelector:@selector(identityProviderFilter:selectedProvider:)])
	{

		[self.delegate identityProviderFilter:self selectedProvider:
		 [selectedProviderKey isEqualToString:@""]?nil:selectedProviderKey  ];
	}
 
}


// prevent deselection - in effect we have radio buttons
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
	return nil;
}


@end
