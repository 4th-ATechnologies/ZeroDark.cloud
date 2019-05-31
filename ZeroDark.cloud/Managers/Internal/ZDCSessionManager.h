#import <Foundation/Foundation.h>

#import "ZDCCloudOperation.h"
#import "ZDCSessionInfo.h"
#import "ZDCSessionUserInfo.h"

#import <AFNetworking/AFNetworking.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The SessionManager manages NSURLSession's for the framework.
 *
 * Each localUser get's their own network session.
 * On iOS, there are are actually two sessions per user: background & foreground session.
 *
 * The primary task of the SessionManager is to handle the complicated parts of NSURLSession.
 *
 * The most onerous tasks are background downloads on iOS.
 * Properly handling a background download means using a delegate-based system (instead of
 * a block-based system), and automatically persisting information about the background
 * download in case the app is terminated.
 */
@interface ZDCSessionManager : NSObject

/**
 * Returns a session for the given userID, creating it on-demand if needed.
 * Sessions are only destroyed if the user is deleted from the database.
 */
- (ZDCSessionInfo *)sessionInfoForUserID:(nonnull NSString *)userID;

/**
 * For background tasks that require the use of delegate callbacks (vs blocks),
 * this method allows you to associate a context object with a task.
 * 
 * The context object can be whatever you want, so long as it can be serialized & deserialized.
 * The context object may be stored to the database if the task is still
 * in-flight while the app is backgrounded.
 */
- (void)associateContext:(ZDCObject *)context
                withTask:(NSURLSessionTask *)task
               inSession:(NSURLSession *)session;

/**
 * If using [NSURLSession uploadTaskWithStreamedRequest:],
 * then you should use this method so we can automatically return the stream via
 * [NSURLSessionTaskDelegate URLSession:task:needNewBodyStream:].
 * 
 * Note: You should make your stream copyable (implement NSCopying protocol) in case
 * the URLSession:task:needNewBodyStream: method is invoked more than once.
 */
- (void)associateStream:(NSInputStream *)stream
               withTask:(NSURLSessionTask *)task
              inSession:(NSURLSession *)session;

@end

NS_ASSUME_NONNULL_END
