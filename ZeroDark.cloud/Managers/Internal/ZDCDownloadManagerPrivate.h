/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCDownloadManager.h"
#import "ZeroDarkCloud.h"

@class ZDCDownloadContext;

NS_ASSUME_NONNULL_BEGIN

@interface ZDCDownloadManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (void)downloadTaskDidComplete:(NSURLSessionDownloadTask *)task
                      inSession:(NSURLSession *)session
                    withContext:(ZDCDownloadContext *)context
                          error:(NSError *)error
              downloadedFileURL:(NSURL *)downloadedFileURL;

- (ZDCDownloadTicket *)downloadUserAvatar:(NSString *)userID
                                  auth0ID:(NSString *)auth0ID
                                  fromURL:(NSURL *)url
                                   options:(nullable ZDCDownloadOptions *)options
                          completionQueue:(nullable dispatch_queue_t)completionQueue
                          completionBlock:(UserAvatarDownloadCompletionBlock)completionBlock;

@end

NS_ASSUME_NONNULL_END
