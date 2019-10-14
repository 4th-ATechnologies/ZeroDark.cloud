/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCCloud.h"
#import "ZDCCloudPrivate.h"


@implementation ZDCCloud

@synthesize localUserID = localUserID;
@synthesize treeID = treeID;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             treeID:(NSString *)inTreeID
{
	NSParameterAssert(inLocalUserID != nil);
	NSParameterAssert(inTreeID != nil);
	
	YapDatabaseCloudCoreOptions *super_options = [[YapDatabaseCloudCoreOptions alloc] init];
	super_options.allowedOperationClasses = [NSSet setWithObject:[ZDCCloudOperation class]];
	super_options.enableTagSupport = YES;
	super_options.enableAttachDetachSupport = YES;
	
	if ((self = [super initWithVersionTag:nil options:super_options]))
	{
		localUserID = [inLocalUserID copy];
		treeID = [inTreeID copy];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtension Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses MUST implement this method.
 * Returns a proper instance of the YapDatabaseExtensionConnection subclass.
**/
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[ZDCCloudConnection alloc] initWithParent:self databaseConnection:databaseConnection];
}

@end
