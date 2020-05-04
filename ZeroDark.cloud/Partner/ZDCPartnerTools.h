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

/**
 * Represents the nature of the error that occurred when attempting to create the localUser.
 */
typedef NS_ENUM(NSInteger, PartnerErrorCode) {
	/**
	 * One or more of the parameters you passed in invalid.
	 * More details are provided within `error.userInfo[NSLocalizedDescriptionKey]`.
	 */
	PartnerErrorCode_InvalidParameter,
	
	/**
	 * A network error occurred, possibly because of an Internet disconnection.
	 */
	PartnerErrorCode_NetworkError,
	
	/**
	 * The server returned an unrecognized response or status code.
	 * More details are provided within `error.userInfo[NSLocalizedDescriptionKey]`.
	 */
	PartnerErrorCode_ServerError,
	
	/**
	 * An error occurred while performing a cryptographic operation.
	 * More details are provided within `error.userInfo[NSLocalizedDescriptionKey]`.
	 */
	PartnerErrorCode_CryptoError
};

/**
 * Provides various tools needed by partners to interact with the ZeroDark cloud.
 */
@interface ZDCPartnerTools : NSObject

/**
 * Partners provide their own authentication solution.
 * (As opposed to Friends, which use the co-op provided authentication built into this framework.)
 *
 * After your server has invoked the ZeroDark API to manually create a user,
 * the server will return information that can be used to create a `ZDCPartnerUserInfo` instance.
 * That info can then be used to create the user here.
 *
 * For more info, see the [docs](https://zerodarkcloud.readthedocs.io/en/latest/client/partners/).
 *
 * If an error occurs, the error code will be one of the PartnerErrorCode enum values.
 */
- (void)createLocalUser:(ZDCPartnerUserInfo *)info
        completionQueue:(nullable dispatch_queue_t)completionQueue
        completionBlock:(void (^)(ZDCLocalUser *_Nullable, NSError *_Nullable))completionBlock;

@end

NS_ASSUME_NONNULL_END
