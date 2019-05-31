/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseExtensionTypes.h>

#import "ZDCCloudLocator.h"
#import "ZDCCloudRcrd.h"

@class ZDCCloudOperation;

@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Handler
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The Handler block is used to generate cloud operations.
 * It simplifies converting object changes into cloud operations that push content to the cloud.
 */
@interface ZDCCloudHandler : NSObject

typedef id ZDCCloudHandlerBlock; // One of the ZDCCloudHandlerX types below.

typedef void (^ZDCCloudHandlerWithKeyBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key);

typedef void (^ZDCCloudHandlerWithObjectBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key, id object);

typedef void (^ZDCCloudHandlerWithMetadataBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key, id metadata);

typedef void (^ZDCCloudHandlerWithRowBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key, id object, id metadata);

+ (instancetype)withKeyBlock:(ZDCCloudHandlerWithKeyBlock)block;
+ (instancetype)withObjectBlock:(ZDCCloudHandlerWithObjectBlock)block;
+ (instancetype)withMetadataBlock:(ZDCCloudHandlerWithMetadataBlock)block;
+ (instancetype)withRowBlock:(ZDCCloudHandlerWithRowBlock)block;

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(ZDCCloudHandlerWithKeyBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(ZDCCloudHandlerWithObjectBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(ZDCCloudHandlerWithMetadataBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(ZDCCloudHandlerWithRowBlock)block;

@property (nonatomic, strong, readonly) ZDCCloudHandlerBlock   block;
@property (nonatomic, assign, readonly) YapDatabaseBlockType   blockType;
@property (nonatomic, assign, readonly) YapDatabaseBlockInvoke blockInvokeOptions;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Merge Block
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef void (^ZDCCloudMergeBlock)
  (YapDatabaseReadWriteTransaction *transaction, ZDCCloudRcrd *cloudRecord,
   ZDCCloudLocator *cloudLocator, NSString *eTag, NSDate *cloudLastModified);

