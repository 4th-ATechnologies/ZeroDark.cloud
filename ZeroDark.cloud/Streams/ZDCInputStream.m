#import "ZDCInputStream.h"

#import "ZDCLogging.h"

#import <CoreFoundation/CoreFoundation.h>
#import <mach/mach.h>

#if DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)


/* extern */ NSString *const ZDCStreamFileMinOffset        = @"ZDCStreamFileMinOffset";
/* extern */ NSString *const ZDCStreamFileMaxOffset        = @"ZDCStreamFileMaxOffset";
/* extern */ NSString *const ZDCStreamReturnEOFOnWouldBlock = @"ZDCStreamReturnEOFOnWouldBlock";

/* extern */ NSInteger const ZDCStreamUnexpectedFileSize = 1001;

struct ZDCInputStream_Mach_Message {
	mach_msg_header_t header;
	mach_msg_body_t body;
	mach_msg_type_descriptor_t type;
};

/**
 * Subclasses can copy this into their implementation.
**/
@interface ZDCInputStream (Private)

- (NSError *)errorWithDescription:(NSString *)description;
+ (NSError *)errorWithDescription:(NSString *)description;
- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;
+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code;

/**
 * Subclasses should use this method to indirectly invoke [self stream:handleEvent:].
 *
 * That is, do NOT directly invoke [self stream:handleEvent:].
 * That method is expected to be invoked on the proper thread & runloop + mode.
 * Instead, invoke this method, which will indirectly invoke [self stream:handleEvent:],
 * but on the proper thread & runloop + mode.
**/
- (void)sendEvent:(NSStreamEvent)streamEvent;

/**
 * Subclasses may use this method to invoke the "delegate".
 *
 * Remember that CoreFoundation uses a requestCallback (C function), and not the usual delegate system.
 * This method handles all those details automatically, and does the right thing.
**/
- (void)notifyDelegateOfEvent:(NSStreamEvent)streamEvent;

@end

@interface ZDCInputStream () <NSStreamDelegate, NSMachPortDelegate>
@end

@implementation ZDCInputStream {
@private
	
	CFOptionFlags               requestedEvents;
	CFReadStreamClientCallBack  requestedCallback;
	CFStreamClientContext       copiedContext;
	
	CFMachPortRef cfMachPort;
	CFRunLoopSourceRef cfRunLoopSource;
	
	NSMachPort *nsMachPort;
}

@synthesize underlyingInputStream = inputStream;
@synthesize retainToken;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

/**
 * Overrides [NSInputStream initWithFileAtPath:]
**/
- (instancetype)initWithData:(NSData *)data
{
	@throw [NSException exceptionWithName:@"ZDCInputStream"
	                               reason:@"Unsupported initializer method"
	                             userInfo:nil];
	
	return nil;
}

/**
 * Overrides [NSInputStream initWithFileAtPath:]
**/
- (instancetype)initWithFileAtPath:(NSString *)path
{
	@throw [NSException exceptionWithName:@"ZDCInputStream"
	                               reason:@"Unsupported initializer method"
	                             userInfo:nil];
	
	return nil;
}

/**
 * Overrides [NSInputStream initWithURL:]
**/
- (instancetype)initWithURL:(NSURL *)url
{
	@throw [NSException exceptionWithName:@"ZDCInputStream"
	                               reason:@"Unsupported initializer method"
	                             userInfo:nil];
	
	return nil;
}

#pragma clang diagnostic pop

- (instancetype)init
{
	if ((self = [super init]))
	{
		streamStatus = NSStreamStatusNotOpen;
		delegate = (id <NSStreamDelegate>)self; // as per contract requirements (see docs for NSStream.delegate)
	}
	return self;
}

