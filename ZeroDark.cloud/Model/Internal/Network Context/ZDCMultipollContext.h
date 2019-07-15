/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCPollContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCMultipollContext : ZDCPollContext

#if TARGET_OS_IPHONE

@property (nonatomic, strong, readwrite) NSURL * uploadFileURL;
@property (nonatomic, assign, readwrite) BOOL deleteUploadFileURL;

#else // macOS

@property (nonatomic, strong, readwrite) NSData *uploadData;

#endif

@property (nonatomic, copy, readwrite) NSString *sha256Hash;

@end

NS_ASSUME_NONNULL_END
