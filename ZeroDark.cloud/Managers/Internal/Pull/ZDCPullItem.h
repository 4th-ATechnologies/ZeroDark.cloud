/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "ZDCCloudPath.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPullItem : NSObject <NSCopying>

@property (nonatomic, assign, readwrite) AWSRegion region;
@property (nonatomic, copy, readwrite) NSString *bucket;

@property (nonatomic, copy, readwrite) NSArray<NSString*> *parents;

@property (nonatomic, copy, readwrite) ZDCCloudPath *rcrdCloudPath;
@property (nonatomic, copy, readwrite, nullable) NSString *rcrdETag;
@property (nonatomic, copy, readwrite, nullable) NSDate *rcrdLastModified;

@property (nonatomic, copy, readwrite, nullable) ZDCCloudPath *dataCloudPath;
@property (nonatomic, copy, readwrite, nullable) NSString *dataETag;
@property (nonatomic, copy, readwrite, nullable) NSDate *dataLastModified;

@property (nonatomic, strong, readwrite) id rcrdCompletionBlock;
@property (nonatomic, strong, readwrite, nullable) id ptrCompletionBlock;
@property (nonatomic, strong, readwrite, nullable) id dirCompletionBlock;

@end

NS_ASSUME_NONNULL_END
