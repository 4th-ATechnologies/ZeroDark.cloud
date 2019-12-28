#import <Foundation/Foundation.h>


/**
 * Shared utilities for Activity Monitor on macOS & iOS.
**/
@interface ActivityDescriptions : NSObject

+ (NSString *)descriptionForNetworkThroughput:(NSNumber *)number;

+ (NSString *)descriptionForTimeRemaining:(NSNumber *)number;

@end
