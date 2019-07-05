/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <S4Crypto/S4Crypto.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The SymmetricKey class holds the information necessary to create a symmetric key within the S4Crypto library.
 */
@interface ZDCSymmetricKey : ZDCObject <NSCoding, NSCopying>

/**
 * Generates a random symmetic key.
 */
+ (instancetype)keyWithAlgorithm:(Cipher_Algorithm)algorithm
                      storageKey:(S4KeyContextRef)storageKey;

+ (instancetype)keyWithString:(NSString *)inKeyJSON
                     passCode:(NSString *)passCode;

+ (instancetype)keyWithS4Key:(S4KeyContextRef)symCtx
                  storageKey:(S4KeyContextRef)storageKey;

- (instancetype)initWithUUID:(NSString *)uuid
			            keyJSON:(NSString *)keyJSON;

@property (nonatomic, copy, readonly) NSString * uuid;

/**
 * A string that contains the serialized JSON parameters that can be used to create the symmetic key.
 */
@property (nonatomic, copy, readonly) NSString * keyJSON;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Convenience Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a parsed version of `pubKeyJSON`.
 * The parsed version is kept cached in memory for performance.
 */
@property (nonatomic, readonly) NSDictionary * keyDict;

@end

NS_ASSUME_NONNULL_END
