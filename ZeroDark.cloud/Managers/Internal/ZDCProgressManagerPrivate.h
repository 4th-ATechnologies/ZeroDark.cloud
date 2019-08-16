/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "ZDCProgressManager.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCProgressManager (Private)

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

- (BOOL)setMetaDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                     components:(ZDCNodeMetaComponents)components
                    localUserID:(NSString *)localUserID
               existingProgress:(NSProgress *_Nullable *_Nullable)outExistingProgress
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable NodeMetaDownloadCompletionBlock)completionBlock;

- (BOOL)setDataDownloadProgress:(NSProgress *)progress
                      forNodeID:(NSString *)nodeID
                    localUserID:(NSString *)localUserID
               existingProgress:(NSProgress *_Nullable *_Nullable)outExistingProgress
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable NodeDataDownloadCompletionBlock)completionBlock;

@end

NS_ASSUME_NONNULL_END
