/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>
#import "ZDCCloudPath.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A GraftInvite encompasses the information required to complete a graft.
 *
 * For example, if Alice wants to collaborate with Bob,
 * then she wants to share a branch of her treesystem with Bob.
 * There are 2 steps required for Alice.
 *
 * First, she needs to give Bob permission to access her branch.
 * She can accomplish this with `-[ZDCCloudTransaction recursiveAddShareItem:forUserID:nodeID:]`.
 *
 * Second, she needs to send a message to Bob.
 * The message is some kind of application-specific "invite".
 * And the invite must contain, at a minimum, the information contained in this class.
 *
 * After Bob receives the invite message, he can accept the invite via
 * `-[ZDCCloudTransaction graftNodeWithLocalPath:::::]`.
 */
@interface ZDCGraftInvite : NSObject

/**
 * Standard initializer.
 */
- (instancetype)initWithCloudID:(NSString *)cloudID cloudPath:(ZDCCloudPath *)cloudPath;

/**
 * Corresponds to ZDCNode.cloudID.
 *
 * Every node has a server-assigned uuid, called the cloudID.
 * Since the value is server-assigned, we won't know this value until after the node has been uploaded.
 *
 * This value is important, because it ensures the recipient of the invite can still accept our
 * invitation even if we move the node.
 *
 * For example:
 * If Alice wants to collaborate with Bob, she may send an invite the references her node at home://foo/bar
 * But if Alice renamed the node to home://foo/buzz, then the location of the node changes,
 * both in her treesystem, and in the cloud.
 * By including the cloudID, Bob will be able to track down the current location of the node.
 * (The server has an API that allows Bob to perform this task, if necessary.)
 */
@property (nonatomic, copy, readonly) NSString *cloudID;

/**
 * Represents the current location of the node in the cloud.
 *
 * If the cloudPath happens to change, the cloudID ensures the recipient can still
 * track down current cloudPath of the node.
 */
@property (nonatomic, copy, readonly) ZDCCloudPath *cloudPath;

@end

NS_ASSUME_NONNULL_END
