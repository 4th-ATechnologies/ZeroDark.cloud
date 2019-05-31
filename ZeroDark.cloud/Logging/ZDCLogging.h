@import CocoaLumberjack;
//#import "LumberjackUser.h" // Required !!!

/**
 * Add this to the top of your implementation file:
 * 
 * // LEVELS: off, error, warn, info, verbose; FLAGS: trace
 * #if DEBUG
 *   static const int ddLogLevel = DDLogLevelVerbose;
 * #else
 *   static const int ddLogLevel = DDLogLevelWarning;
 * #endif
 * 
 * If you want per-user log levels, then use your name as it appears in LumberjackUser.h (post compile):
 * 
 * // LEVELS: off, error, warn, info, verbose; FLAGS: trace
 * #if DEBUG && john_doe
 *   static const int ddLogLevel = DDLogLevelVerbose;
 * #elif DEBUG
 *   static const int ddLogLevel = DDLogLevelInfo;
 * #else
 *   static const int ddLogLevel = DDLogLevelWarning;
 * #endif
 * 
 *
**/

// Undefine logging settings (DDLogMacros.h)

#undef LOG_ASYNC_ENABLED

// Redefine logging options.
// We want to customize the asynchronous logging configuration.

#ifndef LOG_ASYNC_ENABLED
  #ifdef DEBUG
    #define LOG_ASYNC_ENABLED  NO
  #else
    #define LOG_ASYNC_ENABLED  YES
  #endif
#endif

// Macro definitions (DDLogMacros.h)

/*

 #define LOG_MACRO(async, lvl, flg, ctx, tag, fnct, frmt, ...)
 
 #define LOG_MAYBE(async, lvl, flg, ctx, tag, fnct, frmt, ...)

*/

// Fine grained logging.
// The first 4 bits are being used by the standard log levels (0 - 3)

typedef NS_OPTIONS(NSUInteger, DDLogFlagExtensions) {
//	DDLogFlagError      = (1 << 0), // 0...0000001
//	DDLogFlagWarning    = (1 << 1), // 0...0000010
//	DDLogFlagInfo       = (1 << 2), // 0...0000100
//	DDLogFlagDebug      = (1 << 3), // 0...0001000
//	DDLogFlagVerbose    = (1 << 4)  // 0...0010000
	
	DDLogFlagTrace      = (1 << 5), // 0...0100000
	DDLogFlagColor      = (1 << 6)  // 0...1000000
};

// Trace - Used to trace program execution. Generally placed at the top of methods.
//         Very handy for tracking down bugs like "why isn't this code executing..." or "is this method getting hit"
//
// DDLogAutoTrace() - Prints "[Method Name]"
// DDLogTrace()     - Prints whatever you put. Generally used to print arg values.

#define LOG_ASYNC_TRACE (LOG_ASYNC_ENABLED && YES)

// #define LOG_MAYBE(async, lvl, flg, ctx, tag, fnct, frmt, ...)

#define DDLogAutoTrace()      \
    LOG_MAYBE(LOG_ASYNC_TRACE, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)DDLogFlagTrace, 0, nil, \
              __PRETTY_FUNCTION__, @"%s", __PRETTY_FUNCTION__)

#define DDLogTrace(frmt, ...) \
    LOG_MAYBE(LOG_ASYNC_TRACE, (DDLogLevel)LOG_LEVEL_DEF, (DDLogFlag)DDLogFlagTrace, 0, nil, \
              __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)

// NSLog color replacements.
// 
// The log statements below are straight NSLog replacements, and are NOT affected by the file's log level.
// In other words, they're exactly like NSLog, but they print in color.
// 
// They are handy for quick debugging sessions,
// but please don't leave them in your code, or commit them to the repository.

static NSString *const RedTag       = @"Red";
static NSString *const OrangeTag    = @"Orange";
static NSString *const YellowTag    = @"Yellow";
static NSString *const GreenTag     = @"Green";
static NSString *const BlueTag      = @"Blue";
static NSString *const PurpleTag    = @"Purple";
static NSString *const BlackTag     = @"Black";
static NSString *const PinkTag      = @"Pink";

static NSString *const DonutTag     = @"Donut";
static NSString *const CookieTag    = @"Cookie";
static NSString *const CupcakeTag   = @"Cupcake";


#define DDLogColor(ColorTag, frmt, ...)  \
  LOG_MACRO(NO, (DDLogLevel)0, (DDLogFlag)DDLogFlagColor, 0, ColorTag, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)

#define DDLogRed(frmt, ...)       DDLogColor(RedTag,     frmt, ##__VA_ARGS__)
#define DDLogOrange(frmt, ...)    DDLogColor(OrangeTag,  frmt, ##__VA_ARGS__)
#define DDLogYellow(frmt, ...)    DDLogColor(YellowTag,  frmt, ##__VA_ARGS__)
#define DDLogGreen(frmt, ...)     DDLogColor(GreenTag,   frmt, ##__VA_ARGS__)
#define DDLogBlue(frmt, ...)      DDLogColor(BlueTag,    frmt, ##__VA_ARGS__)
#define DDLogPurple(frmt, ...)    DDLogColor(PurpleTag,  frmt, ##__VA_ARGS__)
#define DDLogBlack(frmt, ...)     DDLogColor(BlackTag,   frmt, ##__VA_ARGS__)
#define DDLogPink(frmt, ...)      DDLogColor(PinkTag,    frmt, ##__VA_ARGS__)

#define DDLogDonut(frmt, ...)     DDLogColor(DonutTag,   frmt, ##__VA_ARGS__)
#define DDLogCookie(frmt, ...)    DDLogColor(CookieTag,  frmt, ##__VA_ARGS__)
#define DDLogCupcake(frmt, ...)   DDLogColor(CupcakeTag, frmt, ##__VA_ARGS__)
