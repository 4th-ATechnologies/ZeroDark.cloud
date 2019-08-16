/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import "ZDCTaskContext.h"

/**
 * Utility class used by the PullManager.
 */
@interface ZDCPollContext : ZDCObject <NSCoding, NSCopying>

@property (nonatomic, copy, readwrite) ZDCTaskContext *taskContext;

@property (nonatomic, copy, readwrite) NSString * eTag;

/**
 * Polling could complete via the poll request itself,
 * or via an arriving push notification.
 *
 * If both arrive at the same time, we need a way to ensure it's only processed once.
 * 
 * The completed marker is reset if the requestID is changed.
**/
- (BOOL)atomicMarkCompleted;

@end
