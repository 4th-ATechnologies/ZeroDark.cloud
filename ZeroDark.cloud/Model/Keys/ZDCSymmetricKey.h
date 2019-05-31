/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <S4Crypto/S4Crypto.h>
#import <ZDCSyncableObjC/ZDCObject.h>

@interface ZDCSymmetricKey : ZDCObject <NSCoding, NSCopying>

+ (id)keyWithAlgorithm:(Cipher_Algorithm)algorithm
            storageKey:(S4KeyContextRef)storageKey;

+ (id)keyWithString:(NSString *)inKeyJSON passCode:(NSString*)passCode;

- (id)initWithUUID:(NSString *)inUUID
           keyJSON:(NSString *)inKeyJSON;

+(id) keyWithS4Key:(S4KeyContextRef)symCtx
        storageKey:(S4KeyContextRef)storageKey;


@property (nonatomic, copy, readonly) NSString * uuid;
@property (nonatomic, copy, readonly) NSString * keyJSON;

// Convenience properties

@property (nonatomic, readonly) NSDictionary * keyDict; // parsed keyJSON (cached, thread-safe)

@end
