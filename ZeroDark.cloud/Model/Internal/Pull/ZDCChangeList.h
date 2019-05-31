#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

#import "ZDCChangeItem.h"

/**
 * This class stores the ordered array of changes that the client has fetched from the server.
 * It encapsulates the logic to properly update the array, and process the array.
 *
 * Note: Both the client & server have limits on the size of this array,
 * so it shouldn't be a problem to simply store the entire array in a single object.
 */
@interface ZDCChangeList : ZDCObject

/**
 * Use this when starting a full pull.
 */
- (instancetype)initWithLatestChangeID_remote:(NSString *)latestChangeID_remote;

/**
 * This is the latest changeToken (that we know about) on the server.
 * The knowledge about the server state doesn't imply anything about the local state.
 */
@property (nonatomic, readonly) NSString *latestChangeID_remote;

/**
 * This is the latest changeToken that we've synced locally.
 * If this value is nil, then a full pull is required.
 * If this value is non-nil, then a quick pull can be attempted.
 */
@property (nonatomic, readonly) NSString *latestChangeID_local;

/**
 * A full pull involves 2 steps:
 * 1. the server informs us of the latest changeToken that it has
 *    - we can either ask for this info directly
 *    - or we obtain it indirectly, because we attempt a quick pull,
 *      but the server informs us that we're too far behind,
 *      and also gives us the latest changeToken (to prevent another roundtrip).
 * 2. we sync the entire bucket (app specific subset)
 *
 * Upon completion, this method is called, which will set the
 * latestChangeToken_local to match latestChangeToken_remote.
 *
 * Note: We could theoretically be a little bit further ahead.
 * But this is always the case with asynchronous networking.
 * And the sync logic will sort out any discrepencies.
 */
- (void)didCompleteFullPull;

/**
 * Merges the changes into the ordered list.
 * Protects against possible edge cases that can occur due to simulataneous push & pull operations.
 */
- (void)didFetchChanges:(NSArray<ZDCChangeItem *> *)changes
                  since:(NSString *)changeID
                 latest:(NSString *)latestChangeID;

- (BOOL)hasPendingChange;

- (void)didProcessChangeIDs:(NSSet<NSString *> *)changeIDs;

- (void)didReceiveLocallyTriggeredPushWithOldChangeID:(NSString *)oldChangeID
                                          newChangeID:(NSString *)newChangeID;

- (void)didReceivePushWithChange:(ZDCChangeItem *)change
                     oldChangeID:(NSString *)oldChangeID
                     newChangeID:(NSString *)newChangeID;

#pragma mark Optimization Engine

/**
 * Returns the next change that can be processed.
 * The optimization engine may merge multiple changes in the queue into a single change,
 * and then return that change to you. When this occurs, the outChangeIDs will contain multiple values.
 *
 * You should ALWAYS use the returned outChangeIDs when invoking `didProcessChangeIDs`.
 */
- (ZDCChangeItem *)popNextPendingChange:(NSOrderedSet<NSString *> **)outChangeIDs;

@end
