/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (ZeroDark)

/**
 * Standardized routines for encrypting small amounts of data with a symmetric key.
**/

- (NSData *)encryptedDataWithSymmetricKey:(NSData *)key error:(NSError **)errorOut;
- (NSData *)decryptedDataWithSymmetricKey:(NSData *)key error:(NSError **)errorOut;

@end

NS_ASSUME_NONNULL_END
