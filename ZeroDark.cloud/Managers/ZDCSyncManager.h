/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This notification is broadcast when changes are discovered in the cloud,
 * and the PullManager has started working to update the treesystem state.
 *
 * The following keys are available in the notification's userInfo:
 * - kLocalUserIDKey : value is string
 * - kAppIDKey : value is string
 *
 * This notification is always broadcast on the main thread.
 */
extern NSString *const ZDCPullStartedNotification;

/**
 * This notification is broadcast after:
 * - changes were discovered in the cloud
 * - the PullManager attempted to update the treesystem state
 * - and the PullManager is now done with its attempt (either success or failure)
 *
 * The following keys are available in the notification's userInfo:
 * - kLocalUserIDKey : value is string
 * - kAppIDKey : value is string
 * - kPullResultKey : value is (wrapped) `ZDCPullResult`
 *
 * This notification is always broadcast on the main thread.
 */
extern NSString *const ZDCPullStoppedNotification;

/**
 * This notifications is broadcast when the PushManager changes active status.
 * This happens when:
 * - the PushManager receives new upload operations, and starts working on them
 *
 * The following keys are available in the notification's userInfo:
 * - kLocalUserIDKey : value is string
 * - kAppIDKey : value is string
 *
 * This notification is always broadcast on the main thread.
 */
extern NSString *const ZDCPushStartedNotification;

/**
 * This notification is broadcast when the PushManager changes active status.
 * This happens when:
 * - the PushManager completes all the upload operations in its queue
 * - or the PushManager is stopped due to Internet reachability changes
 *
 * The following keys are available in the notification's userInfo:
 * - kLocalUserIDKey : value is string
 * - kAppIDKey : value is string
 *
 * This notification is always broadcast on the main thread.
 */
extern NSString *const ZDCPushStoppedNotification;

/**
 * This notification is broadcast when a user's syncingNodeID's list changes.
 *
 * @see `-syncingNodeIDsForLocalUserID`
 *
 * This notification is always broadcast on the main thread.
 */
extern NSString *const ZDCSyncingNodeIDsChangedNotification;

extern NSString *const kLocalUserIDKey;
extern NSString *const kAppIDKey;
extern NSString *const kPullResultKey;

/**
 * The SyncManager simplifies many aspects of determining sync state.
 *
 * In particular, it can tell you:
 * - whether or not the framework is "syncing" data (pushing or pulling)
 * - which nodes are being synced
 *
 * The framework can run on autopilot most of the time.
 * But this class gives you fine grained controls.
 * For example, you can pause the push queue for a particular user so changes aren't uploaded.
 */
@interface ZDCSyncManager : NSObject

#pragma mark Manual Pull

/**
 * This method is typically only used on the iOS simulator, which doesn't support push notifications.
 * So for testing & debugging on the simulator, you may wish to add a manual pull button that calls this method.
 *
 * Under normal operating conditions however, there's little reason to use this method.
 * Your application should be receiving push notifications when changes occur in the cloud that affect the user.
 * And the push notifications will trigger the pull system correctly.
 *
 * Further, the LocalUserManager performs a poll on the server every so often
 * (in the absence of push notifications) to ensure it's up-to-date.
 */
- (void)pullChangesForLocalUserID:(NSString *)localUserID;

/**
 * This method is typically only used on the iOS simulator, which doesn't support push notifications.
 * So for testing & debugging on the simulator, you may wish to add a manual pull button that calls this method.
 *
 * Under normal operating conditions however, there's little reason to use this method.
 * Your application should be receive push notifications when changes occur in the cloud that affect the user.
 * And the push notifications will trigger the pull system correctly.
 *
 * Further, the LocalUserManager performs a poll on the server every so often
 * (in the absence of push notifications) to ensure it's up-to-date.
 */
- (void)pullChangesForAllLocalUsers;

#pragma mark Pause & Resume Push

/**
 * Allows you to pause the push system.
 * That is, to pause the upload operation queue for the given user.
 *
 * This will only pause the push/upload system.
 * Pulls & downloads are separate, and may continue while the push system is paused.
 *
 * @param localUserID
 *   The user for which you wish to pause push/uploads. (localUserID == ZDCLocalUser.uuid)
 *
 * @param shouldAbortUploads
 *   Whether or not you wish to cancal active/in-flight uploads.
 *   If yes, any corresponding uploads will be cancelled.
 *   Otherwise, in-flight uploads will continue until the task finishes (either success or failure),
 *   but new uploads won't be started until you resume the push system.
 */
- (void)pausePushForLocalUserID:(NSString *)localUserID andAbortUploads:(BOOL)shouldAbortUploads;

