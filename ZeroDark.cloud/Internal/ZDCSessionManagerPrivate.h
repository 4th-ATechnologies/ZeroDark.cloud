/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
