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
 * Various shared utilities between PullManager & PushManager.
 * This class is private, and is designed to be used ONLY by ZDCPullManager & ZDCPushManager.
**/
@interface ZDCNetworkTools : NSObject

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (YapDatabaseConnection *)rwConnection;
- (YapDatabaseConnection *)decryptConnection;

- (NSTimeInterval)exponentialBackoffForFailCount:(NSUInteger)failCount;

- (void)addRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID;
- (BOOL)isRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID;

- (void)handleAuthFailureForUser:(NSString *)userID withError:(NSError *)error;
- (void)handleAuthFailureForUser:(NSString *)userID
                       withError:(NSError *)error
                       pullState:(nullable ZDCPullState *)pullState;

@end

NS_ASSUME_NONNULL_END
