#import <Foundation/Foundation.h>
#import "ZDCSessionUserInfo.h"

#import <AFNetworking/AFNetworking.h>

/**
 * Stores the network session(s) associated with a particular user.
 *
 * Each localUser gets their own network session.
 * On iOS, there are are actually two sessions per user: background & foreground session.
 */
@interface ZDCSessionInfo : NSObject <NSCopying>

#if TARGET_OS_IPHONE
- (instancetype)initWithForegroundSession:(AFURLSessionManager *)foregroundSession
                        backgroundSession:(AFURLSessionManager *)backgroundSession
                                    queue:(dispatch_queue_t)queue;
#else
- (instancetype)initWithSession:(AFURLSessionManager *)session
                          queue:(dispatch_queue_t)queue;
#endif

#if TARGET_OS_IPHONE
@property (nonatomic, strong, readonly) AFURLSessionManager *foregroundSession;
@property (nonatomic, strong, readonly) AFURLSessionManager *backgroundSession;
#else
@property (nonatomic, strong, readonly) AFURLSessionManager *session;
#endif

@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, copy, readwrite) ZDCSessionUserInfo *userInfo;

@end
