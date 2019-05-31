/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPullItem : NSObject

@property (nonatomic, copy, readwrite) NSString *rcrdPath;
@property (nonatomic, copy, readwrite) NSString *rcrdETag;
@property (nonatomic, copy, readwrite) NSDate *rcrdLastModified;

@property (nonatomic, copy, readwrite, nullable) NSString *dataPath;
@property (nonatomic, copy, readwrite, nullable) NSString *dataETag;
@property (nonatomic, copy, readwrite, nullable) NSDate *dataLastModified;

@property (nonatomic, copy, readwrite) NSString *bucket;
@property (nonatomic, assign, readwrite) AWSRegion region;

@property (nonatomic, copy, readwrite) NSArray<NSString*> *parents;

@property (nonatomic, strong, readwrite) id rcrdCompletionBlock;
@property (nonatomic, strong, readwrite) id dirCompletionBlock;

@end

NS_ASSUME_NONNULL_END
