/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <UIKit/UIKit.h>
#import "AccountSetupViewController_IOS.h"

@interface SocialIdentityAuthenticationViewController_IOS : AccountSetupSubViewController_Base

@property (nonatomic, assign) NSString *URLEventQueryString;
@property (nonatomic, assign) NSString *providerName;

- (void)continueWithURLEventQueryString:(NSString *)queryString
                               provider:(NSString *)provider;

@end

