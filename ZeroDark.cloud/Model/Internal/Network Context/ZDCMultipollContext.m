/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCMultipollContext.h"

static int const kCurrentVersion = 1;
#pragma unused(kCurrentVersion)

#if TARGET_OS_IPHONE
static NSString *const k_uploadFileURL       = @"uploadFileURL";
static NSString *const k_deleteUploadFileURL = @"deleteUploadFileURL";
#endif
static NSString *const k_sha256Hash          = @"sha256Hash";


@implementation ZDCMultipollContext

#if TARGET_OS_IPHONE
@synthesize uploadFileURL = uploadFileURL;
@synthesize deleteUploadFileURL = deleteUploadFileURL;

#else // macOS
@synthesize uploadData = uploadData;

#endif

@synthesize sha256Hash = sha256Hash;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder])) // [ZDCPollContext initWithCoder:]
	{
	#if TARGET_OS_IPHONE
		uploadFileURL = [self deserializeFileURL:[decoder decodeObjectForKey:k_uploadFileURL]];
		deleteUploadFileURL = [decoder decodeBoolForKey:k_deleteUploadFileURL];
	#else
		// uploadData not serialized/deserialzed to disk
	#endif
		
		sha256Hash = [decoder decodeObjectForKey:k_sha256Hash];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder]; // [ZDCPollContext encodeWithCoder:]
	
#if TARGET_OS_IPHONE
	[coder encodeObject:[self serializeFileURL:uploadFileURL] forKey:k_uploadFileURL];
	[coder encodeBool:deleteUploadFileURL forKey:k_deleteUploadFileURL];
#else
	// uploadData not serialized/deserialzed to disk
#endif
	
	[coder encodeObject:sha256Hash forKey:k_sha256Hash];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCMultipollContext *copy = [super copyWithZone:zone]; // [ZDCPollContext copyWithZone:]
	
#if TARGET_OS_IPHONE
	copy->uploadFileURL = uploadFileURL;
	copy->deleteUploadFileURL = deleteUploadFileURL;
#else
	copy->uploadData = uploadData;
	
#endif
	copy->sha256Hash = sha256Hash;
	
	return copy;
}

@end
