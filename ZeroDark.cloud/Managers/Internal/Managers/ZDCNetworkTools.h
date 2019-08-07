/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZeroDarkCloud.h"
#import "ZDCPullState.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Various shared utilities for networking.
 * Primarily used by the PullManager & PushManager.
**/
@interface ZDCNetworkTools : NSObject

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

#pragma mark PushManager & PullManager

- (YapDatabaseConnection *)rwConnection;
- (YapDatabaseConnection *)decryptConnection;

- (NSTimeInterval)exponentialBackoffForFailCount:(NSUInteger)failCount;

- (void)addRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID;
- (BOOL)isRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID;

- (void)handleAuthFailureForUser:(NSString *)userID withError:(NSError *)error;
- (void)handleAuthFailureForUser:(NSString *)userID
                       withError:(NSError *)error
                       pullState:(nullable ZDCPullState *)pullState;

#pragma mark General

/**
 * Downloads the file into memory.
 *
 * If canBackground is set to YES, then on iOS a download task will be used,
 * and the downloaded file will be automatically read into memory for the completionBlock.
 *
 * The 'responseObject' will be the downloaded data (on sucess).
 */
- (void)downloadDataAtPath:(NSString *)remotePath
                  inBucket:(NSString *)bucket
                    region:(AWSRegion)region
                  withETag:(nullable NSString *)eTag
                     range:(nullable NSValue *)range
               requesterID:(NSString *)localUserID
             canBackground:(BOOL)canBackground
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completion;

/**
 * Downloads a generic URL using an ephemeral session.
 */
- (void)downloadFileFromURL:(NSURL *)sourceURL
               andSaveToURL:(NSURL *)destinationURL
                       eTag:(nullable NSString *)eTag
            completionQueue:(nullable dispatch_queue_t)completionQueue
            completionBlock:(void (^)(NSString *_Nullable eTag, NSError *_Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
