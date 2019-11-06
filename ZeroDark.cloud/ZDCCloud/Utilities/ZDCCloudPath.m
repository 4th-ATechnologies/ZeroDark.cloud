#import "ZDCCloudPath.h"

#import "ZDCConstants.h"

// Encoding/Decoding keys
static NSString *const k_treeID    = @"appPrefix";
static NSString *const k_dirPrefix = @"dirPrefix";
static NSString *const k_fileName  = @"fileName";


@implementation ZDCCloudPath

@synthesize treeID = treeID;
@synthesize dirPrefix = dirPrefix;
@synthesize fileName = fileName;

static BOOL ZDCCloudPathParse(NSString **treeIDPtr,
                              NSString **dirPrefixPtr,
                              NSString **fileNamePtr,
                              NSString *path)
{
	NSString *treeID    = nil;
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
		treeID    = components[0];
		dirPrefix = components[1];
		fileName  = components[2];
		
		if (![ZDCCloudPath isValidTreeID:treeID]) {
			isValid = NO;
		}
		else if (![ZDCCloudPath isValidDirPrefix:dirPrefix]) {
			isValid = NO;
		}
		else if (![ZDCCloudPath isValidFileName:fileName]) {
			isValid = NO;
		}
	}
	else
	{
		isValid = NO;
	}
	
	if (treeIDPtr)    *treeIDPtr    = treeID;
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

