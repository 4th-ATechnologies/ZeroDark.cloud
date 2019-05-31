#import <Foundation/Foundation.h>
#import "ZDCSessionUserInfo.h"

#import <AFNetworking/AFNetworking.h>


@interface ZDCSessionInfo : NSObject <NSCopying>

#if TARGET_OS_IPHONE
@property (nonatomic, strong, readonly) AFURLSessionManager *foregroundSession;
@property (nonatomic, strong, readonly) AFURLSessionManager *backgroundSession;
#else
@property (nonatomic, strong, readonly) AFURLSessionManager *session;
#endif

@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, copy, readonly) ZDCSessionUserInfo *userInfo;

@end
