/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZeroDarkCloud.h"

@class ZDCSymmetricKey;

NS_ASSUME_NONNULL_BEGIN

@interface ZDCAccessKeyBlob : NSObject

- (id)initWithLocalUserID:(NSString *)localUserID
			accessKey:(ZDCSymmetricKey *)accessKey;

@property (nonatomic, copy, readonly) NSString * localUserID;
@property (nonatomic, copy, readonly) ZDCSymmetricKey * accessKey;

@end

@interface ZDCUserAccessKeyManager : NSObject

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (ZDCAccessKeyBlob *)blobFromData:(NSData *)blobData
					   localUserID:(NSString *)localUserID
							 error:(NSError *_Nullable *_Nullable)errorOut;

@end

NS_ASSUME_NONNULL_END
