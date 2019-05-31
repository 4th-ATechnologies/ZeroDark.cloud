/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableDictionary (ZeroDark)

/**
 * JSON doesn't support raw data.
 * This method automatically converts data objects to base64 encoded strings.
**/
- (void)normalizeForJSON;

/**
 * JSON doesn't support raw data.
 * This method performs the inverse of normalizeForJSON,
 * and automatically converts base64 encoded strings back to raw data objects.
**/
- (void)normalizeFromJSON;

@end

NS_ASSUME_NONNULL_END
