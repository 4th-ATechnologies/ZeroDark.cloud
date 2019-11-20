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
 * Simple utility methods for parsing the JSON & fields within a JWT.
 */
@interface JWTUtilities : NSObject

/**
 * Parses the JSON from the JWT, and extracts the expiration date.
 *
 * @note This method doesn't verify the JWT in any manner. If you need that, use a proper JWT framework.
 */
+ (nullable NSDate *)expireDateFromJWTString:(NSString *)token error:(NSError *_Nullable *_Nullable)errorOut;

@end

NS_ASSUME_NONNULL_END
