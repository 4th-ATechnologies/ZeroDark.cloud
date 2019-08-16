/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The objects that you link to nodes may optionally implement this protocol.
 *
 * Here's how it works:
 * - You create an object (of your own custom class) and store it in the database.
 * - You also link that object to a node/treesystemPath in the cloud.
 * - At some later point in time, you modify the object and re-save it to the database.
 * - At this point the framework knows your object is linked to an object in the cloud.
 *   And it sees that you're modifying the object in the database.
 *   So the framework wants to know if the modification you made affects the cloud,
 *   and whether it should queue an upload for the modified node.
 * - The framework can get an answer to this question by using this protocol.
 */
@protocol ZDCNodeLink
@required

/**
 * Return non-nil if the changes to your object affect the cloud-version of the node,
 * and you would like the framework to automatically schedule an upload operation to update the cloud.
 *
 * The dictionary you return will be stored in the queued `-[ZDCCloudOperation changeset_obj]`.
 *
 * If you take advantage of the ZDCSyncable system, the changeset can be generated for you automatically,
 * and you'll get proper merging & conflict resolution too.
 */
- (nullable NSDictionary *)changeset;

@end

NS_ASSUME_NONNULL_END
