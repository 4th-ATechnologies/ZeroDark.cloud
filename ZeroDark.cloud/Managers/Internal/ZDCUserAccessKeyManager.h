/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ZDCSymmetricKey;

@interface ZDCAccessKeyBlob : NSObject

- (id)initWithLocalUserID:(NSString *)localUserID
			accessKey:(ZDCSymmetricKey *)accessKey;

@property (nonatomic, copy, readonly) NSString * localUserID;
@property (nonatomic, copy, readonly) ZDCSymmetricKey * accessKey;

@end

@interface ZDCUserAccessKeyManager : NSObject

- (ZDCAccessKeyBlob *)blobFromData:(NSData *)blobData
					   localUserID:(NSString *)localUserID
							 error:(NSError *_Nullable *_Nullable)errorOut;

@end

NS_ASSUME_NONNULL_END
