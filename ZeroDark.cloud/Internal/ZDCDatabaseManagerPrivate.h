/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCDatabaseManager.h"
#import "ZeroDarkCloud.h"

@interface ZDCDatabaseManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Attempts to create the YapDatabase instance using the given encrytionKey.
 * Returns NO if it fails.
 */
- (BOOL)setupDatabase:(ZDCDatabaseConfig *)config;

/**
 * The list of {localUserID, zAppID} tuples that currently have a ZDCCloud extension registered.
 */
- (NSArray<YapCollectionKey *> *)currentlyRegisteredTuples;

/**
 * The list of appIDs (for the given user) that currently have a ZDCloud extension.
 */
- (NSArray<NSString *> *)currentlyRegisteredAppIDsForUser:(NSString *)localUserID;

/**
 * The list of {localUserID, appID} tuples that had a ZDCCloud extension re-registered during database setup.
 */
- (NSArray<YapCollectionKey *> *)previouslyRegisteredTuples;

/**
 * The list of localUserIDs that had a ZDCCloud extension re-registered during database setup.
 */
- (NSSet<NSString *> *)previouslyRegisteredLocalUserIDs;

/**
 * The list of appIDs (for the given user) that had a ZDCloud extension re-registered during database setup.
 */
- (NSArray<NSString *> *)previouslyRegisteredAppIDsForUser:(NSString *)localUserID;

@end
