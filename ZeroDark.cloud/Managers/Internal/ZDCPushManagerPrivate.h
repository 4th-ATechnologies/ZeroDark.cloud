/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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

#if TARGET_OS_IPHONE
/** Forwarded from ZDCSessionManager. */
- (void)taskDidRestore:(NSURLSessionTask *)task
             inSession:(NSURLSession *)session
               context:(ZDCObject *)context;
#endif

/** Forwarded from ZDCPullManager */
- (void)resumeOperationsPendingPullCompletion:(NSString *)latestChangeToken
                               forLocalUserID:(NSString *)localUserID
                                       treeID:(NSString *)treeID;

@end

NS_ASSUME_NONNULL_END
