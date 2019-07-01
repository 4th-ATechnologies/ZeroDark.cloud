/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDCNodeAnchor : NSObject <NSCoding, NSCopying>

- (instancetype)initWithUserID:(NSString *)userID zAppID:(NSString *)zAppID dirPrefix:(NSString *)dirPrefix;

@property (nonatomic, copy, readonly) NSString *userID;

@property (nonatomic, copy, readonly) NSString *zAppID;

@property (nonatomic, copy, readonly) NSString *dirPrefix;

@end

NS_ASSUME_NONNULL_END
