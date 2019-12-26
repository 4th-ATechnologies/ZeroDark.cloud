/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/


#import <UIKit/UIKit.h>
#import "ZDCUITools.h"

@class ZeroDarkCloud;

NS_ASSUME_NONNULL_BEGIN

@interface LocalUserSettingsViewController_IOS : UIViewController

- (instancetype)initWithOwner:(ZeroDarkCloud *)zdc
                  localUserID:(NSString *)localUserID;

@property (nonatomic, strong, readonly) ZeroDarkCloud *zdc;
@property (nonatomic, copy, readonly) NSString *localUserID;

@end

NS_ASSUME_NONNULL_END
