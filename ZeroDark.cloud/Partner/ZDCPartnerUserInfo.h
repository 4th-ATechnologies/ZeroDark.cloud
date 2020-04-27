/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 */

#import <Foundation/Foundation.h>

#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPartnerUserInfo : NSObject

- (instancetype)initWithUserID:(NSString *)userID
                        region:(AWSRegion)region
                        bucket:(NSString *)bucket
                         stage:(NSString *)stage
                          salt:(NSString *)salt;

@property (nonatomic, copy, readonly) NSString *userID;

@property (nonatomic, assign, readonly) AWSRegion region;

@property (nonatomic, copy, readonly) NSString *bucket;

@property (nonatomic, copy, readonly) NSString *stage;

@property (nonatomic, copy, readonly) NSString *salt;

@end

NS_ASSUME_NONNULL_END
