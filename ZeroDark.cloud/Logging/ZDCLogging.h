#import <Foundation/Foundation.h>

#import "ZeroDarkCloud.h"
#import "ZDCLogMessage.h"

/**
 * Logging plays a very important role in open-source libraries.
 *
 * Good documentation and comments decrease the learning time required to use a library.
 * But proper logging takes this futher by:
 * - Providing a way to trace the execution of the library
 * - Allowing developers to quickly identify subsets of the code that need analysis
 * - Making it easier for developers to find potential bugs, either in their code or the library
 * - Drawing attention to potential mis-configurations or mis-uses of the API
 *
 * Ultimately logging is an interactive extension to comments.
 */

@interface ZeroDarkCloud ()

+ (void)log:(ZDCLogLevel)level
       flag:(ZDCLogFlag)flag
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
     format:(NSString *)format, ... NS_FORMAT_FUNCTION(6,7);

@end

#define ZDC_LOG_MACRO(lvl, flg, frmt, ...)           \
        [ZeroDarkCloud log : lvl                     \
                      flag : flg                     \
                      file : __FILE__                \
                  function : __PRETTY_FUNCTION__     \
                      line : __LINE__                \
                    format : (frmt), ## __VA_ARGS__]

#define ZDC_LOG_MAYBE(lvl, flg, frmt, ...) \
        do { if(lvl & flg) ZDC_LOG_MACRO(lvl, flg, frmt, ##__VA_ARGS__); } while(0)

#define ZDCLogError(frmt, ...)   ZDC_LOG_MAYBE(zdcLogLevel, ZDCLogFlagError,   frmt, ##__VA_ARGS__)
#define ZDCLogWarn(frmt, ...)    ZDC_LOG_MAYBE(zdcLogLevel, ZDCLogFlagWarning, frmt, ##__VA_ARGS__)
#define ZDCLogInfo(frmt, ...)    ZDC_LOG_MAYBE(zdcLogLevel, ZDCLogFlagInfo,    frmt, ##__VA_ARGS__)
#define ZDCLogVerbose(frmt, ...) ZDC_LOG_MAYBE(zdcLogLevel, ZDCLogFlagVerbose, frmt, ##__VA_ARGS__)
#define ZDCLogTrace(frmt, ...)   ZDC_LOG_MAYBE(zdcLogLevel, ZDCLogFlagTrace,   frmt, ##__VA_ARGS__)
#define ZDCLogAutoTrace()        ZDC_LOG_MAYBE(zdcLogLevel, ZDCLogFlagTrace,   @"%s", __FUNCTION__)
