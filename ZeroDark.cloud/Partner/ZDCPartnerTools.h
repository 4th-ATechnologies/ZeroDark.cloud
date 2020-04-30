/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCLocalUser.h"
#import "ZDCPartnerUserInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPartnerTools : NSObject

/**
 * Partners provide their own authentication solution.
 * (As opposed to Friends, which use the co-op provided authentication built into this framework.)
 *
 * After your server has invoked the ZeroDark API to manually create a user,
 * the server will return information that can be used to create a `ZDCPartnerUserInfo` instance.
 * That info can then be used to create the user here.
 */
- (void)createLocalUser:(ZDCPartnerUserInfo *)info
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(ZDCLocalUser *_Nullable, NSError *_Nullable))completionBlock;

@end

NS_ASSUME_NONNULL_END
