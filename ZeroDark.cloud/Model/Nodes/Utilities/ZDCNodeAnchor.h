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
 * When a node is located in a different bucket (not the localUserID's bucket),
 * then the ZDCNodeAnchor class is used as a reference point for the foreign node.
 *
 * The ZDCNodeAnchor class is immutable.
 */
@interface ZDCNodeAnchor : NSObject <NSCoding, NSCopying>

/**
 * Creates a new anchor instance using the given properties.
 */
- (instancetype)initWithUserID:(NSString *)userID zAppID:(NSString *)zAppID dirPrefix:(NSString *)dirPrefix;

/**
 * The userID who owns the bucket in which the node resides. (userID == ZDCUser.uuid)
 *
 * The corresponding AWS region & bucket can be fetched from the ZDCUser.
 */
@property (nonatomic, copy, readonly) NSString *userID;

/**
 * Corresponds to `[ZDCCloudPath zAppID]`.
 */
@property (nonatomic, copy, readonly) NSString *zAppID;

/**
 * Corresponds to `[ZDCCloudPath dirPrefix]`.
 */
@property (nonatomic, copy, readonly) NSString *dirPrefix;

@end

NS_ASSUME_NONNULL_END
