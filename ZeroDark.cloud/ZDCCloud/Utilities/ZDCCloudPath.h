/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A cloudPath has the form: {treeID}/{dirPrefix}/{filename}
 */
typedef NS_OPTIONS(NSUInteger, ZDCCloudPathComponents) {
	
	/**
	 * The first component of a cloudPath.
	 * Also called the treesystem container.
	 */
	ZDCCloudPathComponents_TreeID              = 1 << 0, // 00001
	
	/**
	 * The second component of a cloudPath.
	 * Represents the parentNode.
	 */
	ZDCCloudPathComponents_DirPrefix           = 1 << 1, // 00010
	
	/** The filename (including extension) */
	ZDCCloudPathComponents_FileName_WithExt    = 1 << 2, // 00100
	
	/** The fileName (excluding extension) */
	ZDCCloudPathComponents_FileName_WithoutExt = 1 << 3, // 01000
	
	/**
	 * treeID + dirPrefix + filename (including extension)
	 */
	ZDCCloudPathComponents_All_WithExt     = (ZDCCloudPathComponents_TreeID |
	                                          ZDCCloudPathComponents_DirPrefix |
	                                          ZDCCloudPathComponents_FileName_WithExt),   // 00111
	
	/**
	 * treeID + dirPrefix + filename (excluding extension)
	 */
	ZDCCloudPathComponents_All_WithoutExt  = (ZDCCloudPathComponents_TreeID |
	                                          ZDCCloudPathComponents_DirPrefix |
	                                          ZDCCloudPathComponents_FileName_WithoutExt), // 01011
};

/**
 * Encapsultes a standardized & parsed cloudPath, which takes the form of: {treeID}/{dirPrefix}/{filename}
 *
 * For example, the following are valid cloudPaths:
 *
 * - com.4th-a.storm4/00000000000000000000000000000000/3h6omkbtsn3o7xfsjtz6xcnyxn5e6bug.rcrd
 * - tld.foo.bar/640C24E8B6874D428A19C63652DF5F8C/54yqj8u5796uaoaa41n6unywki8t3wpn.data
 * - tld.foo.bar/mgsIn/7ckebgr1c4s7a9xgu6gqcb7ix55mndbg
 */
@interface ZDCCloudPath : NSObject <NSCoding, NSCopying>

#pragma mark Validation

/**
 * Returns YES if the given value is a valid treeID.
 *
 * A treeID has the following requirements:
 * - minimum of 8 characters
 * - maximum of 64 characters
 * - cannot start with a period
 * - all characters are in set: 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-_
 */
+ (BOOL)isValidTreeID:(NSString *)treeID;

/**
 * Returns YES if the given value is a valid dirPrefix.
 *
 * A dirPrefix has the following requirements:
 * - 32 characters
 * - all characters are hexadecimal (UPPER-CASE)
 */
+ (BOOL)isValidDirPrefix:(NSString *)dirPrefix;

/**
 * Returns YES if the given value is a valid filename.
 *
 * A filename has the following requirements;
 * - 32 characters
 * - all characters are in zBase32 alphabet
 * - may or may not have a file extension
 */
+ (BOOL)isValidFileName:(NSString *)filename;

/**
 * Returns YES if the given value is a valid cloudPath.
 *
 * A cloudPath is of the form "X/Y/Z", where:
 * - X is a valid treeID
 * - Y is a valid dirPrefix
 * - Z is a valid filename
 */
+ (BOOL)isValidCloudPath:(NSString *)cloudPath;

#pragma mark Creation

/**
 * Attempts to parse the given string into a cloudPath.
 *
 * @param path
 *   A cloud path of the form "X/Y/Z", where X=treeID, Y=dirPrefix, Z=fileName
 */
- (nullable instancetype)initWithPath:(NSString *)path;

/**
 * Creates a new instance with the given components.
 *
 * @param treeID
 *   The treesystem container name.
 *   This is the name you registered via dashboard.zerodark.cloud.
 *
 * @param dirPrefix
 *   Represents the parentNode.dirPrefix value.
 *   That is, all direct children of the same parentNode share the same dirPrefix.
 *
 * @param fileName
 *   The (hashed) name of the file. This is also referred to as the cloudName.
 *   The fileName does not require a fileExtension.
 */
