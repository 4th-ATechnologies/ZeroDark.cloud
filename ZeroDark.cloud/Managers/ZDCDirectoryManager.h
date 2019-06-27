/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Simple utility class to provide standardized URL's for common local directories & for temp files.
 */
@interface ZDCDirectoryManager : NSObject

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Top Level Directories
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The typical "Application Support" directory for the app.
 *
 * - macOS : ~/Library/Application Support/{Bundle Identifier}
 * - iOS   : {App Sandbox}/Application Support
 *
 * Files stored in this directory are persistent,
 * and must be manually deleted by the application.
 */
+ (NSURL *)appSupportDirectoryURL;

/**
 * The typical "Cache" directory for the app.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}
 * - iOS    : {App Sandbox}/Caches
 *
 * Files stored in this directory are NOT persistent,
 * and are eligible for deletion at the discretion of the OS.
 */
+ (NSURL *)appCacheDirectoryURL;

/**
 * The typical "Temp" directory for the app.
 *
 * This directory is used for temporary files which do not need to be persistent for long.
 */
+ (NSURL *)tempDirectoryURL;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDC Containers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The ZeroDarkCloud framework attempts to keep all stored files within a few "zdc" folders.
 * This method returns the top-level "zdc" directory for persistent files.
 * Within this directory there will be multiple sub-directories,
 * one for each database/ZeroDarCloud instance.
 *
 * - macOS : ~/Library/Application Support/{Bundle Identifier}/zdc
 * - iOS   : {App Sandbox}/Application Support/zdc
 *
 * Files stored in this directory are persistent,
 * and must be manually deleted by the application.
 */
+ (NSURL *)zdcPersistentDirectoryURL;

/**
 * The ZeroDarkCloud framework attempts to keep all stored files within a few "zdc" folders.
 * This method returns the top-level "zdc" directory for temporarily cached files.
 * Within this directory there will be multiple sub-directories,
 * one for each database/ZeroDarCloud instance.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}/zdc
 * - iOS    : {App Sandbox}/Caches/zdc
 *
 * Files stored in this directory are NOT persistent,
 * and are eligible for deletion at the discretion of the OS.
 */
+ (NSURL *)zdcCacheDirectoryURL;

/**
 * The ZeroDarkCloud framework attempts to keep all stored files within a few "zdc" folders.
 * This method returns the top-level container for persistent files
 * stored by the ZeroDarkCloud instance using the given databaseName.
 *
 * - macOS : ~/Library/Application Support/{Bundle Identifier}/zdc/db/{Database Name}
 * - iOS   : {App Sandbox}/Application Support/zdc/db/{Database Name}
 *
 * Files stored in this directory are persistent,
 * and must be manually deleted by the application.
 */
+ (NSURL *)zdcPersistentDirectoryForDatabaseName:(NSString *)databaseName;

/**
 * The ZeroDarkCloud framework attempts to keep all stored files within a few "zdc" folders.
 * This method returns the top-level container for temporary cached files
 * stored by the ZeroDarkCloud instance using the given databaseName.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}/zdc/db/{Database Name}
 * - iOS    : {App Sandbox}/Caches/zdc/db/{Database Name}
 *
 * Files stored in this directory are NOT persistent,
 * and are eligible for deletion at the discretion of the OS.
 */
+ (NSURL *)zdcCacheDirectoryForDatabaseName:(NSString *)databaseName;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Sqlite creates multiple files for each database.
 * This method returns all the corresponding fileURL's.
 *
 * - .../zdc/db/database.sqlite
 * - .../zdc/db/database.sqlite-wal
 * - .../zdc/db/database.sqlite-shm
 */
+ (NSArray<NSURL*> *)fileURLsForDatabaseName:(NSString *)databaseName;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Social Media Icons cache directory.
 *
 * ZeroDark.cloud supports a number of different social media providers (for sign-in / sign-up).
 * The framework needs to fetch various related information, such as the images for each provider.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}/zdc/socialmediaicons
 * - iOS    : {App Sandbox}/Caches/zdc/socialmediaicons
 */
+ (NSURL *)smiCacheDirectoryURL;

/**
 * Background NSURLSession's only support download & upload tasks.
 * They explicitly do not support data tasks.
 *
 * So if you want to do perform a data task in the background,
 * you may have to masquerade it as an upload task, and provide an empty file.
 *
 * This file acts as the empty file which can be shared for such tasks.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}/zdc/empty
 * - iOS    : {App Sandbox}/Caches/zdc/empty
 */
+ (NSURL *)emptyUploadFileURL;

/**
 * Generates a random fileName (using a UUID), and returns a fileURL for it within the tempDirectory.
 */
+ (NSURL *)generateTempURL;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A common download directory used by the framework.
 * The directory is specific to the ZeroDarkCloud instance.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}/zdc/db/{Database Name}/downloads
 * - iOS    : {App Sandbox}/Caches/zdc/db/{Database Name}/downloads
 */
- (NSURL *)downloadDirectoryURL;

/**
 * Generates a random fileName (using a UUID), and returns a fileURL for it.
 * The fileURL resides within the `downloadDirectoryURL`, which is specific to the ZeroDarkCloud instance.
 *
 * - mac OS : ~/Library/Caches/{Bundle Identifier}/zdc/db/{Database Name}/downloads/{uuid}
 * - iOS    : {App Sandbox}/Caches/zdc/db/{Database Name}/downloads/{uuid}
 */
- (NSURL *)generateDownloadURL;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Bundle Info
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Extracted from main NSBundle using key `kCFBundleIdentifierKey`.
 */
+ (NSString *)bundleIdentifier;

/**
 * Extracted from main NSBundle using key `kCFBundleNameKey`.
 */
+ (NSString *)bundleName;

@end

NS_ASSUME_NONNULL_END
