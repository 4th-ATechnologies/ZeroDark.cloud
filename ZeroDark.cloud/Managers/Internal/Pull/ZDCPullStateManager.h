/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "ZDCPullState.h"


@interface ZDCPullStateManager : NSObject

- (instancetype)init;

#pragma mark Creating & Deleting SyncState

/**
 * If a syncState already exists for this localUserID, returns nil.
 * Otherwise, a new syncState is created and returned.
 */
- (ZDCPullState *)maybeCreatePullStateForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;

/**
 * Deletes the associated sync state, if it exists.
 */
- (void)deletePullState:(ZDCPullState *)pullStateToDelete;

/**
 * Deletes the associated sync state, if it exists.
 */
- (ZDCPullState *)deletePullStateForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;

#pragma mark Checking PullState

/**
 * Returns whether or not the pull has been cancelled.
 * The methods within the pull logic should check this method regularly.
 */
- (BOOL)isPullCancelled:(ZDCPullState *)syncState;

@end
