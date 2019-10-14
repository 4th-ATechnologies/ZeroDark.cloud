/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "ZDCPullState.h"


@interface ZDCPullStateManager : NSObject

- (instancetype)init;

#pragma mark Creating & Deleting SyncState

/**
 * If a syncState already exists for this tuple, returns nil.
 * Otherwise, a new syncState is created and returned.
 */
- (ZDCPullState *)maybeCreatePullStateForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID;

/**
 * Deletes the associated sync state, if it exists.
 */
- (void)deletePullState:(ZDCPullState *)pullStateToDelete;

/**
 * Deletes the associated sync state, if it exists.
 */
- (ZDCPullState *)deletePullStateForLocalUserID:(NSString *)localUserID treeID:(NSString *)treeID;

#pragma mark Checking PullState

/**
 * Returns whether or not the pull has been cancelled.
 * The methods within the pull logic should check this method regularly.
 */
- (BOOL)isPullCancelled:(ZDCPullState *)syncState;

@end
