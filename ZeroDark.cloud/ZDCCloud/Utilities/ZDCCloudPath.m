#import "ZDCCloudPath.h"

// Encoding/Decoding keys
static NSString *const k_appPrefix = @"appPrefix";
static NSString *const k_dirPrefix = @"dirPrefix";
static NSString *const k_fileName  = @"fileName";


@implementation ZDCCloudPath

@synthesize appPrefix = appPrefix;
@synthesize dirPrefix = dirPrefix;
@synthesize fileName = fileName;

static BOOL ZDCCloudPathParse(NSString **appPrefixPtr,
                              NSString **dirPrefixPtr,
                              NSString **fileNamePtr,
                              NSString *path)
{
	NSString *appPrefix = nil;
	NSString *dirPrefix = nil;
	NSString *fileName  = nil;
	
	// Example paths:
	//
	// - com.4th-a.storm4/00000000000000000000000000000000/3h6omkbtsn3o7xfsjtz6xcnyxn5e6bug.rcrd
	// - tld.foo.bar/640C24E8B6874D428A19C63652DF5F8C/54yqj8u5796uaoaa41n6unywki8t3wpn.data
	// - tld.foo.bar/948953757E5E47F3A4BD7DC270F99BC3/7ckebgr1c4s7a9xgu6gqcb7ix55mndbg
	
	NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
	BOOL isValid = YES;
	
	if (components.count == 3)
	{
		appPrefix = components[0];
		dirPrefix = components[1];
		fileName  = components[2];
	}
	else
	{
		isValid = NO;
	}
	
	if (appPrefixPtr) *appPrefixPtr = appPrefix;
	if (dirPrefixPtr) *dirPrefixPtr = dirPrefix;
	if (fileNamePtr)  *fileNamePtr  = fileName;
	
	return isValid;
}

static BOOL ZDCCloudFileNameEqual(NSString *fileName1, NSString *fileName2, ZDCCloudPathComponents components)
{
	if ((components & ZDCCloudPathComponents_FileName_WithExt))
	{
		return [fileName1 isEqualToString:fileName2];
	}
	else
	{
		// This subsection has been (prematurely) optimized for speed, as it is very commonly used.
		//
		// Purpose: avoid allocating new strings via [NString stringByDeletingPathExtension]
		
		// Old code:
	//	NSString *bareFileName1 = [fileName1 stringByDeletingPathExtension];
	//	NSString *bareFileName2 = [fileName2 stringByDeletingPathExtension];
	//
	//	if (bareFileName1.length > 0) {
	//		if (![bareFileName1 isEqualToString:bareFileName2]) return NO;
	//	}
	//	else { // e.g.: ".pubKey"
	//		if (![fileName1 isEqualToString:fileName2]) return NO;
	//	}
		
		// New code:
		CFRange bareRange1;
		CFRange bareRange2;
		
		{
			CFRange dotRange1 = CFStringFind((CFStringRef)fileName1, CFSTR("."), kCFCompareBackwards);
			
			if (dotRange1.location == kCFNotFound || dotRange1.location == 0) // e.g.: ".pubKey"
				bareRange1 = CFRangeMake(0, fileName1.length);
			else
				bareRange1 = CFRangeMake(0, dotRange1.location);
		}
		{
			CFRange dotRange2 = CFStringFind((CFStringRef)fileName2, CFSTR("."), kCFCompareBackwards);
			
			if (dotRange2.location == kCFNotFound || dotRange2.location == 0) // e.g.: ".pubKey"
				bareRange2 = CFRangeMake(0, fileName2.length);
			else
				bareRange2 = CFRangeMake(0, dotRange2.location);
		}
		
		if (bareRange1.length != bareRange2.length) return NO;
		
		for (CFIndex i = 0; i < bareRange1.length; i++)
		{
			UniChar charA = CFStringGetCharacterAtIndex((CFStringRef)fileName1, i);
			UniChar charB = CFStringGetCharacterAtIndex((CFStringRef)fileName2, i);
			
			if (charA != charB) return NO;
		}
		
		return YES;
	}
}

static BOOL ZDCCloudPathEqual(NSString *appPrefix1, NSString *dirPrefix1, NSString *fileName1,
                             NSString *appPrefix2, NSString *dirPrefix2, NSString *fileName2,
                             ZDCCloudPathComponents components)
{
	// Performance optimization:
	// The fileName is the most likely component to be different.
	// And the appPrefix is the least likely component to be different.
	//
	// Thus we perform the comparisons in that order.
	
	if (!ZDCCloudFileNameEqual(fileName1, fileName2, components))
	{
		return NO;
	}
	
	if (components & ZDCCloudPathComponents_DirPrefix)
	{
		if (dirPrefix1) {
			if (![dirPrefix1 isEqualToString:dirPrefix2]) return NO;
		}
		else {
			if (dirPrefix2) return NO;
		}
	}
	
	if (components & ZDCCloudPathComponents_AppPrefix)
	{
		if (appPrefix1) {
			if (![appPrefix1 isEqualToString:appPrefix2]) return NO;
		}
		else {
			if (appPrefix2) return NO;
		}
	}
	
	return YES;
}

+ (instancetype)cloudPathFromPath:(NSString *)path
{
	NSString *appPrefix = nil;
	NSString *dirPrefix = nil;
	NSString *fileName  = nil;
	
	BOOL isValid = ZDCCloudPathParse(&appPrefix, &dirPrefix, &fileName, path);
	if (!isValid)
		return nil;
	else
		return [[self alloc] initWithAppPrefix:appPrefix dirPrefix:dirPrefix fileName:fileName];
}

