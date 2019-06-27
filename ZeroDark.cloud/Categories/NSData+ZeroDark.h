/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
