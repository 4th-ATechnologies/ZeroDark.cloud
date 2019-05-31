/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCNode.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCNode ()

/**
 * Used by ZDCContainerNode, which has a deterministic uuid.
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID uuid:(nullable NSString *)uuid;

@property (nonatomic, copy, readwrite, nullable) NSData   * encryptionKey;
@property (nonatomic, copy, readwrite, nullable) NSData   * dirSalt;
@property (nonatomic, copy, readwrite, nullable) NSString * dirPrefix;

#pragma mark Cloud Info

@property (nonatomic, copy, readwrite, nullable) NSString *cloudID;

@property (nonatomic, copy, readwrite, nullable) NSString *eTag_rcrd;
@property (nonatomic, copy, readwrite, nullable) NSString *eTag_data;

@property (nonatomic, copy, readwrite, nullable) NSDate *lastModified_rcrd;
@property (nonatomic, copy, readwrite, nullable) NSDate *lastModified_data;

@property (nonatomic, copy, readwrite, nullable) ZDCCloudDataInfo *cloudDataInfo;

@property (nonatomic, copy, readwrite, nullable) NSString *explicitCloudName;

@property (nonatomic, copy, readwrite, nullable) NSString *ownerID;
@property (nonatomic, copy, readwrite, nullable) NSString *ownerCloudAnchor;

@end

NS_ASSUME_NONNULL_END
