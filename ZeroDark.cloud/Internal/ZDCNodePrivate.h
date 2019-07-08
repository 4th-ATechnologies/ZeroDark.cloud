/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCNode.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCNode ()

/**
 * Used by ZDCTrunkNode, which has a deterministic uuid.
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID uuid:(nullable NSString *)uuid;

#pragma mark Messaging

@property (nonatomic, copy, readwrite, nullable) NSSet<NSString *> *pendingRecipients;

#pragma mark Encryption Info

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

@property (nonatomic, copy, readwrite, nullable) ZDCNodeAnchor *anchor;

@end

NS_ASSUME_NONNULL_END
