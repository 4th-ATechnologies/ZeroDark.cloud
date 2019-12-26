/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Log flags are a bitmask, which are biwise-OR'd with the log level
 * to determine if the log message should be emitted.
 */
typedef NS_OPTIONS(NSUInteger, ZDCLogFlag){
	/**
	 *  Bitmask: 0...00001
	 */
	ZDCLogFlagError   = (1 << 0),
	
	/**
	 *  Bitmask: 0...00010
	 */
	ZDCLogFlagWarning = (1 << 1),
    
	/**
	 *  Bitmask: 0...00100
	 */
	ZDCLogFlagInfo    = (1 << 2),
    
	/**
	 *  Bitmask: 0...01000
	 */
	ZDCLogFlagVerbose = (1 << 3),
	
	/**
	 *  Bitmask: 0...10000
	 */
	ZDCLogFlagTrace   = (1 << 4)
};

/**
 *  Log levels are used to filter out logs. Used together with flags.
 */
typedef NS_ENUM(NSUInteger, ZDCLogLevel){
	/**
	 *  No logs
	*/
	ZDCLogLevelOff       = 0,
	
	/**
	 *  Error logs only
	 */
	ZDCLogLevelError     = (ZDCLogFlagError),
	
	/**
	 *  Error and warning logs
	 */
	ZDCLogLevelWarning   = (ZDCLogLevelError   | ZDCLogFlagWarning),
	
	/**
	 *  Error, warning and info logs
	 */
	ZDCLogLevelInfo      = (ZDCLogLevelWarning | ZDCLogFlagInfo),
	
	/**
	 *  Error, warning, info, and verbose logs
	 */
	ZDCLogLevelVerbose   = (ZDCLogLevelInfo    | ZDCLogFlagVerbose),
	
	/**
	 *  All logs (1...11111)
	 */
	ZDCLogLevelAll       = NSUIntegerMax
};

/**
 * Ecapsulates detailed information about an emitted log message.
 */
@interface ZDCLogMessage : NSObject

/**
 * Standard init method
 */
- (instancetype)initWithMessage:(NSString *)message
                          level:(ZDCLogLevel)level
                           flag:(ZDCLogFlag)flag
                           file:(NSString *)file
                       function:(NSString *)function
                           line:(NSUInteger)line;

/**
 * The log message. (e.g. "foo failed because bar returned 404")
 */
@property (readonly, nonatomic) NSString *message;

/**
 * The configured `zdcLogLevel` of the file from which the log was emitted.
 */
@property (readonly, nonatomic) ZDCLogLevel level;

/**
 * Tells you which flag triggered the log.
 * For example, `if flag == ZDCLogFlagError`, then this is an error log message, emitted via ZDCLogError()
 */
@property (readonly, nonatomic) ZDCLogFlag flag;

/**
 * The full filePath (e.g. /Users/alice/code/myproject/ZeroDarkCloud/Managers/ZDCPushManager.m)
 * This comes from `__FILE__`
 */
@property (readonly, nonatomic) NSString *file;

/**
 * The lastPathComponent of the filePath, with the fileExtension removed. (e.g. ZDCPushManager)
 */
@property (readonly, nonatomic) NSString *fileName;

/**
 * The name of function that triggered the log message.
 * This comes from __PRETTY_FUNCTION__
 */
@property (readonly, nonatomic) NSString *function;

/**
 * The line number within the file. (i.e. location of emitted log message)
 */
@property (readonly, nonatomic) NSUInteger line;

@end

NS_ASSUME_NONNULL_END
