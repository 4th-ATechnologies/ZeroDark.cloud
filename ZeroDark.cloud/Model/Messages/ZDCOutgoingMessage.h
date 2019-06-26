/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <ZDCSyncableObjC/ZDCSyncableObjC.h>

#import "ZDCCloudDataInfo.h"
#import "ZDCShareList.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * ZDCOutgoingMessage is a local representation of an outgoing message.
 * That is, a message being sent from a localUser to another user within the system.
 * The class encapsulates the minimum information needed by the ZeroDark framework to send the message.
 */
@interface ZDCOutgoingMessage : ZDCObject <NSCoding, NSCopying>

/**
 * Creates a new ZDCOutgoingMessage instance.
 */
- (instancetype)initWithSender:(NSString *)senderUserID receiver:(NSString *)receiverUserID;

/**
 * Every ZDCOutgoingMessage has a uuid. This is commonly referred to as the messageID:
 * > messageID == ZDCOutgoingMessage.uuid
 */
@property (nonatomic, copy, readonly) NSString *uuid;

/**
 * A reference to the corresponding localUser. (senderUserID == ZDCLocalUser.uuid)
 */
@property (nonatomic, copy, readonly) NSString *senderUserID;

/**
 * A reference to the corresponding user. (receiverUserID == ZDCUser.uuid)
 */
@property (nonatomic, copy, readonly) NSString *receiverUserID;

/**
 * The shareList encompasses the permissions for the node.
 */
@property (nonatomic, readonly) ZDCShareList *shareList;

/**
 * Message's can be assigned a "burn" date.
 * which tells the server to automatically delete the message at the specified time.
 *
 * This is especially useful when:
 * - you have temporary content that you want to cleanup from the cloud after a set time period
 * - you're sharing content with other users on a temporary basis
 *
 * @note The time at which the server deletes the content isn't exact.
 *       Currently the server performs this task as a batch operation every hour on the hour.
 */
@property (nonatomic, copy, readwrite, nullable) NSDate *burnDate;

#pragma mark Encryption Info

/**
 * The symmetric key that's used to encrypt & decrypt the message's data.
 * Every message uses a different (randomly generated) symmetric key.
 *
 * This property is created for you automatically.
 * For locally created messages, the property is randomly generated.
 * For nodes that are pulled down from the server,
 * the encryption key is extracted & decrypted from the cloud data.
 */
@property (nonatomic, copy, readonly) NSData *encryptionKey;

#pragma mark Cloud Info

/**
 * Every node has a server-assigned uuid, called the cloudID.
 * This value is immutable - once set by the server, it cannot be changed.
 *
 * The sync system uses the cloudID to detect when a node has been renamed or moved within the filesystem.
 * Since the server assigns this value, it is unknown until either:
 * - we've successfully uploaded the node's RCRD to the server at least once
 * - we've downloaded the node's RCRD from the server at least once
 */
@property (nonatomic, copy, readonly, nullable) NSString *cloudID;

/**
 * The eTag value of the RCRD file in the cloud.
 *
 * If this value is nil, then the node was created on this device,
 * and hasn't been updated yet.
 */
@property (nonatomic, copy, readonly, nullable) NSString *eTag_rcrd;

/**
 * The eTag value of the data fork in the cloud.
 *
 * If this value is nil, any of the following could be true:
 * - the node was created on this device, and hasn't been uploaded yet
 * - there isn't a data fork for this node (it's an empty node)
 * - the PullManager is in the process of updating, and hasn't discovered it yet
 */
@property (nonatomic, copy, readonly, nullable) NSString *eTag_data;

/**
 * Returns the later of the 2 dates: lastModified_rcrd & lastModified_data
 */
@property (nonatomic, readonly, nullable) NSDate *lastModified;

/**
 * The date in which the RCRD file was last modified on the server.
 * This relates to the last time the node's "filesystem" information was changed, such as permissions.
 */
@property (nonatomic, copy, readonly, nullable) NSDate *lastModified_rcrd;

/**
 * The date in which the DATA file was last modified on the server.
 * This relates to the last time the node's content was changed.
 */
@property (nonatomic, copy, readonly, nullable) NSDate *lastModified_data;

@end

NS_ASSUME_NONNULL_END
