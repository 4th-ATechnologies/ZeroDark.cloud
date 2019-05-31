#import <Foundation/Foundation.h>

#import "ZDCPollContext.h"

/**
 * Utility class used by the sync manager(s).
**/
@interface ZDCTouchContext : ZDCObject <NSCoding, NSCopying>

@property (nonatomic, copy, readwrite) ZDCPollContext *pollContext;

@end
