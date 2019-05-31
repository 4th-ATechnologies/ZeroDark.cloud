/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
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
