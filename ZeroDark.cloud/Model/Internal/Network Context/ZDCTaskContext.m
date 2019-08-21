/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCTaskContext.h"

static int const kCurrentVersion = 1;
#pragma unused(kCurrentVersion)

static NSString *const k_version              = @"version";
static NSString *const k_operationUUID        = @"operationUUID";
static NSString *const k_pipeline             = @"pipeline";
static NSString *const k_localUserID          = @"localUserID";
static NSString *const k_nodeID               = @"nodeID";
static NSString *const k_zAppID               = @"zAppID";
static NSString *const k_cloudLocator         = @"cloudLocator";
static NSString *const k_dstCloudPath         = @"dstCloudPath";
static NSString *const k_eTag                 = @"eTag";
static NSString *const k_multipart_initiate   = @"multipart_initiate";
static NSString *const k_multipart_complete   = @"multipart_complete";
static NSString *const k_multipart_abort      = @"multipart_abort";
static NSString *const k_multipart_index      = @"multipart_index";
static NSString *const k_uploadFileURL        = @"uploadFileURL";
static NSString *const k_deleteUploadFileURL  = @"deleteUploadFileURL";
static NSString *const k_duplicateOpUUIDs     = @"matchingOpUUIDs";
static NSString *const k_sha256Hash           = @"sha256Hash";


@implementation ZDCTaskContext

@synthesize operationUUID = operationUUID;
@synthesize pipeline = pipeline;
@synthesize localUserID = localUserID;
@synthesize zAppID = zAppID;

@synthesize eTag = eTag;

@synthesize multipart_initiate = multipart_initiate;
@synthesize multipart_complete = multipart_complete;
@synthesize multipart_abort    = multipart_abort;
@synthesize multipart_index    = multipart_index;

@synthesize uploadFileURL = uploadFileURL;

#if TARGET_OS_IPHONE
@synthesize deleteUploadFileURL = deleteUploadFileURL;

#else // macOS
@synthesize uploadData = uploadData;
@synthesize uploadStream = uploadStream;

#endif

@synthesize duplicateOpUUIDs = duplicateOpUUIDs;
@synthesize sha256Hash = sha256Hash;
@synthesize progress = progress;


- (instancetype)initWithOperation:(ZDCCloudOperation *)operation
{
	if ((self = [super init]))
	{
		operationUUID = [operation.uuid copy];
		pipeline      = [operation.pipeline copy];
		localUserID   = [operation.localUserID copy];
		zAppID        = [operation.zAppID copy];
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
		operationUUID = [decoder decodeObjectForKey:k_operationUUID];
		pipeline      = [decoder decodeObjectForKey:k_pipeline];
		localUserID   = [decoder decodeObjectForKey:k_localUserID];
		zAppID        = [decoder decodeObjectForKey:k_zAppID];
		
		eTag = [decoder decodeObjectForKey:k_eTag];
		
		multipart_initiate = [decoder decodeBoolForKey:k_multipart_initiate];
		multipart_complete = [decoder decodeBoolForKey:k_multipart_complete];
		multipart_abort    = [decoder decodeBoolForKey:k_multipart_abort];
		multipart_index    = (NSUInteger)[decoder decodeIntegerForKey:k_multipart_index];
		
		uploadFileURL = [self deserializeFileURL:[decoder decodeObjectForKey:k_uploadFileURL]];
		
	#if TARGET_OS_IPHONE
		deleteUploadFileURL  = [decoder decodeBoolForKey:k_deleteUploadFileURL];
	#endif
		
		duplicateOpUUIDs = [decoder decodeObjectForKey:k_duplicateOpUUIDs];
		sha256Hash = [decoder decodeObjectForKey:k_sha256Hash];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:operationUUID forKey:k_operationUUID];
	[coder encodeObject:pipeline      forKey:k_pipeline];
	[coder encodeObject:localUserID   forKey:k_localUserID];
	[coder encodeObject:zAppID        forKey:k_zAppID];
	
	[coder encodeObject:eTag forKey:k_eTag];
	
	[coder encodeBool:multipart_initiate forKey:k_multipart_initiate];
	[coder encodeBool:multipart_complete forKey:k_multipart_complete];
	[coder encodeBool:multipart_abort    forKey:k_multipart_abort];
	[coder encodeInteger:multipart_index forKey:k_multipart_index];
	
	[coder encodeObject:[self serializeFileURL:uploadFileURL] forKey:k_uploadFileURL];
	
#if TARGET_OS_IPHONE
	[coder encodeBool:deleteUploadFileURL forKey:k_deleteUploadFileURL];
#endif
	
	[coder encodeObject:duplicateOpUUIDs forKey:k_duplicateOpUUIDs];
	[coder encodeObject:sha256Hash forKey:k_sha256Hash];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCTaskContext *copy = [super copyWithZone:zone]; // [ZDCObject copyWithZone:]
	
	copy->operationUUID = operationUUID;
	copy->pipeline      = pipeline;
	copy->localUserID   = localUserID;
	copy->zAppID        = zAppID;
	
	copy->eTag = eTag;
	
	copy->multipart_initiate = multipart_initiate;
	copy->multipart_complete = multipart_complete;
	copy->multipart_abort    = multipart_abort;
	copy->multipart_index    = multipart_index;
	
	copy->uploadFileURL    = uploadFileURL;
	
#if TARGET_OS_IPHONE
	copy->deleteUploadFileURL = deleteUploadFileURL;
#else
	copy->uploadData = uploadData;
	copy->uploadStream = uploadStream;
#endif
	
	copy->duplicateOpUUIDs = duplicateOpUUIDs;
	copy->sha256Hash = sha256Hash;
	copy->progress = progress;
	
	return copy;
}

@end
