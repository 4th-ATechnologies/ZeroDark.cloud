/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserIdentity.h"

@interface ZDCUserIdentity ()

@property (nonatomic, readwrite, copy) NSDictionary *profileData;
@property (nonatomic, readwrite, assign) BOOL isOwnerPreferredIdentity;

@end
