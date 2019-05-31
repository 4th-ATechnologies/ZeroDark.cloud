#import "ZDCSessionUserInfo.h"


@interface ZDCSessionUserInfo ()

@property (nonatomic, assign, readwrite) AWSRegion  region;
@property (nonatomic, copy,   readwrite) NSString * bucket;
@property (nonatomic, copy,   readwrite) NSString * stage;

@end
