/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "AddIdentitityProviderViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"

#import "ZDCLogging.h"

#import "SocialIDUITableViewCell.h"

#import "Auth0ProviderManager.h"
#import "Auth0Utilities.h"
#import "IdentityProviderTableViewCell.h"
#import "SCLAlertView.h"
#import "SCLAlertViewStyleKit.h"

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

 @implementation AddIdentitityProviderViewController_IOS
{
	IBOutlet __weak UITableView   	 *_tblProviders;

	Auth0ProviderManager*		providerManager;
	NSArray*    				identityProviderKeys;
	NSDictionary* 				selectedProvider;
}

@synthesize accountSetupVC = accountSetupVC;



- (void)viewDidLoad {
	[super viewDidLoad];
	self.automaticallyAdjustsScrollViewInsets = NO;
	
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	
	[IdentityProviderTableViewCell registerViewsforTable:_tblProviders
																 bundle:bundle];

}

-(void) viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	providerManager = accountSetupVC.owner.auth0ProviderManager;

	[self fillIdentityProvidersWithCompletion:^{
		[self->_tblProviders reloadData];
	}];

}

-(void) viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if(self.accountSetupVC.identityMode == IdenititySelectionMode_ReauthorizeAccount)
	{
		self.navigationItem.title = @"Login To Account";
	}
	else
	{
		self.navigationItem.title = @"Add Identitiy";

	}


}


- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return NO;

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
		 if (strongSelf == nil) return;

		 if(providerKeys)
		 {
			 supportedKeys = [NSMutableArray arrayWithArray:providerKeys];

			 // if we are in trial mode we dont show the auth0 login
			 // but in social mode we fall through.
			 if(   strongSelf->accountSetupVC.setupMode ==  AccountSetupMode_Trial)
			 {
				 [supportedKeys removeObject:@"auth0"];
			 }

		 }
		 strongSelf->identityProviderKeys = supportedKeys;

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

	cell._imgProvider.image = [image scaledToHeight:32];
	cell._imgProvider.contentMode =  UIViewContentModeLeft;

	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSString* key  = identityProviderKeys[indexPath.row];
	NSDictionary* identDict = providerManager.providersInfo[key];

	if(identDict)
	{
		self.accountSetupVC.selectedProvider = identDict;

		Auth0ProviderType strategyType = [identDict[kAuth0ProviderInfo_Key_Type] integerValue];

		if(strategyType == Auth0ProviderType_Database)
		{
			if(self.accountSetupVC.identityMode == IdenititySelectionMode_ReauthorizeAccount)
			{
				[self.accountSetupVC pushDataBaseAccountLogin:accountSetupVC.user.uuid
									 withNavigationController:self.navigationController];
			}
			else
			{
				[self.accountSetupVC pushDataBaseAccountCreate:accountSetupVC.user.uuid
									  withNavigationController:self.navigationController];
			}

		}
		else  if(strategyType == Auth0ProviderType_Social)
		{
			[self.accountSetupVC pushSocialAuthenticate:accountSetupVC.user.uuid
											   provider:identDict
							   withNavigationController:self.navigationController];;
		}
	}
	else
	{
		self.accountSetupVC.selectedProvider = nil;

	}
};


@end

