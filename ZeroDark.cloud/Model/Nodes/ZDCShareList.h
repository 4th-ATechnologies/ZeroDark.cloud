/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

#import "ZDCShareItem.h"
#import "ZDCTreesystemPath.h"

#import <ZDCSyncableObjC/ZDCSyncableObjC.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Keys are a compound component: "{type}:{identifier}"
 * This is the type when sharing to another user.
 */
extern NSString *const ZDCShareKeyType_User;

/**
 * Keys are a compound component: "{type}:{identifier}"
 * This is the type when sharing with a server.
 *
 * Website resource goes here:
 *   Explains how app developers can selectively share node content
 *   with their own customer server(s), and how ZeroDark.cloud notifies their server endpoint(s).
 */
extern NSString *const ZDCShareKeyType_Server;

/**
 * Keys are a compound component: "{type}:{identifier}"
 * This is a type that allows a node's encryptionKey to be wrapped with a passphrase (e.g. PBKDF2).
 *
 * You might use this if you want to share a node with a non-app-user.
 * For example, you may develop a website to accompany your app.
 * And the website enables your users to share content with non-users via a passphrase.
 */
extern NSString *const ZDCShareKeyType_Passphrase;

/**
 * ZDCShareList encapsulates the permissions information for a node.
 *
 * By default, a node inherits the same permissions as its parent node.
 * For example, a newly created node in the root of the Home container
 * will only include permissions for the localUser (rw).
 *
 * To share a node with another user will require you to add permissions for that user here.
 * For information on sharing data with other users:
 * - amazing website resource #1
 * - amazing website resource #2
 *
 * Advanced Options:
 *
 * The ZeroDark.cloud server also allows you to share to resources other than users.
 * For example, your application may wish to share information with your custom backend system.
 * Here's how that works:
 * - Sign into the ZeroDark.cloud developer dashboard
 * - Create a server instance (you'll receive a UUID for this instance)
 * - Register one or more endpoints so that the ZeroDark.cloud system can notify your server(s)
 * - Then, when nodes are created/modified/deleted, which have in their
 *   shareList a key of "SRV:<your_server_id>", the ZeroDark.cloud will notify your server(s) via
 *   the current set of registered endpoints.
 */
@interface ZDCShareList : ZDCObject <NSCoding, NSCopying, ZDCSyncable>

/**
 * Creates an empty shareList.
 */
- (id)init;

/**
 * Creates a shareList by parsing the given dictionary.
 * This dictionary comes from a RCRD file.
 */
- (id)initWithDictionary:(nullable NSDictionary *)dictionary;


/** Returns the "raw" version of the shareList, as it would appear in the cloud. */
@property (nonatomic, readonly) NSDictionary *rawDictionary;

#pragma mark Counts

/** Returns the number of shareItems in the list */
@property (nonatomic, readonly) NSUInteger count;

/**
 * Returns the number of shareItems in the list,
 * counting only the shareItems that are for a user.
 */
- (NSUInteger)countOfUserIDs;

/**
 * Returns the number of shareItems in the list,
 * counting only the shareItems that are for a user,
 * and excluing the given userID.
 *
 * This is a common use case.
 * For example, you want to know how many other people the node is being shared with.
 * I.e. the count excluding the localUserID.
 */
- (NSUInteger)countOfUserIDsExcluding:(nullable NSString *)userID
NS_SWIFT_NAME(countOfUserIDs(excluding:));

#pragma mark Read

/**
 * Returns whether or not a shareItem exists for the given key.
 * Keys are a compound component: "{type}:{identifier}"
 *
 * @see `-hasShareItemForUserID:`
 * @see `-hasShareItemForServerID:`
 */
- (BOOL)hasShareItemForKey:(NSString *)key;

/** Returns whether or not a shareItem exists for the given userID. */
- (BOOL)hasShareItemForUserID:(NSString *)userID;

/** Returns whether or not a shareItem exists for the given serverID. */
- (BOOL)hasShareItemForServerID:(NSString *)serverID;

/**
 * Returns the shareItem for the given key.
 * Keys are a compound component: "{type}:{identifier}"
 *
 * @see `-shareItemForUserID:`
 * @see `-shareItemForServerID:`
 */
- (nullable ZDCShareItem *)shareItemForKey:(NSString *)key;

/** Returns the shareItem for the given userID. */
- (nullable ZDCShareItem *)shareItemForUserID:(NSString *)userID;

