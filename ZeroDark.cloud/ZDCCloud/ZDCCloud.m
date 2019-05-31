/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCCloud.h"
#import "ZDCCloudPrivate.h"


@implementation ZDCCloud

@synthesize localUserID = localUserID;
@synthesize zAppID = zAppID;
@synthesize handler = handler;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             zAppID:(NSString *)inZAppID
                            handler:(ZDCCloudHandler *)inHandler
{
	NSParameterAssert(inLocalUserID != nil);
	NSParameterAssert(inZAppID != nil);
	NSParameterAssert(inHandler != nil);
	
	YapDatabaseCloudCoreOptions *super_options = [[YapDatabaseCloudCoreOptions alloc] init];
	super_options.allowedOperationClasses = [NSSet setWithObject:[ZDCCloudOperation class]];
	super_options.enableTagSupport = YES;
	super_options.enableAttachDetachSupport = YES;
	
	if ((self = [super initWithVersionTag:nil options:super_options]))
	{
		localUserID = [inLocalUserID copy];
		zAppID = [inZAppID copy];
		handler = inHandler;
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
