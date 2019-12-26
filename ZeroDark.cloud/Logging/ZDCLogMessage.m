/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCLogMessage.h"

@implementation ZDCLogMessage

@synthesize message = _message;
@synthesize level = _level;
@synthesize flag = _flag;
@synthesize file = _file;
@synthesize function = _function;
@synthesize line = _line;

@dynamic fileName;

- (instancetype)initWithMessage:(NSString *)message
                          level:(ZDCLogLevel)level
                           flag:(ZDCLogFlag)flag
                           file:(NSString *)file
                       function:(NSString *)function
                           line:(NSUInteger)line
{
	if ((self = [super init]))
	{
		_message  = [message copy];
		_level    = level;
		_flag     = flag;
		_file     = file;     // Not copying here since parameter supplied via __FILE__
		_function = function; // Not copying here since parameter supplied via __FUNCTION__
		_line     = line;
	}
	return self;
}

- (NSString *)fileName
{
	NSString *fileName = [_file lastPathComponent];
	
	NSUInteger dotLocation = [fileName rangeOfString:@"." options:NSBackwardsSearch].location;
	if (dotLocation != NSNotFound) {
		 fileName = [fileName substringToIndex:dotLocation];
	}
	
	return fileName;
}

@end