- (nullable instancetype)initWithTreeID:(NSString *)treeID
                              dirPrefix:(NSString *)dirPrefix
                               fileName:(NSString *)fileName;

/**
 * Creates a new instance, where the dirPrefix is set to be the inbox.
 *
 * @param treeID
 *   The treesystem container name.
 *   This is the name you registered via dashboard.zerodark.cloud.
 *
 * @param fileName
 *   The (hashed) name of the file. This is also referred to as the cloudName.
 *   The fileName does not require a fileExtension.
 */
- (nullable instancetype)initWithTreeID:(NSString *)treeID
                          inboxFileName:(NSString *)fileName;

/**
 * Creates a new instance, where the dirPrefix is set to be the outbox.
 *
 * @param treeID
 *   The treesystem container name.
 *   This is the name you registered via dashboard.zerodark.cloud.
 *
 * @param fileName
 *   The (hashed) name of the file. This is also referred to as the cloudName.
 *   The fileName does not require a fileExtension.
 */
- (nullable instancetype)initWithTreeID:(NSString *)treeID
                         outboxFileName:(NSString *)fileName;

#pragma mark Properties

/**
 * The treesystem container name.
 * This is the name you registered via dashboard.zerodark.cloud.
 */
@property (nonatomic, copy, readonly) NSString * treeID;

/**
 * Represents the parentNode.dirPrefix value.
 * That is, all direct children of the same parentNode share the same dirPrefix.
 */
@property (nonatomic, copy, readonly) NSString * dirPrefix;

/**
 * The (hashed) name of the file. This is also referred to as the cloudName.
 * The fileName may or may not include a fileExtension.
 */
@property (nonatomic, copy, readonly) NSString * fileName;

#pragma mark FileName

/**
 * Extracts the fileExtension, if it includes ones.
 * E.g. "rcrd" or "data".
 */
- (nullable NSString *)fileNameExt;

/**
 * Returns the current fileName, stripped of its existing fileExtension,
 * and with the given fileNameExt added instead.
 */
- (NSString *)fileNameWithExt:(nullable NSString *)fileNameExt;

#pragma mark Path (as string)

/**
 * Returns the full cloudPath in string form. (i.e. with '/' separator between components)
 */
- (NSString *)path;

/**
 * Returns a path including only the specific components (with '/' separator between components).
 */
- (NSString *)pathWithComponents:(ZDCCloudPathComponents)components;

/**
 * Returns the full cloudPath in string form, but with the given fileExtension.
 */
- (NSString *)pathWithExt:(nullable NSString *)fileNameExt;

#pragma mark Comparison (with string)

/** Returns YES if the fileNames match (including fileExtension). */
- (BOOL)matchesFileName:(NSString *)fileName;

/** Returns YES if the fileNames match, comparing only the given components. */
- (BOOL)matchesFileName:(NSString *)fileName comparingComponents:(ZDCCloudPathComponents)components;

/** Retursn YES if the cloudPath matches the given path, including all components & fileExtension. */
- (BOOL)matchesPath:(NSString *)path;

/** Returns YES if the cloudPath matches the given path, comparing only the given components. */
- (BOOL)matchesPath:(NSString *)path comparingComponents:(ZDCCloudPathComponents)components;

#pragma mark Equality

/** Compares the cloudPaths, and returns YES if they match exactly. */
- (BOOL)isEqualToCloudPath:(ZDCCloudPath *)another;

/** Compares the cloudPaths, and returne YES if they match (excluding fileExtension). */
- (BOOL)isEqualToCloudPathIgnoringExt:(ZDCCloudPath *)another;

/** Compares the cloudPaths, but only comparing the given components. */
- (BOOL)isEqualToCloudPath:(ZDCCloudPath *)another components:(ZDCCloudPathComponents)components;

#pragma mark Copying

/**
 * Returns a copy with a different fileExtension.
 * For example, if the cloudPath has a "rcrd" fileExtension,
 * you can use this method to get a cloudPath for the "data" extension.
 */
- (id)copyWithFileNameExt:(nullable NSString *)newFileNameExt;

@end

NS_ASSUME_NONNULL_END
