/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
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
