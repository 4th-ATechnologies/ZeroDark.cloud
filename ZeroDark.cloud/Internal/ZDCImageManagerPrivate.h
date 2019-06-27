/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCImageManager.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCImageManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (nullable ZDCDownloadTicket *)
        fetchUserAvatar:(NSString *)userID
                auth0ID:(NSString *)auth0ID
                fromURL:(NSURL *)url
                options:(nullable ZDCDownloadOptions *)options
           processingID:(nullable NSString *)processingID
        processingBlock:(ZDCImageProcessingBlock)imageProcessingBlock
          preFetchBlock:(void(^)(OSImage *_Nullable image))preFetchBlock
         postFetchBlock:(void(^)(OSImage *_Nullable image, NSError *_Nullable error))postFetchBlock;

@end

NS_ASSUME_NONNULL_END
