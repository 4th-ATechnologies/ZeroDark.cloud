/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "S3ObjectInfo.h"
#import "ZDCPullState.h"
#import "ZeroDarkCloud.h"

/**
 * How does Bob get a list of items within a shared node that resides in Alice's bucket ?
 *
 * Description of the problem:
 *
 * - Alice is the only user with permission to perform an AWS-S3-level "list" of her bucket:
 *   https://docs.aws.amazon.com/AmazonS3/latest/API/v2-RESTBucketGET.html
 *
 * - But if Alice is sharing a node with Bob,
 *   then Bob will ultimately need the ability to list the children of that node.
 *
 * - So to handle this, the ZeroDark.cloud servers act as a "list proxy".
 *   They will forward the info to Bob IFF he has read permission for the node.
 */
@interface ZDCProxyList : NSObject

+ (void)recursiveProxyList:(ZeroDarkCloud *)zdc
                    region:(AWSRegion)region
                    bucket:(NSString *)bucket
                 cloudPath:(NSString *)cloudPath
                 pullState:(ZDCPullState *)pullState
           completionQueue:(dispatch_queue_t)completionQueue
           completionBlock:(void (^)(NSArray<S3ObjectInfo *>*, NSError*))completionBlock;

@end
