#import "ZDCDownloadContext.h"


static int const kCurrentVersion = 0;
#pragma unused(kCurrentVersion)

static NSString *const k_version                = @"version";
static NSString *const k_localUserID            = @"localUserID";
static NSString *const k_nodeID                 = @"nodeID";
static NSString *const k_isMeta                 = @"isMeta";
static NSString *const k_components             = @"components";
static NSString *const k_options                = @"options";
static NSString *const k_header                 = @"header";
static NSString *const k_range_data_location    = @"range_data_location";
static NSString *const k_range_data_length      = @"range_data_length";
static NSString *const k_range_request_location = @"range_request_location";
static NSString *const k_range_request_length   = @"range_request_length";


@implementation ZDCDownloadContext

@synthesize localUserID = localUserID;
@synthesize nodeID = nodeID;
@synthesize isMeta = isMeta;
@synthesize components = components;
@synthesize options = options;
@synthesize header = header;
@synthesize range_data = range_data;
@synthesize range_request = range_request;
@synthesize ephemeralInfo = ephemeralInfo;

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             nodeID:(NSString *)inNodeID
                             isMeta:(BOOL)inIsMeta
                         components:(ZDCNodeMetaComponents)inComponents
                            options:(ZDCDownloadOptions *)inOptions
{
	if ((self = [super init]))
	{
		localUserID = [inLocalUserID copy];
		nodeID = [inNodeID copy];
		isMeta = inIsMeta;
		components = inComponents;
		options = inOptions;
		
		ephemeralInfo = [[ZDCDownloadContext_EphemeralInfo alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		localUserID = [decoder decodeObjectForKey:k_localUserID];
		nodeID      = [decoder decodeObjectForKey:k_nodeID];
		isMeta      = [decoder decodeBoolForKey:k_isMeta];
		components  = [decoder decodeIntegerForKey:k_components];
		options     = [decoder decodeObjectForKey:k_options];
		
		header = [decoder decodeObjectForKey:k_header];
		
		range_data = NSMakeRange(0, 0);
		range_data.location = (NSUInteger)[decoder decodeIntegerForKey:k_range_data_location];
		range_data.length   = (NSUInteger)[decoder decodeIntegerForKey:k_range_data_length];
		
		range_request = NSMakeRange(0, 0);
		range_request.location = (NSUInteger)[decoder decodeIntegerForKey:k_range_request_location];
		range_request.length   = (NSUInteger)[decoder decodeIntegerForKey:k_range_request_length];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:localUserID forKey:k_localUserID];
	[coder encodeObject:nodeID      forKey:k_nodeID];
	[coder encodeBool:isMeta        forKey:k_isMeta];
	[coder encodeInteger:components forKey:k_components];
	[coder encodeObject:options     forKey:k_options];
	
	[coder encodeObject:header forKey:k_header];
	
	[coder encodeInteger:(NSInteger)range_data.location forKey:k_range_data_location];
	[coder encodeInteger:(NSInteger)range_data.length   forKey:k_range_data_length];
	
	[coder encodeInteger:(NSInteger)range_request.location forKey:k_range_request_location];
	[coder encodeInteger:(NSInteger)range_request.length   forKey:k_range_request_length];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCDownloadContext *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->localUserID = localUserID;
	copy->nodeID      = nodeID;
	copy->isMeta      = isMeta;
	copy->components  = components;
	copy->options     = [options copy];
	
	copy->header = [header copy];
	copy->range_data = range_data;
	copy->range_request = range_request;
	
	copy->ephemeralInfo = ephemeralInfo; // shared - only used by DownloadManager
	
	return copy;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCDownloadContext_EphemeralInfo

@synthesize node;
@synthesize cloudLocator;
@synthesize progress;
@synthesize failCount;

@end
