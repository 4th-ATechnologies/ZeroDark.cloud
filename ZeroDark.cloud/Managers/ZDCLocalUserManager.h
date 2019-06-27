/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

#import "ZDCLocalUser.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The LocalUserManager simplifies many aspects of determining sync state.
 */
@interface ZDCLocalUserManager : NSObject

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


/**
 * Given an array of ZDCLocalUser this will produce an array of unambiguous names
 and uuids  in the form  - useful for filling an NSMenu
 
 <__NSArrayM 0x60000084d410>(
 {
 displayName = "Vinnie Moscaritolo (Amazon)";
 userID = 641ihdfw7qf5pj78pfxbunwkkwonu5rg;
 },
 {
 displayName = "Vinnie Moscaritolo (Facebook)";
 userID = 7gzeud1d9iam5b1d31j8sk6pnnktosut;
 },
 {
 displayName = "Vinnie Moscaritolo (GitHub)";
 userID = euf9kcc4sfqmwc6h5u66zguhxx78bmen;
 },
 {
 displayName = vinthewrench;
 userID = j1bhup8yts5wi81q4pdkdj9owzs1w5kh;
 },
 {
 displayName = xxx;
 userID = b3o8qh8gy4fzfiwrrho3wd9dtjypryue;
 }
 )
 **/

-(NSArray <NSDictionary*> *) sortedUnambiguousUserInfoWithLocalUsers:(NSArray <ZDCLocalUser *> *)usersIn;

#pragma mark User Management

/**
 * Creates a local user from a JSON file.
 *
 * @param json
 *   A dictionary that contains all the information necessary to create a localUser.
 *
 * @param transaction
 *   The database transaction in which to create the necessary objects
 *
 * @param outLocalUserID
 *   Returns the ZDCLocalUser.uuid that was created.
 *
 * @return If an error occurs, this will describe what went wrong
 */
- (nullable NSError *)createLocalUserFromJSON:(NSDictionary *)json
                                  transaction:(YapDatabaseReadWriteTransaction *)transaction
                               outLocalUserID:(NSString *_Nullable *_Nullable)outLocalUserID;

/**
 * Delete the Local User
 */
- (void)deleteLocalUser:(NSString *)localUserID
            transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
