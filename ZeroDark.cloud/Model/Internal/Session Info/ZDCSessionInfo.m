#import "ZDCSessionInfo.h"


@implementation ZDCSessionInfo

#if TARGET_OS_IPHONE
@synthesize foregroundSession = foregroundSession;
@synthesize backgroundSession = backgroundSession;
#else
@synthesize session = session;
#endif

@synthesize queue = queue;
@synthesize userInfo = userInfo;

#if TARGET_OS_IPHONE
- (instancetype)initWithForegroundSession:(AFURLSessionManager *)inForegroundSession
                        backgroundSession:(AFURLSessionManager *)inBackgroundSession
                                    queue:(dispatch_queue_t)inQueue
{
	if ((self = [super init]))
	{
		foregroundSession = inForegroundSession;
		backgroundSession = inBackgroundSession;
		queue = inQueue;
	}
	return self;
}
#else
- (instancetype)initWithSession:(AFURLSessionManager *)inSession
                          queue:(dispatch_queue_t)inQueue
{
	if ((self = [super init]))
	{
		session = inSession;
		queue = inQueue;
	}
	return self;
}
#endif

- (instancetype)copyWithZone:(NSZone *)zone
{
	ZDCSessionInfo *copy = [[ZDCSessionInfo alloc] init];
	
#if TARGET_OS_IPHONE
	copy->foregroundSession = foregroundSession;
	copy->backgroundSession = backgroundSession;
#else
	copy->session = session;
#endif
	copy->queue = queue;
	copy->userInfo = [userInfo copy];
	
	return copy;
}

@end