- (void)dealloc
{
	if (copiedContext.info && copiedContext.release) {
		copiedContext.release(copiedContext.info);
		memset(&copiedContext, 0, sizeof(CFStreamClientContext));
	}
	
	if (cfMachPort) {
		CFMachPortInvalidate(cfMachPort);
		
		CFRelease(cfRunLoopSource);
		cfRunLoopSource = NULL;
		
		CFRelease(cfMachPort);
		cfMachPort = NULL;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSStream subclass overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	[inputStream scheduleInRunLoop:aRunLoop forMode:mode];
	
	[self setupNSMachPort];
	[aRunLoop addPort:nsMachPort forMode:mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	[inputStream removeFromRunLoop:aRunLoop forMode:mode];
	
	[aRunLoop removePort:nsMachPort forMode:mode];
}

- (NSStreamStatus)streamStatus
{
	// Important: Do NOT rely on the underlyingInputStream here.
	//
	// First, not all subclasses initialize an underlyingInputStream instance.
	// 
	// Second, our streamStatus doesn't always match the underlying stream.
	// E.g. we might have more bytes, even though we've reached EOF on the underlying stream.
	//
	return streamStatus;
}

- (NSError *)streamError
{
	return streamError;
}

- (id <NSStreamDelegate>)delegate {
	return delegate;
}

- (void)setDelegate:(id<NSStreamDelegate>)inDelegate
{
	if (inDelegate) {
		delegate = inDelegate;
	}
	else {
		// From the docs:
		//
		// By default, a stream is its own delegate, and subclasses of NSInputStream and NSOutputStream
		// must maintain this contract. If you override this method in a subclass, passing nil must restore
		// the receiver as its own delegate.
		delegate = self;
	}
}

- (id)propertyForKey:(NSString *)key
{
	if ([key isEqualToString:ZDCStreamFileMinOffset])
	{
		return fileMinOffset;
	}
	
	if ([key isEqualToString:ZDCStreamFileMaxOffset])
	{
		return fileMaxOffset;
	}
	
	if ([key isEqualToString:ZDCStreamReturnEOFOnWouldBlock])
	{
		return returnEOFOnWouldBlock;
	}
	
//	DDLogWarn(@"Unhandled propertyForKey: %@", key);
//	return nil;
	
	return [super propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
	if ([key isEqualToString:ZDCStreamFileMinOffset])
	{
		if (![self supportsFileMinMaxOffset]) return NO;
		if (![property isKindOfClass:[NSNumber class]]) return NO;
		
		fileMinOffset = (NSNumber *)property;
		if (fileMinOffset != nil)
		{
			if (fileMaxOffset != nil)
			{
				uint64_t min = [fileMinOffset unsignedLongLongValue];
				uint64_t max = [fileMaxOffset unsignedLongLongValue];
				
				if (min > max) {
					fileMaxOffset = nil;
				}
			}
			
			NSNumber *currentOffset = [self propertyForKey:NSStreamFileCurrentOffsetKey];
			if (currentOffset != nil)
			{
				uint64_t min = [fileMinOffset unsignedLongLongValue];
				uint64_t cur = [currentOffset unsignedLongLongValue];
				
				if (cur < min) {
					[self setProperty:fileMinOffset forKey:NSStreamFileCurrentOffsetKey];
				}
			}
		}
		
		return YES;
	}
	
	if ([key isEqualToString:ZDCStreamFileMaxOffset])
	{
		if (![self supportsFileMinMaxOffset]) return NO;
		if (![property isKindOfClass:[NSNumber class]]) return NO;
		
		fileMaxOffset = (NSNumber *)property;
		if (fileMaxOffset)
		{
			if (fileMinOffset)
			{
				uint64_t min = [fileMinOffset unsignedLongLongValue];
				uint64_t max = [fileMaxOffset unsignedLongLongValue];
				
				if (min > max) {
					fileMinOffset = nil;
				}
			}
		}
		
		return YES;
	}
	
	if ([key isEqualToString:ZDCStreamReturnEOFOnWouldBlock])
	{
		if (![self supportsEOFOnWouldBlock]) return NO;
		if (![property isKindOfClass:[NSNumber class]]) return NO;
		
		returnEOFOnWouldBlock = (NSNumber *)property;
		return YES;
	}
	
//	DDLogWarn(@"Unhandled setProperty:forKey: %@", key);
//	return NO;
	
	return [super setProperty:property forKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSStreamEvent Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses should use this method to indirectly invoke [self stream:handleEvent:].
 *
 * That is, do NOT directly invoke [self stream:handleEvent:].
 * That method is expected to be invoked on the proper thread & runloop + mode.
 * Instead, invoke this method, which will indirectly invoke [self stream:handleEvent:],
 * but on the proper thread & runloop + mode.
**/
- (void)sendEvent:(NSStreamEvent)streamEvent
{
	if (cfMachPort || nsMachPort)
	{
		natural_t data = (natural_t)streamEvent;
		
		struct ZDCInputStream_Mach_Message message;
		
		message.header = (mach_msg_header_t) {
			.msgh_remote_port = 0,
			.msgh_local_port = MACH_PORT_NULL,
			.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0),
			.msgh_size = sizeof(message)
		};
		
		message.body = (mach_msg_body_t) {
			.msgh_descriptor_count = 1
		};
		
		message.type = (mach_msg_type_descriptor_t) {
			.pad1 = data,
			.pad2 = sizeof(data)
		};
		
		if (cfMachPort)
		{
			message.header.msgh_remote_port = CFMachPortGetPort(cfMachPort);
			mach_msg_return_t error = mach_msg_send(&message.header);
		
			if (error != MACH_MSG_SUCCESS) {
				DDLogError(@"Error sending on CFMachPort: %d", error);
			}
		}
		
		if (nsMachPort)
		{
			message.header.msgh_remote_port = nsMachPort.machPort;
			mach_msg_return_t error = mach_msg_send(&message.header);
			
			if (error != MACH_MSG_SUCCESS) {
				DDLogError(@"Error sending on NSMachPort: %d", error);
			}
		}
	}
}

/**
 * Subclasses may use this method to invoke the "delegate".
 *
 * Remember that CoreFoundation uses a requestCallback (C function), and not the usual delegate system.
 * This method handles all those details automatically, and does the right thing.
**/
- (void)notifyDelegateOfEvent:(NSStreamEvent)streamEvent
{
	if (requestedEvents & streamEvent) {
		requestedCallback((__bridge CFReadStreamRef)self, (CFStreamEventType)streamEvent, copiedContext.info);
	}
	if (delegate != self) {
		[delegate stream:self handleEvent:streamEvent];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSStreamDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Do NOT call this method directly.
 * Instead, you should use [self sendEvent:streamEvent].
 * 
 * @see [ZDCInputStream sendEvent:]
 * 
 * Subclasses can override this method if needed.
**/
- (void)stream:(NSStream *)sender handleEvent:(NSStreamEvent)streamEvent
{
	[self notifyDelegateOfEvent:streamEvent];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mach Port
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void cfMachPortCallBack(CFMachPortRef port, void *machMessage, CFIndex size, void *info)
{
	struct ZDCInputStream_Mach_Message *msg = (struct ZDCInputStream_Mach_Message *)machMessage;
	NSStreamEvent streamEvent = (NSStreamEvent)msg->type.pad1;
	
	__unsafe_unretained ZDCInputStream *sender = (__bridge ZDCInputStream *)info;
	
	[sender stream:sender handleEvent:streamEvent];
}

- (void)setupCFMachPort
{
	if (cfMachPort == NULL)
	{
		CFMachPortContext context;
		memset(&context, 0, sizeof(context));
		
		context.info = (__bridge void *)self;
		
		cfMachPort = CFMachPortCreate(NULL, cfMachPortCallBack, &context, NULL);
		cfRunLoopSource = CFMachPortCreateRunLoopSource(NULL, cfMachPort, 0);
	}
}

- (void)setupNSMachPort
{
	if (nsMachPort == nil)
	{
		nsMachPort = (NSMachPort *)[NSMachPort port];
		nsMachPort.delegate = self;
	}
}

- (void)handleMachMessage:(void *)machMessage
{
	struct ZDCInputStream_Mach_Message *msg = (struct ZDCInputStream_Mach_Message *)machMessage;
	NSStreamEvent streamEvent = (NSStreamEvent)msg->type.pad1;
	
	[self stream:self handleEvent:streamEvent];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Undocumented CFReadStream bridged methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_scheduleInCFRunLoop:(CFRunLoopRef)aRunLoop forMode:(CFStringRef)aMode
{
	if (inputStream) {
		CFReadStreamScheduleWithRunLoop((CFReadStreamRef)inputStream, aRunLoop, aMode);
	}
	
	[self setupCFMachPort];
	if (cfRunLoopSource) {
		CFRunLoopAddSource(aRunLoop, cfRunLoopSource, aMode);
	}
}

- (void)_unscheduleFromCFRunLoop:(CFRunLoopRef)aRunLoop forMode:(CFStringRef)aMode
{
	if (inputStream) {
		CFReadStreamUnscheduleFromRunLoop((CFReadStreamRef)inputStream, aRunLoop, aMode);
	}
	
	if (cfRunLoopSource) {
		CFRunLoopRemoveSource(aRunLoop, cfRunLoopSource, aMode);
	}
}

- (BOOL)_setCFClientFlags:(CFOptionFlags)inFlags
                 callback:(CFReadStreamClientCallBack)inCallback
                  context:(CFStreamClientContext *)inContext {
    
	if (inCallback)
	{
		requestedEvents = inFlags;
		requestedCallback = inCallback;
		 
      if (inContext)
			memcpy(&copiedContext, inContext, sizeof(CFStreamClientContext));
		else
			memset(&copiedContext, 0, sizeof(CFStreamClientContext));
		
		if (copiedContext.info && copiedContext.retain) {
			copiedContext.retain(copiedContext.info);
		}
	}
	else
	{
		requestedEvents = kCFStreamEventNone;
		requestedCallback = NULL;
		
		if (copiedContext.info && copiedContext.release) {
			copiedContext.release(copiedContext.info);
		}
        
		memset(&copiedContext, 0, sizeof(CFStreamClientContext));
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(NSString *)description
{
	return [[self class] errorWithDescription:description];
}

+ (NSError *)errorWithDescription:(NSString *)description
{
	return [self errorWithDescription:description code:0];
}

- (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code
{
	return [[self class] errorWithDescription:description code:code];
}

+ (NSError *)errorWithDescription:(NSString *)description code:(NSInteger)code
{
	NSDictionary *userInfo = nil;
	if (description) {
		userInfo = @{ NSLocalizedDescriptionKey: description };
	}
	
	NSString *domain = NSStringFromClass(self);
	return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses should override this method & return YES if these properties are supported.
 * Otherwise ZDCInputStream will refuse to set them, and return NO in `setProperty:forKey:`.
**/
- (BOOL)supportsFileMinMaxOffset
{
	return NO;
}

/**
 * Subclasses should return YES if the `ZDCStreamReturnEOFOnWouldBlock` property is supported.
 * Otherwise ZDCInputStream will refuse to set it, and will return NO in `setProperty:forKey:`.
**/
- (BOOL)supportsEOFOnWouldBlock
{
	return NO;
}

@end
