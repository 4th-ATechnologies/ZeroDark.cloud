/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/
#import <Foundation/Foundation.h>
#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN
@class ZDCUser;

 
@interface ZDCSearchUserMatching : NSObject  <NSCopying>
@property (nonatomic, copy, readonly) NSString     * auth0_profileID;
@property (nonatomic, copy, readonly) NSString     * matchingString;
@property (nonatomic, copy, readonly) NSArray <NSValue /*(NSRange) */*> * matchingRanges;
@end

/**
 * ZDCSearchUserResult is s similar to ZDCUser and it's values can be copied to ZDCUser
 */

@interface ZDCSearchUserResult : NSObject  <NSCopying>
@property (nonatomic, copy, readonly)           NSString     * uuid;
@property (nonatomic, readonly)                 AWSRegion      aws_region;
@property (nonatomic, copy, readonly, nullable) NSString     * aws_bucket;
@property (nonatomic, copy, readonly)           NSDictionary * auth0_profiles;
@property (nonatomic, copy, readwrite,nullable) NSString     * auth0_preferredID;
@property (nonatomic, copy, readonly, nullable) NSDate       * auth0_lastUpdated;
@property (nonatomic, copy, readonly, nullable) NSArray<ZDCSearchUserMatching*>* matches;

- (instancetype)initWithUser:( ZDCUser* _Nonnull )inUser;
@end

@interface ZDCSearchUserManager : NSObject

typedef NS_ENUM(NSInteger, ZDCSearchUserManagerResultStage) {
    ZDCSearchUserManagerResultStage_Unknown                = 0,
    ZDCSearchUserManagerResultStage_Database,
    ZDCSearchUserManagerResultStage_Cache,
    ZDCSearchUserManagerResultStage_Server,
    ZDCSearchUserManagerResultStage_Done,
    
};

-(void) unCacheAll;

-(void) unCacheUserID:(NSString*)userID;

-(void)queryForUsersWithString:(NSString *)queryString
                     forUserID:(NSString *)userID
               providerFilters:(nullable NSArray <NSString*>* )providers
               localSearchOnly:(BOOL)localSearchOnly
               completionQueue:(nullable dispatch_queue_t)completionQueue
                  resultsBlock:(void (^)(
                                         ZDCSearchUserManagerResultStage stage, NSArray <ZDCSearchUserResult*>* __nullable results,
                                         NSError * __nullable error))resultsBlock;


@end

NS_ASSUME_NONNULL_END
