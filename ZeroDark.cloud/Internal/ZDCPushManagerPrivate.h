/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCPushManager.h"
#import "ZeroDarkCloud.h"

#import "ZDCPollContext.h"
#import "ZDCPushInfo.h"
#import "ZDCTaskContext.h"
#import "ZDCTouchContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPushManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/** Forwarded from ZeroDarkCloud. */
- (void)processPushNotification:(ZDCPushInfo *)pushInfo;

/** Forwarded from ZDCSessionManager. */
- (void)downloadTaskDidComplete:(NSURLSessionDownloadTask *)task
                      inSession:(NSURLSession *)session
                      withError:(NSError *)error
                        context:(ZDCObject *)context
              downloadedFileURL:(NSURL *)downloadedFileURL;

/** Forwarded from ZDCSessionManager. */
- (void)taskDidComplete:(NSURLSessionTask *)task
              inSession:(NSURLSession *)session
              withError:(nullable NSError *)error
                context:(ZDCObject *)context;

/** Forwarded from ZDCPullManager */
- (void)resumeOperationsPendingPullCompletion:(NSString *)latestChangeToken
                               forLocalUserID:(NSString *)localUserID
                                       zAppID:(NSString *)zAppID;

@end

NS_ASSUME_NONNULL_END
