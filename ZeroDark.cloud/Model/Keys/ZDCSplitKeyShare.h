/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZDCSplitKeyShare class holds the information necessary to create a split key key within the S4Crypto library.
 */

@interface ZDCSplitKeyShare : ZDCObject <NSCoding, NSCopying>

- (instancetype)initWithLocalUserID:(NSString *)localUserID
								  shareData:(NSData *)shareData;

@property (nonatomic, copy, readonly) NSString * uuid;
@property (nonatomic, copy, readonly) NSString * localUserID;

// calculated from shareData
@property (nonatomic, readonly) NSDictionary *keyDict; // Parsed splitKeyData

@property (nonatomic, copy, readonly) NSString * ownerID;
@property (nonatomic, copy, readonly) NSString * shareID;
@property (nonatomic, copy, readonly) NSString * shareUserID;


@end

NS_ASSUME_NONNULL_END
