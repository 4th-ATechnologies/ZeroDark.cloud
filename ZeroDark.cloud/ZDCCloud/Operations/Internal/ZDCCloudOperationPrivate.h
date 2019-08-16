/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCCloudOperation.h"

#import "ZDCCloudOperation_MultipartInfo.h"
#import "ZDCCloudOperation_EphemeralInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCCloudOperation ()

/**
 * Encapsulates ephemeral information about the operation that isn't stored to disk.
 *
 * This includes information used by the PushManager while the application is running.
 * It is for use solely by the ZeroDarkCloud framework.
 */
@property (nonatomic, strong, readonly) ZDCCloudOperation_EphemeralInfo *ephemeralInfo;

/**
 * Encapsulates information about a multipart operation.
 *
 * Multipart operations are used when the file/data being uploaded is above a size threshold.
 * When this scenario occurs, the data is split into multiple files during the upload,
 * in order to facilitate resuming long upload operations which may get interrupted.
 *
 * This includes information used by the PushManager while the application is running.
 * It is for use solely by the ZeroDarkCloud framework.
 */
@property (nonatomic, copy, readwrite, nullable) ZDCCloudOperation_MultipartInfo *multipartInfo;

@end

NS_ASSUME_NONNULL_END
