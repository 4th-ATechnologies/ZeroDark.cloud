/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const Auth0APIManagerErrorDataKey;

@interface NSError (Auth0API)

- (nullable NSString *)auth0API_error;

@end

NS_ASSUME_NONNULL_END
