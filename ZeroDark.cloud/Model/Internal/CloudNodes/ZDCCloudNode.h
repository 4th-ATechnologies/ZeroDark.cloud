#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

#import "AWSRegions.h"
#import "ZDCCloudLocator.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * ZDCCloudNode represents a node that exists in the cloud,
 * but isn't represented in the local treesystem (as a ZDCCNode) because either:
 *
 * - the node has been deleted locally (but we haven't yet pushed the delete request to the server)
 * - the node appears to be an orphan (the rcrd file exists on the server, but there's no matching data file)
 */
@interface ZDCCloudNode : ZDCObject <NSCoding, NSCopying>

/** Designated initializer */
- (instancetype)initWithLocalUserID:(NSString *)localUserID cloudLocator:(ZDCCloudLocator *)cloudLocator;

/**
 * Every ZDCCloudNode has a uuid. This is commonly referred to as the cloudNodeID:
 * > cloudNodeID == ZDCCloudNode.uuid
 *
 * The cloudNodeID is only for referencing a ZDCCloudNode instance in the LOCAL DATABASE.
 * CloudNodeID's are NOT uploaded to the cloud, nor are they synced in any way.
 */
@property (nonatomic, copy, readonly) NSString *uuid;

/**
 * A reference to the corresponding localUser. (localUserID == ZDCLocalUser.uuid)
 */
@property (nonatomic, copy, readonly) NSString *localUserID;

/**
 * The location of the node in the cloud.
 */
@property (nonatomic, copy, readwrite) ZDCCloudLocator *cloudLocator;

/**
 * Corresponds to `-[ZDCNode dirPrefix]`.
 *
 * That is, if this node has children,
 * this property specifies the dirPrefix that will be a part of the child's cloudLocator.cloudPath.dirPrefix.
 *
 * This value is only known if the node has been queued for deletion.
 */
@property (nonatomic, copy, readonly, nullable) NSString *dirPrefix;

/**
 * Corresponds to `-[ZDCNode eTag_rcrd]`.
 */
@property (nonatomic, copy, readwrite) NSString * eTag_rcrd;

/**
 * Corresponds to `-[ZDCNode eTag_data]`.
 *
 * If this value is null, the node may be an orphan.
 * (i.e. the rcrd file exists on the server, but there's no matching data file)
 */
@property (nonatomic, copy, readwrite, nullable) NSString * eTag_data;

/**
 * True if the node is queued for deletion.
 * (i.e. it exists in the cloud, but not in the local treesystem due to a local delete request)
 */
@property (nonatomic, assign, readwrite) BOOL isQueuedForDeletion;

//@property (nonatomic, copy, readwrite) NSDate *orphan_detectionDate;    // when we discovered it
//@property (nonatomic, copy, readwrite) NSDate *orphan_modificationDate; // when it was modified on cloud
//@property (nonatomic, copy, readwrite) NSDate *orphan_verificationDate; // used by PushManager for double-check

@end

NS_ASSUME_NONNULL_END
