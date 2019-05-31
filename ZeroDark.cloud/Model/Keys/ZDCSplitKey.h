/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/

#import <S4Crypto/S4Crypto.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The ZDCSplitKey class holds the information necessary to create a split key key within the S4Crypto library.
 */

@interface ZDCSplitKey : ZDCObject <NSCoding, NSCopying>

- (instancetype)initWithLocalUserID:(NSString *)localUserID
									splitNum:(NSUInteger)splitNum
								  splitData:(NSData *)splitData;

@property (nonatomic, copy, readonly) NSString * uuid;
@property (nonatomic, copy, readonly) NSString * localUserID;
@property (nonatomic, readonly) 		  NSUInteger splitNum;

/**
 *  Set of shareIDs that have been successfully shared
 *
 */

@property (nonatomic, copy, readwrite, nullable) NSSet<NSString*> *sentShares;

/**
 *  User settable comment for description of what this key is for.
 *
 */

@property (nonatomic, copy, readwrite, nullable) NSString* comment;

// calculated from splitKeyData
@property (nonatomic, readonly) NSDictionary *keyDict; // Parsed splitKeyData
@property (nonatomic, copy, readonly) NSString * ownerID;
@property (nonatomic, readonly) NSUInteger threshold;
@property (nonatomic, readonly) NSUInteger totalShares;
@property (strong, nonatomic, readonly, nullable) NSDate *creationDate;
@property (strong, nonatomic, readonly, nullable) NSArray <NSString*>*shareIDs;
@property (strong, nonatomic, readonly, nullable) NSDictionary <NSString*, NSNumber*>* shareNums;

@end

NS_ASSUME_NONNULL_END
