/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <UIKit/UIKit.h>
@class ZeroDarkCloud;

NS_ASSUME_NONNULL_BEGIN

@interface VerifyPublicKey_IOS : UIViewController

- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
                 remoteUserID:(NSString* __nonnull)remoteUserID
                     localUserID:(NSString* __nonnull)inLocalUserID;

@end

NS_ASSUME_NONNULL_END
