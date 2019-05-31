/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCSessionManager.h"
#import "ZeroDarkCloud.h"

@interface ZDCSessionManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Forward through the system:
 * AppDelegate -> ZeroDarkCloud -> ZDCSessionManager
 */
- (void)handleEventsForBackgroundURLSession:(NSString *)sessionIdentifier;

@end
