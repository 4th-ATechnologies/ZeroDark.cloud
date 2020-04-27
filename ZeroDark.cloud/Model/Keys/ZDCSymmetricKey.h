/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <S4Crypto/S4Crypto.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The SymmetricKey class holds the information necessary to create a symmetric key within the S4Crypto library.
 */
@interface ZDCSymmetricKey : ZDCObject <NSCoding, NSCopying>

/**
 * The uuid is used for referencing a ZDCSymmetricKey instance in the LOCAL DATABASE.
 */
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
