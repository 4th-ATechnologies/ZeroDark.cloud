/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCCloudTypes.h"

#import "ZDCCloudOperation.h"
#import "ZDCCloudPrivate.h"


@implementation ZDCCloudHandler

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(ZDCCloudHandlerWithKeyBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:iops keyBlock:block];
}

+ (instancetype)withObjectBlock:(ZDCCloudHandlerWithObjectBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:iops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(ZDCCloudHandlerWithMetadataBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:iops metadataBlock:block];
}

+ (instancetype)withRowBlock:(ZDCCloudHandlerWithRowBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:iops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(ZDCCloudHandlerWithKeyBlock)block
{
	return [[ZDCCloudHandler alloc] initWithBlock:block
	                                   blockType:YapDatabaseBlockTypeWithKey
	                          blockInvokeOptions:ops];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(ZDCCloudHandlerWithObjectBlock)block
{
	return [[ZDCCloudHandler alloc] initWithBlock:block
	                                   blockType:YapDatabaseBlockTypeWithObject
	                          blockInvokeOptions:ops];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(ZDCCloudHandlerWithMetadataBlock)block
{
	return [[ZDCCloudHandler alloc] initWithBlock:block
	                                   blockType:YapDatabaseBlockTypeWithMetadata
	                          blockInvokeOptions:ops];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(ZDCCloudHandlerWithRowBlock)block
{
	return [[ZDCCloudHandler alloc] initWithBlock:block
	                                   blockType:YapDatabaseBlockTypeWithRow
	                          blockInvokeOptions:ops];
}

- (instancetype)init
{
	return nil;
}

- (instancetype)initWithBlock:(ZDCCloudHandlerBlock)inBlock
                    blockType:(YapDatabaseBlockType)inBlockType
           blockInvokeOptions:(YapDatabaseBlockInvoke)inBlockInvokeOptions
{
	if (inBlock == nil) return nil;
	
	if ((self = [super init]))
	{
		block = inBlock;
		blockType = inBlockType;
		blockInvokeOptions = inBlockInvokeOptions;
	}
	return self;
}

@end