- (instancetype)initWithAppPrefix:(NSString *)inAppPrefix
                        dirPrefix:(NSString *)inDirPrefix
                         fileName:(NSString *)inFileName
{
	if (inFileName.length == 0) {
		return nil;
	}
	
	if ((self = [super init]))
	{
		appPrefix = [inAppPrefix copy];
		dirPrefix = [inDirPrefix copy];
		fileName  = [inFileName copy];
	}
	return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		appPrefix = [decoder decodeObjectForKey:k_appPrefix];
		dirPrefix = [decoder decodeObjectForKey:k_dirPrefix];
		fileName  = [decoder decodeObjectForKey:k_fileName];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:appPrefix forKey:k_appPrefix];
	[coder encodeObject:dirPrefix forKey:k_dirPrefix];
	[coder encodeObject:fileName  forKey:k_fileName];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	// ZDCCloudPath is immutable
	return self;
}

- (id)copyWithFileNameExt:(NSString *)newFileNameExt
{
	ZDCCloudPath *copy = [[ZDCCloudPath alloc] init];
	
	copy->appPrefix = appPrefix;
	copy->dirPrefix = dirPrefix;
	copy->fileName = [self fileNameWithExt:newFileNameExt];
	
	return copy;
}

#pragma mark General

- (NSString *)fileNameExt
{
	return [fileName pathExtension];
}

- (NSString *)fileNameWithExt:(NSString *)newFileNameExt
{
	NSString *newFileName = [fileName stringByDeletingPathExtension];
	
	if (newFileName.length == 0) // e.g.: fileName was ".pubKey"
		newFileName = fileName;
	
	if (newFileNameExt)
		newFileName = [newFileName stringByAppendingPathExtension:newFileNameExt];
	
	return newFileName;
}

- (NSString *)path
{
	return [self pathWithComponents:ZDCCloudPathComponents_All_WithExt];
}

- (NSString *)pathWithComponents:(ZDCCloudPathComponents)components
{
	NSMutableString *path = [NSMutableString stringWithCapacity:(32 + 1 + 32 + 1 + 32 + 5)];
	
	if ((components & ZDCCloudPathComponents_AppPrefix) && appPrefix) {
		[path appendString:appPrefix];
		[path appendString:@"/"];
	}
	
	if ((components & ZDCCloudPathComponents_DirPrefix) && dirPrefix) {
		[path appendString:dirPrefix];
		[path appendString:@"/"];
	}
	
	if ((components & ZDCCloudPathComponents_FileName_WithExt)) {
		[path appendString:fileName];
	}
	else if ((components & ZDCCloudPathComponents_FileName_WithoutExt)) {
		[path appendString:[self fileNameWithExt:nil]];
	}
	
	return [path copy];
}

- (NSString *)pathWithExt:(nullable NSString *)fileNameExt
{
	NSMutableString *path = [NSMutableString stringWithCapacity:(32 + 1 + 32 + 1 + 32 + 5)];
	
	if (appPrefix)
	{
		[path appendString:appPrefix];
		[path appendString:@"/"];
	}
	
	if (dirPrefix)
	{
		[path appendString:dirPrefix];
		[path appendString:@"/"];
	}
	
	[path appendString:[self fileNameWithExt:fileNameExt]];
	
	return [path copy];
}

#pragma mark Comparisons

- (BOOL)matchesFileName:(NSString *)_fileName
{
	return [self matchesFileName:_fileName comparingComponents:ZDCCloudPathComponents_All_WithExt];
}

- (BOOL)matchesFileName:(NSString *)_fileName comparingComponents:(ZDCCloudPathComponents)components
{
	if (_fileName == nil)
		return NO;
	else
		return ZDCCloudFileNameEqual(fileName, _fileName, components);
}

- (BOOL)matchesPath:(NSString *)path
{
	return [self matchesPath:path comparingComponents:ZDCCloudPathComponents_All_WithExt];
}

- (BOOL)matchesPath:(NSString *)path comparingComponents:(ZDCCloudPathComponents)components
{
	NSString *_appPrefix = nil;
	NSString *_dirPrefix = nil;
	NSString *_fileName  = nil;
	
	BOOL isValid = ZDCCloudPathParse(&_appPrefix, &_dirPrefix, &_fileName, path);
	
	if (!isValid) return NO;
	
	return ZDCCloudPathEqual(appPrefix, dirPrefix, fileName, _appPrefix, _dirPrefix, _fileName, components);
}

- (BOOL)isEqual:(id)another
{
	if (![another isKindOfClass:[ZDCCloudPath class]])
		return NO;
	else
		return [self isEqualToCloudPath:(ZDCCloudPath *)another];
}

- (BOOL)isEqualToCloudPath:(ZDCCloudPath *)another
{
	return [self isEqualToCloudPath:another components:ZDCCloudPathComponents_All_WithExt];
}

- (BOOL)isEqualToCloudPathIgnoringExt:(ZDCCloudPath *)another
{
	return [self isEqualToCloudPath:another components:ZDCCloudPathComponents_All_WithoutExt];
}

- (BOOL)isEqualToCloudPath:(ZDCCloudPath *)another components:(ZDCCloudPathComponents)components
{
	if (another == nil) return NO;
	
	return ZDCCloudPathEqual(appPrefix, dirPrefix, fileName,
	                        another->appPrefix, another->dirPrefix, another->fileName, components);
}

- (NSString *)description
{
	return [self pathWithComponents:ZDCCloudPathComponents_All_WithExt];
}

@end
