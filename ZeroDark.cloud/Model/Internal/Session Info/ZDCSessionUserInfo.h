#import <Foundation/Foundation.h>
#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Stores the basic user information required for most network operations.
 *
 * The SessionManager is responsible for setting & updating these properties.
 */
@interface ZDCSessionUserInfo : NSObject <NSCopying>

@property (nonatomic, assign, readwrite) AWSRegion  region;
@property (nonatomic, copy,   readwrite) NSString * bucket;
@property (nonatomic, copy,   readwrite) NSString * stage;

@end

NS_ASSUME_NONNULL_END
