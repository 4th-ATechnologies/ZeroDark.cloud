@import CocoaLumberjack;
//#import "LumberjackUser.h" // Required !!!

static const NSInteger ZDCLoggingContext = 2147483647; // ((2^31) - 1), largest 32-bit prime

// Fine grained logging.
// The first 4 bits are being used by the standard log levels (0 - 3)

typedef NS_OPTIONS(NSUInteger, ZDCLogFlag) {
	ZDCLogFlagError      = (1 << 0), // 0...00000001
	ZDCLogFlagWarning    = (1 << 1), // 0...00000010
	ZDCLogFlagInfo       = (1 << 2), // 0...00000100
	ZDCLogFlagDebug      = (1 << 3), // 0...00001000
	ZDCLogFlagVerbose    = (1 << 4), // 0...00010000
	ZDCLogFlagTrace      = (1 << 5), // 0...00100000
	ZDCLogFlagColor      = (1 << 6)  // 0...01000000
};

typedef NS_ENUM(NSUInteger, ZDCLogLevel){
	ZDCLogLevelOff       = 0,
	ZDCLogLevelError     = (ZDCLogFlagError),
	ZDCLogLevelWarning   = (ZDCLogLevelError   | ZDCLogFlagWarning),
	ZDCLogLevelInfo      = (ZDCLogLevelWarning | ZDCLogFlagInfo),
	ZDCLogLevelDebug     = (ZDCLogLevelInfo    | ZDCLogFlagDebug),
	ZDCLogLevelVerbose   = (ZDCLogLevelDebug   | ZDCLogFlagVerbose),
	ZDCLogLevelAll       = NSUIntegerMax
};

// Customize asynchronous logging configuration.

#undef LOG_ASYNC_ENABLED
#ifdef DEBUG
  #define LOG_ASYNC_ENABLED  NO
#else
  #define LOG_ASYNC_ENABLED  YES
#endif

#define LOG_ASYNC_ERROR   (LOG_ASYNC_ENABLED && NO)
#define LOG_ASYNC_WARN    (LOG_ASYNC_ENABLED && NO)
#define LOG_ASYNC_INFO    (LOG_ASYNC_ENABLED && YES)
#define LOG_ASYNC_DEBUG   (LOG_ASYNC_ENABLED && YES)
#define LOG_ASYNC_VERBOSE (LOG_ASYNC_ENABLED && YES)
#define LOG_ASYNC_TRACE   (LOG_ASYNC_ENABLED && YES)
#define LOG_ASYNC_COLOR   (LOG_ASYNC_ENABLED && NO)


#undef LOG_LEVEL_DEF
#define LOG_LEVEL_DEF zdcLogLevel

#define ZDCLogError(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_ERROR, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagError, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)

#define ZDCLogWarn(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_WARN, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagWarning, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)

#define ZDCLogInfo(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_INFO, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagInfo, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)

#define ZDCLogDebug(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_DEBUG, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagDebug, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)

#define ZDCLogVerbose(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_VERBOSE, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagVerbose, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)

#define ZDCLogTrace(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_TRACE, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagTrace, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)

#define ZDCLogAutoTrace() \
    LOG_MAYBE(LOG_ASYNC_TRACE, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)ZDCLogFlagTrace, ZDCLoggingContext, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)
