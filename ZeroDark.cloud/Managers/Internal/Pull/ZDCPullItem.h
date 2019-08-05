/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPullItem : NSObject

@property (nonatomic, assign, readwrite) AWSRegion region;
@property (nonatomic, copy, readwrite) NSString *bucket;

@property (nonatomic, copy, readwrite) NSArray<NSString*> *parents;

@property (nonatomic, copy, readwrite) NSString *rcrdPath;
@property (nonatomic, copy, readwrite, nullable) NSString *rcrdETag;
@property (nonatomic, copy, readwrite, nullable) NSDate *rcrdLastModified;

@property (nonatomic, copy, readwrite, nullable) NSString *dataPath;
@property (nonatomic, copy, readwrite, nullable) NSString *dataETag;
@property (nonatomic, copy, readwrite, nullable) NSDate *dataLastModified;

@property (nonatomic, strong, readwrite) id rcrdCompletionBlock;
@property (nonatomic, strong, readwrite, nullable) id ptrCompletionBlock;
@property (nonatomic, strong, readwrite, nullable) id dirCompletionBlock;

@end

NS_ASSUME_NONNULL_END
