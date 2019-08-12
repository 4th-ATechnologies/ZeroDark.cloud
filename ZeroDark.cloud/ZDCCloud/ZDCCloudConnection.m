/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCCloudConnection.h"
#import "ZDCCloudPrivate.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
  static const int zdcLogLevel = ZDCLogLevelVerbose;
#elif DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


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
	ZDCLogAutoTrace();
	
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
	ZDCLogAutoTrace();
	
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
