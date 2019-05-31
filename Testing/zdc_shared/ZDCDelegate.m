/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCDelegate.h"

@implementation ZDCDelegate

- (ZDCNodeData *)dataForNode:(ZDCNode *)node
                      atPath:(ZDCTreesystemPath *)path
                 transaction:(YapDatabaseReadTransaction *)transaction
{
	return [[ZDCNodeData alloc] initWithData:[NSData data]];
}

- (nullable NSData *)metadataForNode:(ZDCNode *)node
                              atPath:(ZDCTreesystemPath *)path
                         transaction:(YapDatabaseReadTransaction *)transaction
{
	return nil;
}

- (nullable NSData *)thumbnailForNode:(ZDCNode *)node
                               atPath:(ZDCTreesystemPath *)path
                          transaction:(YapDatabaseReadTransaction *)transaction
{
	return nil;
}

- (void)didPushNodeData:(nonnull ZDCNode *)node
                 atPath:(nonnull ZDCTreesystemPath *)path
            transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didPushNodeData:atPath: %@", path.fullPath);
}

#pragma mark Pull

- (void)didDiscoverNewNode:(nonnull ZDCNode *)node
                    atPath:(nonnull ZDCTreesystemPath *)path
               transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverNodeNode:atPath: %@", path.fullPath);
}

- (void)didDiscoverModifiedNode:(nonnull ZDCNode *)node
                     withChange:(ZDCNodeChange)change
                         atPath:(nonnull ZDCTreesystemPath *)path
                    transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverModifiedNode:atPath: %@", path.fullPath);
}

- (void)didDiscoverMovedNode:(nonnull ZDCNode *)node
                        from:(nonnull ZDCTreesystemPath *)oldPath
                          to:(nonnull ZDCTreesystemPath *)newPath
                 transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverMovedNode: %@ -> %@", oldPath.fullPath, newPath.fullPath);
}

- (void)didDiscoverDeletedNode:(nonnull ZDCNode *)node
                        atPath:(nonnull ZDCTreesystemPath *)path
                     timestamp:(nullable NSDate *)timestamp
                   transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverDeletedNode:atPath: %@", path.fullPath);
}

@end
