#import <Foundation/Foundation.h>
#import "AWSRegions.h"


@interface ZDCSessionUserInfo : NSObject <NSCopying>

@property (nonatomic, assign, readonly) AWSRegion  region;
@property (nonatomic, copy,   readonly) NSString * bucket;
@property (nonatomic, copy,   readonly) NSString * stage;

@end
