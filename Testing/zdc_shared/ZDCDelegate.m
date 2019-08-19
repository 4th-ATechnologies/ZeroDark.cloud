/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCDelegate.h"


@implementation ZDCDelegate

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push - Nodes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (ZDCData *)dataForNode:(ZDCNode *)node
                  atPath:(ZDCTreesystemPath *)path
             transaction:(YapDatabaseReadTransaction *)transaction;
{
	return [[ZDCData alloc] initWithData:[NSData data]];
}

- (nullable ZDCData *)metadataForNode:(ZDCNode *)node
                               atPath:(ZDCTreesystemPath *)path
                          transaction:(YapDatabaseReadTransaction *)transaction
{
	return nil;
}

- (nullable ZDCData *)thumbnailForNode:(ZDCNode *)node
                                atPath:(ZDCTreesystemPath *)path
                           transaction:(YapDatabaseReadTransaction *)transaction
{
	return nil;
}

- (void)didPushNodeData:(ZDCNode *)node
                 atPath:(ZDCTreesystemPath *)path
            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didPushNodeData:atPath: %@", path);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push - Messages
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable ZDCData *)dataForMessage:(nonnull ZDCNode *)message
                         transaction:(nonnull YapDatabaseReadTransaction *)transaction
{
	
	return nil;
}

- (void)didSendMessage:(nonnull ZDCNode *)message
           toRecipient:(nonnull ZDCUser *)recipient
           transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didSendMessage:toRecipient:::");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pull
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)didDiscoverNewNode:(ZDCNode *)node
                    atPath:(ZDCTreesystemPath *)path
               transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverNewNode:atPath: %@", path);
}

- (void)didDiscoverModifiedNode:(ZDCNode *)node
                     withChange:(ZDCNodeChange)change
                         atPath:(ZDCTreesystemPath *)path
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverModifiedNode:withChange:atPath: %@", path);
}

- (void)didDiscoverMovedNode:(ZDCNode *)node
                        from:(ZDCTreesystemPath *)oldPath
                          to:(ZDCTreesystemPath *)newPath
                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverMovedNode:from:to: %@ -> %@", oldPath, newPath);
}

- (void)didDiscoverDeletedNode:(ZDCNode *)node
                        atPath:(ZDCTreesystemPath *)path
                     timestamp:(nullable NSDate *)timestamp
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverDeletedNode:atPath: %@", path);
}

- (void)didDiscoverConflict:(ZDCNodeConflict)conflict
                    forNode:(nonnull ZDCNode *)node
                     atPath:(nonnull ZDCTreesystemPath *)path
                transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
	NSLog(@"didDiscoverConflict:forNode::atPath:: %@", path);
}

@end
