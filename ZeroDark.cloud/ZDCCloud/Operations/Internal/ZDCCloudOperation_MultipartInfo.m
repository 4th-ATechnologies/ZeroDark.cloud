/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCCloudOperation_MultipartInfo.h"

#import <YapDatabase/YapDatabaseCloudCoreOperationPrivate.h>

/**
 * Constants used for NSCoding
**/
static int const kCurrentVersion = 0;

static NSString *const k_version          = @"version";
static NSString *const k_stagingPath      = @"stagingPath";
static NSString *const k_sha256Hash       = @"sha256Hash";
static NSString *const k_uploadID         = @"uploadID";
static NSString *const k_rawMetadata      = @"rawMetadata";
static NSString *const k_rawThumbnail     = @"rawThumbnail";
static NSString *const k_cloudFileSize    = @"cloudFileSize";
static NSString *const k_chunkSize        = @"chunkSize";
static NSString *const k_checksums        = @"checksums";
static NSString *const k_eTags            = @"eTags";
static NSString *const k_duplicateOpUUIDs = @"duplicateOpUUIDs";
static NSString *const k_needsAbort       = @"needsAbort";
static NSString *const k_needsSkip        = @"needsSkip";


@implementation ZDCCloudOperation_MultipartInfo

@synthesize stagingPath = stagingPath;
@synthesize sha256Hash = sha256Hash;
@synthesize uploadID = uploadID;

@synthesize rawMetadata = rawMetadata;
@synthesize rawThumbnail = rawThumbnail;

@synthesize cloudFileSize = cloudFileSize;
@synthesize chunkSize = chunkSize;

@synthesize checksums = checksums;
@synthesize eTags = eTags;

@synthesize duplicateOpUUIDs = duplicateOpUUIDs;

@synthesize needsAbort = needsAbort;
@synthesize needsSkip = needsSkip;

@dynamic numberOfParts;

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		stagingPath = [decoder decodeObjectForKey:k_stagingPath];
		sha256Hash = [decoder decodeObjectForKey:k_sha256Hash];
		uploadID = [decoder decodeObjectForKey:k_uploadID];
		
		rawMetadata = [decoder decodeObjectForKey:k_rawMetadata];
		rawThumbnail = [decoder decodeObjectForKey:k_rawThumbnail];
		
		cloudFileSize = (uint64_t)[decoder decodeInt64ForKey:k_cloudFileSize];
		chunkSize = (uint64_t)[decoder decodeInt64ForKey:k_chunkSize];
		
		checksums = [decoder decodeObjectForKey:k_checksums];
		eTags = [decoder decodeObjectForKey:k_eTags];
		
		duplicateOpUUIDs= [decoder decodeObjectForKey:k_duplicateOpUUIDs];
		
		needsAbort = [decoder decodeBoolForKey:k_needsAbort];
		needsSkip = [decoder decodeBoolForKey:k_needsSkip];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:stagingPath forKey:k_stagingPath];
	[coder encodeObject:uploadID forKey:k_uploadID];
	[coder encodeObject:sha256Hash forKey:k_sha256Hash];
	
	[coder encodeObject:rawMetadata forKey:k_rawMetadata];
	[coder encodeObject:rawThumbnail forKey:k_rawThumbnail];
	
	[coder encodeInt64:(int64_t)cloudFileSize forKey:k_cloudFileSize];
	[coder encodeInt64:(int64_t)chunkSize forKey:k_chunkSize];
	
	[coder encodeObject:checksums forKey:k_checksums];
	[coder encodeObject:eTags forKey:k_eTags];
	
	[coder encodeObject:duplicateOpUUIDs forKey:k_duplicateOpUUIDs];
	
	[coder encodeBool:needsAbort forKey:k_needsAbort];
	[coder encodeBool:needsSkip forKey:k_needsSkip];
}

- (id)copyWithZone:(NSZone *)zone
{
	ZDCCloudOperation_MultipartInfo *copy = [[ZDCCloudOperation_MultipartInfo alloc] init];
	
	copy->stagingPath = stagingPath;
	copy->uploadID = uploadID;
	copy->sha256Hash = sha256Hash;
	
	copy->rawMetadata = rawMetadata;
	copy->rawThumbnail = rawThumbnail;
	
	copy->cloudFileSize = cloudFileSize;
	copy->chunkSize = chunkSize;
	
	copy->checksums = checksums;
	copy->eTags = eTags;
	
	copy->duplicateOpUUIDs = duplicateOpUUIDs;
	
	copy->needsAbort = needsAbort;
	copy->needsSkip = needsSkip;
	
	return copy;
}

- (NSUInteger)numberOfParts
{
	return checksums.count;
}

- (BOOL)isEqual:(id)object
{
	if (![object isKindOfClass:[ZDCCloudOperation_MultipartInfo class]]) return NO;
	
	ZDCCloudOperation_MultipartInfo *another = (ZDCCloudOperation_MultipartInfo *)object;
	
	if (!YDB_IsEqualOrBothNil(stagingPath, another->stagingPath)) return NO;
	if (!YDB_IsEqualOrBothNil(uploadID, another->uploadID)) return NO;
	if (!YDB_IsEqualOrBothNil(sha256Hash, another->sha256Hash)) return NO;
	
	if (!YDB_IsEqualOrBothNil(rawMetadata, another->rawMetadata)) return NO;
	if (!YDB_IsEqualOrBothNil(rawThumbnail, another->rawThumbnail)) return NO;
	
	if (cloudFileSize != another->cloudFileSize) return NO;
	if (chunkSize != another->chunkSize) return NO;
	
	if (!YDB_IsEqualOrBothNil(checksums, another->checksums)) return NO;
	if (!YDB_IsEqualOrBothNil(eTags, another->eTags)) return NO;
	
	if (!YDB_IsEqualOrBothNil(duplicateOpUUIDs, another->duplicateOpUUIDs)) return NO;
	
	if (needsAbort != another->needsAbort) return NO;
	if (needsSkip != another->needsSkip) return NO;
	
	return YES;
}

@end