/** Returns the shareItem for the gien serverID. */
- (nullable ZDCShareItem *)shareItemForServerID:(NSString *)serverID;

#pragma mark Write

/**
 * Sets the shareItem for the given key.
 * Keys are a compound component: "{type}:{identifier}"
 *
 * @see `-setShareItem:forUserID:`
 * @see `-setShareItem:forServerID:`
 *
 * @return NO if a shareItem already exists for the given key.
 *         In which case you shouldn't be replacing it.
 *         You should be modifying the existing shareItem.
 *         That way your changes are properly tracked & merged.
 */
- (BOOL)addShareItem:(ZDCShareItem *)item forKey:(NSString *)key;

/**
 * Sets the shareItem for the given userID.
 *
 * @return NO if a shareItem already exists for the given key.
 *         In which case you shouldn't be replacing it.
 *         You should be modifying the existing shareItem.
 *         That way your changes are properly tracked & merged.
 */
- (BOOL)addShareItem:(ZDCShareItem *)item forUserID:(NSString *)userID;

/**
 * Sets the shareItem for the given serverID.
 *
 * @return NO if a shareItem already exists for the given key.
 *         In which case you shouldn't be replacing it.
 *         You should be modifying the existing shareItem.
 *         That way your changes are properly tracked & merged.
 */
- (BOOL)addShareItem:(ZDCShareItem *)item forServerID:(NSString *)serverID;

/**
 * Removes the shareItem with the given key.
 * Keys are a compound component: "{type}:{identifier}"
 *
 * @see `-removeShareItemForUserID:`
 * @see `-removeShareItemForServerID:`
 */
- (void)removeShareItemForKey:(NSString *)key;

/** Removes the shareItem for the given userID. */
- (void)removeShareItemForUserID:(NSString *)userID;

/** Removes the shareItem for the given serverID. */
- (void)removeShareItemForServerID:(NSString *)serverID;

/** Clears the list - afterwards there will be zero shareItems in the list. */
- (void)removeAllShareItems;

#pragma mark Enumerate

/**
 * Returns all keys in the list.
 * Keys are a compound component: "{type}:{identifier}"
 */
- (NSArray<NSString *> *)allKeys;

/**
 * Returns all userID's in the list.
 *
 * Each key is a compound component: "{type}:{identifier}"
 * If the 'type' == ZDCShareKeyType_User, then the 'identifier' component is a userID.
 * This method extracts all the userID's from those keys which are user keys.
 *
 * @see countOfUserIDs
 * @see countOfUserIDsExcluding:
 */
- (NSArray<NSString *> *)allUserIDs;

/**
 * Enumerates all items in the list.
 */
- (void)enumerateListWithBlock:(void (^)(NSString *key, ZDCShareItem *shareItem, BOOL *stop))block;

#pragma mark Equality

/**
 * Returns true if the parameter is of type ZDCShareList, and all values are the same.
 */
- (BOOL)isEqual:(nullable id)another;

/**
 * Returns true if both lists contain the same shareItems.
 */
- (BOOL)isEqualToShareList:(ZDCShareList *)another;

#pragma mark Class Utilities

/**
 * Keys are a compound component: "{type}:{identifier}"
 * This method returns whether the type is ZDCShareKeyType_User.
 */
+ (BOOL)isUserKey:(NSString *)key;

/**
 * Keys are a compound component: "{type}:{identifier}"
 * This method returns whether the type is ZDCShareKeyType_Server.
 */
+ (BOOL)isServerKey:(NSString *)key;

/** Creates a key: "UID:{userID_goes_here}" */
+ (NSString *)keyForUserID:(NSString *)userID;

/** Extracts userID from key: "UID:{userID_extracted_from_here}" */
+ (nullable NSString *)userIDFromKey:(NSString *)key;

/** Creates a key: "SRV:{serverID_goes_here}" */
+ (NSString *)keyForServerID:(NSString *)serverID;

/** Extracts serverID from key: "SRV:{serverID_extracted_from_here}" */
+ (nullable NSString *)serverIDFromKey:(NSString *)key;

/**
 * Returns the default set of permissions for the given container.
 * These are hard-coded on a per-container basis.
 */
+ (ZDCShareList *)defaultShareListForContainer:(ZDCTreesystemContainer)container
                               withLocalUserID:(NSString *)localUserID;

@end

NS_ASSUME_NONNULL_END
