/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCAudit.h"

@interface ZDCAudit ()

- (instancetype)initWithLocalUserID:(NSString *)localUserID
                             region:(NSString *)region
                             bucket:(NSString *)bucket
                        accessKeyID:(NSString *)accessKeyID
                             secret:(NSString *)secret
                            session:(NSString *)session
                         expiration:(NSDate *)expiration;

@end
