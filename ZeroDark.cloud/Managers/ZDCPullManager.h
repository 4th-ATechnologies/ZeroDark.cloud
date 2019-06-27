/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ZDCPullResult) {
	
	ZDCPullResult_Success           = 0,
	ZDCPullResult_ManuallyAborted   = 1, // explicitly cancelled (by user, or due to backgrounding, etc)
	
	ZDCPullResult_Fail_CloudChanged = 2, // retry soon
	ZDCPullResult_Fail_Unknown      = 3, // retry after exponential delay
	ZDCPullResult_Fail_Auth         = 4, // retry requires new auth
};

/**
 * The sync process can be broken down into 2 components:
 * - Push
 * - Pull
 *
 * If you've used git before, you're already familiar with the process.
 * You push changes (made locally) to the cloud. And you pull changes (made on remote devices) from the cloud.
 *
 * This class handles the PULL side of things.
 *
 * In particular, the PullManager will automatically keep the local filesystem information
 * up-to-date with the cloud. This ONLY includes the bare filesystem information:
 * - names of nodes
 * - their permissions
 * - their location within the filesystem/tree
 *
 * The ZeroDarkCloud framework doesn't automatically download node data (date == the content your app generates).
 * You are in complete control of that, which allows you to optimize for your app. For example,
 * you may choose to only download a small part of what's stored in the cloud. Or perhaps there
 * are certain items you only download on demand.
 */
@interface ZDCPullManager : NSObject

/**
 * Performs a "pull" for the given {localUserID, zAppID} tuple.
 *
 * Only one recursive pull per {localUserID, zAppID} tuple is allowed at a time.
 * So if this method is invoked multiple times for the same tuple,
 * each spurious request (after the first) is ignored.
 *
 * @note You generally don't ever have to invoke this method manually.
 *       The SyncManager takes care of this for each ZDCLocalUser in the database,
 *       paired with the registered ZeroDarkCloud.zAppID.
 */
- (void)pullRemoteChangesForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;

/**
 * Aborts an in-progress pull (if exists) for the given {localUserID, zAppID} tuple.
 *
 * You may wish to do this when certain events occur.
 * For example, if you're deleting a localUser.
 */
- (void)abortPullForLocalUserID:(NSString *)localUserID zAppID:(NSString *)zAppID;

@end
