/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "S3ObjectInfo.h"
#import "ZDCPullItem.h"

@interface ZDCPullState : NSObject

@property (nonatomic, copy, readonly) NSString *localUserID;
@property (nonatomic, copy, readonly) NSString *treeID;
@property (nonatomic, copy, readonly) NSString *pullID;

@property (atomic, assign, readwrite) BOOL hasProcessedChanges;
@property (atomic, assign, readwrite) BOOL needsFetchMoreChanges;
@property (atomic, assign, readwrite) BOOL isFullPull;

@property (atomic, strong, readonly) NSArray<NSURLSessionTask *> *tasks;
@property (atomic, assign, readonly) NSUInteger tasksCount;

@property (atomic, strong, readonly) NSSet<NSString *>* unprocessedNodeIDs;
@property (atomic, strong, readonly) NSSet<NSString *>* unprocessedIdentityIDs;
@property (atomic, strong, readonly) NSSet<NSString *>* unknownUserIDs;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark List Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)pushList:(NSArray<S3ObjectInfo *> *)objectList withRootNodeID:(NSString *)rootNodeID;

- (NSArray<S3ObjectInfo *> *)popListWithPrefix:(NSString *)prefix rootNodeID:(NSString *)rootNodeID;

- (S3ObjectInfo *)popItemWithPath:(NSString *)path rootNodeID:(NSString *)rootNodeID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull Queue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enqueueItem:(ZDCPullItem *)item;

- (NSUInteger)queueLength;

- (ZDCPullItem *)dequeueItemWithPreferredNodeIDs:(NSSet<NSString *> *)preferredNodeIDs;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Task Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Adds a task to the list.
 *
 * We maintain a list of pending tasks so that we can cancel them all if
 * the recursive sync operation (as a whole) is cancelled.
**/
- (void)addTask:(NSURLSessionTask *)task;

/**
 * We maintain a list of pending tasks so that we can cancel them all if
 * the recursive sync operation (as a whole) is cancelled.
 **/
- (void)removeTask:(NSURLSessionTask *)task;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Node Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * When we start a full pull, we add all uploaded nodeIDs to this list.
 * Thenk as we find remote matches, we remove nodeIDs from this list.
 *
 * Some nodes that initially appear to be deleted may have actually been moved.
 * However, during the recursive sync, we have no idea where a moved node may have ended up.
 *
 * If they end up being moved, then they'll be automatically moved (and removed from this list).
 * But if they're actually deleted, then we'll have this list to process at the end of the recursive sync.
**/
- (void)addUnprocessedNodeIDs:(NSArray<NSString *>*)nodeIDs;

- (void)removeUnprocessedNodeID:(NSString *)nodeID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Avatar Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)addUnprocessedIdentityIDs:(NSArray<NSString *> *)identityIDs;

- (void)removeUnprocessedIdentityID:(NSString *)identityID;
 
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Tracking
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * As we process each node, we keep track of any unknown users we encounter.
 * We then fetch these users upon pull completion.
**/
- (void)addUnknownUserIDs:(NSSet<NSString *> *)userIDs;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark One-Time Flags
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns YES if this is the first time we've detected a change on the server that requires pulling.
**/
- (BOOL)isFirstChangeDetected;

/**
 * Returns YES if this is the first time we're processing an auth failure.
**/
- (BOOL)isFirstAuthFailure;

@end
