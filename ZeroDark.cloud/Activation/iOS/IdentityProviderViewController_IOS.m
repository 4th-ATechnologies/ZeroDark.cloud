/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "IdentityProviderViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"

#import "ZDCLogging.h"

#import "Auth0ProviderManager.h"
#import "IdentityProviderTableViewCell.h"

// Categories
#import "OSImage+ZeroDark.h"

// Libraries
#import <stdatomic.h>

// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation IdentityProviderViewController_IOS
{
    IBOutlet __weak UIView              *_viewTableContainer;
    IBOutlet __weak NSLayoutConstraint  *_TableContainerBottomConstraint;
    IBOutlet __weak UIView              *_viewAuth0ButtonContainer;
    IBOutlet __weak UITableView         *_tblProviders;
    
    CGFloat  originalTableContainerBottomConstraint;
    
    NSArray*    identityProviderKeys;
    NSDictionary* selectedProvider;

	Auth0ProviderManager * providerManager;
}

@synthesize accountSetupVC = accountSetupVC;
@synthesize idenitityMode = idenitityMode;



- (void)viewDidLoad {
    [super viewDidLoad];

	// figure out how to get this..
	providerManager = accountSetupVC.zdc.auth0ProviderManager;

    originalTableContainerBottomConstraint = _TableContainerBottomConstraint.constant;
    
    void (^PrepContainer)(UIView *) = ^(UIView *container){
        container.layer.cornerRadius   = 16;
        container.layer.masksToBounds  = YES;
        container.layer.borderColor    = [UIColor whiteColor].CGColor;
        container.layer.borderWidth    = 1.0f;
        container.backgroundColor      = [UIColor colorWithWhite:.8 alpha:.4];
    };
    PrepContainer(_viewTableContainer);

//    PrepContainer(_viewAuth0ButtonContainer);
    _viewAuth0ButtonContainer.layer.cornerRadius = 16;
    _viewAuth0ButtonContainer.layer.masksToBounds  = YES;
    _viewAuth0ButtonContainer.layer.borderColor    = [UIColor blackColor].CGColor;
    _viewAuth0ButtonContainer.layer.borderWidth    = 4.0f;
    _viewAuth0ButtonContainer.backgroundColor  = [UIColor whiteColor];

	[IdentityProviderTableViewCell registerViewsforTable:_tblProviders
												  bundle:[ZeroDarkCloud frameworkBundle]];
 
    _tblProviders.backgroundColor = [UIColor clearColor];
    _tblProviders.backgroundView.backgroundColor =  [UIColor clearColor];
	
	_tblProviders.scrollIndicatorInsets = UIEdgeInsetsMake(6, 0, 6, 4);
	_tblProviders.indicatorStyle = UIScrollViewIndicatorStyleDefault;
 }

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(providersUpdated:)
												 name:Auth0ProviderManagerDidUpdateNotification
											   object:nil];

    if(accountSetupVC.setupMode ==  AccountSetupMode_Trial)
    {
        _viewAuth0ButtonContainer.hidden = NO;
        _TableContainerBottomConstraint.constant = originalTableContainerBottomConstraint;
    }
    else
    {
        _viewAuth0ButtonContainer.hidden = YES;
        _TableContainerBottomConstraint.constant = 0;
    }
    
    accountSetupVC.btnBack.hidden  = (accountSetupVC.identityMode == IdenititySelectionMode_ReauthorizeAccount );
    
   }


-(void) viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[accountSetupVC setHelpButtonHidden:NO];
	
	__weak typeof(self) weakSelf = self;
	
	if(!providerManager.isUpdated)
	{
		[accountSetupVC showWait: NSLocalizedString(@"Please Wait…", @"Please Wait…")
							  message: NSLocalizedString(@"Updating providers", @"Updating providers")
					completionBlock: nil];
	}
	
	[self fillIdentityProvidersWithCompletion:^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		if( strongSelf->providerManager.isUpdated)
		{
			[strongSelf->_tblProviders reloadData];
			[strongSelf->accountSetupVC cancelWait];
		}
	}];
}

-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
    [accountSetupVC cancelWait];
}

- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
    return YES;
    
}

- (void)providersUpdated:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	NSAssert([NSThread isMainThread], @"Cannot perform UI changes on non-main thread.");

	__weak typeof(self) weakSelf = self;

	[self fillIdentityProvidersWithCompletion:^{

		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		[strongSelf->accountSetupVC cancelWait];
		[strongSelf->_tblProviders reloadData];
		//	[_tblProviders scrollRowToVisible:0];

		strongSelf->selectedProvider = nil;
	}];
}


#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void) fillIdentityProvidersWithCompletion:(dispatch_block_t)completionBlock
{
	__weak typeof(self) weakSelf = self;

	[providerManager fetchSupportedProvidersWithCompletion:^(NSArray<NSString *> * _Nullable providerKeys, NSError * _Nullable error)
	 {
		 NSMutableArray* supportedKeys = nil;

		 __strong typeof(self) strongSelf = weakSelf;

		 if(strongSelf)
		 {
			 if(error)
			 {

				 [strongSelf.accountSetupVC showError:@"Could not get list of identity providers "
											  message:error.localizedDescription
									   viewController:self
									  completionBlock:^{

										  [strongSelf.accountSetupVC popFromCurrentView   ];
									  }];
			 }

			 if(providerKeys)
			 {
				 supportedKeys = [NSMutableArray arrayWithArray:providerKeys];

				 // if we are in trial mode we dont show the auth0 login
				 // but in social mode we fall through.
				 if(   strongSelf.accountSetupVC.setupMode ==  AccountSetupMode_Trial
					|| strongSelf.accountSetupVC.identityMode == IdenititySelectionMode_ExistingAccount)
				 {
					 [supportedKeys removeObject:@"auth0"];
				 }

			 }
			 strongSelf->identityProviderKeys = supportedKeys;

		 }

		 if(completionBlock)
			 completionBlock();
	 }];
}


#pragma mark - host table
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
	OSImage* image = [providerManager providerIcon:Auth0ProviderIconType_Signin forProvider:key];
    if(!image) image = [OSImage imageNamed:@"provider_auth0"];

    cell.backgroundColor     = [UIColor colorWithWhite:1 alpha:1];
    
    cell.layer.cornerRadius = 16.0;
    cell.layer.borderColor = [UIColor blackColor].CGColor;
    cell.layer.borderWidth = 4.0f;
    cell.layer.masksToBounds = YES;
  
    cell._imgProvider.image = [image scaledToHeight:32];
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSString* key  = identityProviderKeys[indexPath.row];
	NSDictionary* identDict = [providerManager.providersInfo objectForKey:key];

	if(identDict)
	{
		self.accountSetupVC.selectedProvider = identDict;

		Auth0ProviderType strategyType = [identDict[kAuth0ProviderInfo_Key_Type] integerValue];

		if(strategyType == Auth0ProviderType_Database)
		{
			[self.accountSetupVC pushDataBaseAuthenticate];
		}
		else  if(strategyType == Auth0ProviderType_Social)
		{
			[self.accountSetupVC pushSocialAuthenticate];
		}
	}
	else
	{
		self.accountSetupVC.selectedProvider = nil;

	}
};

#pragma mark - Actions

-(IBAction) btnCreateS4AccountClicked:(id) sender
{
    [self.accountSetupVC pushDataBaseAccountCreate];
}


@end
