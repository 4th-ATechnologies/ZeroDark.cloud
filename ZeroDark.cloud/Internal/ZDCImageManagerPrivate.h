/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
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
