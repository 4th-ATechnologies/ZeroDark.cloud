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
 * Monitors the filesystem for changes to a file or directory,
 * and uses a block-based notification system to alert you when changes are signaled by the OS.
 */
@interface ZDCFilesystemMonitor : NSObject

/**
 * Creates a new monitor designed to watch the given file for changes.
 * The url should represent a file, not a directory.
 */
- (instancetype)initWithFileURL:(NSURL *)fileURL;

/**
 * Creates a new monitor designed to watch the given directory for changes.
 * The url should represent a directory, not a file.
 */
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL;

/** The URL specified during init */
@property (nonatomic, readonly) NSURL *url;

/** YES if initWithDirectoryURL was used. NO otherwise */
@property (nonatomic, readonly) BOOL isDirectory;

/**
 * Starts monitoring the url for changes.
 *
 * @param mask
 *   A bitmask that lists the options for monitoring the url.
 *   There are class methods that may be of assistance: `+vnode_flags+all` & `+vnode_flags_data_changed`.
 *
 * @param queue
 *   The dispatch queue on which to invoke your block.
 *
 * @param block
 *   The block to invoke when the OS informs us of changes to the file/directory.
 */
- (BOOL)monitorWithMask:(dispatch_source_vnode_flags_t)mask
                  queue:(nullable dispatch_queue_t)queue
                  block:(void (^)(dispatch_source_vnode_flags_t mask))block;

/** Returns a mask with every possible event */
+ (dispatch_source_vnode_flags_t)vnode_flags_all;

/** Returns a mask with flags only for when the actual bytes change */
+ (dispatch_source_vnode_flags_t)vnode_flags_data_changed;

/** Returns a string listing the flags specified by the given mask */
+ (NSString *)vnode_flags_description:(dispatch_source_vnode_flags_t)mask;

@end

NS_ASSUME_NONNULL_END