/**
 * Allows you to pause the push system.
 * That is, to pause the upload operation queue.
 *
 * This will only pause the push/upload system.
 * Pulls & downloads are separate, and may continue while the push system is paused.
 *
 * @param shouldAbortUploads
 *   Whether or not you wish to cancal active/in-flight uploads.
 *   If yes, any corresponding uploads will be cancelled.
 *   Otherwise, in-flight uploads will continue until the task finishes (either success or failure),
 *   but new uploads won't be started until you resume the push system.
 */
- (void)pausePushForAllLocalUsersAndAbortUploads:(BOOL)shouldAbortUploads;

/**
 * Resumes the push system if it's currently paused.
 * If the user has Internet reachability, the upload operation queue will resume immediately.
 *
 @param localUserID
 *   The user for which you wish to resume push/uploads. (localUserID == ZDCLocalUser.uuid)
 */
- (void)resumePushForLocalUserID:(NSString *)localUserID;

/**
 * Resumes all push systems.
 * If the user has Internet reachability, the upload operation queue will resume immediately.
 */
- (void)resumePushForAllLocalUsers;

/**
 * Returns true if push is paused for the localUser.
 *
 * That is, if you've manually called either `pausePushForLocalUserID::`
 * or `pausePushForAllLocalUsersAndAbortUploads`.
 */
- (BOOL)isPushingPausedForLocalUserID:(NSString *)localUserID;

/** Returns true if push is paused for every single localUser */
- (BOOL)isPushingPausedForAllUsers;

/** Returns true if push is paused for any localUser */
- (BOOL)isPushingPausedForAnyUser;

#pragma mark Activity State

/**
 * This method can be used to discover if a pull is currently in progress for the given user.
 *
 * It's important to understand what a "pull" means within the context of the ZeroDark.cloud framework,
 * as its meaning may differ from the perspective of your application.
 * The ZeroDark.cloud framework automatically updates the local cache of the
 * treesystem hierarchy to match that of the cloud. This tree heirarchy
 * that it maintains is separate from the node data. For example, if it discovers
 * that new nodes have been added to the cloud, it automatically downloads the
 * tree information (node name, position within tree, permsissions, etc),
 * but not the underlying node data (the data that your application generates).
 *
 * So if a "pull" is active this means the PullManager has discovered:
 * - one or more nodes that have been added, modified or deleted from the cloud
 * - and the PullManager is actively working to update the local tree heirarchy to match the cloud
 *
 * Now, the perspective of your application may be a little different.
 * For example, if a node is discovered with name "some-random-uuid", this doesn't tell you much.
 * And more than likely, your application will choose to immedately request a download of this node.
 * So your application will likely have a slightly different perspective,
 * for example you may animate some UI component for your user if:
 * - this method says it's updating the tree
 * - OR the download manager says it's downloading stuff for the localUserID
 *
 * The following notifications can be used to determine when this state changes:
 * - `ZDCPullStartedNotification`
 * - `ZDCPullStoppedNotification`
 */
- (BOOL)isPullingChangesForLocalUserID:(NSString *)localUserID;

/**
 * This method can be used to discover is a push is currently in progress for the given user.
 *
 * The following notifications can be used to determine when this state changes:
 * - ZDCPushStartedNotification
 * - ZDCPushStoppedNotification
 */
- (BOOL)isPushingChangesForLocalUserID:(NSString *)localUserID;

/**
 * Helpful for checking general sync activity.
 */
- (BOOL)isPullingOrPushingChangesForLocalUserID:(NSString *)localUserID;

/**
 * Helpful for checking general sync activity.
 */
- (BOOL)isPullingOrPushingChangesForAnyLocalUser;

#pragma mark Node State

/**
 * Returns a set of nodeIDs for which ANY of the following are true:
 *
 * - The node is being pushed to the server, or scheduled to be pushed.
 * - The node has children, and there's a descendant (at any depth - child, grandchild, etc)
 *   that's being pushed to the server (or scheduled to be pushed).
 * - The node has changes on the cloud, and we're pulling the changes to it.
 * - The node has children, and there's a descendant (at any depth - child, grandchild, etc)
 *   for which we're pulling changes for.
 * - There's an active dowload for the given nodeID (which was requested via DownloadManager).
 *
 * This list is updated automatically as the sync system operates in the background.
 * The following notification can be used to determine when this state changes:
 * - ZDCSyncingNodeIDsChangedNotification
 *
 * @note The functionality of this method may not perfectly match your application's requirements.
 *       But it's usually a helpful starting point from which you can copy code into your own app,
 *       and then make changes to better suite your needs.
**/
- (NSSet<NSString *> *)syncingNodeIDsForLocalUserID:(NSString *)localUserID;

@end

NS_ASSUME_NONNULL_END
