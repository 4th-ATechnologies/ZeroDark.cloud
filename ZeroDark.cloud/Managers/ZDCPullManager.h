/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

/**
 * Specifies the final result of a pull attempt.
 */
typedef NS_ENUM(NSInteger, ZDCPullResult) {
	
	/**
	 * The pull operation was successful, and the client is now up-to-date with the cloud.
	 */
	ZDCPullResult_Success = 0,
	
	/**
	 * The pull operation was cancelled by request.
	 */
	ZDCPullResult_ManuallyAborted = 1, // explicitly cancelled (by user, or due to backgrounding, etc)
	
	/**
	 * The pull operation failed temporarily.
	 *
	 * While the framework was pulling data from the cloud,
	 * the state of the treesystem changed sufficiently to require the pull system to start over.
	 *
	 * When this failure occurs, the framework will retry a pull soon.
	 */
	ZDCPullResult_Fail_CloudChanged = 2,
	
	/**
	 * The pull operation failed.
	 *
	 * The framework encountered an unknown error during the pull process.
	 * When this failure occurs, the framework will rety, using a delay based on exponential backoff.
	 */
	ZDCPullResult_Fail_Unknown = 3,
	
	/**
	 * The pull operation failed due to an authentication problem.
	 *
	 * The framework will be unable to retry a pull until the user is reauthenticated.
	 * Typically this occurs when the user account has been suspended or deleted (due to a missed payment).
	 */
	ZDCPullResult_Fail_Auth = 4,
};

/**
 * The PullManager handles pulling changes down from the cloud.
 *
 * The sync process can be broken down into 2 components: Push & Pull.
 * If you've used git before, you're already familiar with the process.
 * You push changes (made locally) to the cloud. And you pull changes (made on remote devices) from the cloud.
 *
 * This class handles the PULL side of things.
 *
 * In particular, the PullManager will automatically keep the local treesystem information
 * up-to-date with the cloud. This ONLY includes the treesystem metadata information, such as:
 * - names of nodes
 * - their permissions
 * - their location within the tree
 *
 * The ZeroDarkCloud framework doesn't automatically download node data (the content your app generates).
 * You are in complete control of that, which allows you to optimize for your app. For example, you can:
 * - download only recent data
 * - download data on demand (as the app needs it)
 * - download a small part of what's stored in the cloud (i.e. thumbnails instead of full images)
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
