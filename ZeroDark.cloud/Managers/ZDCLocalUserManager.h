/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCLocalUser.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The LocalUserManager simplifies many aspects of determining sync state.
 */
@interface ZDCLocalUserManager : NSObject

#pragma mark Single User Mode

/**
 * Returns non-nil if a ZDCLocalUser exists in the database.
 * This is primarily useful for applications that support only a single logged-in user.
 *
 * @note If there are multiple logged in users, the returned localUser is not guaranteed to be consistent.
 */
- (nullable ZDCLocalUser *)anyLocalUser:(YapDatabaseReadTransaction *)transaction;

#pragma mark List & Enumerate

/**
 * Returns a list of all localUserIDs. (localUserID == ZDCLocalUser.uuid)
 */
- (NSArray<NSString *> *)allLocalUserIDs:(YapDatabaseReadTransaction *)transaction;

/**
 * Returns a list of all localUsers.
**/
- (NSArray<ZDCLocalUser *> *)allLocalUsers:(YapDatabaseReadTransaction *)transaction;

/**
 * Enumerates all localUserID's. (localUserID == ZDCLocalUser.uuid)
 */
- (void)enumerateLocalUserIDsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                  usingBlock:(void (^)(NSString *localUserID, BOOL *stop))enumBlock;

/**
 * Enumerates all local users.
 */
- (void)enumerateLocalUsersWithTransaction:(YapDatabaseReadTransaction *)transaction
                                usingBlock:(void (^)(ZDCLocalUser *localUser, BOOL *stop))enumBlock;

#pragma mark User Management

/**
 * Fully deletes the local user and all associated items.
 *
 * The following items will be deleted from the database:
 * - ZDCLocalUser
 * - Local user's private key
 * - Local user's access key
 * - Local user's cached authentication
 * - All treesystem ZDCNode's
 * - All queued ZDCCloudOperation's
 */
- (void)deleteLocalUser:(NSString *)localUserID
            transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark Debugging & Development

/**
 * Creates a local user from a JSON file.
 *
 * @param json
 *   A dictionary that contains all the information necessary to create a localUser.
 *
 * @param transaction
 *   The database transaction in which to create the necessary objects
 *
 * @param outError
 *   If an error occurs, this will describe what went wrong
 */
- (nullable ZDCLocalUser *)createLocalUserFromJSON:(NSDictionary *)json
                                       transaction:(YapDatabaseReadWriteTransaction *)transaction
                                             error:(NSError *_Nullable *_Nullable)outError;

@end

NS_ASSUME_NONNULL_END
