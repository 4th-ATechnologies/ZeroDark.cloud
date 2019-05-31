#import "ZDCSessionInfo.h"

@interface ZDCSessionInfo ()

#if TARGET_OS_IPHONE
- (instancetype)initWithForegroundSession:(AFURLSessionManager *)foregroundSession
                        backgroundSession:(AFURLSessionManager *)backgroundSession
                                    queue:(dispatch_queue_t)queue;
#else
- (instancetype)initWithSession:(AFURLSessionManager *)session
                          queue:(dispatch_queue_t)queue;
#endif

@property (nonatomic, copy, readwrite) ZDCSessionUserInfo *userInfo;

@end
