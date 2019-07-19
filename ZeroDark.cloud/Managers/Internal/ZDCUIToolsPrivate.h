/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "ZDCUITools.h"
#import "ZeroDarkCloud.h"

@interface ZDCUITools (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;


#if TARGET_OS_IPHONE

-(void)displayPhotoAccessSettingsAlert;

-(void)displayCameraAccessSettingsAlert;

#else // OSX

#endif

@end