static BOOL ZDCCloudPathEqual(NSString *treeID1, NSString *dirPrefix1, NSString *fileName1,
                             NSString *treeID2, NSString *dirPrefix2, NSString *fileName2,
                             ZDCCloudPathComponents components)
{
	// Performance optimization:
	// The fileName is the most likely component to be different.
	// And the treeID is the least likely component to be different.
	//
	// Thus we perform the comparisons in that order.
	
	if (!ZDCCloudFileNameEqual(fileName1, fileName2, components))
	{
		return NO;
	}
	
	if (components & ZDCCloudPathComponents_DirPrefix)
	{
		if (dirPrefix1) {
			if (![dirPrefix1 isEqual:dirPrefix2]) return NO;
		}
		else {
			if (dirPrefix2) return NO;
		}
	}
	
	if (components & ZDCCloudPathComponents_TreeID)
	{
		if (treeID1) {
			if (![treeID1 isEqual:treeID2]) return NO;
		}
		else {
			if (treeID2) return NO;
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Validity
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
+ (BOOL)isValidTreeID:(NSString *)treeID
{
	if (treeID.length < 8) return NO;
	if (treeID.length > 64) return NO;
	
	if ([treeID hasPrefix:@"."]) return NO;
	
	NSString *str =
	  @"0123456789"
	  @"abcdefghijklmnopqrstuvwxyz"
	  @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	  @".-_";
	
	NSCharacterSet *goodSet = [NSCharacterSet characterSetWithCharactersInString:str];
	NSCharacterSet *badSet = [goodSet invertedSet];
	
	NSRange badRange = [treeID rangeOfCharacterFromSet:badSet];
	return (badRange.location == NSNotFound);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
+ (BOOL)isValidDirPrefix:(NSString *)dirPrefix
{
	if (dirPrefix.length != 32)
	{
		if ([dirPrefix isEqualToString:kZDCDirPrefix_Prefs])   return YES;
		if ([dirPrefix isEqualToString:kZDCDirPrefix_MsgsIn])  return YES;
		if ([dirPrefix isEqualToString:kZDCDirPrefix_MsgsOut]) return YES;
		
		if ([dirPrefix isEqualToString:kZDCDirPrefix_Deprecated_Msgs])   return YES;
		if ([dirPrefix isEqualToString:kZDCDirPrefix_Deprecated_Inbox])  return YES;
		if ([dirPrefix isEqualToString:kZDCDirPrefix_Deprecated_Outbox]) return YES;
		
		return NO;
	}
	
	NSCharacterSet *goodSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"];
	NSCharacterSet *badSet = [goodSet invertedSet];
	
	NSRange badRange = [dirPrefix rangeOfCharacterFromSet:badSet];
	return (badRange.location == NSNotFound);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
+ (BOOL)isValidFileName:(NSString *)filename
{
	NSRange range = [filename rangeOfString:@"."];
	if (range.location != NSNotFound) {
		filename = [filename substringToIndex:range.location];
	}
	
	if (filename.length != 32) return NO;
	
	NSCharacterSet *goodSet = [NSCharacterSet characterSetWithCharactersInString:@"ybndrfg8ejkmcpqxot1uwisza345h769"];
	NSCharacterSet *badSet = [goodSet invertedSet];
	
	range = [filename rangeOfCharacterFromSet:badSet];
	return (range.location == NSNotFound);
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
+ (BOOL)isValidCloudPath:(NSString *)cloudPath
{
	BOOL isValid = ZDCCloudPathParse(NULL, NULL, NULL, cloudPath);
	return isValid;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
- (nullable instancetype)initWithPath:(NSString *)path
{
	NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
	if (components.count != 3) {
		return nil;
	}
	
	return [self initWithTreeID: components[0]
	                  dirPrefix: components[1]
	                   fileName: components[2]];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
- (nullable instancetype)initWithTreeID:(NSString *)inTreeID
                              dirPrefix:(NSString *)inDirPrefix
                               fileName:(NSString *)inFileName
{
	if (![ZDCCloudPath isValidTreeID:inTreeID]) {
		return nil;
	}
	if (![ZDCCloudPath isValidDirPrefix:inDirPrefix]) {
		return nil;
	}
	if (![ZDCCloudPath isValidFileName:inFileName]) {
		return nil;
	}
	
	if ((self = [super init]))
	{
		treeID    = [inTreeID copy];
		dirPrefix = [inDirPrefix copy];
		fileName  = [inFileName copy];
	}
	return self;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
- (nullable instancetype)initWithTreeID:(NSString *)inTreeID
                          inboxFileName:(NSString *)inFileName
{
	return [self initWithTreeID: inTreeID
	                  dirPrefix: kZDCDirPrefix_MsgsIn
	                   fileName: inFileName];
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPath.html
 */
- (nullable instancetype)initWithTreeID:(NSString *)inTreeID
                         outboxFileName:(NSString *)inFileName
{
	return [self initWithTreeID: inTreeID
	                  dirPrefix: kZDCDirPrefix_MsgsOut
	                   fileName: inFileName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		treeID    = [decoder decodeObjectForKey:k_treeID];
		dirPrefix = [decoder decodeObjectForKey:k_dirPrefix];
		fileName  = [decoder decodeObjectForKey:k_fileName];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:treeID    forKey:k_treeID];
	[coder encodeObject:dirPrefix forKey:k_dirPrefix];
	[coder encodeObject:fileName  forKey:k_fileName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	// ZDCCloudPath is immutable
	return self;
}

- (id)copyWithFileNameExt:(NSString *)newFileNameExt
{
	ZDCCloudPath *copy = [[ZDCCloudPath alloc] init];
	
	copy->treeID = treeID;
	copy->dirPrefix = dirPrefix;
	copy->fileName = [self fileNameWithExt:newFileNameExt];
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark FileName
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Path (as string)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)path
{
	return [self pathWithComponents:ZDCCloudPathComponents_All_WithExt];
}

- (NSString *)pathWithComponents:(ZDCCloudPathComponents)components
{
	NSMutableString *path = [NSMutableString stringWithCapacity:(64 + 1 + 32 + 1 + 32 + 1 + 16)];
	
	if ((components & ZDCCloudPathComponents_TreeID) && treeID) {
		[path appendString:treeID];
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
	
	if (treeID)
	{
		[path appendString:treeID];
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Comparisons
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	NSString *_treeID    = nil;
	NSString *_dirPrefix = nil;
	NSString *_fileName  = nil;
	
	BOOL isValid = ZDCCloudPathParse(&_treeID, &_dirPrefix, &_fileName, path);
	
	if (!isValid) return NO;
	
	return ZDCCloudPathEqual(treeID, dirPrefix, fileName, _treeID, _dirPrefix, _fileName, components);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	
	return ZDCCloudPathEqual(treeID, dirPrefix, fileName,
	                         another->treeID, another->dirPrefix, another->fileName, components);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [self pathWithComponents:ZDCCloudPathComponents_All_WithExt];
}

@end
