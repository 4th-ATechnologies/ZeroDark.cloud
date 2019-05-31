/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import <UIKit/UIKit.h>
#import "AccountSetupViewController_IOS.h"

@interface SocialIdentityAuthenticationViewController_IOS : AccountSetupSubViewController_Base

@property (nonatomic, assign) NSString *URLEventQueryString;
@property (nonatomic, assign) NSString *providerName;;

-(void) continueWithURLEventQueryString:(NSString *)queryString
							   provider:(NSString*)provider;

@end

