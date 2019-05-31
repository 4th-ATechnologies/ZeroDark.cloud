/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCCloudConnection.h"
#import "ZDCCloudPrivate.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int ddLogLevel = DDLogLevelVerbose;
#elif DEBUG
  static const int ddLogLevel = DDLogLevelWarning;
#else
  static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)


@implementation ZDCCloudConnection

/**
 * Strongly typed getter.
**/
- (ZDCCloud *)cloud
{
	return (ZDCCloud *)parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	DDLogAutoTrace();
	
	ZDCCloudTransaction *transaction =
	  [[ZDCCloudTransaction alloc] initWithParentConnection:self
	                                   databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	DDLogAutoTrace();
	
	ZDCCloudTransaction *transaction =
	  [[ZDCCloudTransaction alloc] initWithParentConnection:self
	                                   databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

- (void)prepareForReadWriteTransaction
{
	[super prepareForReadWriteTransaction];
	
	if (operations_block == nil)
		operations_block = [[NSMutableArray alloc] init];
}

@end
